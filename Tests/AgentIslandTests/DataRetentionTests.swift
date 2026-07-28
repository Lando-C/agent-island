// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func dataRetentionFailure() -> String? {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-island-retention-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let settingsURL = root.appendingPathComponent("data-retention.json")
    let settings = DataRetentionStore(settingsURL: settingsURL)
    guard settings.settings == .conservativeDefault else {
        return "new installs did not use conservative retention defaults"
    }
    settings.settings.eventLog = .sevenDays
    settings.settings.diagnostics = .ninetyDays
    settings.settings.conversationProjection = .disabled

    let reloaded = DataRetentionStore(settingsURL: settingsURL)
    guard reloaded.settings == settings.settings else {
        return "retention settings did not round-trip"
    }
    let permissions = (try? FileManager.default.attributesOfItem(atPath: settingsURL.path)[.posixPermissions] as? NSNumber)?
        .intValue
    guard permissions == 0o600 else {
        return "retention settings were not restricted to 0600"
    }

    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let events = root.appendingPathComponent("events.jsonl")
    let providerTranscript = root.deletingLastPathComponent()
        .appendingPathComponent("provider-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: providerTranscript) }
    try? Data(#"{"message":"owned event"}"#.utf8).write(to: events)
    try? Data(#"{"message":"provider source"}"#.utf8).write(to: providerTranscript)

    let diagnosticsURL = root.appendingPathComponent("diagnostics-history.json")
    let diagnostics = DiagnosticsHistoryStore(outputURL: diagnosticsURL)
    let health = TransportHealthStore(outputURL: root.appendingPathComponent("health.json"))
    let conversations = ConversationStore(health: health)
    AgentIslandOwnedDataCleaner(
        dataRoot: root,
        diagnosticsHistory: diagnostics,
        conversationStore: conversations
    ).clear(.events)

    guard (try? Data(contentsOf: events).isEmpty) == true else {
        return "event projection was not cleared"
    }
    guard (try? String(contentsOf: providerTranscript, encoding: .utf8))?.contains("provider source") == true else {
        return "cleanup modified data outside Agent Island's data root"
    }
    return nil
}

private func onboardingChecklistFailure() -> String? {
    let suite = "agent-island-onboarding-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { return "failed to create defaults suite" }
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = OnboardingChecklistStore(defaults: defaults)
    guard !store.hasSeenChecklist, store.completed.isEmpty else {
        return "new installs should start with an unseen, unchecked guide"
    }
    store.markSeen()
    store.setCompleted("local-only", true)
    store.setCompleted("unknown-item", true)

    let reloaded = OnboardingChecklistStore(defaults: defaults)
    guard reloaded.hasSeenChecklist,
          reloaded.isCompleted("local-only"),
          !reloaded.isCompleted("unknown-item") else {
        return "onboarding progress was not persisted safely"
    }
    return nil
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Test("retention policy persists and cleanup stays inside Agent Island data")
func dataRetentionIsScoped() {
    #expect(dataRetentionFailure() == nil)
}

@Test("onboarding progress is local and explicit")
func onboardingProgressIsLocal() {
    #expect(onboardingChecklistFailure() == nil)
}
#elseif canImport(XCTest)
final class DataRetentionTests: XCTestCase {
    func testDataRetentionIsScoped() {
        XCTAssertNil(dataRetentionFailure())
    }

    func testOnboardingProgressIsLocal() {
        XCTAssertNil(onboardingChecklistFailure())
    }
}
#endif
