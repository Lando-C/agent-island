// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Combine
import Foundation

struct ConversationKey: Hashable {
    var family: String
    var sessionID: String

    init(family: AgentFamily, sessionID: String) {
        self.family = family.rawValue
        self.sessionID = sessionID
    }
}

struct ConversationRecord: Equatable {
    var items: [ChatDetailItem]
    var sourcePath: String?
    var loading: Bool
    var errorMessage: String?
    var lastUpdated: Date?
}

/// Shared incremental transcript tailer. Every detail window observes the same
/// session record, while hook and broker events can be merged before a JSONL
/// transcript is available.
final class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    @Published private(set) var records: [ConversationKey: ConversationRecord] = [:]

    private struct TailState {
        var snapshot: AgentSnapshot
        var watchers: Int
        var sourceURL: URL?
        var inode: UInt64?
        var offset: UInt64
        var fragment: String
        var nextLineNumber: Int
        var items: [ChatDetailItem]
        var lastSourceLookup: Date
    }

    private let queue = DispatchQueue(label: "local.agent-island.conversation-store", qos: .utility)
    private let health: TransportHealthStore
    private var states: [ConversationKey: TailState] = [:]
    private var injectedItems: [ConversationKey: [ChatDetailItem]] = [:]
    private var timer: DispatchSourceTimer?
    private var lastUnavailableHealthUpdate = Date.distantPast

    init(health: TransportHealthStore = .shared) {
        self.health = health
    }

    @discardableResult
    func watch(snapshot: AgentSnapshot) -> ConversationKey? {
        guard let sessionID = snapshot.sessionID, !sessionID.isEmpty else { return nil }
        let key = ConversationKey(family: snapshot.family, sessionID: sessionID)
        publish(key: key, record: ConversationRecord(
            items: records[key]?.items ?? [],
            sourcePath: records[key]?.sourcePath,
            loading: true,
            errorMessage: nil,
            lastUpdated: records[key]?.lastUpdated
        ))
        queue.async { [weak self] in
            guard let self else { return }
            if var state = self.states[key] {
                state.watchers += 1
                state.snapshot = snapshot
                self.states[key] = state
            } else {
                self.states[key] = TailState(
                    snapshot: snapshot,
                    watchers: 1,
                    sourceURL: nil,
                    inode: nil,
                    offset: 0,
                    fragment: "",
                    nextLineNumber: 0,
                    items: self.injectedItems[key] ?? [],
                    lastSourceLookup: .distantPast
                )
            }
            self.ensureTimer()
            self.refreshOnQueue(key: key, forceFull: false)
        }
        return key
    }

    func unwatch(_ key: ConversationKey?) {
        guard let key else { return }
        queue.async { [weak self] in
            guard let self, var state = self.states[key] else { return }
            state.watchers = max(0, state.watchers - 1)
            if state.watchers == 0 {
                self.states.removeValue(forKey: key)
            } else {
                self.states[key] = state
            }
            self.stopTimerIfIdle()
        }
    }

    func refresh(snapshot: AgentSnapshot) {
        guard let sessionID = snapshot.sessionID, !sessionID.isEmpty else { return }
        let key = ConversationKey(family: snapshot.family, sessionID: sessionID)
        queue.async { [weak self] in
            guard let self else { return }
            if self.states[key] == nil {
                self.states[key] = TailState(
                    snapshot: snapshot,
                    watchers: 0,
                    sourceURL: nil,
                    inode: nil,
                    offset: 0,
                    fragment: "",
                    nextLineNumber: 0,
                    items: self.injectedItems[key] ?? [],
                    lastSourceLookup: .distantPast
                )
            }
            self.refreshOnQueue(key: key, forceFull: true)
        }
    }

    func ingestHookRequest(_ request: HookSocketRequest) {
        guard let sessionID = request.logicalSessionID, !sessionID.isEmpty else { return }
        let family: AgentFamily = request.source?.lowercased().contains("codex") == true ? .codex : .claude
        let key = ConversationKey(family: family, sessionID: sessionID)
        let timestamp = Date(timeIntervalSince1970: request.ts ?? Date().timeIntervalSince1970)
        let title = request.tool ?? request.event ?? "Agent event"
        let body = request.question
            ?? request.message
            ?? request.toolInputSummary
            ?? "Waiting for input"
        let item = ChatDetailItem(
            id: "hook-\(request.pendingID)-\(Int(timestamp.timeIntervalSince1970 * 1000))",
            role: request.tool == nil ? .system : .tool,
            title: title,
            body: body,
            timestamp: timestamp
        )
        ingest(items: [item], for: key)
    }

    func ingestCodexThread(_ thread: [String: Any]) {
        guard let id = thread["id"] as? String, !id.isEmpty else { return }
        let key = ConversationKey(family: .codex, sessionID: id)
        let turns = thread["turns"] as? [[String: Any]] ?? []
        var items: [ChatDetailItem] = []
        for (turnIndex, turn) in turns.enumerated() {
            let turnID = turn["id"] as? String ?? "turn-\(turnIndex)"
            let rawItems = turn["items"] as? [[String: Any]] ?? []
            for (itemIndex, raw) in rawItems.enumerated() {
                items.append(contentsOf: ConversationTranscriptParser.parseCodexBrokerItem(
                    raw,
                    baseID: "broker-\(turnID)-\(itemIndex)"
                ))
            }
        }
        ingest(items: items, for: key)
    }

    private func ingest(items: [ChatDetailItem], for key: ConversationKey) {
        guard !items.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let merged = ChatDetailStore.deduplicated((self.injectedItems[key] ?? []) + items)
            self.injectedItems[key] = Array(merged.suffix(500))
            if var state = self.states[key] {
                state.items = ChatDetailStore.deduplicated(state.items + items)
                self.states[key] = state
                self.publishState(state, key: key, error: nil)
            } else {
                self.publish(key: key, record: ConversationRecord(
                    items: self.injectedItems[key] ?? [],
                    sourcePath: nil,
                    loading: false,
                    errorMessage: nil,
                    lastUpdated: Date()
                ))
            }
        }
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.refreshWatchedSessions() }
        self.timer = timer
        timer.resume()
    }

    private func stopTimerIfIdle() {
        guard states.values.allSatisfy({ $0.watchers == 0 }) else { return }
        timer?.cancel()
        timer = nil
    }

    private func refreshWatchedSessions() {
        for key in states.keys where states[key]?.watchers ?? 0 > 0 {
            refreshOnQueue(key: key, forceFull: false)
        }
    }

    private func refreshOnQueue(key: ConversationKey, forceFull: Bool) {
        guard var state = states[key] else { return }
        let now = Date()
        if forceFull || state.sourceURL == nil || now.timeIntervalSince(state.lastSourceLookup) >= 15 {
            state.lastSourceLookup = now
            let located = ConversationTranscriptLocator.transcript(for: state.snapshot)
            if located != state.sourceURL {
                state.sourceURL = located
                state.inode = nil
                state.offset = 0
                state.fragment = ""
                state.nextLineNumber = 0
                state.items = injectedItems[key] ?? []
            }
        }

        guard let sourceURL = state.sourceURL else {
            states[key] = state
            let message = state.items.isEmpty
                ? "没有找到 session \(String(key.sessionID.prefix(8))) 的本地记录"
                : nil
            publishState(state, key: key, error: message)
            if now.timeIntervalSince(lastUnavailableHealthUpdate) >= 30 {
                lastUnavailableHealthUpdate = now
                health.markFailure(
                    id: TransportHealthStore.conversationTailID,
                    name: "Conversation Tail",
                    state: .unavailable,
                    error: message ?? "Waiting for transcript path"
                )
            }
            return
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
            if forceFull || state.inode != inode || size < state.offset {
                state.offset = 0
                state.fragment = ""
                state.nextLineNumber = 0
                state.items = injectedItems[key] ?? []
            }
            state.inode = inode

            let didReadNewBytes = size > state.offset
            if didReadNewBytes {
                let handle = try FileHandle(forReadingFrom: sourceURL)
                try handle.seek(toOffset: state.offset)
                let data = try handle.readToEnd() ?? Data()
                try handle.close()
                state.offset += UInt64(data.count)
                if let chunk = String(data: data, encoding: .utf8) {
                    let decoded = ConversationTranscriptParser.decodeChunk(
                        state.fragment + chunk,
                        family: state.snapshot.family,
                        startingLineNumber: state.nextLineNumber
                    )
                    state.fragment = decoded.fragment
                    state.nextLineNumber += decoded.completeLineCount
                    state.items = ChatDetailStore.deduplicated(state.items + decoded.items)
                }
            }

            states[key] = state
            let error = state.items.isEmpty ? "记录存在，但没有可展示的对话或工具事件" : nil
            publishState(state, key: key, error: error)
            if didReadNewBytes {
                health.markConnected(
                    id: TransportHealthStore.conversationTailID,
                    name: "Conversation Tail",
                    protocolVersion: "jsonl-tail/v1",
                    endpoint: sourceURL.path,
                    event: true
                )
            }
        } catch {
            states[key] = state
            publishState(state, key: key, error: "聊天记录无法读取：\(error.localizedDescription)")
            health.markFailure(
                id: TransportHealthStore.conversationTailID,
                name: "Conversation Tail",
                endpoint: sourceURL.path,
                error: error.localizedDescription
            )
        }
    }

    private func publishState(_ state: TailState, key: ConversationKey, error: String?) {
        publish(key: key, record: ConversationRecord(
            items: state.items,
            sourcePath: state.sourceURL?.path,
            loading: false,
            errorMessage: error,
            lastUpdated: Date()
        ))
    }

    private func publish(key: ConversationKey, record: ConversationRecord) {
        DispatchQueue.main.async { [weak self] in
            self?.records[key] = record
        }
    }
}

