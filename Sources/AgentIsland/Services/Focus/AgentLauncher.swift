// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import Foundation

enum AgentLauncher {
    static func focus(_ snapshot: AgentSnapshot) {
        islandLog("focus requested \(snapshot.id) pid=\(snapshot.targetPID.map(String.init) ?? "none")")
        if let jumpTarget = snapshot.jumpTarget, focus(jumpTarget) {
            return
        }

        switch snapshot.surface {
        case .app:
            if focusAppWindow(snapshot) {
                return
            }
            if focusHostProcess(startingAt: snapshot.targetPID) {
                return
            }
            focusApp(snapshot.family)
        case .cli:
            if focusHostProcess(startingAt: snapshot.targetPID) {
                return
            }
            if focusFirstRunningBundle(terminalBundleIDs) {
                return
            }
            focusApp(snapshot.family)
        case .runtime:
            if focusHostProcess(startingAt: snapshot.targetPID) {
                return
            }
            focusApp(snapshot.family)
        case .web:
            if snapshot.family == .chatgpt, focusChatGPTWeb() {
                return
            }
            if focusHostProcess(startingAt: snapshot.targetPID) {
                return
            }
            if focusFirstRunningBundle(browserBundleIDs) {
                return
            }
            if !focusBundle("com.openai.chat") {
                openBundle("com.openai.chat", fallbackPath: "/Applications/ChatGPT Classic.app")
            }
        }
    }

    private static func focus(_ target: JumpTarget) -> Bool {
        switch target {
        case .url(let rawURL):
            guard let url = URL(string: rawURL) else { return false }
            let opened = NSWorkspace.shared.open(url)
            if opened {
                islandLog("opened jump url=\(rawURL)")
            }
            return opened
        case .process(let pid):
            return focusHostProcess(startingAt: pid)
        case .terminal(let target):
            return TerminalFocuser.focus(target)
        case .tmux(let target):
            return TerminalFocuser.focus(target)
        case .claudeApp(let target):
            return ClaudeAppFocuser.focus(target)
        case .app(let bundleID, let fallbackPath):
            if focusBundle(bundleID) {
                return true
            }
            if let fallbackPath {
                openBundle(bundleID, fallbackPath: fallbackPath)
                return true
            }
            return false
        case .chatGPTWeb:
            return focusChatGPTWeb()
        }
    }

    private static func focusChatGPTWeb() -> Bool {
        let browsers = [
            ("Google Chrome", "com.google.Chrome", false),
            ("Safari", "com.apple.Safari", true),
            ("Microsoft Edge", "com.microsoft.edgemac", false),
            ("Brave Browser", "com.brave.Browser", false),
            ("Arc", "company.thebrowser.Browser", false)
        ]

        for (appName, bundleID, safari) in browsers {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
                continue
            }
            let script = safari
                ? safariFocusScript(appName: appName)
                : chromiumFocusScript(appName: appName)
            let result = runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
            if result == "focused" {
                islandLog("focused ChatGPT web app=\(appName)")
                return true
            }
        }

