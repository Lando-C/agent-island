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

extension ChatDetailItem {
    var isConversation: Bool {
        role == .user || role == .assistant
    }

    var isActivity: Bool {
        !isConversation
    }

    /// A short, human-facing description for the activity timeline. Tool output is
    /// intentionally not used here: terminal payloads and JSON results are useful
    /// for diagnostics, but obscure the actual conversation when shown by default.
    var activitySummary: String {
        let compact = body
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let lowercasedTitle = title.lowercased()

        if role == .tool {
            if lowercasedTitle.contains("result") || lowercasedTitle.contains("output") {
                if let duration = compact.components(separatedBy: "Wall time").dropFirst().first {
                    return "已返回结果 \u{00b7} \(shortened("耗时" + duration, limit: 64))"
                }
                return "已返回结果"
            }
            if lowercasedTitle.contains("command") || lowercasedTitle == "exec" || lowercasedTitle == "bash" {
                return "已执行命令"
            }
            return compact.isEmpty ? "已执行" : shortened(compact, limit: 150)
        }

        return compact.isEmpty ? "状态已更新" : shortened(compact, limit: 150)
    }

    var rawActivityPreview: String {
        shortened(body, limit: 6_000)
    }

    private func shortened(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n\n已省略剩余内容"
    }
}

/// Window-scoped projection of the shared incremental ConversationStore.
final class ChatDetailStore: ObservableObject {
    @Published private(set) var items: [ChatDetailItem] = []
    @Published private(set) var loading = false
    @Published private(set) var sourcePath: String?
    @Published private(set) var historyTruncated = false
    @Published private(set) var errorMessage: String?

    private let conversations: ConversationStore
    private var key: ConversationKey?
    private var cancellable: AnyCancellable?
    private var snapshot: AgentSnapshot?

    init(conversations: ConversationStore = .shared) {
        self.conversations = conversations
        cancellable = conversations.$records
            .receive(on: DispatchQueue.main)
            .sink { [weak self] records in
                guard let self, let key = self.key, let record = records[key] else { return }
                // ConversationStore publishes a health heartbeat while tailing. Do
                // not invalidate a detail window when the visible record is unchanged.
                if self.items != record.items { self.items = record.items }
                if self.loading != record.loading { self.loading = record.loading }
                if self.sourcePath != record.sourcePath { self.sourcePath = record.sourcePath }
                if self.historyTruncated != record.historyTruncated {
                    self.historyTruncated = record.historyTruncated
                }
                if self.errorMessage != record.errorMessage { self.errorMessage = record.errorMessage }
            }
    }

    deinit {
        conversations.unwatch(key)
    }

    func load(snapshot: AgentSnapshot) {
        conversations.unwatch(key)
        self.snapshot = snapshot
        guard let sessionID = snapshot.sessionID, !sessionID.isEmpty else {
            key = nil
            items = []
            loading = false
            sourcePath = nil
            historyTruncated = false
            errorMessage = "该状态没有可定位的会话 ID"
            return
        }
        key = ConversationKey(family: snapshot.family, sessionID: sessionID)
        loading = true
        errorMessage = nil
        _ = conversations.watch(snapshot: snapshot)
    }

    func refresh() {
        guard let snapshot else { return }
        loading = true
        conversations.refresh(snapshot: snapshot)
    }

    static func transcriptPath(
        inEventLog text: String,
        sessionID: String,
        fileExists: (String) -> Bool
    ) -> String? {
        ConversationTranscriptLocator.transcriptPath(
            inEventLog: text,
            sessionID: sessionID,
            fileExists: fileExists
        )
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
}
