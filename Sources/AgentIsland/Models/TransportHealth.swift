// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Combine
import Foundation

enum TransportConnectionState: String, Codable, CaseIterable {
    case disabled
    case unavailable
    case connecting
    case connected
    case degraded
    case failed

    var label: String {
        switch self {
        case .disabled: return "Disabled"
        case .unavailable: return "Unavailable"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .degraded: return "Degraded"
        case .failed: return "Failed"
        }
    }
}

struct TransportHealthSnapshot: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var state: TransportConnectionState
    var protocolVersion: String?
    var endpoint: String?
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var lastEventAt: Date?
    var failure: String?

    static func initial(id: String, name: String) -> TransportHealthSnapshot {
        TransportHealthSnapshot(
            id: id,
            name: name,
            state: .unavailable,
            protocolVersion: nil,
            endpoint: nil,
            lastAttemptAt: nil,
            lastSuccessAt: nil,
            lastEventAt: nil,
            failure: nil
        )
    }
}

final class TransportHealthStore: ObservableObject {
    static let shared = TransportHealthStore()

    static let hookSocketID = "hook-socket"
    static let codexBrokerID = "codex-broker"
    static let conversationTailID = "conversation-tail"
    static let processProbeID = "process-probe"
    static let tmuxProbeID = "tmux-probe"

    @Published private(set) var snapshots: [TransportHealthSnapshot]

    private let queue = DispatchQueue(label: "local.agent-island.transport-health")
    private var values: [String: TransportHealthSnapshot]
    private let outputURL: URL

    init(outputURL: URL? = nil) {
        self.outputURL = outputURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-island/transport-health.json")
        let initial = [
            TransportHealthSnapshot.initial(id: Self.hookSocketID, name: "Claude Hook Socket"),
            TransportHealthSnapshot.initial(id: Self.codexBrokerID, name: "Codex App Server"),
            TransportHealthSnapshot.initial(id: Self.conversationTailID, name: "Conversation Tail"),
            TransportHealthSnapshot.initial(id: Self.processProbeID, name: "Process / TTY Probe"),
            TransportHealthSnapshot.initial(id: Self.tmuxProbeID, name: "tmux Pane Probe")
        ]
        snapshots = initial
        values = Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0) })
    }

    func markAttempt(id: String, name: String, endpoint: String? = nil) {
        update(id: id, name: name) { value in
            value.state = .connecting
            value.endpoint = endpoint ?? value.endpoint
            value.lastAttemptAt = Date()
            value.failure = nil
        }
    }

    func markConnected(
        id: String,
        name: String,
        protocolVersion: String? = nil,
        endpoint: String? = nil,
        event: Bool = false
    ) {
        update(id: id, name: name) { value in
            let now = Date()
            value.state = .connected
            value.protocolVersion = protocolVersion ?? value.protocolVersion
            value.endpoint = endpoint ?? value.endpoint
            value.lastSuccessAt = now
            if event { value.lastEventAt = now }
            value.failure = nil
        }
    }

    func markEvent(id: String, name: String) {
        update(id: id, name: name) { value in
            let now = Date()
            value.state = .connected
            value.lastSuccessAt = now
            value.lastEventAt = now
            value.failure = nil
        }
    }

    func markFailure(
        id: String,
        name: String,
        state: TransportConnectionState = .failed,
        endpoint: String? = nil,
        error: String
    ) {
        update(id: id, name: name) { value in
            value.state = state
            value.endpoint = endpoint ?? value.endpoint
            value.lastAttemptAt = Date()
            value.failure = Self.compactFailure(error)
        }
    }

    func snapshot(id: String) -> TransportHealthSnapshot? {
        queue.sync { values[id] }
    }

    private func update(
        id: String,
        name: String,
        mutate: @escaping (inout TransportHealthSnapshot) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            var value = self.values[id] ?? .initial(id: id, name: name)
            value.name = name
            mutate(&value)
            self.values[id] = value
            let ordered = self.values.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.persist(ordered)
            DispatchQueue.main.async { [weak self] in
                self?.snapshots = ordered
            }
        }
    }

    private func persist(_ snapshots: [TransportHealthSnapshot]) {
        do {
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshots).write(to: outputURL, options: .atomic)
        } catch {
            islandLog("transport health persist failed error=\(error.localizedDescription)")
        }
    }

    private static func compactFailure(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        return String(singleLine.prefix(400))
    }
}