enum ConversationTranscriptLocator {
    static func transcript(for snapshot: AgentSnapshot) -> URL? {
        guard let sessionID = snapshot.sessionID, !sessionID.isEmpty else { return nil }
        if let exact = transcriptFromEventLog(sessionID: sessionID) { return exact }
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
        case .claudeScience, .chatgpt:
            return nil
        }
        return newestTranscript(roots: roots, sessionID: sessionID)
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
}

enum ConversationTranscriptParser {
    static func decodeChunk(
        _ text: String,
        family: AgentFamily,
        startingLineNumber: Int
    ) -> (items: [ChatDetailItem], fragment: String, completeLineCount: Int) {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let fragment: String
        if text.hasSuffix("\n") {
            fragment = ""
            // `split(..., omittingEmptySubsequences: false)` includes a synthetic
            // empty element after a trailing newline. It is not a JSONL record.
            if lines.last?.isEmpty == true {
                lines.removeLast()
            }
        } else {
            fragment = lines.popLast().map(String.init) ?? ""
        }
        var items: [ChatDetailItem] = []
        for (offset, line) in lines.enumerated() {
            guard !line.isEmpty,
                  let data = String(line).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let lineNumber = startingLineNumber + offset
            switch family {
            case .claude:
                items.append(contentsOf: parseClaude(root, lineNumber: lineNumber))
            case .codex:
                items.append(contentsOf: parseCodex(root, lineNumber: lineNumber))
            case .claudeScience, .chatgpt:
                break
            }
        }
        return (items, fragment, lines.count)
    }

