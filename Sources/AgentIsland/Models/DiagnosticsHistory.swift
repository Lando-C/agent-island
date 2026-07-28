// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Combine
import Foundation

/// A deliberately small projection of transport health for local troubleshooting.
/// It must never contain conversation text, commands, credentials, or raw payloads.
struct DiagnosticsHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let recordedAt: Date
    let transportID: String
    let transportName: String
    let state: TransportConnectionState
    let protocolVersion: String?
    let endpoint: String?
    let failure: String?

    fileprivate var deduplicationKey: String {
        [
            transportID,
            state.rawValue,
            protocolVersion ?? "",
            endpoint ?? "",
            failure ?? ""
        ].joined(separator: "\u{1f}")
    }
}

final class DiagnosticsHistoryStore: ObservableObject {
    static let shared = DiagnosticsHistoryStore()
    static let defaultLimit = 100

    @Published private(set) var entries: [DiagnosticsHistoryEntry]

    private let queue = DispatchQueue(label: "local.agent-island.diagnostics-history")
    private let outputURL: URL
    private let limit: Int
    private let usesConfiguredRetention: Bool
    private var storedEntries: [DiagnosticsHistoryEntry]

    init(outputURL: URL? = nil, limit: Int = defaultLimit) {
        self.outputURL = outputURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-island/diagnostics-history.json")
        self.limit = max(1, limit)
        usesConfiguredRetention = outputURL == nil
        let configuredMaximumAge: TimeInterval? = outputURL == nil
            ? TimeInterval(DataRetentionStore.shared.settings.diagnostics.days * 24 * 60 * 60)
            : nil
        let loaded = Self.load(from: self.outputURL).filter { entry in
            guard let configuredMaximumAge else { return true }
            return Date().timeIntervalSince(entry.recordedAt) <= configuredMaximumAge
        }
        let bounded = Array(loaded.suffix(self.limit))
        entries = bounded.reversed()
        storedEntries = bounded
    }

    func record(_ snapshot: TransportHealthSnapshot, at date: Date = Date()) {
        let entry = DiagnosticsHistoryEntry(
            id: UUID(),
            recordedAt: date,
            transportID: Self.safeIdentifier(snapshot.id),
            transportName: Self.safeName(snapshot.name),
            state: snapshot.state,
            protocolVersion: Self.safeProtocol(snapshot.protocolVersion),
            endpoint: Self.redactedEndpoint(snapshot.endpoint),
            failure: Self.redactedFailure(snapshot.failure)
        )

        queue.async { [weak self] in
            guard let self else { return }
            if self.storedEntries.last?.deduplicationKey == entry.deduplicationKey {
                return
            }
            self.storedEntries.append(entry)
            let maximumAge = self.usesConfiguredRetention
                ? TimeInterval(DataRetentionStore.shared.settings.diagnostics.days * 24 * 60 * 60)
                : nil
            if let maximumAge {
                self.storedEntries.removeAll {
                    date.timeIntervalSince($0.recordedAt) > maximumAge
                }
            }
            if self.storedEntries.count > self.limit {
                self.storedEntries.removeFirst(self.storedEntries.count - self.limit)
            }
            self.persist(self.storedEntries)
            let published = Array(self.storedEntries.reversed())
            DispatchQueue.main.async { [weak self] in
                self?.entries = published
            }
        }
    }

    func flushForTesting() {
        queue.sync {}
    }

    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            self.storedEntries.removeAll()
            self.persist([])
            DispatchQueue.main.async { [weak self] in
                self?.entries = []
            }
        }
    }

    private func persist(_ values: [DiagnosticsHistoryEntry]) {
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(values).write(to: outputURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: outputURL.path
            )
        } catch {
            islandLog("diagnostics history persist failed error=\(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> [DiagnosticsHistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DiagnosticsHistoryEntry].self, from: data)) ?? []
    }

    private static func safeIdentifier(_ value: String) -> String {
        String(value.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.prefix(80))
    }

    private static func safeName(_ value: String) -> String {
        compact(redactSecrets(value), limit: 100)
    }

    private static func safeProtocol(_ value: String?) -> String? {
        guard let value else { return nil }
        let safe = compact(redactSecrets(value), limit: 120)
        return safe.isEmpty ? nil : safe
    }

    static func redactedEndpoint(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let parts = value.components(separatedBy: " | ").map(redactEndpointPart)
        let safe = compact(parts.joined(separator: " | "), limit: 240)
        return safe.isEmpty ? nil : safe
    }

    private static func redactEndpointPart(_ value: String) -> String {
        if var components = URLComponents(string: value),
           let scheme = components.scheme,
           ["http", "https", "ws", "wss"].contains(scheme.lowercased()),
           components.host != nil {
            components.user = nil
            components.password = nil
            components.query = nil
            components.fragment = nil
            return components.string ?? "\(scheme)://<redacted>"
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if value == home || value.hasPrefix(home + "/") {
            return "~/<redacted>"
        }
        if value.hasPrefix("/tmp/") || value.hasPrefix("/private/tmp/") ||
            value.contains("/TemporaryItems/") {
            return "/tmp/<redacted>"
        }
        if value.hasPrefix("/dev/tty") {
            return "/dev/tty<redacted>"
        }
        if value.hasPrefix("/") {
            let allowlisted = ["/bin/ps", "/usr/bin/ps"]
            return allowlisted.contains(value) ? value : "/<redacted>"
        }
        return redactSecrets(value)
    }

    private static func redactedFailure(_ value: String?) -> String? {
        guard let value else { return nil }
        var safe = redactSecrets(value)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        safe = safe.replacingOccurrences(of: home, with: "~")
        safe = safe.replacingOccurrences(
            of: #"(?:/Users/[^/\s]+|~)/(?:[^\s:]+/)*[^\s:]+"#,
            with: "~/<redacted>",
            options: .regularExpression
        )
        safe = safe.replacingOccurrences(
            of: #"(?:/private)?/tmp/[^\s:;,]+"#,
            with: "/tmp/<redacted>",
            options: .regularExpression
        )
        safe = safe.replacingOccurrences(
            of: #"/dev/tty[^\s:;,]+"#,
            with: "/dev/tty<redacted>",
            options: .regularExpression
        )
        safe = safe.replacingOccurrences(
            of: #"/(?:[^\s:;,]+/)*[^\s:;,]+"#,
            with: "/<redacted>",
            options: .regularExpression
        )
        safe = compact(safe, limit: 240)
        return safe.isEmpty ? nil : safe
    }

    private static func redactSecrets(_ value: String) -> String {
        var result = value
        let patterns = [
            #"(?i)\b(bearer)\s+\S+"#,
            #"(?i)\b(api[_-]?key|access[_-]?token|token|authorization|password|secret)\b\s*[:=]\s*[^\s,;]+"#,
            #"\b[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}\b"#
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "<redacted>",
                options: .regularExpression
            )
        }
        return result
    }

    private static func compact(_ value: String, limit: Int) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        return String(singleLine.prefix(limit))
    }
}
