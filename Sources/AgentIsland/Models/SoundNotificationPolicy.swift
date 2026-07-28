// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

enum AgentIslandSoundEvent: String, CaseIterable, Codable {
    case started
    case completed
    case needsAttention
}

enum AgentIslandSoundChoice: String, CaseIterable, Identifiable {
    case submarine = "Submarine"
    case glass = "Glass"
    case basso = "Basso"
    case ping = "Ping"
    case pop = "Pop"

    var id: String { rawValue }
    var label: String { rawValue }
}

struct AgentIslandSoundPreferences: Equatable {
    var enabled = false
    var startedEnabled = false
    var completedEnabled = true
    var needsAttentionEnabled = true
    var quietHoursEnabled = false
    var quietHoursStart = 22
    var quietHoursEnd = 8
    var minimumInterval: TimeInterval = 3
    var repeatedSignalInterval: TimeInterval = 30
    var startedSound: AgentIslandSoundChoice = .submarine
    var completedSound: AgentIslandSoundChoice = .glass
    var needsAttentionSound: AgentIslandSoundChoice = .basso

    static let conservativeDefault = AgentIslandSoundPreferences()

    func isEnabled(for event: AgentIslandSoundEvent) -> Bool {
        switch event {
        case .started: return startedEnabled
        case .completed: return completedEnabled
        case .needsAttention: return needsAttentionEnabled
        }
    }

    func sound(for event: AgentIslandSoundEvent) -> AgentIslandSoundChoice {
        switch event {
        case .started: return startedSound
        case .completed: return completedSound
        case .needsAttention: return needsAttentionSound
        }
    }
}

enum SoundNotificationDecision: Equatable {
    case play
    case disabled
    case eventDisabled
    case quietHours
    case throttled
}

/// Pure decision policy shared by sound playback and its tests.
struct SoundNotificationPolicy {
    static func decision(
        for event: AgentIslandSoundEvent,
        preferences: AgentIslandSoundPreferences,
        at date: Date,
        lastPlayedAt: Date?,
        lastSignalPlayedAt: Date?,
        calendar: Calendar = .current
    ) -> SoundNotificationDecision {
        guard preferences.enabled else { return .disabled }
        guard preferences.isEnabled(for: event) else { return .eventDisabled }
        guard !isInsideQuietHours(date, preferences: preferences, calendar: calendar) else {
            return .quietHours
        }
        if let lastPlayedAt {
            let elapsed = date.timeIntervalSince(lastPlayedAt)
            if elapsed >= 0, elapsed < max(0, preferences.minimumInterval) {
                return .throttled
            }
        }
        if let lastSignalPlayedAt {
            let elapsed = date.timeIntervalSince(lastSignalPlayedAt)
            if elapsed >= 0, elapsed < max(0, preferences.repeatedSignalInterval) {
                return .throttled
            }
        }
        return .play
    }

    static func isInsideQuietHours(
        _ date: Date,
        preferences: AgentIslandSoundPreferences,
        calendar: Calendar = .current
    ) -> Bool {
        guard preferences.quietHoursEnabled else { return false }
        let start = normalizedHour(preferences.quietHoursStart)
        let end = normalizedHour(preferences.quietHoursEnd)
        let hour = calendar.component(.hour, from: date)
        if start == end { return true }
        if start < end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }

    private static func normalizedHour(_ value: Int) -> Int {
        min(23, max(0, value))
    }
}
