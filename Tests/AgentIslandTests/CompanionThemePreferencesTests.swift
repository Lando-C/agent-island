// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func companionThemeParsingFailure() -> String? {
    guard CompanionTheme.parsePersisted(" friendly ") == .friendly,
          CompanionTheme.parsePersisted("TECHNICAL") == .technical,
          CompanionTheme.parsePersisted("system") == .system else {
        return "canonical theme parsing did not normalize whitespace and casing"
    }
    guard CompanionTheme.parsePersisted(nil) == nil,
          CompanionTheme.parsePersisted("") == nil,
          CompanionTheme.parsePersisted("mascot") == nil,
          CompanionTheme.parsePersisted("unknown") == nil else {
        return "canonical theme parsing accepted an invalid or legacy value"
    }
    return nil
}

private func companionThemeResolutionFailure() -> String? {
    var preferences = CompanionThemePreferences.conservativeDefault
    guard AgentFamily.allCases.allSatisfy({ preferences.theme(for: $0) == .system }) else {
        return "new installs did not resolve every family to the conservative system theme"
    }

    preferences.defaultTheme = .friendly
    preferences.setOverride(.technical, for: .codex)
    preferences.setOverride(.system, for: .claudeScience)
    guard preferences.theme(for: .codex) == .technical,
          preferences.theme(for: .claudeScience) == .system,
          preferences.theme(for: .claude) == .friendly,
          preferences.theme(for: .chatgpt) == .friendly else {
        return "family overrides did not resolve independently from the default theme"
    }

    preferences.setOverride(nil, for: .codex)
    guard preferences.theme(for: .codex) == .friendly else {
        return "removing a family override did not restore the default theme"
    }
    return nil
}

private func companionThemePersistenceFailure() -> String? {
    let suite = "agent-island-companion-theme-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        return "failed to create defaults suite"
    }
    defer { defaults.removePersistentDomain(forName: suite) }

    guard CompanionThemeSettings.load(from: defaults) == .conservativeDefault else {
        return "new installs did not use conservative theme defaults"
    }

    var preferences = CompanionThemePreferences(defaultTheme: .friendly)
    preferences.setOverride(.technical, for: .codex)
    preferences.setOverride(.system, for: .claudeScience)
    CompanionThemeSettings.save(preferences, to: defaults)
    guard CompanionThemeSettings.load(from: defaults) == preferences else {
        return "theme preferences did not round-trip"
    }

    defaults.set([
        AgentFamily.codex.rawValue: "TECHNICAL",
        AgentFamily.claude.rawValue: "unknown",
        "future-family": "friendly"
    ], forKey: "agentIsland.companionTheme.familyOverrides")
    let repaired = CompanionThemeSettings.load(from: defaults)
    guard repaired.familyOverrides == [.codex: .technical] else {
        return "invalid or future theme overrides were not ignored safely"
    }
    return nil
}

private func companionThemeMigrationFailure() -> String? {
    let suite = "agent-island-companion-theme-migration-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        return "failed to create defaults suite"
    }
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set("mascot", forKey: "agentIsland.companion.theme")
    let migrated = CompanionThemeSettings.load(from: defaults)
    guard migrated.defaultTheme == .friendly,
          defaults.string(forKey: "agentIsland.companionTheme.default") == "friendly",
          defaults.object(forKey: "agentIsland.companion.theme") == nil else {
        return "legacy mascot theme did not migrate to the canonical friendly theme"
    }

    defaults.removeObject(forKey: "agentIsland.companionTheme.default")
    defaults.set("future-theme", forKey: "agentIsland.companion.theme")
    guard CompanionThemeSettings.load(from: defaults) == .conservativeDefault,
          defaults.string(forKey: "agentIsland.companion.theme") == "future-theme" else {
        return "unknown legacy theme was not preserved with a safe fallback"
    }
    return nil
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Companion theme preferences")
struct CompanionThemePreferencesTests {
    @Test("Persisted themes parse conservatively")
    func parsing() { #expect(companionThemeParsingFailure() == nil) }

    @Test("Family overrides resolve independently")
    func resolution() { #expect(companionThemeResolutionFailure() == nil) }

    @Test("Theme preferences persist and repair invalid values")
    func persistence() { #expect(companionThemePersistenceFailure() == nil) }

    @Test("Legacy scalar themes migrate once")
    func migration() { #expect(companionThemeMigrationFailure() == nil) }
}
#elseif canImport(XCTest)
final class CompanionThemePreferencesTests: XCTestCase {
    func testParsing() { XCTAssertNil(companionThemeParsingFailure()) }
    func testResolution() { XCTAssertNil(companionThemeResolutionFailure()) }
    func testPersistence() { XCTAssertNil(companionThemePersistenceFailure()) }
    func testMigration() { XCTAssertNil(companionThemeMigrationFailure()) }
}
#endif
