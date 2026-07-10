// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import Foundation

enum SmartSuppression {
    static let enabledKey = "agentIsland.behavior.smartSuppression"

    static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func shouldSuppressSpotlight(for snapshot: AgentSnapshot) -> Bool {
        guard isEnabled else { return false }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }

        if let target = snapshot.jumpTarget {
            switch target {
            case .terminal(let terminal):
                return TerminalFocuser.isFrontmost(terminal)
            case .tmux(let tmux):
                return TerminalFocuser.isFrontmost(tmux.terminal)
            case .process(let pid):
                return frontmost.processIdentifier == pid_t(pid)
            case .claudeApp:
                return frontmost.bundleIdentifier == "com.anthropic.claudefordesktop"
                    || frontmost.localizedName?.lowercased() == "claude"
            case .url(let url):
                return url.hasPrefix("codex://") && isCodex(frontmost)
            case .app(let bundleID, _):
                return frontmost.bundleIdentifier == bundleID
            case .chatGPTWeb:
                return isBrowser(frontmost)
            }
        }

        switch (snapshot.family, snapshot.surface) {
        case (.codex, .app): return isCodex(frontmost)
        case (.claude, .app):
            return frontmost.bundleIdentifier == "com.anthropic.claudefordesktop"
                || frontmost.localizedName?.lowercased() == "claude"
        case (.chatgpt, .app):
            return frontmost.localizedName?.lowercased().contains("chatgpt") == true
        default:
            return false
        }
    }

    private static func isCodex(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.openai.codex"
            || app.localizedName?.lowercased().contains("codex") == true
    }

    private static func isBrowser(_ app: NSRunningApplication) -> Bool {
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        return bundle.contains("safari")
            || bundle.contains("chrome")
            || bundle.contains("firefox")
            || bundle.contains("arc")
            || bundle.contains("edge")
    }
}
