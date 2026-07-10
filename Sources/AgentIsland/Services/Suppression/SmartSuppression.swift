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
                return TerminalFocuser.isFrontmost(tmux)
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
                return isChatGPTFrontmostBrowser(frontmost)
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

    private static func isChatGPTFrontmostBrowser(_ app: NSRunningApplication) -> Bool {
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        let script: String
        if bundle.contains("safari") {
            script = """
            tell application id "com.apple.Safari"
                if (count of windows) is 0 then return ""
                return (name of current tab of front window) & linefeed & (URL of current tab of front window)
            end tell
            """
        } else if bundle.contains("chrome") || bundle.contains("arc") || bundle.contains("edge") {
            guard let bundleID = app.bundleIdentifier else { return false }
            script = """
            tell application id "\(bundleID)"
                if (count of windows) is 0 then return ""
                return (title of active tab of front window) & linefeed & (URL of active tab of front window)
            end tell
            """
        } else {
            return false
        }
        var error: NSDictionary?
        let value = NSAppleScript(source: script)?
            .executeAndReturnError(&error)
            .stringValue?
            .lowercased() ?? ""
        guard error == nil else { return false }
        return isChatGPTPage(value)
    }

    static func isChatGPTPage(_ titleAndURL: String) -> Bool {
        let value = titleAndURL.lowercased()
        return value.contains("chatgpt.com")
            || value.contains("chat.openai.com")
            || value.split(separator: "\n").first?.contains("chatgpt") == true
    }
}
