// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

/// Activity derived from the JSONL file the Codex desktop app is actively
/// writing. This is a local fallback for app-server instances that expose only
/// stdio and therefore have no broker socket to connect to.
struct CodexTranscriptActivity: Equatable {
    var sessionID: String
    var title: String
    var cwd: String?
    var phase: AgentPhase
    var detail: String
    var lastUpdated: Date
}

enum CodexTranscriptProbe {
    private static let activeWindow: TimeInterval = 15 * 60
    private static let completionWindow: TimeInterval = 10 * 60
    private static let attentionWindow: TimeInterval = 12 * 60 * 60
    private static let maximumTailBytes = 512_000

    static func recentActivities(
        root: URL,
        now: Date = Date(),
        maximumCount: Int = 12
    ) -> [CodexTranscriptActivity] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile != false,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) <= attentionWindow else {
                continue
            }
            candidates.append((url, modified))
        }

        return candidates
            .sorted { $0.modified > $1.modified }
            .prefix(maximumCount)
            .compactMap { candidate in
                guard let data = tailData(url: candidate.url),
                      let sessionID = sessionID(from: candidate.url) else {
                    return nil
                }
                return activity(
                    sessionID: sessionID,
                    data: data,
                    modified: candidate.modified,
                    now: now
                )
            }
    }

    static func activity(
        sessionID: String,
        data: Data,
        modified: Date,
        now: Date = Date()
    ) -> CodexTranscriptActivity? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var title: String?
        var cwd: String?
        var phase: AgentPhase?
        var detail: String?

        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let payload = root["payload"] as? [String: Any] ?? [:]
            if cwd == nil, let value = root["cwd"] as? String, !value.isEmpty { cwd = value }

            if root["type"] as? String == "response_item",
               payload["type"] as? String == "message",
               payload["role"] as? String == "user",
               let text = messageText(payload["content"]),
               let meaningful = AgentText.meaningfulConversationTitle(text) {
                title = meaningful
            }

            let eventType = (payload["type"] as? String ?? "").lowercased()
            switch eventType {
            case "task_started":
                phase = .working
                detail = "任务开始"
            case "task_complete":
                phase = .done
                detail = "本轮完成"
            case "agent_reasoning":
                phase = .thinking
                detail = "正在思考"
            case "custom_tool_call", "function_call":
                phase = .working
                let tool = payload["name"] as? String ?? "工具"
                detail = "工具: \(tool)"
            case "request_user_input", "ask_user_question", "permission_request", "waiting_for_approval", "waiting_for_input":
                phase = .needsAttention
                detail = "等待你的输入或确认"
            case "agent_message":
                if (payload["phase"] as? String)?.lowercased() == "final_answer", phase == nil {
                    phase = .done
                    detail = "本轮完成"
                }
            default:
                break
            }
        }

        let age = now.timeIntervalSince(modified)
        let resolvedPhase = phase ?? .queued
        let allowedAge: TimeInterval
        switch resolvedPhase {
        case .needsAttention:
            allowedAge = attentionWindow
        case .done:
            allowedAge = completionWindow
        case .working, .thinking, .queued:
            allowedAge = activeWindow
        case .online, .idle, .available, .offline, .error:
            return nil
        }
        guard age <= allowedAge else { return nil }

        let displayTitle = title.flatMap(AgentText.meaningfulConversationTitle)
            ?? "会话 \(String(sessionID.prefix(8)))"
        return CodexTranscriptActivity(
            sessionID: sessionID,
            title: AgentText.compact(displayTitle, limit: 72),
            cwd: cwd,
            phase: resolvedPhase,
            detail: detail ?? resolvedPhase.label,
            lastUpdated: modified
        )
    }

    private static func tailData(url: URL) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            return nil
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            if size > UInt64(maximumTailBytes) {
                try handle.seek(toOffset: size - UInt64(maximumTailBytes))
            }
            let data = try handle.readToEnd() ?? Data()
            // A tail can start in the middle of a record. Drop that fragment.
            guard let firstNewline = data.firstIndex(of: 0x0A) else { return data }
            return size > UInt64(maximumTailBytes) ? data.suffix(from: data.index(after: firstNewline)) : data
        } catch {
            return nil
        }
    }

    private static func sessionID(from url: URL) -> String? {
        let filename = url.deletingPathExtension().lastPathComponent
        guard filename.count >= 36 else { return nil }
        let candidate = String(filename.suffix(36))
        let pattern = #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#
        return candidate.range(of: pattern, options: .regularExpression) == nil ? nil : candidate
    }

    private static func messageText(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        guard let blocks = value as? [[String: Any]] else { return nil }
        return blocks.compactMap { block in
            (block["text"] as? String) ?? (block["content"] as? String)
        }.joined(separator: " ")
    }
}
