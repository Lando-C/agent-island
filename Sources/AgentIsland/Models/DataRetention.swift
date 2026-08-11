// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Combine
import Foundation

enum RetentionPeriod: String, Codable, CaseIterable, Identifiable {
    case sevenDays = "7_days"
    case thirtyDays = "30_days"
    case ninetyDays = "90_days"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        }
    }

    var label: String { "\(days) 天" }
}

enum ConversationProjectionRetention: String, Codable, CaseIterable, Identifiable {
    case disabled
    case untilQuit = "until_quit"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .disabled: return "不保留内存投影"
        case .untilQuit: return "仅保留到退出 App"
        }
    }
}

struct DataRetentionSettings: Codable, Equatable {
    var eventLog: RetentionPeriod
    var diagnostics: RetentionPeriod
    var conversationProjection: ConversationProjectionRetention

    static let conservativeDefault = DataRetentionSettings(
        eventLog: .thirtyDays,
        diagnostics: .thirtyDays,
        conversationProjection: .untilQuit
    )
}

/// Settings only govern data created by Agent Island. Provider-owned Claude
/// and Codex transcripts are deliberately outside this model and are never
/// removed by Agent Island.
final class DataRetentionStore: ObservableObject {
    static let shared = DataRetentionStore()

    @Published var settings: DataRetentionSettings {
        didSet {
            guard settings != oldValue else { return }
            persist()
        }
    }

    let settingsURL: URL

    init(settingsURL: URL? = nil) {
        self.settingsURL = settingsURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-island/data-retention.json")
        settings = Self.load(from: self.settingsURL)
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try LocalDataSecurity.writePrivate(encoder.encode(settings), to: settingsURL)
        } catch {
            islandLog("data retention settings persist failed error=\(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> DataRetentionSettings {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(DataRetentionSettings.self, from: data) else {
            return .conservativeDefault
        }
        return decoded
    }
}

enum AgentIslandOwnedDataScope: String, CaseIterable, Identifiable {
    case events
    case diagnostics
    case conversationProjection

    var id: String { rawValue }
}

struct AgentIslandOwnedDataCleaner {
    let dataRoot: URL
    let diagnosticsHistory: DiagnosticsHistoryStore
    let conversationStore: ConversationStore

    init(
        dataRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-island"),
        diagnosticsHistory: DiagnosticsHistoryStore = .shared,
        conversationStore: ConversationStore = .shared
    ) {
        self.dataRoot = dataRoot
        self.diagnosticsHistory = diagnosticsHistory
        self.conversationStore = conversationStore
    }

    func clear(_ scope: AgentIslandOwnedDataScope) {
        switch scope {
        case .events:
            replaceWithEmptyFile(dataRoot.appendingPathComponent("events.jsonl"))
        case .diagnostics:
            diagnosticsHistory.clear()
        case .conversationProjection:
            conversationStore.clearInMemoryProjections()
        }
    }

    private func replaceWithEmptyFile(_ url: URL) {
        do {
            try LocalDataSecurity.writePrivate(Data(), to: url)
        } catch {
            islandLog("owned data cleanup failed file=\(url.lastPathComponent) error=\(error.localizedDescription)")
        }
    }
}