    static func parseCodexBrokerItem(_ item: [String: Any], baseID: String) -> [ChatDetailItem] {
        let type = item["type"] as? String ?? ""
        let timestamp = parseDate(item["completedAt"] ?? item["createdAt"] ?? item["startedAt"])
        switch type {
        case "userMessage":
            return contentItems(item["content"], baseID: baseID, role: .user, timestamp: timestamp)
        case "agentMessage":
            return makeTextItems(item["text"] as? String ?? "", id: baseID, role: .assistant, timestamp: timestamp)
        case "commandExecution":
            return [ChatDetailItem(
                id: baseID,
                role: .tool,
                title: "Command",
                body: compactJSON(item["command"] ?? item["cmd"] ?? "Command execution"),
                timestamp: timestamp
            )]
        case "fileChange":
            return [ChatDetailItem(
                id: baseID,
                role: .tool,
                title: "File changes",
                body: compactJSON(item["changes"] ?? item),
                timestamp: timestamp
            )]
        case "toolCall":
            return [ChatDetailItem(
                id: baseID,
                role: .tool,
                title: item["name"] as? String ?? item["toolName"] as? String ?? "Tool call",
                body: compactJSON(item["arguments"] ?? item["input"] ?? item),
                timestamp: timestamp
            )]
        default:
            guard !type.isEmpty else { return [] }
            return [ChatDetailItem(
                id: baseID,
                role: .system,
                title: type,
                body: compactJSON(item),
                timestamp: timestamp
            )]
        }
    }

