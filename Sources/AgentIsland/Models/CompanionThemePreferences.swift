// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

/// Built-in visual directions for the detached companion. These are semantic
/// themes rather than asset names, so the UI can render them with system
/// symbols and native shapes without downloading external artwork.
enum CompanionTheme: String, CaseIterable, Codable, Identifiable {
    case system
    case friendly
    case technical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "系统原生"
        case .friendly: return "友好伙伴"
        case .technical: return "技术终端"
        }
    }

    /// Parses canonical persisted values while accepting casing and whitespace
    /// left by early development builds.
    static func parsePersisted(_ rawValue: String?) -> CompanionTheme? {
        guard let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty else {
            return nil
        }
        return CompanionTheme(rawValue: normalized)
    }

    fileprivate static func parseLegacy(_ rawValue: String?) -> CompanionTheme? {
        if let canonical = parsePersisted(rawValue) { return canonical }
        guard let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return nil
        }
        switch normalized {
        case "classic", "default", "native":
            return .system
        case "warm", "mascot", "playful":
            return .friendly
        case "developer", "minimal", "terminal":
            return .technical
        default:
            return nil
        }
    }
}

/// Theme preferences support one conservative default plus optional family
/// overrides. Keeping the selection separate from SwiftUI makes it replayable
/// in tests and reusable by future companion renderers.
struct CompanionThemePreferences: Equatable {
    var defaultTheme: CompanionTheme = .system
    var familyOverrides: [AgentFamily: CompanionTheme] = [:]

    static let conservativeDefault = CompanionThemePreferences()

    func theme(for family: AgentFamily) -> CompanionTheme {
        familyOverrides[family] ?? defaultTheme
    }

    mutating func setOverride(_ theme: CompanionTheme?, for family: AgentFamily) {
        familyOverrides[family] = theme
    }
}

/// Foundation-only persistence and migration for companion themes.
enum CompanionThemeSettings {
    private static let defaultThemeKey = "agentIsland.companionTheme.default"
    private static let familyOverridesKey = "agentIsland.companionTheme.familyOverrides"
    private static let legacyThemeKey = "agentIsland.companion.theme"

    static var preferences: CompanionThemePreferences {
        get { load(from: .standard) }
        set { save(newValue, to: .standard) }
    }

    static func load(from defaults: UserDefaults) -> CompanionThemePreferences {
        let fallback = CompanionThemePreferences.conservativeDefault
        let persistedDefault = CompanionTheme.parsePersisted(
            defaults.string(forKey: defaultThemeKey)
        )
        let legacyDefault = CompanionTheme.parseLegacy(
            defaults.string(forKey: legacyThemeKey)
        )
        let defaultTheme = persistedDefault ?? legacyDefault ?? fallback.defaultTheme
        let familyOverrides = parseOverrides(
            defaults.dictionary(forKey: familyOverridesKey)
        )
        let preferences = CompanionThemePreferences(
            defaultTheme: defaultTheme,
            familyOverrides: familyOverrides
        )

        // Canonicalize a valid legacy scalar once. Unknown legacy values remain
        // untouched for diagnostic inspection and safely fall back to system.
        if persistedDefault == nil, legacyDefault != nil {
            save(preferences, to: defaults)
            defaults.removeObject(forKey: legacyThemeKey)
        }
        return preferences
    }

    static func save(_ preferences: CompanionThemePreferences, to defaults: UserDefaults) {
        defaults.set(preferences.defaultTheme.rawValue, forKey: defaultThemeKey)
        let overrides = Dictionary(uniqueKeysWithValues: preferences.familyOverrides.map {
            ($0.key.rawValue, $0.value.rawValue)
        })
        defaults.set(overrides, forKey: familyOverridesKey)
    }

    private static func parseOverrides(_ dictionary: [String: Any]?) -> [AgentFamily: CompanionTheme] {
        guard let dictionary else { return [:] }
        var result: [AgentFamily: CompanionTheme] = [:]
        for (familyRawValue, themeValue) in dictionary {
            guard let family = AgentFamily(rawValue: familyRawValue),
                  let themeRawValue = themeValue as? String,
                  let theme = CompanionTheme.parsePersisted(themeRawValue) else {
                continue
            }
            result[family] = theme
        }
        return result
    }
}
