// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func soundPolicyFailure() -> String? {
    var preferences = AgentIslandSoundPreferences.conservativeDefault
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    guard SoundNotificationPolicy.decision(
        for: .completed,
        preferences: preferences,
        at: now,
        lastPlayedAt: nil,
        lastSignalPlayedAt: nil
    ) == .disabled else {
        return "sound should be disabled by default"
    }

    preferences.enabled = true
    guard SoundNotificationPolicy.decision(
        for: .started,
        preferences: preferences,
        at: now,
        lastPlayedAt: nil,
        lastSignalPlayedAt: nil
    ) == .eventDisabled else {
        return "noisy started event should be disabled by default"
    }
    guard SoundNotificationPolicy.decision(
        for: .completed,
        preferences: preferences,
        at: now,
        lastPlayedAt: nil,
        lastSignalPlayedAt: nil
    ) == .play else {
        return "enabled completion event should play outside quiet hours"
    }
    guard SoundNotificationPolicy.decision(
        for: .completed,
        preferences: preferences,
        at: now.addingTimeInterval(1),
        lastPlayedAt: now,
        lastSignalPlayedAt: nil
    ) == .throttled else {
        return "global minimum interval did not throttle burst playback"
    }
    guard SoundNotificationPolicy.decision(
        for: .completed,
        preferences: preferences,
        at: now.addingTimeInterval(10),
        lastPlayedAt: now,
        lastSignalPlayedAt: now
    ) == .throttled else {
        return "same signal did not use the longer repeat throttle"
    }
    guard SoundNotificationPolicy.decision(
        for: .completed,
        preferences: preferences,
        at: now.addingTimeInterval(-60),
        lastPlayedAt: now,
        lastSignalPlayedAt: now
    ) == .play else {
        return "wall-clock rollback incorrectly extended sound throttling"
    }
    return nil
}

private func quietHoursFailure() -> String? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var preferences = AgentIslandSoundPreferences.conservativeDefault
    preferences.enabled = true
    preferences.quietHoursEnabled = true
    preferences.quietHoursStart = 22
    preferences.quietHoursEnd = 8

    func date(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: hour))!
    }

    guard SoundNotificationPolicy.isInsideQuietHours(
        date(hour: 23),
        preferences: preferences,
        calendar: calendar
    ), SoundNotificationPolicy.isInsideQuietHours(
        date(hour: 7),
        preferences: preferences,
        calendar: calendar
    ), !SoundNotificationPolicy.isInsideQuietHours(
        date(hour: 12),
        preferences: preferences,
        calendar: calendar
    ) else {
        return "overnight quiet-hours boundary was incorrect"
    }
    guard SoundNotificationPolicy.decision(
        for: .needsAttention,
        preferences: preferences,
        at: date(hour: 23),
        lastPlayedAt: nil,
        lastSignalPlayedAt: nil,
        calendar: calendar
    ) == .quietHours else {
        return "quiet hours did not suppress attention sound"
    }
    return nil
}

private func soundSettingsPersistenceFailure() -> String? {
    let suite = "agent-island-sound-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        return "failed to create defaults suite"
    }
    defer { defaults.removePersistentDomain(forName: suite) }

    guard AgentIslandSoundSettings.load(from: defaults) == .conservativeDefault else {
        return "new installs did not use conservative sound defaults"
    }
    defaults.set(true, forKey: "agentIsland.sound.enabled")
    let migrated = AgentIslandSoundSettings.load(from: defaults)
    guard migrated.enabled,
          !migrated.startedEnabled,
          migrated.completedEnabled,
          migrated.needsAttentionEnabled else {
        return "legacy master switch did not migrate with conservative event defaults"
    }
    defaults.set(99, forKey: "agentIsland.sound.quietHours.start")
    defaults.set(-1, forKey: "agentIsland.sound.quietHours.end")
    defaults.set(2, forKey: "agentIsland.sound.minimumInterval")
    defaults.set(-30, forKey: "agentIsland.sound.repeatedSignalInterval")
    let repaired = AgentIslandSoundSettings.load(from: defaults)
    guard repaired.quietHoursStart == 23,
          repaired.quietHoursEnd == 0,
          repaired.minimumInterval == AgentIslandSoundPreferences.conservativeDefault.minimumInterval,
          repaired.repeatedSignalInterval
            == AgentIslandSoundPreferences.conservativeDefault.repeatedSignalInterval else {
        return "invalid persisted sound preferences were not normalized"
    }
    var preferences = AgentIslandSoundPreferences.conservativeDefault
    preferences.enabled = true
    preferences.startedEnabled = true
    preferences.quietHoursEnabled = true
    preferences.quietHoursStart = 21
    preferences.quietHoursEnd = 9
    preferences.minimumInterval = 5
    preferences.startedSound = .ping
    preferences.completedSound = .pop
    AgentIslandSoundSettings.save(preferences, to: defaults)
    guard AgentIslandSoundSettings.load(from: defaults) == preferences else {
        return "sound preferences did not round-trip"
    }
    return nil
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Test("sound policy is conservative and throttles bursts")
func soundPolicyIsConservative() {
    #expect(soundPolicyFailure() == nil)
}

@Test("quiet hours support overnight ranges")
func quietHoursSupportOvernightRanges() {
    #expect(quietHoursFailure() == nil)
}

@Test("sound preferences persist as one policy")
func soundPreferencesPersist() {
    #expect(soundSettingsPersistenceFailure() == nil)
}
#elseif canImport(XCTest)
final class SoundNotificationPolicyTests: XCTestCase {
    func testSoundPolicyIsConservative() {
        XCTAssertNil(soundPolicyFailure())
    }

    func testQuietHoursSupportOvernightRanges() {
        XCTAssertNil(quietHoursFailure())
    }

    func testSoundPreferencesPersist() {
        XCTAssertNil(soundSettingsPersistenceFailure())
    }
}
#endif