    private static func parseClaude(_ root: [String: Any], lineNumber: Int) -> [ChatDetailItem] {
        let type = root["type"] as? String ?? ""
        let date = parseDate(root["timestamp"])
        guard type == "user" || type == "assistant" else { return [] }
        let message = root["message"] as? [String: Any] ?? root
        let role: ChatDetailRole = type == "user" ? .user : .assistant
        return contentItems(message["content"], baseID: "claude-\(lineNumber)", role: role, timestamp: date)
    }

    private static func parseCodex(_ root: [String: Any], lineNumber: Int) -> [ChatDetailItem] {
        let date = parseDate(root["timestamp"])
        let type = root["type"] as? String ?? ""
        let payload = root["payload"] as? [String: Any] ?? [:]
        if type == "response_item" {
            switch payload["type"] as? String {
            case "message":
                let role: ChatDetailRole = payload["role"] as? String == "user" ? .user : .assistant
                return contentItems(payload["content"], baseID: "codex-\(lineNumber)", role: role, timestamp: date)
            case "function_call", "custom_tool_call":
                return [ChatDetailItem(
                    id: "codex-\(lineNumber)",
                    role: .tool,
                    title: payload["name"] as? String ?? "Tool call",
                    body: compactJSON(payload["arguments"] ?? payload["input"] ?? ""),
                    timestamp: date
                )]
            case "function_call_output", "custom_tool_call_output":
                return [ChatDetailItem(
                    id: "codex-\(lineNumber)",
                    role: .tool,
                    title: "Tool result",
                    body: compactJSON(payload["output"] ?? ""),
                    timestamp: date
                )]
            default:
                return []
            }
        }
        if type == "event_msg" {
            let eventType = payload["type"] as? String ?? ""
            if eventType == "agent_message" || eventType == "user_message" {
                let role: ChatDetailRole = eventType == "user_message" ? .user : .assistant
                return makeTextItems(payload["message"] as? String ?? "", id: "codex-\(lineNumber)", role: role, timestamp: date)
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
            return makeTextItems(text, id: baseID, role: role, timestamp: timestamp)
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

    private static func makeTextItems(
        _ text: String,
        id: String,
        role: ChatDetailRole,
        timestamp: Date?
    ) -> [ChatDetailItem] {
        guard let item = makeItem(text: text, id: id, role: role, timestamp: timestamp) else { return [] }
        return [item]
    }

    private static func makeItem(
        text: String,
        id: String,
        role: ChatDetailRole,
        timestamp: Date?
    ) -> ChatDetailItem? {
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

    private static func parseDate(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        if let seconds = value as? Int { return Date(timeIntervalSince1970: Double(seconds)) }
        guard let text = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}
