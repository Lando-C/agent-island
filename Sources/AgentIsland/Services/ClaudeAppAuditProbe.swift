// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

struct ClaudeAppAuditActivity: Equatable {
    var cliSessionID: String
    var localSessionID: String
    var title: String
    var cwd: String?
    var phase: AgentPhase
    var detail: String
    var lastUpdated: Date
}

/// Reads Claude Desktop local-agent audit streams. These are independent from
/// Claude Code CLI hooks and therefore must never be reclassified as CLI work.
enum ClaudeAppAuditProbe {
    private static let activeWindow: TimeInterval = 15 * 60
    private static let completionWindow: TimeInterval = 10 * 60
    private static let attentionWindow: TimeInterval = 12 * 60 * 60
    private static let maximumTailBytes = 384_000

    static func recentActivities(root: URL, now: Date = Date(), maximumCount: Int = 12) -> [ClaudeAppAuditActivity] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [(URL, Date)] = []
        for case let url as URL in enumerator where url.lastPathComponent == "audit.jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile != false,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) <= attentionWindow else {
                continue
            }
            candidates.append((url, modified))
        }

        return candidates.sorted { $0.1 > $1.1 }.prefix(maximumCount).compactMap { audit, modified in
            guard let info = sessionInfo(for: audit), let data = tailData(audit) else { return nil }
            return activity(info: info, data: data, modified: modified, now: now)
        }
    }

    static func activity(
        info: ClaudeAppSessionInfo,
        data: Data,
        modified: Date,
        now: Date = Date()
    ) -> ClaudeAppAuditActivity? {
        guard let cliSessionID = info.cliSessionId, !cliSessionID.isEmpty,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        var phase: AgentPhase?
        var detail: String?
        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let type = (entry["type"] as? String ?? "").lowercased()
            let subtype = (entry["subtype"] as? String ?? "").lowercased()
            let status = (entry["status"] as? String ?? "").lowercased()
            if type == "system", subtype == "status" {
                switch status {
                case "requesting", "working", "processing", "running", "responding":
                    phase = .working
                    detail = "正在执行"
                case "waiting_for_input", "waiting_for_approval", "permission", "needs_attention":
                    phase = .needsAttention
                    detail = "等待你的输入或确认"
                case "idle", "complete", "completed", "success":
                    phase = .done
                    detail = "本轮完成"
                default:
                    break
                }
                continue
            }
            if type == "user" {
                phase = .queued
                detail = "已收到任务"
                continue
            }
            if type == "assistant" || type == "tool_use" {
                phase = .working
                detail = type == "tool_use" ? "正在调用工具" : "正在回复"
            }
        }

        let resolvedPhase = phase ?? .queued
        let age = now.timeIntervalSince(modified)
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

        return ClaudeAppAuditActivity(
            cliSessionID: cliSessionID,
            localSessionID: info.sessionId,
            title: AgentText.compact(ClaudeAppSessionIndex.displayTitle(for: info), limit: 72),
            cwd: info.cwd,
            phase: resolvedPhase,
            detail: detail ?? resolvedPhase.label,
            lastUpdated: modified
        )
    }

    private static func sessionInfo(for auditURL: URL) -> ClaudeAppSessionInfo? {
        let localDirectory = auditURL.deletingLastPathComponent()
        let parent = localDirectory.deletingLastPathComponent()
        let metadata = parent.appendingPathComponent("\(localDirectory.lastPathComponent).json")
        let decoder = JSONDecoder()
        if FileManager.default.fileExists(atPath: metadata.path),
           let data = try? Data(contentsOf: metadata),
           let info = try? decoder.decode(ClaudeAppSessionInfo.self, from: data) {
            return info
        }
        return nil
    }

    private static func tailData(_ url: URL) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else { return nil }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            if size > UInt64(maximumTailBytes) { try handle.seek(toOffset: size - UInt64(maximumTailBytes)) }
            let data = try handle.readToEnd() ?? Data()
            guard size > UInt64(maximumTailBytes), let newline = data.firstIndex(of: 0x0A) else { return data }
            return data.suffix(from: data.index(after: newline))
        } catch {
            return nil
        }
    }
}
