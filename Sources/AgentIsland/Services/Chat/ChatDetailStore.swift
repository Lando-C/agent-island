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

/// Window-scoped projection of the shared incremental ConversationStore.
final class ChatDetailStore: ObservableObject {
    @Published private(set) var items: [ChatDetailItem] = []
    @Published private(set) var loading = false
    @Published private(set) var sourcePath: String?
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
                self.items = record.items
                self.loading = record.loading
                self.sourcePath = record.sourcePath
                self.errorMessage = record.errorMessage
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