        return false
    }

    private static func chromiumFocusScript(appName: String) -> String {
        """
        tell application "\(appName)"
            if not running then return ""
            repeat with wi from 1 to count of windows
                repeat with ti from 1 to count of tabs of window wi
                    set tabURL to URL of tab ti of window wi as text
                    if tabURL contains "://chatgpt.com" or tabURL contains "://www.chatgpt.com" or tabURL contains "://chat.openai.com" then
                        set active tab index of window wi to ti
                        set index of window wi to 1
                        activate
                        return "focused"
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
    }

    private static func safariFocusScript(appName: String) -> String {
        """
        tell application "\(appName)"
            if not running then return ""
            repeat with wi from 1 to count of windows
                repeat with ti from 1 to count of tabs of window wi
                    set tabURL to URL of tab ti of window wi as text
                    if tabURL contains "://chatgpt.com" or tabURL contains "://www.chatgpt.com" or tabURL contains "://chat.openai.com" then
                        set current tab of window wi to tab ti of window wi
                        set index of window wi to 1
                        activate
                        return "focused"
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
    }

    private static let terminalBundleIDs = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm"
    ]

    private static let browserBundleIDs = [
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser"
    ]

    private static func focusApp(_ family: AgentFamily) {
        switch family {
        case .codex:
            if !focusBundle("com.openai.codex") {
                openBundle("com.openai.codex", fallbackPath: "/Applications/ChatGPT.app")
            }
        case .claude:
            if !focusBundle("com.anthropic.claudefordesktop") {
                openBundle("com.anthropic.claudefordesktop", fallbackPath: "/Applications/Claude.app")
            }
        case .claudeScience:
            if !focusBundle("com.anthropic.operon") {
                openBundle("com.anthropic.operon", fallbackPath: "/Applications/Claude Science.app")
            }
        case .chatgpt:
            if !focusBundle("com.openai.chat") {
                openBundle("com.openai.chat", fallbackPath: "/Applications/ChatGPT Classic.app")
            }
        }
    }

    private static func focusAppWindow(_ snapshot: AgentSnapshot) -> Bool {
        let appName: String
        switch snapshot.family {
        case .codex:
            appName = "Codex"
        case .claude:
            appName = "Claude"
        case .claudeScience:
            appName = "Claude Science"
        case .chatgpt:
            appName = "ChatGPT"
        }

        let hints = windowTitleHints(for: snapshot)
        guard !hints.isEmpty else { return false }
        let hintList = hints.map(appleScriptStringLiteral).joined(separator: ", ")
        let script = """
        tell application "System Events"
            if not (exists process "\(appName)") then return ""
            tell process "\(appName)"
                set candidates to {\(hintList)}
                repeat with h in candidates
                    repeat with w in windows
                        set windowName to name of w as text
                        if h is not "" and windowName contains (h as text) then
                            perform action "AXRaise" of w
                            set frontmost to true
                            return "focused"
                        end if
                    end repeat
                end repeat
            end tell
        end tell
        return ""
        """
        if runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines) == "focused" {
            islandLog("focused app window family=\(snapshot.family.rawValue) session=\(snapshot.sessionID ?? "none")")
            return true
        }
        return false
    }

    private static func windowTitleHints(for snapshot: AgentSnapshot) -> [String] {
        var hints: [String] = []
        let marker = "\(snapshot.family.displayName) \(snapshot.surface.displayName) · "
        if snapshot.title.hasPrefix(marker) {
            let title = String(snapshot.title.dropFirst(marker.count))
            appendWindowHint(title, to: &hints)
        } else if snapshot.title != "\(snapshot.family.displayName) \(snapshot.surface.displayName)" {
            appendWindowHint(snapshot.title, to: &hints)
        }
        if let session = snapshot.sessionID, !session.isEmpty {
            appendWindowHint(String(session.prefix(8)), to: &hints)
        }
        return hints.sorted { $0.count > $1.count }
    }

    private static func appendWindowHint(_ raw: String, to hints: inout [String]) {
        let cleaned = AgentText.singleLine(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "…", with: "")
        guard cleaned.count >= 3 else { return }
        guard cleaned != "未命名对话" else { return }
        guard !AgentText.isInternalTaskText(cleaned) else { return }
        guard !hints.contains(cleaned) else { return }
        hints.append(cleaned)
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func focusHostProcess(startingAt pid: Int?) -> Bool {
        guard var current = pid else { return false }
        var visited = Set<Int>()

        for _ in 0..<14 {
            guard current > 1, !visited.contains(current) else { break }
            visited.insert(current)

            if let app = NSRunningApplication(processIdentifier: pid_t(current)),
               canActivate(app),
               activate(app) {
                islandLog("focused host pid=\(current) name=\(app.localizedName ?? "unknown")")
                return true
            }

            guard let parent = parentPID(of: current), parent != current else { break }
            current = parent
        }

        return false
    }

    private static func parentPID(of pid: Int) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "ppid=", "-p", "\(pid)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func focusFirstRunningBundle(_ bundleIDs: [String]) -> Bool {
        for bundleID in bundleIDs where focusBundle(bundleID) {
            return true
        }
        return false
    }

    private static func focusBundle(_ bundleID: String) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in apps where canActivate(app) {
            if activate(app) {
                islandLog("focused bundle=\(bundleID)")
                return true
            }
        }
        return false
    }

    private static func canActivate(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated else { return false }
        if let ownBundle = Bundle.main.bundleIdentifier,
           app.bundleIdentifier == ownBundle {
            return false
        }
        return app.activationPolicy == .regular
    }

    private static func activate(_ app: NSRunningApplication) -> Bool {
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private static func openBundle(_ bundleID: String, fallbackPath: String) {
        let workspace = NSWorkspace.shared
        let url = workspace.urlForApplication(withBundleIdentifier: bundleID)
            ?? URL(fileURLWithPath: fallbackPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            islandLog("open bundle failed missing url bundle=\(bundleID) path=\(url.path)")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        workspace.openApplication(at: url, configuration: config) { app, error in
            if let error {
                islandLog("open bundle failed bundle=\(bundleID) error=\(error.localizedDescription)")
            } else if let app {
                islandLog("opened bundle=\(bundleID) pid=\(app.processIdentifier)")
            }
        }
    }

    private static func runAppleScript(_ source: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { ["-e", String($0)] }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
