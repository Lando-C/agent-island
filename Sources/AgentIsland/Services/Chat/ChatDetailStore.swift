// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Combine
import Foundation

enum ChatDetailRole: String {
    case user
    case assistant
    case tool
    case system
}

struct ChatDetailItem: Identifiable, Equatable {
    var id: String
    var role: ChatDetailRole
    var title: String
    var body: String
    var timestamp: Date?
}

final class ChatDetailStore: ObservableObject {
    @Published private(set) var items: [ChatDetailItem] = []
    @Published private(set) var loading = false
    @Published private(set) var sourcePath: String?
    @Published private(set) var errorMessage: String?

    func load(snapshot: AgentSnapshot) {
        loading = true
        errorMessage = nil
        items = []
        sourcePath = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.read(snapshot: snapshot)
            DispatchQueue.main.async {
                self?.items = result.items
                self?.sourcePath = result.path
                self?.errorMessage = result.error
                self?.loading = false
            }
        }
    }

    private static func read(snapshot: AgentSnapshot) -> (items: [ChatDetailItem], path: String?, error: String?) {
        guard let sessionID = snapshot.sessionID, !sessionID.isEmpty else {
            return ([], nil, "该状态没有可定位的会话 ID")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [URL]
        switch snapshot.family {
        case .claude:
            roots = [
                home.appendingPathComponent(".claude/projects"),
                home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions"),
                home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")
            ]
        case .codex:
            roots = [home.appendingPathComponent(".codex/sessions")]
        default:
            return ([], nil, "当前引擎尚未提供可读的本地聊天记录")
        }

        guard let file = transcriptFromEventLog(sessionID: sessionID) ?? newestTranscript(roots: roots, sessionID: sessionID) else {
            return ([], nil, "没有找到 session \(shortID(sessionID)) 的本地记录")
        }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return ([], file.path, "聊天记录无法读取")
        }

        var items: [ChatDetailItem] = []
        for (lineNumber, line) in text.split(separator: "\n").enumerated() {
            guard let data = String(line).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            switch snapshot.family {
            case .claude:
                items.append(contentsOf: parseClaude(root, lineNumber: lineNumber))
            case .codex:
                items.append(contentsOf: parseCodex(root, lineNumber: lineNumber))
            default:
                break
            }
        }
        let visible = deduplicated(items)
        return visible.isEmpty
            ? ([], file.path, "记录存在，但没有可展示的对话或工具事件")
            : (visible, file.path, nil)
    }

    private static func transcriptFromEventLog(sessionID: String) -> URL? {
        let log = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-island/events.jsonl")
        guard let text = try? String(contentsOf: log, encoding: .utf8),
              let path = transcriptPath(
                inEventLog: text,
                sessionID: sessionID,
                fileExists: FileManager.default.fileExists(atPath:)
              ) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func transcriptPath(
        inEventLog text: String,
        sessionID: String,
        fileExists: (String) -> Bool
    ) -> String? {
        for line in text.split(separator: "\n").reversed() {
            guard let data = String(line).data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let identities = ["session", "raw_session", "primary_session", "parent_session"]
                .compactMap { event[$0] as? String }
            guard identities.contains(sessionID),
                  let rawPath = event["transcript_path"] as? String,
                  !rawPath.isEmpty else { continue }
            let expanded = NSString(string: rawPath).expandingTildeInPath
            guard fileExists(expanded) else { continue }
            return expanded
        }
        return nil
    }

    private static func newestTranscript(roots: [URL], sessionID: String) -> URL? {
        var matches: [(Date, URL)] = []
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" || url.pathExtension == "json",
                      url.lastPathComponent.contains(sessionID) || url.path.contains(sessionID) else { continue }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                matches.append((date, url))
            }
        }
        return matches.max { $0.0 < $1.0 }?.1
    }

    private static func parseClaude(_ root: [String: Any], lineNumber: Int) -> [ChatDetailItem] {
        let type = root["type"] as? String ?? ""
        let date = parseDate(root["timestamp"])
        guard type == "user" || type == "assistant" else { return [] }
        let message = root["message"] as? [String: Any] ?? root
        let role: ChatDetailRole = type == "user" ? .user : .assistant
        let content = message["content"]
        return contentItems(content, baseID: "claude-\(lineNumber)", role: role, timestamp: date)
    }

    private static func parseCodex(_ root: [String: Any], lineNumber: Int) -> [ChatDetailItem] {
        let date = parseDate(root["timestamp"])
        let type = root["type"] as? String ?? ""
        let payload = root["payload"] as? [String: Any] ?? [:]
        if type == "response_item" {
            switch payload["type"] as? String {
            case "message":
                let rawRole = payload["role"] as? String
                let role: ChatDetailRole = rawRole == "user" ? .user : .assistant
                return contentItems(payload["content"], baseID: "codex-\(lineNumber)", role: role, timestamp: date)
            case "function_call", "custom_tool_call":
                let name = payload["name"] as? String ?? "Tool call"
                let body = compactJSON(payload["arguments"] ?? payload["input"] ?? "")
                return [ChatDetailItem(id: "codex-\(lineNumber)", role: .tool, title: name, body: body, timestamp: date)]
            case "function_call_output", "custom_tool_call_output":
                let body = compactJSON(payload["output"] ?? "")
                return [ChatDetailItem(id: "codex-\(lineNumber)", role: .tool, title: "Tool result", body: body, timestamp: date)]
            default:
                return []
            }
        }
        if type == "event_msg" {
            let eventType = payload["type"] as? String ?? ""
            if eventType == "agent_message" || eventType == "user_message" {
                let role: ChatDetailRole = eventType == "user_message" ? .user : .assistant
                let text = payload["message"] as? String ?? ""
                return item(text: text, id: "codex-\(lineNumber)", role: role, timestamp: date)
            }
        }
        return []
    }

    private static func contentItems(
        _ content: Any?,
        baseID: String,
        role: ChatDetailRole,
        timestamp: Date?
    ) -> [ChatDetailItem] {
        if let text = content as? String {
            return item(text: text, id: baseID, role: role, timestamp: timestamp)
        }
        guard let blocks = content as? [[String: Any]] else { return [] }
        return blocks.enumerated().compactMap { index, block in
            let type = block["type"] as? String ?? ""
            if ["text", "input_text", "output_text"].contains(type), let text = block["text"] as? String {
                return makeItem(text: text, id: "\(baseID)-\(index)", role: role, timestamp: timestamp)
            }
            if type == "tool_use" {
                return ChatDetailItem(
                    id: "\(baseID)-\(index)",
                    role: .tool,
                    title: block["name"] as? String ?? "Tool call",
                    body: compactJSON(block["input"] ?? ""),
                    timestamp: timestamp
                )
            }
            if type == "tool_result" {
                return ChatDetailItem(
                    id: "\(baseID)-\(index)",
                    role: .tool,
                    title: "Tool result",
                    body: compactJSON(block["content"] ?? ""),
                    timestamp: timestamp
                )
            }
            return nil
        }
    }

    private static func item(text: String, id: String, role: ChatDetailRole, timestamp: Date?) -> [ChatDetailItem] {
        guard let value = makeItem(text: text, id: id, role: role, timestamp: timestamp) else { return [] }
        return [value]
    }

    private static func makeItem(text: String, id: String, role: ChatDetailRole, timestamp: Date?) -> ChatDetailItem? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let title = role == .user ? "You" : role == .assistant ? "Assistant" : "Event"
        return ChatDetailItem(id: id, role: role, title: title, body: cleaned, timestamp: timestamp)
    }

    private static func compactJSON(_ value: Any) -> String {
        if let text = value as? String { return text }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else { return String(describing: value) }
        return text
    }

    static func deduplicated(_ items: [ChatDetailItem]) -> [ChatDetailItem] {
        var result: [ChatDetailItem] = []
        for item in items {
            let duplicate = result.suffix(8).contains { existing in
                guard existing.role == item.role,
                      existing.title == item.title,
                      existing.body == item.body else { return false }
                switch (existing.timestamp, item.timestamp) {
                case let (.some(lhs), .some(rhs)):
                    return abs(lhs.timeIntervalSince(rhs)) <= 1.5
                case (.none, .none):
                    return existing.id == result.last?.id
                default:
                    return false
                }
            }
            if !duplicate { result.append(item) }
        }
        return result
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        guard let text = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    private static func shortID(_ value: String) -> String {
        String(value.prefix(8))
    }
}
