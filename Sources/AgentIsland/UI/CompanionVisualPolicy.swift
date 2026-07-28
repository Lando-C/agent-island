// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

enum CompanionFamilyPalette: String, CaseIterable {
    case codex
    case claude
    case science
    case chatgpt
}

enum CompanionStateTone: String, CaseIterable {
    case neutral
    case active
    case waiting
    case attention
    case success
    case failure
}

enum CompanionMotion: Equatable {
    case none
    case breathe
}

struct CompanionVisualPolicy: Equatable {
    var theme: CompanionTheme
    var familyGlyph: String
    var phaseGlyph: String
    var familyPalette: CompanionFamilyPalette
    var stateTone: CompanionStateTone
    var motion: CompanionMotion
    var identityLabel: String
    var stateLabel: String
    var stateSummary: String

    static func resolve(
        family: AgentFamily,
        surface: AgentSurface,
        phase: AgentPhase,
        theme: CompanionTheme = .system
    ) -> CompanionVisualPolicy {
        let identity: (String, CompanionFamilyPalette)
        switch family {
        case .codex:
            identity = (familyGlyph(.codex, theme: theme), .codex)
        case .claude:
            identity = (familyGlyph(.claude, theme: theme), .claude)
        case .claudeScience:
            identity = (familyGlyph(.claudeScience, theme: theme), .science)
        case .chatgpt:
            identity = (familyGlyph(.chatgpt, theme: theme), .chatgpt)
        }

        let state: (String, CompanionStateTone, CompanionMotion, String)
        switch phase {
        case .needsAttention:
            state = ("hand.raised.fill", .attention, .none, "需要你的决定")
        case .working:
            state = ("waveform", .active, .breathe, "正在执行任务")
        case .thinking:
            state = ("brain.head.profile", .active, .breathe, "正在组织下一步")
        case .queued:
            state = ("clock.fill", .waiting, .none, "等待继续推进")
        case .done:
            state = ("checkmark.circle.fill", .success, .none, "任务已经完成")
        case .error:
            state = ("exclamationmark.triangle.fill", .failure, .none, "运行遇到问题")
        case .online:
            state = ("bolt.fill", .neutral, .none, "Agent 已连接")
        case .idle:
            state = ("moon.fill", .neutral, .none, "等待新任务")
        case .available:
            state = ("shippingbox.fill", .neutral, .none, "Agent 可以使用")
        case .offline:
            state = ("slash.circle.fill", .neutral, .none, "Agent 当前离线")
        }

        return CompanionVisualPolicy(
            theme: theme,
            familyGlyph: identity.0,
            phaseGlyph: state.0,
            familyPalette: identity.1,
            stateTone: state.1,
            motion: state.2,
            identityLabel: "\(family.displayName) · \(surface.displayName)",
            stateLabel: phase.label,
            stateSummary: state.3
        )
    }

    private static func familyGlyph(_ family: AgentFamily, theme: CompanionTheme) -> String {
        switch (theme, family) {
        case (.system, .codex): return "chevron.left.forwardslash.chevron.right"
        case (.system, .claude): return "sparkles"
        case (.system, .claudeScience): return "atom"
        case (.system, .chatgpt): return "bubble.left.and.bubble.right.fill"
        case (.friendly, .codex): return "ladybug.fill"
        case (.friendly, .claude): return "pawprint.fill"
        case (.friendly, .claudeScience): return "bird.fill"
        case (.friendly, .chatgpt): return "hare.fill"
        case (.technical, .codex): return "terminal.fill"
        case (.technical, .claude): return "cpu"
        case (.technical, .claudeScience): return "server.rack"
        case (.technical, .chatgpt): return "network"
        }
    }
}
