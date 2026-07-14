// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import Foundation

enum AgentIslandSoundEvent {
    case started
    case completed
    case needsAttention
}

enum AgentIslandSoundSettings {
    private static let enabledKey = "agentIsland.sound.enabled"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

final class SoundManager {
    static let shared = SoundManager()

    private var lastPlayed: [String: Date] = [:]

    func play(_ event: AgentIslandSoundEvent, key: String) {
        guard AgentIslandSoundSettings.enabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPlayed[key] ?? .distantPast) >= 1 else { return }
        lastPlayed[key] = now
        let name: NSSound.Name
        switch event {
        case .started: name = .init("Submarine")
        case .completed: name = .init("Glass")
        case .needsAttention: name = .init("Basso")
        }
        NSSound(named: name)?.play()
    }
}
