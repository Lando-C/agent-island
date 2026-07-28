// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import Foundation

enum AgentIslandSoundSettings {
    private static let enabledKey = "agentIsland.sound.enabled"
    private static let startedEnabledKey = "agentIsland.sound.startedEnabled"
    private static let completedEnabledKey = "agentIsland.sound.completedEnabled"
    private static let needsAttentionEnabledKey = "agentIsland.sound.needsAttentionEnabled"
    private static let quietHoursEnabledKey = "agentIsland.sound.quietHours.enabled"
    private static let quietHoursStartKey = "agentIsland.sound.quietHours.start"
    private static let quietHoursEndKey = "agentIsland.sound.quietHours.end"
    private static let minimumIntervalKey = "agentIsland.sound.minimumInterval"
    private static let repeatedSignalIntervalKey = "agentIsland.sound.repeatedSignalInterval"
    private static let startedSoundKey = "agentIsland.sound.startedSound"
    private static let completedSoundKey = "agentIsland.sound.completedSound"
    private static let needsAttentionSoundKey = "agentIsland.sound.needsAttentionSound"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var preferences: AgentIslandSoundPreferences {
        get { load(from: .standard) }
        set { save(newValue, to: .standard) }
    }

    static func load(from defaults: UserDefaults) -> AgentIslandSoundPreferences {
        let fallback = AgentIslandSoundPreferences.conservativeDefault
        return AgentIslandSoundPreferences(
            enabled: defaults.object(forKey: enabledKey) == nil
                ? fallback.enabled
                : defaults.bool(forKey: enabledKey),
            startedEnabled: bool(startedEnabledKey, from: defaults, fallback: fallback.startedEnabled),
            completedEnabled: bool(completedEnabledKey, from: defaults, fallback: fallback.completedEnabled),
            needsAttentionEnabled: bool(
                needsAttentionEnabledKey,
                from: defaults,
                fallback: fallback.needsAttentionEnabled
            ),
            quietHoursEnabled: bool(
                quietHoursEnabledKey,
                from: defaults,
                fallback: fallback.quietHoursEnabled
            ),
            quietHoursStart: hour(
                quietHoursStartKey,
                from: defaults,
                fallback: fallback.quietHoursStart
            ),
            quietHoursEnd: hour(
                quietHoursEndKey,
                from: defaults,
                fallback: fallback.quietHoursEnd
            ),
            minimumInterval: minimumInterval(
                minimumIntervalKey,
                from: defaults,
                fallback: fallback.minimumInterval
            ),
            repeatedSignalInterval: nonnegativeInterval(
                repeatedSignalIntervalKey,
                from: defaults,
                fallback: fallback.repeatedSignalInterval
            ),
            startedSound: sound(startedSoundKey, from: defaults, fallback: fallback.startedSound),
            completedSound: sound(completedSoundKey, from: defaults, fallback: fallback.completedSound),
            needsAttentionSound: sound(
                needsAttentionSoundKey,
                from: defaults,
                fallback: fallback.needsAttentionSound
            )
        )
    }

    static func save(_ preferences: AgentIslandSoundPreferences, to defaults: UserDefaults) {
        defaults.set(preferences.enabled, forKey: enabledKey)
        defaults.set(preferences.startedEnabled, forKey: startedEnabledKey)
        defaults.set(preferences.completedEnabled, forKey: completedEnabledKey)
        defaults.set(preferences.needsAttentionEnabled, forKey: needsAttentionEnabledKey)
        defaults.set(preferences.quietHoursEnabled, forKey: quietHoursEnabledKey)
        defaults.set(preferences.quietHoursStart, forKey: quietHoursStartKey)
        defaults.set(preferences.quietHoursEnd, forKey: quietHoursEndKey)
        defaults.set(max(0, preferences.minimumInterval), forKey: minimumIntervalKey)
        defaults.set(max(0, preferences.repeatedSignalInterval), forKey: repeatedSignalIntervalKey)
        defaults.set(preferences.startedSound.rawValue, forKey: startedSoundKey)
        defaults.set(preferences.completedSound.rawValue, forKey: completedSoundKey)
        defaults.set(preferences.needsAttentionSound.rawValue, forKey: needsAttentionSoundKey)
    }

    private static func bool(_ key: String, from defaults: UserDefaults, fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func hour(_ key: String, from defaults: UserDefaults, fallback: Int) -> Int {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return min(23, max(0, defaults.integer(forKey: key)))
    }

    private static func minimumInterval(
        _ key: String,
        from defaults: UserDefaults,
        fallback: TimeInterval
    ) -> TimeInterval {
        guard defaults.object(forKey: key) != nil else { return fallback }
        let value = defaults.double(forKey: key)
        return [1, 3, 5, 10].contains(value) ? value : fallback
    }

    private static func nonnegativeInterval(
        _ key: String,
        from defaults: UserDefaults,
        fallback: TimeInterval
    ) -> TimeInterval {
        guard defaults.object(forKey: key) != nil else { return fallback }
        let value = defaults.double(forKey: key)
        return value.isFinite && value >= 0 ? value : fallback
    }

    private static func sound(
        _ key: String,
        from defaults: UserDefaults,
        fallback: AgentIslandSoundChoice
    ) -> AgentIslandSoundChoice {
        guard let raw = defaults.string(forKey: key),
              let value = AgentIslandSoundChoice(rawValue: raw) else {
            return fallback
        }
        return value
    }
}

final class SoundManager {
    static let shared = SoundManager()

    private var lastPlayedAt: Date?
    private var lastSignalPlayedAt: [String: Date] = [:]

    func play(_ event: AgentIslandSoundEvent, key: String) {
        let now = Date()
        let preferences = AgentIslandSoundSettings.preferences
        guard SoundNotificationPolicy.decision(
            for: event,
            preferences: preferences,
            at: now,
            lastPlayedAt: lastPlayedAt,
            lastSignalPlayedAt: lastSignalPlayedAt[key]
        ) == .play else { return }
        lastPlayedAt = now
        lastSignalPlayedAt[key] = now
        pruneSignalHistory(before: now.addingTimeInterval(-86_400))
        NSSound(named: .init(preferences.sound(for: event).rawValue))?.play()
    }

    private func pruneSignalHistory(before cutoff: Date) {
        guard lastSignalPlayedAt.count > 256 else { return }
        lastSignalPlayedAt = lastSignalPlayedAt.filter { $0.value >= cutoff }
    }
}
