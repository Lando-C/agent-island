// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import Foundation

enum TerminalFocuser {
    static func isFrontmost(_ target: TerminalJumpTarget) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        let pidMatches = target.pid.map { frontmost.processIdentifier == pid_t($0) } == true
        let bundleMatches = target.bundleID.map { frontmost.bundleIdentifier == $0 } == true
        let expected = bundleID(for: normalizedAppName(target.appName))
        let expectedBundleMatches = expected.map { frontmost.bundleIdentifier == $0 } == true
        let expectedName = normalizedAppName(target.appName)?.lowercased()
        let currentName = normalizedAppName(frontmost.localizedName)?.lowercased()
        let nameMatches = expectedName != nil && expectedName == currentName
        guard pidMatches || bundleMatches || expectedBundleMatches || nameMatches else { return false }

        let normalizedName = normalizedAppName(target.appName ?? frontmost.localizedName)
        if let tty = normalizedTTY(target.tty) {
            switch normalizedName {
            case "iTerm2":
                return ttyMatches(currentITermTTY(), target: tty)
            case "Terminal":
                return ttyMatches(currentTerminalTTY(), target: tty)
            case "WezTerm":
                return ttyMatches(currentWezTermTTY(), target: tty)
            default:
                break
            }
        }
        if normalizedName == "cmux", target.windowID != nil {
            return isCmuxTargetFrontmost(target)
        }
        // App activation proves only that a terminal is frontmost. When an
        // event carries a pane/tab/TTY/CWD identity, suppressing an alert would
        // be unsafe unless this terminal exposes a way to verify that identity.
        return canConfirmAppOnlyForeground(target)
    }

    static func canConfirmAppOnlyForeground(_ target: TerminalJumpTarget) -> Bool {
        [target.tty, target.cwd, target.windowID, target.tabIndex, target.sessionIdentifier, target.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .allSatisfy(\.isEmpty)
    }

    static func isFrontmost(_ target: TmuxJumpTarget) -> Bool {
        guard isFrontmost(target.terminal) else { return false }
        guard let pane = target.pane?.trimmingCharacters(in: .whitespacesAndNewlines),
              isValidTmuxPane(pane) else { return true }
        guard let client = target.client, isValidTmuxClient(client),
              let tmux = tmuxExecutableURL() else { return false }
        let current = tmuxOutput(
            tmux,
            arguments: tmuxArguments(socket: target.socket, command: ["display-message", "-p", "-t", client, "#{pane_id}"])
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return !current.isEmpty && current == pane
    }

    static func focus(_ target: TerminalJumpTarget) -> Bool {
        let outcome = focusOutcome(target)
        record(outcome: outcome, target: target)
        return outcome.success
    }

    private static func focusOutcome(_ target: TerminalJumpTarget) -> FocusOutcome {
        let normalizedName = normalizedAppName(target.appName)

        if normalizedName == "WezTerm",
           let pane = target.sessionIdentifier ?? target.windowID,
           focusWezTermPane(pane) {
            return FocusOutcome(success: activate(target), route: "WezTerm exact pane")
        }

        if normalizedName == "WezTerm",
           focusWezTermByContext(target) {
            return FocusOutcome(success: activate(target), route: "WezTerm TTY/CWD pane")
        }

        if normalizedName == "kitty",
           let window = target.windowID ?? target.sessionIdentifier,
           focusKittyWindow(window) {
            return FocusOutcome(success: activate(target), route: "kitty exact window")
        }

        if normalizedName == "kitty",
           focusKittyByCWD(target.cwd) {
            return FocusOutcome(success: activate(target), route: "kitty CWD match")
        }

        if normalizedName == "Ghostty",
           focusGhostty(target) {
            return FocusOutcome(success: true, route: "Ghostty accessibility/TTY")
        }

        if normalizedName == "cmux",
           focusCmux(target) {
            return FocusOutcome(success: true, route: "cmux tab/terminal")
        }

        if normalizedName == "iTerm2" {
            if focusITerm(target) {
                return FocusOutcome(success: true, route: "iTerm2 session/TTY")
            }
            return FocusOutcome(success: activate(target), route: "iTerm2 app fallback")
        }

        if normalizedName == "Terminal" {
            if focusTerminalApp(target) {
                return FocusOutcome(success: true, route: "Terminal TTY")
            }
            return FocusOutcome(success: activate(target), route: "Terminal app fallback")
        }

        if focusByBundleOrName(target) {
            return FocusOutcome(success: true, route: "application activation fallback")
        }

        if let pid = target.pid {
            return FocusOutcome(success: activateProcess(pid), route: "process activation fallback")
        }

        return FocusOutcome(success: false, route: "no compatible target")
    }

    static func focus(_ target: TmuxJumpTarget) -> Bool {
        let terminalFocused = focus(target.terminal)
        let tmuxFocused = switchTmuxPane(target)
        let success = tmuxFocused || terminalFocused
        let detail = tmuxFocused ? "tmux exact pane" : "tmux fallback terminal"
        record(outcome: FocusOutcome(success: success, route: detail), target: target.terminal)
        return success
    }

    private struct FocusOutcome {
        var success: Bool
        var route: String
    }

    private static func record(outcome: FocusOutcome, target: TerminalJumpTarget) {
        let name = normalizedAppName(target.appName) ?? target.bundleID ?? "unknown terminal"
        let endpoint = [name, target.tty, target.cwd].compactMap { $0 }.joined(separator: " | ")
        if outcome.success {
            TransportHealthStore.shared.markConnected(
                id: TransportHealthStore.terminalFocusID,
                name: "Terminal Focus Matrix",
                protocolVersion: outcome.route,
                endpoint: endpoint,
                event: true
            )
        } else {
            TransportHealthStore.shared.markFailure(
                id: TransportHealthStore.terminalFocusID,
                name: "Terminal Focus Matrix",
                state: .degraded,
                endpoint: endpoint,
                error: outcome.route
            )
        }
    }

    private static func focusITerm(_ target: TerminalJumpTarget) -> Bool {
        // Exact window/tab targeting follows DevIsland's MIT-licensed focuser strategy.
        let ttyPath = normalizedTTY(target.tty)
        let ttyName = ttyPath?.components(separatedBy: "/").last ?? ""
        let sessionID = target.sessionIdentifier ?? ""
        let title = target.title ?? ""
        let windowID = target.windowID ?? ""
        let tabIndex = target.tabIndex ?? ""
        let script = """
        tell application id "com.googlecode.iterm2"
            activate
            set targetTTY to \(appleScriptLiteral(ttyPath ?? ""))
            set targetTTYName to \(appleScriptLiteral(ttyName))
            set targetSessionID to \(appleScriptLiteral(sessionID))
            set targetTitle to \(appleScriptLiteral(title))
            set targetWindowID to \(appleScriptLiteral(windowID))
            set targetTabIndex to \(appleScriptLiteral(tabIndex))
            if targetWindowID is not "" and targetTabIndex is not "" then
                try
                    repeat with aWindow in windows
                        if (id of aWindow as text) is targetWindowID then
                            set aTab to tab (targetTabIndex as integer) of aWindow
                            repeat with aSession in sessions of aTab
                                set sessionTTY to ""
                                set sessionIDText to ""
                                try
                                    set sessionTTY to tty of aSession
                                end try
                                try
                                    set sessionIDText to id of aSession as text
                                end try
                                if (targetSessionID is not "" and sessionIDText is targetSessionID) or (targetTTY is not "" and (sessionTTY is targetTTY or sessionTTY is targetTTYName)) then
                                    select aWindow
                                    select aTab
                                    select aSession
                                    activate
                                    return "focused"
                                end if
                            end repeat
                        end if
                    end repeat
                end try
            end if
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        set sessionTTY to ""
                        set sessionName to ""
                        set sessionIDText to ""
                        try
                            set sessionTTY to tty of aSession
                        end try
                        try
                            set sessionName to name of aSession
                        end try
                        try
                            set sessionIDText to id of aSession as text
                        end try
                        if (targetSessionID is not "" and sessionIDText is targetSessionID) or (targetTTY is not "" and (sessionTTY is targetTTY or sessionTTY is targetTTYName)) or (targetTitle is not "" and sessionName is targetTitle) then
                            select aWindow
                            select aTab
                            select aSession
                            activate
                            return "focused"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return ""
        """
        return runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines) == "focused"
    }

    private static func focusTerminalApp(_ target: TerminalJumpTarget) -> Bool {
        let ttyPath = normalizedTTY(target.tty)
        let ttyName = ttyPath?.components(separatedBy: "/").last ?? ""
        let title = target.title ?? ""
        let windowID = target.windowID ?? ""
        let tabIndex = target.tabIndex ?? ""
        let script = """
        tell application id "com.apple.Terminal"
            set targetTTY to \(appleScriptLiteral(ttyPath ?? ""))
            set targetTTYName to \(appleScriptLiteral(ttyName))
            set targetTitle to \(appleScriptLiteral(title))
            set targetWindowID to \(appleScriptLiteral(windowID))
            set targetTabIndex to \(appleScriptLiteral(tabIndex))
            if targetWindowID is not "" and targetTabIndex is not "" then
                try
                    repeat with aWindow in windows
                        if (id of aWindow as text) is targetWindowID then
                            set targetTab to tab (targetTabIndex as integer) of aWindow
                            set selected tab of aWindow to targetTab
                            set selected of targetTab to true
                            set index of aWindow to 1
                            activate
                            return "focused"
                        end if
                    end repeat
                end try
            end if
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    set tabTTY to ""
                    set tabTitle to ""
                    try
                        set tabTTY to tty of aTab
                    end try
                    try
                        set tabTitle to custom title of aTab
                    end try
                    if (targetTTY is not "" and (tabTTY is targetTTY or tabTTY is targetTTYName)) or (targetTitle is not "" and tabTitle is targetTitle) then
                        set selected tab of aWindow to aTab
                        set selected of aTab to true
                        set index of aWindow to 1
                        activate
                        return "focused"
                    end if
                end repeat
            end repeat
            activate
        end tell
        return ""
        """
        return runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines) == "focused"
    }

    private static func switchTmuxPane(_ target: TmuxJumpTarget) -> Bool {
        guard let pane = target.pane?.trimmingCharacters(in: .whitespacesAndNewlines),
              isValidTmuxPane(pane),
              let tmux = tmuxExecutableURL() else {
            return false
        }

        var ok = false
        if runProcess(tmux, arguments: tmuxArguments(socket: target.socket, command: ["select-window", "-t", pane])) {
            ok = true
        }
        if runProcess(tmux, arguments: tmuxArguments(socket: target.socket, command: ["select-pane", "-t", pane])) {
            ok = true
        }

        if let client = target.client,
           isValidTmuxClient(client) {
            let session = tmuxOutput(tmux, arguments: tmuxArguments(socket: target.socket, command: ["display-message", "-p", "-t", pane, "#{session_id}"]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = session.isEmpty ? pane : session
            if runProcess(tmux, arguments: tmuxArguments(socket: target.socket, command: ["switch-client", "-c", client, "-t", destination])) {
                ok = true
            }
        }

        if ok {
            islandLog("focused tmux pane=\(pane) socket=\(target.socket ?? "nil") client=\(target.client ?? "nil")")
        }
        return ok
    }

    private static func focusWezTermPane(_ pane: String) -> Bool {
        guard !pane.isEmpty, let cli = wezTermCLIURL() else { return false }
        for environment in wezTermEnvironments() {
            let list = processOutput(cli, arguments: ["cli", "list", "--format", "json"], environment: environment)
            guard wezTermPaneExists(pane, in: list) else { continue }
            if runProcess(cli, arguments: ["cli", "activate-pane", "--pane-id", pane], environment: environment) {
                return true
            }
        }
        return false
    }

    private static func focusWezTermByContext(_ target: TerminalJumpTarget) -> Bool {
        guard let cli = wezTermCLIURL(),
              let paneID = wezTermPaneID(cli: cli, tty: normalizedTTY(target.tty), cwd: target.cwd) else {
            return false
        }
        for environment in wezTermEnvironments() {
            let list = processOutput(cli, arguments: ["cli", "list", "--format", "json"], environment: environment)
            guard wezTermPaneExists(paneID, in: list) else { continue }
            if runProcess(cli, arguments: ["cli", "activate-pane", "--pane-id", paneID], environment: environment) {
                return true
            }
        }
        return false
    }

    private static func focusKittyWindow(_ window: String) -> Bool {
        guard !window.isEmpty, let kitten = executable(named: "kitten") ?? executable(named: "kitty") else { return false }
        return runProcess(kitten, arguments: ["@", "focus-window", "--match", "id:\(window)"])
    }

    private static func focusKittyByCWD(_ cwd: String?) -> Bool {
        guard let cwd, !cwd.isEmpty,
              let kitten = executable(named: "kitten") ?? executable(named: "kitty") else {
            return false
        }
        return runProcess(kitten, arguments: ["@", "focus-window", "--match", "cwd:\(cwd)"])
    }

    private static func focusGhostty(_ target: TerminalJumpTarget) -> Bool {
        let cwd = target.cwd ?? ""
        let title = target.title ?? ""
        let script = """
        tell application "Ghostty"
            set targetCWD to \(appleScriptLiteral(cwd))
            set targetTitle to \(appleScriptLiteral(title))
            try
                if targetCWD is not "" then
                    set cwdMatches to every terminal whose working directory contains targetCWD
                    if (count of cwdMatches) > 0 then
                        focus (item 1 of cwdMatches)
                        activate
                        return "focused"
                    end if
                end if
            end try
            try
                if targetTitle is not "" then
                    set titleMatches to every terminal whose title contains targetTitle
                    if (count of titleMatches) > 0 then
                        focus (item 1 of titleMatches)
                        activate
                        return "focused"
                    end if
                end if
            end try
            activate
        end tell
        return ""
        """
        return runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines) == "focused"
    }

    private static func focusCmux(_ target: TerminalJumpTarget) -> Bool {
        let tabID = target.windowID ?? ""
        let terminalID = target.tabIndex ?? target.sessionIdentifier ?? ""
        guard !tabID.isEmpty else { return false }
        let script = """
        tell application "cmux"
            activate
            set wantedTabId to \(appleScriptLiteral(tabID))
            set wantedTermId to \(appleScriptLiteral(terminalID))
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    if (id of aTab as text) is wantedTabId then
                        activate window aWindow
                        select tab aTab
                        if wantedTermId is not "" then
                            repeat with aTerm in terminals of aTab
                                if (id of aTerm as text) is wantedTermId then
                                    focus aTerm
                                    delay 0.05
                                    activate window aWindow
                                    activate
                                    return "focused"
                                end if
                            end repeat
                        end if
                        return "focused"
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        return runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines) == "focused"
    }

    private static func currentITermTTY() -> String? {
        let output = runAppleScript("""
        tell application id "com.googlecode.iterm2"
            if (count of windows) is 0 then return ""
            return tty of current session of current window
        end tell
        """)
        return normalizedTTY(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func currentTerminalTTY() -> String? {
        let output = runAppleScript("""
        tell application id "com.apple.Terminal"
            if (count of windows) is 0 then return ""
            return tty of selected tab of front window
        end tell
        """)
        return normalizedTTY(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func currentWezTermTTY() -> String? {
        guard let cli = wezTermCLIURL() else { return nil }
        for environment in wezTermEnvironments() {
            let output = processOutput(cli, arguments: ["cli", "list", "--format", "json"], environment: environment)
            guard let data = output.data(using: .utf8),
                  let panes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let active = panes.first(where: { $0["is_active"] as? Bool == true }),
                  let tty = active["tty_name"] as? String else { continue }
            return normalizedTTY(tty)
        }
        return nil
    }

    private static func isCmuxTargetFrontmost(_ target: TerminalJumpTarget) -> Bool {
        let tabID = target.windowID ?? ""
        let terminalID = target.tabIndex ?? target.sessionIdentifier ?? ""
        let output = runAppleScript("""
        tell application "cmux"
            if (count of windows) is 0 then return "false"
            set selectedTab to selected tab of front window
            if \(appleScriptLiteral(tabID)) is not "" and (id of selectedTab as text) is not \(appleScriptLiteral(tabID)) then return "false"
            if \(appleScriptLiteral(terminalID)) is not "" then
                if (id of focused terminal of selectedTab as text) is not \(appleScriptLiteral(terminalID)) then return "false"
            end if
            return "true"
        end tell
        """)
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    private static func ttyMatches(_ current: String?, target: String) -> Bool {
        guard let current else { return false }
        return current == target || current.components(separatedBy: "/").last == target.components(separatedBy: "/").last
    }

    private static func focusByBundleOrName(_ target: TerminalJumpTarget) -> Bool {
        if let bundleID = target.bundleID, activateBundle(bundleID) {
            return true
        }

        if let bundleID = bundleID(for: normalizedAppName(target.appName)), activateBundle(bundleID) {
            return true
        }

        if let appName = appActivationName(for: normalizedAppName(target.appName)),
           runProcess(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", appName]) {
            islandLog("focused terminal app=\(appName)")
            return true
        }

        return false
    }

    private static func activate(_ target: TerminalJumpTarget) -> Bool {
        focusByBundleOrName(target) || target.pid.map(activateProcess) == true
    }

    private static func activateProcess(_ pid: Int) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid_t(pid)),
              !app.isTerminated,
              app.activationPolicy == .regular else {
            return false
        }
        return app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private static func activateBundle(_ bundleID: String) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in apps where !app.isTerminated && app.activationPolicy == .regular {
            if app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) {
                islandLog("focused terminal bundle=\(bundleID)")
                return true
            }
        }
        return false
    }

    private static func normalizedAppName(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let lower = value.lowercased()
        if lower.contains("iterm") { return "iTerm2" }
        if lower.contains("apple_terminal") || lower == "terminal" || lower.contains("terminal.app") { return "Terminal" }
        if lower.contains("ghostty") { return "Ghostty" }
        if lower.contains("wezterm") || lower.contains("wez") { return "WezTerm" }
        if lower.contains("kitty") { return "kitty" }
        if lower.contains("kaku") { return "Kaku" }
        if lower.contains("cmux") { return "cmux" }
        if lower.contains("warp") { return "Warp" }
        if lower.contains("wave") { return "Wave" }
        if lower.contains("alacritty") { return "Alacritty" }
        return value
    }

    private static func bundleID(for appName: String?) -> String? {
        switch appName {
        case "iTerm2": return "com.googlecode.iterm2"
        case "Terminal": return "com.apple.Terminal"
        case "Ghostty": return "com.mitchellh.ghostty"
        case "WezTerm": return "com.github.wez.wezterm"
        case "Warp": return "dev.warp.Warp-Stable"
        case "kitty": return "net.kovidgoyal.kitty"
        case "cmux": return "com.cmuxterm.app"
        default: return nil
        }
    }

    private static func appActivationName(for appName: String?) -> String? {
        switch appName {
        case "iTerm2": return "iTerm"
        case "Terminal": return "Terminal"
        case "Ghostty": return "Ghostty"
        case "WezTerm": return "WezTerm"
        case "Warp": return "Warp"
        case "kitty": return "kitty"
        case "cmux": return "cmux"
        case "Kaku": return "Kaku"
        case "Alacritty": return "Alacritty"
        default: return appName
        }
    }

    private static func normalizedTTY(_ tty: String?) -> String? {
        guard let tty = tty?.trimmingCharacters(in: .whitespacesAndNewlines), !tty.isEmpty else {
            return nil
        }
        if tty.hasPrefix("/dev/") { return tty }
        if tty.hasPrefix("tty") { return "/dev/\(tty)" }
        return "/dev/tty\(tty)"
    }

    private static func isValidTmuxPane(_ pane: String) -> Bool {
        pane.range(of: #"^%?\d+$"#, options: .regularExpression) != nil
    }

    private static func isValidTmuxSocket(_ socket: String?) -> Bool {
        guard let socket, !socket.isEmpty else { return false }
        return socket.hasPrefix("/") && !socket.contains("\u{0}")
    }

    private static func isValidTmuxClient(_ client: String) -> Bool {
        !client.isEmpty && !client.contains("\u{0}")
    }

    private static func tmuxExecutableURL() -> URL? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }.map(URL.init(fileURLWithPath:))
    }

    private static func tmuxArguments(socket: String?, command: [String]) -> [String] {
        var arguments: [String] = []
        if isValidTmuxSocket(socket), let socket {
            arguments += ["-S", socket]
        }
        arguments += command
        return arguments
    }

    private static func wezTermCLIURL() -> URL? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.github.wez.wezterm") {
            let cli = appURL.appendingPathComponent("Contents/MacOS/wezterm")
            if FileManager.default.isExecutableFile(atPath: cli.path) {
                return cli
            }
        }
        return executable(named: "wezterm")
    }

    private static func wezTermPaneID(cli: URL, tty: String?, cwd: String?) -> String? {
        for environment in wezTermEnvironments() {
            let output = processOutput(cli, arguments: ["cli", "list", "--format", "json"], environment: environment)
            guard let data = output.data(using: .utf8),
                  let panes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
        let ttyName = tty?.components(separatedBy: "/").last
        let cwd = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)

        for pane in panes {
            let paneTTY = pane["tty_name"] as? String
            let paneTTYName = paneTTY?.components(separatedBy: "/").last
            if let tty, !tty.isEmpty, paneTTY == tty || paneTTYName == ttyName {
                return paneID(from: pane)
            }
        }

        guard let cwd, !cwd.isEmpty else { return nil }
        for pane in panes {
            let paneCWD = (pane["cwd"] as? String) ?? (pane["current_working_dir"] as? String) ?? ""
            if paneCWD == cwd || paneCWD.hasPrefix("\(cwd)/") || cwd.hasPrefix("\(paneCWD)/") {
                return paneID(from: pane)
            }
        }
        }
        return nil
    }

    private static func wezTermPaneExists(_ targetPaneID: String, in output: String) -> Bool {
        guard let data = output.data(using: .utf8),
              let panes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
        return panes.contains { paneID(from: $0) == targetPaneID }
    }

    private static func wezTermEnvironments() -> [[String: String]?] {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/wezterm")
        let sockets = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?.filter { $0.lastPathComponent.hasPrefix("gui-sock-") }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            } ?? []
        let environments = sockets.map { ["WEZTERM_UNIX_SOCKET": $0.path] }
        return environments.isEmpty ? [nil] : environments.map(Optional.some)
    }

    private static func paneID(from pane: [String: Any]) -> String? {
        if let id = pane["pane_id"] as? String { return id }
        if let id = pane["pane_id"] as? Int { return String(id) }
        if let id = pane["paneId"] as? String { return id }
        if let id = pane["paneId"] as? Int { return String(id) }
        return nil
    }

    private static func executable(named name: String) -> URL? {
        [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "\(NSHomeDirectory())/.local/bin/\(name)"
        ].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }.map(URL.init(fileURLWithPath:))
    }

    @discardableResult
    private static func runProcess(_ executable: URL, arguments: [String], environment: [String: String]? = nil) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new } }
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            islandLog("terminal focus process failed exe=\(executable.path) error=\(error.localizedDescription)")
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func tmuxOutput(_ executable: URL, arguments: [String]) -> String {
        processOutput(executable, arguments: arguments)
    }

    private static func processOutput(_ executable: URL, arguments: [String], environment: [String: String]? = nil) -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new } }
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

    private static func appleScriptLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
