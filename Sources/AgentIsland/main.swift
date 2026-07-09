// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import Foundation
import SwiftUI

func islandLog(_ message: String) {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-island")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("agent-island.log")
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

enum AgentFamily: String, Codable, CaseIterable {
    case codex
    case claude
    case claudeScience = "claude_science"
    case chatgpt

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .claudeScience: return "Claude Science"
        case .chatgpt: return "ChatGPT"
        }
    }

    var tint: Color {
        switch self {
        case .codex: return Color(red: 0.18, green: 0.78, blue: 0.47)
        case .claude: return Color(red: 0.93, green: 0.55, blue: 0.22)
        case .claudeScience: return Color(red: 0.37, green: 0.68, blue: 1.0)
        case .chatgpt: return Color(red: 0.10, green: 0.74, blue: 0.60)
        }
    }
}

enum AgentSurface: String, Codable, CaseIterable {
    case app
    case cli
    case runtime
    case web

    var displayName: String {
        switch self {
        case .app: return "App"
        case .cli: return "CLI"
        case .runtime: return "Runtime"
        case .web: return "Web"
        }
    }

    var icon: String {
        switch self {
        case .app: return "macwindow"
        case .cli: return "terminal"
        case .runtime: return "cpu"
        case .web: return "globe"
        }
    }
}

enum AgentPhase: String, Codable {
    case needsAttention
    case working
    case thinking
    case queued
    case done
    case error
    case online
    case idle
    case offline

    var label: String {
        switch self {
        case .needsAttention: return "需处理"
        case .working: return "工作中"
        case .thinking: return "思考中"
        case .queued: return "待推进"
        case .done: return "已完成"
        case .error: return "异常"
        case .online: return "在线"
        case .idle: return "待命"
        case .offline: return "离线"
        }
    }

    var rank: Int {
        switch self {
        case .needsAttention: return 0
        case .error: return 1
        case .working: return 2
        case .thinking: return 3
        case .queued: return 4
        case .done: return 5
        case .online: return 6
        case .idle: return 7
        case .offline: return 8
        }
    }

    var icon: String {
        switch self {
        case .needsAttention: return "person.crop.circle.badge.exclamationmark"
        case .working: return "waveform"
        case .thinking: return "brain.head.profile"
        case .queued: return "arrow.forward.circle"
        case .done: return "checkmark"
        case .error: return "exclamationmark"
        case .online: return "power"
        case .idle: return "pause"
        case .offline: return "minus"
        }
    }
}

private enum AgentIslandControlKeys {
    static let collapseRequested = Notification.Name("AgentIslandCollapseRequested")
    static let toggleRequested = Notification.Name("AgentIslandToggleRequested")
}

struct AgentSnapshot: Identifiable, Equatable {
    var family: AgentFamily
    var surface: AgentSurface
    var sessionID: String?
    var phase: AgentPhase
    var title: String
    var detail: String
    var jumpTarget: JumpTarget?
    var targetPID: Int?
    var requestID: String?
    var toolInputSummary: String?
    var toolRisk: String?
    var toolRiskReason: String?
    var autoApprovalEligible: Bool?
    var pidCount: Int
    var pendingCount: Int
    var blockedCount: Int
    var runningCount: Int
    var completedCount: Int
    var lastUpdated: Date?

    var surfaceID: String { "\(family.rawValue)-\(surface.rawValue)" }
    var id: String {
        guard let sessionID, !sessionID.isEmpty else { return surfaceID }
        return "\(surfaceID)-\(sessionID)"
    }

    var hasQuickActions: Bool {
        switch phase {
        case .needsAttention, .queued, .done, .error:
            return true
        case .working, .thinking, .online, .idle, .offline:
            return false
        }
    }

    static func empty(_ family: AgentFamily, _ surface: AgentSurface) -> AgentSnapshot {
        AgentSnapshot(
            family: family,
            surface: surface,
            sessionID: nil,
            phase: .offline,
            title: "\(family.displayName) \(surface.displayName)",
            detail: "未检测到",
            jumpTarget: nil,
            targetPID: nil,
            requestID: nil,
            toolInputSummary: nil,
            toolRisk: nil,
            toolRiskReason: nil,
            autoApprovalEligible: nil,
            pidCount: 0,
            pendingCount: 0,
            blockedCount: 0,
            runningCount: 0,
            completedCount: 0,
            lastUpdated: nil
        )
    }
}

struct AgentEvent: Decodable {
    var agent: String?
    var family: String?
    var surface: String?
    var channel: String?
    var status: String?
    var phase: String?
    var title: String?
    var message: String?
    var session: String?
    var tool: String?
    var event: String?
    var pid: Int?
    var cwd: String?
    var terminalApp: String?
    var terminalBundleID: String?
    var terminalTTY: String?
    var terminalWindowID: String?
    var terminalTabIndex: String?
    var terminalSessionID: String?
    var terminalTmuxPane: String?
    var terminalTmuxSocket: String?
    var terminalTmuxClient: String?
    var requestID: String?
    var toolInputSummary: String?
    var toolRisk: String?
    var toolRiskReason: String?
    var autoApprovalEligible: Bool?
    var ts: Double?

    private enum CodingKeys: String, CodingKey {
        case agent, family, surface, channel, status, phase, title, message, session, tool, event, pid, cwd, ts
        case terminalApp = "terminal_app"
        case terminalBundleID = "terminal_bundle_id"
        case terminalTTY = "terminal_tty"
        case terminalWindowID = "terminal_window_id"
        case terminalTabIndex = "terminal_tab_index"
        case terminalSessionID = "terminal_session_id"
        case terminalTmuxPane = "terminal_tmux_pane"
        case terminalTmuxSocket = "terminal_tmux_socket"
        case terminalTmuxClient = "terminal_tmux_client"
        case requestID = "request_id"
        case toolInputSummary = "tool_input_summary"
        case toolRisk = "tool_risk"
        case toolRiskReason = "tool_risk_reason"
        case autoApprovalEligible = "auto_approval_eligible"
    }
}

struct ConversationInfo {
    var title: String
    var workspace: String?
    var preview: String?

    var shortTitle: String {
        AgentText.compact(title, limit: 34)
    }

    var workspaceName: String? {
        guard let workspace, !workspace.isEmpty else { return nil }
        return URL(fileURLWithPath: workspace).lastPathComponent
    }
}

struct AgentEventRollup {
    var family: AgentFamily?
    var surface: AgentSurface?
    var session: String?
    var displayEvent: AgentEvent?
    var displayPhase: AgentPhase?
    var displayTs: Double = 0
    var workingCount = 0
    var thinkingCount = 0
    var attentionCount = 0
    var queuedCount = 0
    var doneCount = 0

    mutating func observe(event: AgentEvent, family: AgentFamily, surface: AgentSurface, session: String, phase: AgentPhase, ts: Double) {
        self.family = family
        self.surface = surface
        self.session = session

        switch phase {
        case .working:
            workingCount += 1
        case .thinking:
            thinkingCount += 1
        case .needsAttention, .error:
            attentionCount += 1
        case .queued:
            queuedCount += 1
        case .done:
            doneCount += 1
        case .online, .idle, .offline:
            break
        }

        let currentRank = displayPhase?.rank ?? Int.max
        if displayPhase == nil
            || phase.rank < currentRank
            || (phase.rank == currentRank && ts >= displayTs) {
            displayEvent = event
            displayPhase = phase
            displayTs = ts
        }
    }

    var countSummary: String {
        var chunks: [String] = []
        if attentionCount > 0 { chunks.append("\(attentionCount) 需处理") }
        if workingCount > 0 { chunks.append("\(workingCount) 工作中") }
        if thinkingCount > 0 { chunks.append("\(thinkingCount) 思考中") }
        if queuedCount > 0 { chunks.append("\(queuedCount) 待推进") }
        if doneCount > 0 { chunks.append("\(doneCount) 已完成") }
        return chunks.joined(separator: " · ")
    }
}

private enum AgentSnapshotSummary {
    static func text(for snapshot: AgentSnapshot) -> String {
        var lines: [String] = []
        lines.append("Agent Island")
        lines.append("Title: \(snapshot.title)")
        lines.append("Agent: \(snapshot.family.displayName)")
        lines.append("Surface: \(snapshot.surface.displayName)")
        lines.append("Status: \(snapshot.phase.label)")
        if !snapshot.detail.isEmpty {
            lines.append("Detail: \(snapshot.detail)")
        }
        if let sessionID = snapshot.sessionID, !sessionID.isEmpty {
            lines.append("Session: \(sessionID)")
        }
        if let requestID = snapshot.requestID, !requestID.isEmpty {
            lines.append("Request: \(requestID)")
        }
        if let toolInputSummary = snapshot.toolInputSummary, !toolInputSummary.isEmpty {
            lines.append("Tool Input: \(toolInputSummary)")
        }
        if let toolRisk = snapshot.toolRisk, !toolRisk.isEmpty {
            var risk = toolRisk
            if let reason = snapshot.toolRiskReason, !reason.isEmpty {
                risk += " (\(reason))"
            }
            lines.append("Risk: \(risk)")
        }
        if let lastUpdated = snapshot.lastUpdated {
            lines.append("Updated: \(ISO8601DateFormatter().string(from: lastUpdated))")
        }
        if let jumpTarget = snapshot.jumpTarget {
            lines.append("Jump: \(jumpDescription(jumpTarget))")
        } else if let pid = snapshot.targetPID {
            lines.append("PID: \(pid)")
        }
        return lines.joined(separator: "\n")
    }

    private static func jumpDescription(_ target: JumpTarget) -> String {
        switch target {
        case .url(let value):
            return value
        case .process(let pid):
            return "process pid=\(pid)"
        case .app(let bundleID, let fallbackPath):
            return [bundleID, fallbackPath].compactMap { $0 }.joined(separator: " ")
        case .chatGPTWeb:
            return "ChatGPT web tab"
        case .terminal(let terminal):
            return terminalDescription(terminal)
        case .tmux(let tmux):
            let pane = tmux.pane.map { "pane=\($0)" } ?? "pane=unknown"
            let socket = tmux.socket.map { "socket=\($0)" } ?? ""
            return ["tmux", pane, socket, terminalDescription(tmux.terminal)]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    private static func terminalDescription(_ terminal: TerminalJumpTarget) -> String {
        [
            terminal.appName.map { "app=\($0)" },
            terminal.bundleID.map { "bundle=\($0)" },
            terminal.tty.map { "tty=\($0)" },
            terminal.cwd.map { "cwd=\($0)" },
            terminal.sessionIdentifier.map { "session=\($0)" },
            terminal.pid.map { "pid=\($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

struct ProcessRow {
    var pid: Int
    var ppid: Int?
    var command: String
}

enum AgentText {
    static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compact(_ value: String, limit: Int) -> String {
        let cleaned = cleanConversationTitle(value)
        guard cleaned.count > limit else { return cleaned }
        let end = cleaned.index(cleaned.startIndex, offsetBy: max(1, limit - 1))
        return String(cleaned[..<end]) + "…"
    }

    static func meaningfulConversationTitle(_ value: String) -> String? {
        let cleaned = cleanConversationTitle(value)
        guard cleaned != "未命名对话", !isInternalTaskText(cleaned) else { return nil }
        return cleaned
    }

    static func isInternalTaskText(_ value: String) -> Bool {
        let text = singleLine(value).lowercased()
        if text.isEmpty { return true }
        if text.contains("<task-notification") { return true }
        if text.contains("<task-id>") { return true }
        if text.contains("</task-notification>") { return true }
        if text.contains("<system-reminder") { return true }
        if text.contains("this session is being continued from a previous conversation") {
            return true
        }
        if text == "null" || text == "none" { return true }
        return false
    }

    static func cleanConversationTitle(_ value: String) -> String {
        var cleaned = singleLine(value)
        if cleaned.hasPrefix("Codex Companion Task:") {
            cleaned = cleaned.replacingOccurrences(of: "Codex Companion Task:", with: "Companion review:")
        }
        if isInternalTaskText(cleaned) {
            return "未命名对话"
        }
        if cleaned.hasPrefix("<task> Run a stop-gate review") || cleaned.contains("Run a stop-gate review of the previous Claude turn") {
            return "Stop-gate review"
        }
        if cleaned.hasPrefix("<task>") {
            cleaned = cleaned.replacingOccurrences(of: "<task>", with: "")
        }
        cleaned = cleaned
            .replacingOccurrences(of: "</task>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "未命名对话" : cleaned
    }
}

private enum AgentLauncher {
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
                openBundle("com.openai.chat", fallbackPath: "/Applications/ChatGPT.app")
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
                openBundle("com.openai.codex", fallbackPath: "/Applications/Codex.app")
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
                openBundle("com.openai.chat", fallbackPath: "/Applications/ChatGPT.app")
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

struct ClaudeTask: Decodable {
    var subject: String?
    var activeForm: String?
    var status: String?
    var blocks: [String]?
    var blockedBy: [String]?
}

struct ClaudeTaskSummary {
    var pendingCount = 0
    var runningCount = 0
    var blockedCount = 0
    var completedRecentCount = 0
    var latestRunningTitle: String?
    var latestPendingTitle: String?
    var latestBlockedTitle: String?
    var latestCompletedTitle: String?
    var latestStatus: String?
    var latestModified: Date?
}

struct CodexGoalSummary {
    var activeCount = 0
    var blockedCount = 0
    var completedRecentCount = 0
    var latestActiveTitle: String?
    var latestBlockedTitle: String?
    var latestCompletedTitle: String?
    var latestModified: Date?
}

struct CodexBrokerThread: Decodable {
    var id: String?
    var sessionId: String?
    var name: String?
    var preview: String?
    var cwd: String?
    var path: String?
    var source: String?
    var statusType: String?
    var updatedAt: Double?
    var createdAt: Double?
    var approvalMode: String?
    var turnCount: Int?
    var lastTurnId: String?
    var lastTurnStatus: String?
    var lastTurnStartedAt: Double?
    var lastTurnCompletedAt: Double?
    var lastTurnDurationMs: Double?
    var lastUserText: String?
    var lastAgentText: String?
    var lastWorkLabel: String?
    var lastItemType: String?
    var lastItemStatus: String?
    var activeItemCount: Int?
    var failedItemCount: Int?
    var readError: String?
}

struct CodexBrokerProbeResult: Decodable {
    var ok: Bool
    var socket: String?
    var threads: [CodexBrokerThread]?
}

struct CodexBrokerSummary {
    var threadCount = 0
    var activeCount = 0
    var blockedCount = 0
    var queuedCount = 0
    var completedRecentCount = 0
    var latestThreadTitle: String?
    var latestActiveTitle: String?
    var latestBlockedTitle: String?
    var latestQueuedTitle: String?
    var latestCompletedTitle: String?
    var latestModified: Date?
}

struct ClaudeScienceSummary {
    var processingCount = 0
    var awaitingCount = 0
    var queuedCount = 0
    var completedRecentCount = 0
    var kernelCount = 0
    var latestProcessingTitle: String?
    var latestAwaitingTitle: String?
    var latestQueuedTitle: String?
    var latestCompletedTitle: String?
    var latestModified: Date?
}

struct ChatGPTSummary {
    var appPhase: AgentPhase = .offline
    var appDetail = "未检测到"
    var appPID: Int?
    var appPIDCount = 0
    var appLastUpdated: Date?
    var webPhase: AgentPhase = .offline
    var webDetail = "未检测到 ChatGPT 标签"
    var webPID: Int?
    var webTabCount = 0
    var webLastUpdated: Date?
}

struct BrowserProbe {
    var appName: String
    var processName: String
    var bundleID: String
    var pid: Int?
    var chatGPTTabCount: Int
    var activeIsChatGPT: Bool
    var activeTitle: String?
}

final class AgentMonitor: ObservableObject {
    @Published var snapshots: [AgentSnapshot] = [
        .empty(.codex, .app),
        .empty(.codex, .cli),
        .empty(.claude, .app),
        .empty(.claude, .cli),
        .empty(.claudeScience, .app),
        .empty(.claudeScience, .runtime),
        .empty(.chatgpt, .app),
        .empty(.chatgpt, .web)
    ]
    @Published var lastRefresh = Date()

    private var timer: Timer?
    private var isRefreshing = false
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var cachedCodexBrokerThreads: [CodexBrokerThread] = []
    private var lastCodexBrokerScan = Date.distantPast
    private var lastCodexBrokerSuccess = Date.distantPast
    private var cachedChatGPTSummary = ChatGPTSummary()
    private var lastChatGPTScan = Date.distantPast
    private var chatGPTAppWasWorking = false
    private var chatGPTWebWasWorking = false
    private var chatGPTAppDoneUntil: Date?
    private var chatGPTWebDoneUntil: Date?

    var activeCount: Int {
        snapshots.filter { $0.phase == .working }.count
    }

    var thinkingCount: Int {
        snapshots.filter { $0.phase == .thinking }.count
    }

    var attentionCount: Int {
        snapshots.filter { $0.phase == .needsAttention || $0.phase == .error }.count
    }

    var queuedCount: Int {
        snapshots.filter { $0.phase == .queued }.count
    }

    var issueCount: Int {
        snapshots.filter { $0.phase == .error }.count
    }

    var doneCount: Int {
        snapshots.filter { $0.phase == .done }.count
    }

    var headline: String {
        if attentionCount > 0 { return "\(attentionCount) 项需要处理" }
        if activeCount > 0 { return "\(activeCount) 个任务工作中" }
        if thinkingCount > 0 { return "\(thinkingCount) 个任务思考中" }
        if queuedCount > 0 { return "\(queuedCount) 项待推进" }
        if doneCount > 0 { return "\(doneCount) 个任务刚完成" }
        return "在线待命"
    }

    func start() {
        refreshAsync()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshAsync()
        }
    }

    func refreshAsync() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let next = self.collectSnapshots()
            DispatchQueue.main.async {
                self.snapshots = next
                self.lastRefresh = Date()
                self.isRefreshing = false
            }
        }
    }

    private func collectSnapshots() -> [AgentSnapshot] {
        let rows = readProcesses()
        let events = eventRollups(rows: rows)
        let claudeTasks = readClaudeTaskSummary()
        let codexGoals = readCodexGoalSummary()
        let codexBrokerThreads = readCodexBrokerThreads()
        let codexBroker = summarizeCodexBrokerThreads(codexBrokerThreads)
        let science = readClaudeScienceSummary(rows: rows)
        let chatGPT = readChatGPTSummary(rows: rows)
        let claudeAppOwnsTasks = !claudeAppRows(from: rows).isEmpty
        let conversations = readConversationInfo(codexBrokerThreads: codexBrokerThreads)
        let eventSnapshots = makeEventSnapshots(from: events, conversations: conversations)
        let eventSurfaceIDs = Set(eventSnapshots.map(\.surfaceID))
        let appEventSurfaceIDs = Set(eventSnapshots.filter { $0.surface == .app }.map { "\($0.family.rawValue)-\($0.surface.rawValue)" })

        let baseSnapshots = [
            makeCodexApp(rows: rows, goals: codexGoals, broker: codexBroker),
            makeCodexCLI(rows: rows),
            makeClaudeApp(rows: rows, tasks: claudeAppOwnsTasks ? claudeTasks : nil),
            makeClaudeCLI(rows: rows, tasks: claudeAppOwnsTasks ? nil : claudeTasks),
            makeClaudeScienceApp(rows: rows),
            makeClaudeScienceRuntime(rows: rows, summary: science),
            makeChatGPTApp(summary: chatGPT),
            makeChatGPTWeb(summary: chatGPT)
        ]

        let fallbackSnapshots = baseSnapshots.filter { snapshot in
            if eventSurfaceIDs.contains(snapshot.surfaceID) {
                return false
            }
            if snapshot.surface == .cli,
               snapshot.targetPID == nil,
               appEventSurfaceIDs.contains("\(snapshot.family.rawValue)-app") {
                return false
            }
            return true
        }

        let next = (eventSnapshots + fallbackSnapshots)
            .sorted { lhs, rhs in
                if lhs.phase.rank != rhs.phase.rank {
                    return lhs.phase.rank < rhs.phase.rank
                }
                if lhs.lastUpdated != rhs.lastUpdated {
                    return (lhs.lastUpdated ?? .distantPast) > (rhs.lastUpdated ?? .distantPast)
                }
                if lhs.family.rawValue != rhs.family.rawValue {
                    return lhs.family.rawValue < rhs.family.rawValue
            }
                return lhs.surface.rawValue < rhs.surface.rawValue
            }

        return next
    }

    private func readProcesses() -> [ProcessRow] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["axww", "-o", "pid=,ppid=,command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 2)
            guard parts.count == 3, let pid = Int(parts[0]), let ppid = Int(parts[1]) else { return nil }
            return ProcessRow(pid: pid, ppid: ppid, command: String(parts[2]))
        }
    }

    private func makeCodexApp(rows: [ProcessRow], goals: CodexGoalSummary, broker: CodexBrokerSummary) -> AgentSnapshot {
        let appRows = rows.filter { row in
            isCodexAppProcess(row.command)
                && !row.command.contains("crashpad_handler")
        }
        let appServer = appRows.contains { $0.command.contains("codex app-server") }
        let mainAppPID = appRows.first { row in
            row.command.lowercased().contains("/applications/codex.app/contents/macos/codex")
        }?.pid
        var snapshot = AgentSnapshot.empty(.codex, .app)
        snapshot.runningCount = max(goals.activeCount, broker.activeCount)
        snapshot.blockedCount = max(goals.blockedCount, broker.blockedCount)
        snapshot.pendingCount = broker.queuedCount
        snapshot.completedCount = broker.activeCount == 0 && broker.blockedCount == 0 && broker.queuedCount == 0
            ? max(goals.completedRecentCount, broker.completedRecentCount)
            : 0
        if !appRows.isEmpty {
            snapshot.phase = .online
            if broker.threadCount > 0 {
                let title = broker.latestThreadTitle.map { " · \($0)" } ?? ""
                snapshot.detail = "Codex app-server 可读；\(broker.threadCount) 个近期线程\(title)"
            } else {
                snapshot.detail = appServer ? "Codex.app server 在线；等待任务事件" : "Codex.app 已打开"
            }
            snapshot.targetPID = mainAppPID ?? appRows.first?.pid
            snapshot.pidCount = appRows.count
            snapshot.lastUpdated = broker.latestModified ?? Date()
        }
        if broker.blockedCount > 0 {
            snapshot.phase = .needsAttention
            snapshot.detail = broker.latestBlockedTitle ?? "\(broker.blockedCount) 个 Codex 线程需要处理"
            snapshot.title = "Codex App · \(broker.blockedCount) 需处理"
        } else if broker.activeCount > 0 {
            snapshot.phase = .working
            snapshot.detail = broker.latestActiveTitle ?? "\(broker.activeCount) 个 Codex 线程正在执行"
            snapshot.title = "Codex App · \(broker.activeCount) 工作中"
        } else if broker.queuedCount > 0 {
            snapshot.phase = .queued
            snapshot.detail = broker.latestQueuedTitle ?? "\(broker.queuedCount) 个 Codex 线程待推进"
            snapshot.title = "Codex App · \(broker.queuedCount) 待推进"
        } else if broker.completedRecentCount > 0 {
            snapshot.phase = .done
            snapshot.detail = broker.latestCompletedTitle ?? "最近有 Codex 线程完成"
        } else if goals.blockedCount > 0 {
            snapshot.phase = .needsAttention
            snapshot.detail = goals.latestBlockedTitle ?? "\(goals.blockedCount) 个 Codex goal 需要处理"
        } else if goals.activeCount > 0, isRecent(goals.latestModified, within: 10 * 60) {
            snapshot.phase = .working
            snapshot.detail = goals.latestActiveTitle ?? "\(goals.activeCount) 个 Codex goal 活跃"
        } else if goals.completedRecentCount > 0 {
            snapshot.phase = .done
            snapshot.detail = goals.latestCompletedTitle ?? "最近有 Codex goal 完成"
        }
        return snapshot
    }

    private func makeCodexCLI(rows: [ProcessRow]) -> AgentSnapshot {
        let cliRows = rows.filter { isCodexCLIProcess($0.command) }

        var snapshot = AgentSnapshot.empty(.codex, .cli)
        if !cliRows.isEmpty {
            snapshot.phase = .online
            snapshot.detail = "Codex CLI 在线；hook 事件才算工作中"
            snapshot.targetPID = cliRows.first?.pid
            snapshot.pidCount = cliRows.count
            snapshot.lastUpdated = Date()
        } else if executableExists("codex") {
            snapshot.phase = .online
            snapshot.detail = "CLI 已安装，未检测到任务事件"
        }
        return snapshot
    }

    private func makeClaudeApp(rows: [ProcessRow], tasks: ClaudeTaskSummary?) -> AgentSnapshot {
        let appRows = claudeAppRows(from: rows)
        var snapshot = AgentSnapshot.empty(.claude, .app)
        if !appRows.isEmpty {
            snapshot.phase = .online
            snapshot.detail = "Claude.app 已打开"
            snapshot.targetPID = appRows.first?.pid
            snapshot.pidCount = appRows.count
            snapshot.lastUpdated = Date()
        }
        if let tasks {
            applyClaudeTasks(tasks, to: &snapshot, surfaceName: "Claude App")
        }
        return snapshot
    }

    private func makeClaudeCLI(rows: [ProcessRow], tasks: ClaudeTaskSummary?) -> AgentSnapshot {
        let cliRows = rows.filter { isClaudeCLIProcess($0.command) }

        var snapshot = AgentSnapshot.empty(.claude, .cli)
        if !cliRows.isEmpty {
            snapshot.phase = .online
            snapshot.detail = "Claude Code 进程在线；无活动任务信号"
            snapshot.targetPID = cliRows.first?.pid
            snapshot.pidCount = cliRows.count
        } else if executableExists("claude") {
            snapshot.phase = .online
            snapshot.detail = "CLI 已安装，未检测到任务事件"
        }
        if let tasks {
            applyClaudeTasks(tasks, to: &snapshot, surfaceName: "Claude CLI")
        }
        if !cliRows.isEmpty {
            snapshot.targetPID = cliRows.first?.pid
            snapshot.pidCount = cliRows.count
        }

        return snapshot
    }

    private func claudeAppRows(from rows: [ProcessRow]) -> [ProcessRow] {
        rows.filter { row in
            isClaudeAppProcess(row.command) && !row.command.contains("crashpad_handler")
        }
    }

    private func isCodexAppProcess(_ command: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.contains("/applications/codex.app/")
            || cmd.contains("/contents/resources/codex app-server")
            || cmd.hasSuffix("/codex app-server")
            || cmd.contains(" codex app-server ")
    }

    private func isCodexCLIProcess(_ command: String) -> Bool {
        let cmd = command.lowercased()
        guard cmd.contains("codex") else { return false }
        if isCodexAppProcess(command) { return false }
        if cmd.contains(" app-server") { return false }
        if cmd.contains("mcp-server") { return false }
        if cmd.contains("node_repl") { return false }
        if cmd.contains("agentisland") { return false }
        if cmd.contains("rg -i") || cmd.contains("/bin/ps") { return false }
        return cmd.contains("/bin/codex") || cmd.contains(" codex ")
    }

    private func isClaudeAppProcess(_ command: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.contains("/applications/claude.app/")
            || (cmd.contains("/library/application support/claude/claude-code/")
                && cmd.contains("/claude.app/contents/macos/claude"))
    }

    private func isClaudeCLIProcess(_ command: String) -> Bool {
        let cmd = command.lowercased()
        if cmd.contains("agentisland") { return false }
        if isClaudeAppProcess(command) { return false }
        return cmd.contains("/bin/claude ")
            || cmd.hasSuffix("/bin/claude")
            || cmd.contains(" claude --output-format")
    }

    private func applyClaudeTasks(_ tasks: ClaudeTaskSummary, to snapshot: inout AgentSnapshot, surfaceName: String) {
        snapshot.pendingCount = tasks.pendingCount
        snapshot.runningCount = tasks.runningCount
        snapshot.blockedCount = tasks.blockedCount
        snapshot.completedCount = tasks.completedRecentCount
        if let latestModified = tasks.latestModified {
            snapshot.lastUpdated = latestModified
        }

        if tasks.blockedCount > 0 {
            snapshot.phase = .needsAttention
            snapshot.detail = tasks.latestBlockedTitle ?? "\(tasks.blockedCount) 个任务需要处理"
            snapshot.title = "\(surfaceName) · \(tasks.blockedCount) 需处理"
        } else if tasks.runningCount > 0 {
            snapshot.phase = .working
            snapshot.detail = tasks.latestRunningTitle ?? "\(tasks.runningCount) 个任务正在执行"
            snapshot.title = "\(surfaceName) · \(tasks.runningCount) 工作中"
        } else if tasks.pendingCount > 0 {
            snapshot.phase = .queued
            snapshot.detail = tasks.latestPendingTitle ?? "\(tasks.pendingCount) 个任务待推进"
            snapshot.title = "\(surfaceName) · \(tasks.pendingCount) 待推进"
        } else if tasks.completedRecentCount > 0 {
            snapshot.phase = .done
            snapshot.detail = tasks.latestCompletedTitle ?? "最近有任务完成"
        }
    }

    private func makeClaudeScienceApp(rows: [ProcessRow]) -> AgentSnapshot {
        let appRows = rows.filter { row in
            row.command.contains("/Applications/Claude Science.app/")
                || row.command.contains("/Contents/MacOS/ClaudeScience")
        }

        var snapshot = AgentSnapshot.empty(.claudeScience, .app)
        snapshot.title = "Claude Science App"
        if !appRows.isEmpty {
            snapshot.phase = .online
            snapshot.detail = "Claude Science.app 已打开"
            snapshot.targetPID = appRows.first?.pid
            snapshot.pidCount = appRows.count
            snapshot.lastUpdated = Date()
        }
        return snapshot
    }

    private func makeClaudeScienceRuntime(rows: [ProcessRow], summary: ClaudeScienceSummary) -> AgentSnapshot {
        let serverRows = rows.filter { row in
            let cmd = row.command.lowercased()
            return cmd.contains("/.claude-science/bin/claude-science")
                && cmd.contains(" serve ")
        }
        let kernelRows = claudeScienceKernelRows(from: rows)

        var snapshot = AgentSnapshot.empty(.claudeScience, .runtime)
        snapshot.title = "Claude Science Runtime"
        snapshot.runningCount = summary.processingCount
        snapshot.blockedCount = summary.awaitingCount
        snapshot.pendingCount = summary.queuedCount
        snapshot.completedCount = (summary.processingCount == 0 && summary.awaitingCount == 0 && summary.queuedCount == 0)
            ? summary.completedRecentCount
            : 0
        snapshot.lastUpdated = summary.latestModified

        if !serverRows.isEmpty {
            snapshot.phase = .online
            snapshot.detail = kernelRows.isEmpty
                ? "后台服务在线；无活动 frame"
                : "后台服务在线；\(kernelRows.count) 个 kernel"
            snapshot.targetPID = serverRows.first?.pid
            snapshot.pidCount = serverRows.count + kernelRows.count
            snapshot.lastUpdated = Date()
        } else if FileManager.default.isExecutableFile(atPath: home.appendingPathComponent(".claude-science/bin/claude-science").path) {
            snapshot.phase = .online
            snapshot.detail = "CLI 已安装，后台服务未运行"
        }

        if summary.awaitingCount > 0 {
            snapshot.phase = .needsAttention
            snapshot.detail = summary.latestAwaitingTitle ?? "\(summary.awaitingCount) 个 Science frame 异常/阻塞"
        } else if summary.processingCount > 0, isRecent(summary.latestModified, within: 30 * 60) {
            snapshot.phase = .working
            snapshot.detail = summary.latestProcessingTitle ?? "\(summary.processingCount) 个 Science frame 处理中"
        } else if summary.queuedCount > 0 {
            snapshot.phase = .queued
            snapshot.detail = summary.latestQueuedTitle ?? "\(summary.queuedCount) 个 Science frame 待推进"
        } else if summary.completedRecentCount > 0 {
            snapshot.phase = .done
            snapshot.detail = summary.latestCompletedTitle ?? "最近有 Science frame 完成"
        }

        if !kernelRows.isEmpty {
            snapshot.targetPID = kernelRows.first?.pid ?? snapshot.targetPID
            if summary.processingCount > 0 {
                snapshot.detail += " · \(kernelRows.count) 个 kernel"
            }
        }

        return snapshot
    }

    private func makeChatGPTApp(summary: ChatGPTSummary) -> AgentSnapshot {
        var snapshot = AgentSnapshot.empty(.chatgpt, .app)
        snapshot.phase = summary.appPhase
        snapshot.detail = summary.appDetail
        snapshot.targetPID = summary.appPID
        snapshot.pidCount = summary.appPIDCount
        snapshot.lastUpdated = summary.appLastUpdated
        snapshot.runningCount = summary.appPhase == .working ? 1 : 0
        snapshot.blockedCount = summary.appPhase == .needsAttention ? 1 : 0
        snapshot.pendingCount = summary.appPhase == .queued ? 1 : 0
        snapshot.completedCount = summary.appPhase == .done ? 1 : 0
        return snapshot
    }

    private func makeChatGPTWeb(summary: ChatGPTSummary) -> AgentSnapshot {
        var snapshot = AgentSnapshot.empty(.chatgpt, .web)
        snapshot.phase = summary.webPhase
        snapshot.detail = summary.webDetail
        if summary.webTabCount > 0 {
            snapshot.jumpTarget = .chatGPTWeb
        }
        snapshot.targetPID = summary.webPID
        snapshot.pidCount = summary.webTabCount
        snapshot.lastUpdated = summary.webLastUpdated
        snapshot.runningCount = summary.webPhase == .working ? 1 : 0
        snapshot.blockedCount = summary.webPhase == .needsAttention ? 1 : 0
        snapshot.pendingCount = summary.webPhase == .queued ? 1 : 0
        snapshot.completedCount = summary.webPhase == .done ? 1 : 0
        if summary.webTabCount > 1 {
            snapshot.title = "ChatGPT Web · \(summary.webTabCount) 标签"
        }
        return snapshot
    }

    private func claudeScienceKernelRows(from rows: [ProcessRow]) -> [ProcessRow] {
        rows.filter { row in
            let cmd = row.command.lowercased()
            guard cmd.contains("/.claude-science/orgs/") else { return false }
            if cmd.contains("find ") || cmd.contains("rg -i") || cmd.contains("/bin/ps") { return false }
            return cmd.contains("/.venv/")
                || cmd.contains("/conda/envs/")
                || cmd.contains("/r/bin/exec/r")
        }
    }

    private func readChatGPTSummary(rows: [ProcessRow]) -> ChatGPTSummary {
        let now = Date()
        if now.timeIntervalSince(lastChatGPTScan) < 5 {
            return cachedChatGPTSummary
        }
        lastChatGPTScan = now

        var summary = ChatGPTSummary()
        let appRows = chatGPTAppRows(from: rows)
        if !appRows.isEmpty {
            summary.appPhase = .online
            summary.appDetail = "App 在线；未发现回答中信号"
            summary.appPID = appRows.first { $0.command.contains("/Contents/MacOS/ChatGPT") }?.pid ?? appRows.first?.pid
            summary.appPIDCount = appRows.count
            summary.appLastUpdated = now

            if frontmostProcessName() == "ChatGPT" {
                let text = accessibilityText(forProcess: "ChatGPT")
                let signal = classifyChatGPTUI(text)
                switch signal {
                case .working:
                    summary.appPhase = .working
                    summary.appDetail = "正在回答；检测到停止生成控件"
                case .needsAttention:
                    summary.appPhase = .needsAttention
                    summary.appDetail = "需要点击继续/重试或处理错误"
                case .queued:
                    summary.appPhase = .queued
                    summary.appDetail = "等待继续生成或用户下一步"
                default:
                    summary.appPhase = .idle
                    summary.appDetail = text.isEmpty
                        ? "App 前台；辅助功能未暴露回答控件"
                        : "App 前台待命；未见停止生成控件"
                }
            } else {
                summary.appDetail = "App 在线；切到前台可判断回答中/完成"
            }
        }

        let probes = readBrowserProbes()
        let tabCount = probes.reduce(0) { $0 + $1.chatGPTTabCount }
        if tabCount > 0 {
            summary.webPhase = .online
            summary.webTabCount = tabCount
            summary.webPID = probes.first { $0.chatGPTTabCount > 0 }?.pid
            summary.webLastUpdated = now
            let frontmost = frontmostProcessName()

            if let active = probes.first(where: { $0.activeIsChatGPT && $0.processName == frontmost }) {
                let text = accessibilityText(forProcess: active.processName)
                let signal = classifyChatGPTUI(text)
                switch signal {
                case .working:
                    summary.webPhase = .working
                    summary.webDetail = "\(active.appName) 正在回答；检测到停止生成控件"
                case .needsAttention:
                    summary.webPhase = .needsAttention
                    summary.webDetail = "\(active.appName) 需要点击继续/重试或处理错误"
                case .queued:
                    summary.webPhase = .queued
                    summary.webDetail = "\(active.appName) 等待继续生成或用户下一步"
                default:
                    summary.webPhase = .idle
                    summary.webDetail = text.isEmpty
                        ? "\(active.appName) 前台标签；辅助功能未暴露回答控件"
                        : "\(active.appName) 前台标签待命；未见停止生成控件"
                }
            } else {
                summary.webDetail = "\(tabCount) 个 ChatGPT 标签在线；切到对应标签可判断回答状态"
            }
        }

        applyChatGPTTransitions(to: &summary, now: now)
        cachedChatGPTSummary = summary
        return summary
    }

    private func chatGPTAppRows(from rows: [ProcessRow]) -> [ProcessRow] {
        rows.filter { row in
            let cmd = row.command.lowercased()
            if cmd.contains("crashpad_handler") { return false }
            return cmd.contains("/applications/chatgpt.app/")
                || cmd.contains("/contents/macos/chatgpt")
        }
    }

    private func applyChatGPTTransitions(to summary: inout ChatGPTSummary, now: Date) {
        let appCurrentlyWorking = summary.appPhase == .working
        if chatGPTAppWasWorking && !appCurrentlyWorking && (summary.appPhase == .online || summary.appPhase == .idle) {
            chatGPTAppDoneUntil = now.addingTimeInterval(25)
        }
        chatGPTAppWasWorking = appCurrentlyWorking
        if let until = chatGPTAppDoneUntil, now <= until, summary.appPhase == .online || summary.appPhase == .idle {
            summary.appPhase = .done
            summary.appDetail = "回答刚结束；点击查看结果"
            summary.appLastUpdated = now
        } else if let until = chatGPTAppDoneUntil, now > until {
            chatGPTAppDoneUntil = nil
        }

        let webCurrentlyWorking = summary.webPhase == .working
        if chatGPTWebWasWorking && !webCurrentlyWorking && (summary.webPhase == .online || summary.webPhase == .idle) {
            chatGPTWebDoneUntil = now.addingTimeInterval(25)
        }
        chatGPTWebWasWorking = webCurrentlyWorking
        if let until = chatGPTWebDoneUntil, now <= until, summary.webPhase == .online || summary.webPhase == .idle {
            summary.webPhase = .done
            summary.webDetail = "回答刚结束；点击查看标签"
            summary.webLastUpdated = now
        } else if let until = chatGPTWebDoneUntil, now > until {
            chatGPTWebDoneUntil = nil
        }
    }

    private func readBrowserProbes() -> [BrowserProbe] {
        let browsers = [
            ("Google Chrome", "Google Chrome", "com.google.Chrome", false),
            ("Safari", "Safari", "com.apple.Safari", true),
            ("Microsoft Edge", "Microsoft Edge", "com.microsoft.edgemac", false),
            ("Brave", "Brave Browser", "com.brave.Browser", false),
            ("Arc", "Arc", "company.thebrowser.Browser", false)
        ]

        return browsers.compactMap { appName, processName, bundleID, isSafari in
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
                return nil
            }
            let tabs = browserTabs(appName: appName, safari: isSafari)
            let active = activeBrowserTab(appName: appName, safari: isSafari)
            let count = tabs.filter { isChatGPTURL($0.url) }.count
            guard count > 0 else { return nil }
            return BrowserProbe(
                appName: appName,
                processName: processName,
                bundleID: bundleID,
                pid: Int(app.processIdentifier),
                chatGPTTabCount: count,
                activeIsChatGPT: isChatGPTURL(active.url),
                activeTitle: active.title
            )
        }
    }

    private func browserTabs(appName: String, safari: Bool) -> [(url: String, title: String)] {
        let titleProperty = safari ? "name" : "title"
        let source = """
        tell application "\(appName)"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set out to out & (URL of t as text) & tab & (\(titleProperty) of t as text) & linefeed
                    end try
                end repeat
            end repeat
            return out
        end tell
        """
        return parseTabLines(runAppleScript(source))
    }

    private func activeBrowserTab(appName: String, safari: Bool) -> (url: String, title: String) {
        let titleProperty = safari ? "name" : "title"
        let source = """
        tell application "\(appName)"
            if (count of windows) is 0 then return ""
            return (URL of active tab of front window as text) & tab & (\(titleProperty) of active tab of front window as text)
        end tell
        """
        return parseTabLines(runAppleScript(source)).first ?? ("", "")
    }

    private func parseTabLines(_ output: String) -> [(url: String, title: String)] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard let url = parts.first, !url.isEmpty else { return nil }
            return (url, parts.count > 1 ? parts[1] : "")
        }
    }

    private func isChatGPTURL(_ raw: String) -> Bool {
        let value = raw.lowercased()
        return value.contains("://chatgpt.com")
            || value.contains("://www.chatgpt.com")
            || value.contains("://chat.openai.com")
    }

    private func frontmostProcessName() -> String? {
        let source = """
        tell application "System Events"
            return name of first application process whose frontmost is true
        end tell
        """
        let value = runAppleScript(source).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func accessibilityText(forProcess processName: String) -> String {
        let source = """
        tell application "System Events"
            if not (exists process "\(processName)") then return ""
            tell process "\(processName)"
                if not (exists window 1) then return ""
                set bits to {}
                try
                    set bits to bits & (name of every button of window 1)
                end try
                try
                    set bits to bits & (description of every button of window 1)
                end try
                try
                    set bits to bits & (value of every static text of window 1)
                end try
                try
                    set bits to bits & (description of every UI element of window 1)
                end try
                try
                    repeat with g in groups of window 1
                        try
                            set bits to bits & (name of every UI element of g)
                        end try
                        try
                            set bits to bits & (description of every UI element of g)
                        end try
                    end repeat
                end try
                return bits as string
            end tell
        end tell
        """
        let output = runAppleScript(source)
        if output.contains("not authorized") || output.contains("未获授权") {
            return ""
        }
        return output
    }

    private func classifyChatGPTUI(_ text: String) -> AgentPhase? {
        let value = text.lowercased()
        guard !value.isEmpty else { return nil }

        if containsAny(value, [
            "stop generating",
            "stop streaming",
            "stop responding",
            "cancel generating",
            "停止生成",
            "停止回答",
            "中止生成"
        ]) {
            return .working
        }

        if containsAny(value, [
            "continue generating",
            "try again",
            "retry",
            "something went wrong",
            "network error",
            "继续生成",
            "重试",
            "出错",
            "网络错误"
        ]) {
            return .needsAttention
        }

        if containsAny(value, [
            "queued",
            "waiting",
            "排队",
            "等待"
        ]) {
            return .queued
        }

        return nil
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private func isRecent(_ date: Date?, within seconds: TimeInterval) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) <= seconds
    }

    private func executableExists(_ name: String) -> Bool {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            let path = URL(fileURLWithPath: String(dir)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: path) {
                return true
            }
        }

        let common = [
            home.appendingPathComponent(".nvm/versions/node/v22.20.0/bin/\(name)").path,
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)"
        ]
        return common.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func readConversationInfo(codexBrokerThreads: [CodexBrokerThread]) -> [String: ConversationInfo] {
        var result = readCodexConversationInfo()
        let broker = readCodexBrokerConversationInfo(threads: codexBrokerThreads)
        result.merge(broker) { current, incoming in
            mergeConversationInfo(current: current, incoming: incoming)
        }
        let recentSessions = recentEventSessionIDs()
        let claude = readClaudeConversationInfo(sessionIDs: recentSessions[.claude] ?? [])
        result.merge(claude) { current, _ in current }
        return result
    }

    private func readCodexBrokerThreads() -> [CodexBrokerThread] {
        let now = Date()
        if now.timeIntervalSince(lastCodexBrokerScan) < 6 {
            return cachedCodexBrokerThreads
        }
        lastCodexBrokerScan = now

        guard let script = helperScriptPath("codex-broker-probe") else {
            return now.timeIntervalSince(lastCodexBrokerSuccess) < 30 ? cachedCodexBrokerThreads : []
        }

        let output = runCommand(
            executable: "/usr/bin/python3",
            arguments: [script, "--limit", "80", "--read-visible-details", "--read-limit", "8"]
        )
        guard let data = output.data(using: .utf8),
              let result = try? JSONDecoder().decode(CodexBrokerProbeResult.self, from: data),
              result.ok else {
            if now.timeIntervalSince(lastCodexBrokerSuccess) >= 30 {
                cachedCodexBrokerThreads = []
            }
            return cachedCodexBrokerThreads
        }

        cachedCodexBrokerThreads = result.threads ?? []
        lastCodexBrokerSuccess = now
        return cachedCodexBrokerThreads
    }

    private func readCodexBrokerConversationInfo(threads: [CodexBrokerThread]) -> [String: ConversationInfo] {
        var result: [String: ConversationInfo] = [:]
        for thread in threads {
            guard let id = thread.id, !id.isEmpty else { continue }
            guard !isAuxiliaryCodexThread(thread) else { continue }

            let title = codexBrokerThreadTitle(thread) ?? "Codex \(shortSession(id))"
            result[conversationKey(.codex, id)] = ConversationInfo(
                title: title,
                workspace: thread.cwd,
                preview: thread.preview
            )
        }
        return result
    }

    private func mergeConversationInfo(current: ConversationInfo, incoming: ConversationInfo) -> ConversationInfo {
        let currentMeaningful = AgentText.meaningfulConversationTitle(current.title) != nil
        let incomingMeaningful = AgentText.meaningfulConversationTitle(incoming.title) != nil
        let title = incomingMeaningful && (!currentMeaningful || current.title.hasPrefix("Codex "))
            ? incoming.title
            : current.title
        return ConversationInfo(
            title: title,
            workspace: current.workspace ?? incoming.workspace,
            preview: current.preview ?? incoming.preview
        )
    }

    private func summarizeCodexBrokerThreads(_ threads: [CodexBrokerThread]) -> CodexBrokerSummary {
        let visible = threads
            .filter { !isAuxiliaryCodexThread($0) }
            .sorted {
                ($0.updatedAt ?? $0.createdAt ?? 0) > ($1.updatedAt ?? $1.createdAt ?? 0)
            }

        var summary = CodexBrokerSummary()
        summary.threadCount = visible.count
        if let latest = visible.first {
            summary.latestThreadTitle = codexBrokerThreadTitle(latest)
            summary.latestModified = dateFromSeconds(latest.updatedAt ?? latest.createdAt)
        }

        for thread in visible {
            let title = codexBrokerThreadTitle(thread) ?? thread.id.map { "Codex \(shortSession($0))" }
            let modified = dateFromSeconds(thread.updatedAt ?? thread.createdAt)
            if let modified, summary.latestModified == nil || modified > (summary.latestModified ?? .distantPast) {
                summary.latestModified = modified
            }

            let phase = codexBrokerPhase(for: thread)
            let activity = codexBrokerActivityText(thread) ?? title
            switch phase {
            case .needsAttention:
                guard isRecent(modified, within: 24 * 60 * 60) || modified == nil else { continue }
                summary.blockedCount += 1
                if summary.latestBlockedTitle == nil { summary.latestBlockedTitle = activity }
            case .working:
                guard isRecent(modified, within: 30 * 60) || modified == nil else { continue }
                summary.activeCount += 1
                if summary.latestActiveTitle == nil { summary.latestActiveTitle = activity }
            case .queued:
                guard isRecent(modified, within: 24 * 60 * 60) || modified == nil else { continue }
                summary.queuedCount += 1
                if summary.latestQueuedTitle == nil { summary.latestQueuedTitle = activity }
            case .done:
                let completed = dateFromSeconds(thread.lastTurnCompletedAt ?? thread.updatedAt)
                guard isRecent(completed, within: 10 * 60) else { continue }
                summary.completedRecentCount += 1
                if summary.latestCompletedTitle == nil { summary.latestCompletedTitle = activity }
            default:
                break
            }
        }

        return summary
    }

    private func codexBrokerPhase(for thread: CodexBrokerThread) -> AgentPhase? {
        if (thread.failedItemCount ?? 0) > 0 {
            return .needsAttention
        }
        if (thread.activeItemCount ?? 0) > 0 {
            return .working
        }

        if let turnStatus = normalizedCodexStatus(thread.lastTurnStatus) {
            switch turnStatus {
            case "waitingforapproval", "approval", "permission", "inputrequired", "waitingforinput", "requiresaction", "blocked", "failed", "failure", "error":
                return .needsAttention
            case "running", "processing", "inprogress", "executing", "streaming", "generating", "busy", "started":
                return .working
            case "queued", "pending", "waiting", "interrupted", "cancelled", "canceled":
                return .queued
            case "completed", "complete", "succeeded", "success":
                return .done
            default:
                break
            }
        }

        return codexBrokerStatusPhase(thread.statusType)
    }

    private func codexBrokerStatusPhase(_ statusType: String?) -> AgentPhase? {
        guard let value = normalizedCodexStatus(statusType) else { return nil }

        if [
            "waitingforapproval",
            "waitingforinput",
            "requiresaction",
            "approval",
            "permission",
            "human",
            "inputrequired",
            "blocked",
            "systemerror",
            "error",
            "failed",
            "failure"
        ].contains(value) {
            return .needsAttention
        }

        if [
            "running",
            "processing",
            "inprogress",
            "executing",
            "streaming",
            "generating",
            "busy",
            "started"
        ].contains(value) {
            return .working
        }

        if [
            "queued",
            "pending",
            "waiting"
        ].contains(value) {
            return .queued
        }

        return nil
    }

    private func normalizedCodexStatus(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return raw
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func codexBrokerActivityText(_ thread: CodexBrokerThread) -> String? {
        for raw in [thread.lastWorkLabel, thread.lastAgentText, thread.lastUserText] {
            guard let raw, let text = AgentText.meaningfulConversationTitle(raw) else { continue }
            return AgentText.compact(text, limit: 72)
        }
        return codexBrokerThreadTitle(thread).map { AgentText.compact($0, limit: 72) }
    }

    private func isAuxiliaryCodexThread(_ thread: CodexBrokerThread) -> Bool {
        let text = [thread.name, thread.preview, thread.path]
            .compactMap { $0 }
            .map(AgentText.singleLine)
            .joined(separator: " ")
            .lowercased()
        if text.contains("codex companion task:") { return true }
        if text.contains("run a stop-gate review") { return true }
        if text.contains("<compact_output_contract>") { return true }
        if text.contains("previous claude turn") { return true }
        if text.contains("stop-gate review") { return true }
        return false
    }

    private func codexBrokerThreadTitle(_ thread: CodexBrokerThread) -> String? {
        for raw in [thread.name, thread.preview] {
            guard let raw, let title = AgentText.meaningfulConversationTitle(raw) else { continue }
            return title
        }
        return nil
    }

    private func dateFromSeconds(_ seconds: Double?) -> Date? {
        guard let seconds, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func helperScriptPath(_ name: String) -> String? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("scripts/\(name)").path(percentEncoded: false),
            ProcessInfo.processInfo.environment["AGENT_ISLAND_ROOT"].map { "\($0)/scripts/\(name)" },
            FileManager.default.currentDirectoryPath + "/scripts/\(name)"
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func readCodexConversationInfo() -> [String: ConversationInfo] {
        let paths = [
            home.appendingPathComponent(".codex/state_5.sqlite").path,
            home.appendingPathComponent(".codex/sqlite/state_5.sqlite").path
        ]
        let separator = "\u{1F}"
        let sql = """
        select id,
               replace(replace(coalesce(title,''), char(10), ' '), char(31), ' '),
               replace(replace(coalesce(cwd,''), char(10), ' '), char(31), ' '),
               replace(replace(case when length(coalesce(preview,'')) > 0 then preview else coalesce(first_user_message,'') end, char(10), ' '), char(31), ' ')
        from threads
        order by coalesce(updated_at_ms, created_at_ms, updated_at, created_at, 0) desc
        limit 600;
        """

        var result: [String: ConversationInfo] = [:]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            let output = runCommand(
                executable: "/usr/bin/sqlite3",
                arguments: ["-separator", separator, path, sql]
            )
            for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = String(line).components(separatedBy: separator)
                guard parts.count >= 4 else { continue }
                let id = parts[0]
                guard result[conversationKey(.codex, id)] == nil else { continue }
                let rawTitle = parts[1].isEmpty ? parts[3] : parts[1]
                let title = AgentText.meaningfulConversationTitle(rawTitle)
                    ?? AgentText.cleanConversationTitle(parts[3])
                result[conversationKey(.codex, id)] = ConversationInfo(
                    title: title,
                    workspace: parts[2].isEmpty ? nil : parts[2],
                    preview: parts[3].isEmpty ? nil : parts[3]
                )
            }
        }
        return result
    }

    private func recentEventSessionIDs() -> [AgentFamily: Set<String>] {
        let url = home.appendingPathComponent(".agent-island/events.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        let decoder = JSONDecoder()
        var result: [AgentFamily: Set<String>] = [:]
        for line in text.split(separator: "\n").suffix(1200) {
            guard let data = String(line).data(using: .utf8),
                  let event = try? decoder.decode(AgentEvent.self, from: data),
                  let family = normalizeFamily(event.family ?? event.agent),
                  let session = event.session,
                  !session.isEmpty else {
                continue
            }
            result[family, default: []].insert(session)
        }
        return result
    }

    private func readClaudeConversationInfo(sessionIDs: Set<String>) -> [String: ConversationInfo] {
        guard !sessionIDs.isEmpty else { return [:] }
        let root = home.appendingPathComponent(".claude/projects")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var remaining = sessionIDs
        var result: [String: ConversationInfo] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let session = url.deletingPathExtension().lastPathComponent
            guard remaining.contains(session) else { continue }

            let workspaceName = claudeWorkspaceName(from: url)
            let title = extractClaudeConversationTitle(from: url)
                ?? workspaceName
                ?? "Claude \(shortSession(session))"
            result[conversationKey(.claude, session)] = ConversationInfo(
                title: title,
                workspace: workspaceName,
                preview: nil
            )
            remaining.remove(session)
            if remaining.isEmpty { break }
        }
        return result
    }

    private func claudeWorkspaceName(from sessionURL: URL) -> String? {
        let folder = sessionURL.deletingLastPathComponent().lastPathComponent
        guard !folder.isEmpty else { return nil }
        if let tail = folder.components(separatedBy: "----").last, !tail.isEmpty {
            return tail
        }
        return folder
    }

    private func extractClaudeConversationTitle(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 700_000)
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var candidate: String?
        for line in text.split(separator: "\n").prefix(180) {
            guard let data = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "user" else {
                continue
            }
            let raw = claudeUserText(from: json) ?? ""
            let cleaned = AgentText.singleLine(raw)
            guard !cleaned.isEmpty else { continue }
            if cleaned.contains("This session is being continued from a previous conversation") {
                candidate = continuationTitle(from: cleaned) ?? candidate ?? "继续上一段对话"
                continue
            }
            guard let title = AgentText.meaningfulConversationTitle(cleaned) else { continue }
            candidate = title
        }
        return candidate
    }

    private func continuationTitle(from text: String) -> String? {
        for marker in ["Primary Request and Intent:", "Summary:"] {
            guard let range = text.range(of: marker) else { continue }
            let tail = text[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tail.isEmpty else { continue }
            let stopTokens = [". ", "。", "; ", "；"]
            let stop = stopTokens
                .compactMap { token in tail.range(of: token)?.lowerBound }
                .min()
            if let stop {
                return String(tail[..<stop])
            }
            return String(tail.prefix(120))
        }
        return nil
    }

    private func claudeUserText(from json: [String: Any]) -> String? {
        guard let message = json["message"] as? [String: Any] else { return nil }
        let content = message["content"]
        if let text = content as? String {
            return text
        }
        if let chunks = content as? [[String: Any]] {
            let parts = chunks.compactMap { chunk -> String? in
                if let text = chunk["text"] as? String {
                    return text
                }
                return nil
            }
            return parts.joined(separator: " ")
        }
        return nil
    }

    private func conversationKey(_ family: AgentFamily, _ session: String) -> String {
        "\(family.rawValue)::\(session)"
    }

    private func eventRollups(rows: [ProcessRow]) -> [String: AgentEventRollup] {
        let url = home.appendingPathComponent(".agent-island/events.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        let processMap = rows.reduce(into: [Int: ProcessRow]()) { partial, row in
            partial[row.pid] = row
        }

        let now = Date().timeIntervalSince1970
        let lines = text.split(separator: "\n").suffix(1200)
        var resolvedEvents: [ResolvedAgentEvent] = []
        var seenEventKeys: Set<String> = []
        let decoder = JSONDecoder()

        for line in lines {
            guard let data = String(line).data(using: .utf8),
                  let event = try? decoder.decode(AgentEvent.self, from: data),
                  let family = normalizeFamily(event.family ?? event.agent),
                  let phase = normalizeEventPhase(event) else {
                continue
            }
            let rawSurface = normalizeSurface(event.surface ?? event.channel) ?? .cli
            let surface = resolvedSurface(
                for: event,
                family: family,
                defaultSurface: rawSurface,
                processMap: processMap
            )
            let ts = event.ts ?? 0
            guard ts > 0, now - ts <= 24 * 60 * 60 else { continue }

            let session = event.session?.isEmpty == false
                ? event.session!
                : event.pid.map { "pid:\($0)" } ?? "global:\(family.rawValue)-\(surface.rawValue)"
            let hookEvent = normalizeHookEventName(event)
            let dedupeKey = [
                family.rawValue,
                surface.rawValue,
                session,
                hookEvent,
                event.tool ?? "",
                event.pid.map(String.init) ?? "",
                String(Int(ts * 1000))
            ].joined(separator: "\u{1F}")
            guard !seenEventKeys.contains(dedupeKey) else { continue }
            seenEventKeys.insert(dedupeKey)
            resolvedEvents.append(
                ResolvedAgentEvent(
                    family: family,
                    surface: surface,
                    session: session,
                    event: event,
                    hookEvent: hookEvent,
                    normalizedPhase: phase,
                    ts: ts
                )
            )
        }

        return AgentSessionStore.rollups(from: resolvedEvents, now: now)
    }

    private func resolvedSurface(
        for event: AgentEvent,
        family: AgentFamily,
        defaultSurface: AgentSurface,
        processMap: [Int: ProcessRow]
    ) -> AgentSurface {
        let commands = commandChain(startingAt: event.pid, in: processMap)
        guard !commands.isEmpty else { return defaultSurface }

        switch family {
        case .codex:
            if commands.contains(where: isCodexAppProcess) { return .app }
            if commands.contains(where: isCodexCLIProcess) { return .cli }
        case .claude:
            if commands.contains(where: isClaudeAppProcess) { return .app }
            if commands.contains(where: isClaudeCLIProcess) { return .cli }
        case .claudeScience, .chatgpt:
            break
        }

        return defaultSurface
    }

    private func commandChain(startingAt pid: Int?, in processMap: [Int: ProcessRow]) -> [String] {
        guard var currentPID = pid else { return [] }
        var commands: [String] = []
        var seen: Set<Int> = []

        for _ in 0..<8 {
            guard !seen.contains(currentPID),
                  let row = processMap[currentPID] else {
                break
            }
            seen.insert(currentPID)
            commands.append(row.command)
            guard let nextPID = row.ppid, nextPID > 0, nextPID != currentPID else {
                break
            }
            currentPID = nextPID
        }

        return commands
    }

    private func conversationInfo(
        for event: AgentEvent,
        family: AgentFamily,
        conversations: [String: ConversationInfo]
    ) -> ConversationInfo? {
        guard let session = event.session, !session.isEmpty else { return nil }
        return conversations[conversationKey(family, session)]
    }

    private func eventActionText(
        _ event: AgentEvent,
        hookEvent: String,
        phase: AgentPhase,
        conversation: ConversationInfo?
    ) -> String {
        let tool = event.tool ?? ""
        switch hookEvent {
        case "pretooluse", "beforetool", "preinvocation":
            let base = tool.isEmpty ? "任务执行中" : "工具: \(tool)"
            if let input = toolInputText(event) {
                return "\(base) · \(input)"
            }
            return base
        case "posttooluse", "afteragent":
            return tool.isEmpty ? "步骤完成" : "完成工具: \(tool)"
        case "userpromptsubmit":
            return "收到任务"
        case "sessionstart", "startup", "init":
            return "会话开始"
        case "stop", "sessionend", "postinvocation", "subagentstop":
            return "本轮结束"
        case "permissionrequest", "elicitation", "posttoolusefailure":
            let base = tool.isEmpty ? "等待人工确认" : "等待允许/处理: \(tool)"
            return appendRiskText(to: base, event: event)
        case "stopfailure":
            return tool.isEmpty ? "任务执行失败" : "工具失败: \(tool)"
        default:
            if let message = event.message, !message.isEmpty {
                return stripWorkspaceSuffix(message, conversation: conversation)
            }
            return phase.label
        }
    }

    private func appendRiskText(to text: String, event: AgentEvent) -> String {
        var parts = [text]
        if let input = toolInputText(event) {
            parts.append(input)
        }
        if let risk = toolRiskText(event) {
            parts.append(risk)
        }
        return parts.joined(separator: " · ")
    }

    private func toolInputText(_ event: AgentEvent) -> String? {
        guard let raw = event.toolInputSummary else { return nil }
        let text = AgentText.singleLine(raw)
        guard !text.isEmpty else { return nil }
        return AgentText.compact(text, limit: 76)
    }

    private func toolRiskText(_ event: AgentEvent) -> String? {
        guard let raw = event.toolRisk?.lowercased(),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        switch raw {
        case "safe_read":
            return event.autoApprovalEligible == true ? "只读可自动" : "只读"
        case "manual_safe_shell":
            return "Shell 需确认"
        case "dangerous_shell", "dangerous_tool":
            return "危险需人工"
        case "manual_unknown":
            return "未分类需人工"
        default:
            return nil
        }
    }

    private func conversationIdentityText(_ event: AgentEvent, conversation: ConversationInfo?) -> String {
        var parts: [String] = []
        if let session = event.session, !session.isEmpty {
            parts.append("session \(shortSession(session))")
        }
        if let workspace = conversation?.workspaceName, !workspace.isEmpty {
            parts.append(workspace)
        }
        return parts.joined(separator: " · ")
    }

    private func stripWorkspaceSuffix(_ message: String, conversation: ConversationInfo?) -> String {
        var text = AgentText.singleLine(message)
        if let workspace = conversation?.workspaceName, !workspace.isEmpty {
            let suffix = " · \(workspace)"
            if text.hasSuffix(suffix) {
                text.removeLast(suffix.count)
            }
        }
        return text
    }

    private func shortSession(_ session: String) -> String {
        guard session.count > 8 else { return session }
        return String(session.prefix(8))
    }

    private func makeEventSnapshots(
        from events: [String: AgentEventRollup],
        conversations: [String: ConversationInfo]
    ) -> [AgentSnapshot] {
        events.values.compactMap { rollup in
            guard let family = rollup.family,
                  let surface = rollup.surface,
                  let session = rollup.session,
                  let event = rollup.displayEvent,
                  let phase = rollup.displayPhase else {
                return nil
            }

            let now = Date().timeIntervalSince1970
            let ts = event.ts ?? now
            guard now - ts <= eventMaxAge(for: phase) else { return nil }

            let hookEvent = normalizeHookEventName(event)
            let conversation = conversationInfo(for: event, family: family, conversations: conversations)
            var snapshot = AgentSnapshot.empty(family, surface)
            snapshot.sessionID = session
            snapshot.phase = phase
            snapshot.targetPID = event.pid
            snapshot.jumpTarget = jumpTarget(for: event, family: family, surface: surface, session: session)
            snapshot.requestID = event.requestID
            snapshot.toolInputSummary = event.toolInputSummary
            snapshot.toolRisk = event.toolRisk
            snapshot.toolRiskReason = event.toolRiskReason
            snapshot.autoApprovalEligible = event.autoApprovalEligible
            snapshot.lastUpdated = Date(timeIntervalSince1970: ts)

            switch phase {
            case .working:
                snapshot.runningCount = 1
            case .needsAttention, .error:
                snapshot.blockedCount = 1
            case .queued:
                snapshot.pendingCount = 1
            case .done:
                snapshot.completedCount = 1
            case .thinking, .online, .idle, .offline:
                break
            }

            if let conversation {
                snapshot.title = "\(family.displayName) \(surface.displayName) · \(conversation.shortTitle)"
            } else {
                snapshot.title = "\(family.displayName) \(surface.displayName) · session \(shortSession(session))"
            }

            if hookEvent == "posttoolusefailure", phase == .needsAttention {
                let action = eventActionText(event, hookEvent: hookEvent, phase: phase, conversation: conversation)
                let identity = conversationIdentityText(event, conversation: conversation)
                snapshot.detail = [action, identity].filter { !$0.isEmpty }.joined(separator: " · ")
            } else {
                let action = eventActionText(event, hookEvent: hookEvent, phase: phase, conversation: conversation)
                let identity = conversationIdentityText(event, conversation: conversation)
                snapshot.detail = [action, identity].filter { !$0.isEmpty }.joined(separator: " · ")
                if snapshot.detail.isEmpty {
                    snapshot.detail = "session \(shortSession(session))"
                }
            }

            return snapshot
        }
    }

    private func jumpTarget(
        for event: AgentEvent,
        family: AgentFamily,
        surface: AgentSurface,
        session: String?
    ) -> JumpTarget? {
        if family == .codex,
           surface == .app,
           let session,
           !session.isEmpty,
           !session.hasPrefix("pid:"),
           !session.hasPrefix("global:") {
            let encoded = session.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? session
            return .url("codex://threads/\(encoded)")
        }

        if family == .chatgpt, surface == .web {
            return .chatGPTWeb
        }

        if surface == .cli {
            let terminal = TerminalJumpTarget(
                appName: event.terminalApp,
                bundleID: event.terminalBundleID,
                pid: event.pid,
                tty: event.terminalTTY,
                cwd: event.cwd,
                windowID: event.terminalWindowID,
                tabIndex: event.terminalTabIndex,
                sessionIdentifier: event.terminalSessionID,
                title: nil
            )

            if hasValue(event.terminalTmuxPane) {
                return .tmux(TmuxJumpTarget(
                    pane: event.terminalTmuxPane,
                    socket: event.terminalTmuxSocket,
                    client: event.terminalTmuxClient,
                    terminal: terminal
                ))
            }

            if hasTerminalIdentity(terminal) {
                return .terminal(terminal)
            }

            if let pid = event.pid {
                return .process(pid: pid)
            }
        }

        return nil
    }

    private func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func hasTerminalIdentity(_ target: TerminalJumpTarget) -> Bool {
        hasValue(target.appName)
            || hasValue(target.bundleID)
            || hasValue(target.tty)
            || hasValue(target.cwd)
            || hasValue(target.sessionIdentifier)
            || target.pid != nil
    }

    private func applyEventRollup(
        to snapshot: AgentSnapshot,
        events: [String: AgentEventRollup],
        conversations: [String: ConversationInfo]
    ) -> AgentSnapshot {
        guard let rollup = events[snapshot.id],
              let event = rollup.displayEvent,
              let phase = rollup.displayPhase else {
            return snapshot
        }

        let now = Date().timeIntervalSince1970
        let ts = event.ts ?? now
        let age = now - ts
        let maxAge = eventMaxAge(for: phase)

        guard age <= maxAge else { return snapshot }

        var next = snapshot
        next.phase = phase
        next.runningCount = max(next.runningCount, rollup.workingCount)
        next.blockedCount = max(next.blockedCount, rollup.attentionCount)
        next.pendingCount = max(next.pendingCount, rollup.queuedCount)
        next.completedCount = max(next.completedCount, rollup.doneCount)
        let hookEvent = normalizeHookEventName(event)
        let conversation = conversationInfo(for: event, family: snapshot.family, conversations: conversations)

        if hookEvent == "posttoolusefailure", phase == .needsAttention {
            next.title = "\(snapshot.family.displayName) 需要确认"
        } else if let conversation {
            next.title = "\(snapshot.family.displayName) \(snapshot.surface.displayName) · \(conversation.shortTitle)"
        } else if let title = event.title, !title.isEmpty {
            next.title = title
        }

        if rollup.workingCount > 1, phase == .working {
            if let conversation {
                next.title = "\(snapshot.family.displayName) \(snapshot.surface.displayName) · \(conversation.shortTitle) +\(rollup.workingCount - 1)"
            } else {
                next.title = "\(snapshot.family.displayName) \(snapshot.surface.displayName) · \(rollup.workingCount) 工作中"
            }
        } else if rollup.attentionCount > 1, phase == .needsAttention {
            if let conversation {
                next.title = "\(snapshot.family.displayName) \(snapshot.surface.displayName) · \(conversation.shortTitle) +\(rollup.attentionCount - 1)"
            } else {
                next.title = "\(snapshot.family.displayName) \(snapshot.surface.displayName) · \(rollup.attentionCount) 需处理"
            }
        }

        if hookEvent == "posttoolusefailure", phase == .needsAttention {
            next.detail = eventActionText(event, hookEvent: hookEvent, phase: phase, conversation: conversation)
        } else if conversation != nil {
            let action = eventActionText(event, hookEvent: hookEvent, phase: phase, conversation: conversation)
            let identity = conversationIdentityText(event, conversation: conversation)
            next.detail = [action, identity].filter { !$0.isEmpty }.joined(separator: " · ")
        } else if let message = event.message, !message.isEmpty {
            next.detail = message
        } else if let session = event.session, !session.isEmpty {
            next.detail = "session \(session)"
        }
        if !rollup.countSummary.isEmpty {
            next.detail += " · \(rollup.countSummary)"
        }
        if let pid = event.pid {
            next.targetPID = pid
        }
        next.requestID = event.requestID
        next.toolInputSummary = event.toolInputSummary
        next.toolRisk = event.toolRisk
        next.toolRiskReason = event.toolRiskReason
        next.autoApprovalEligible = event.autoApprovalEligible
        next.lastUpdated = Date(timeIntervalSince1970: ts)
        return next
    }

    private func eventMaxAge(for phase: AgentPhase) -> TimeInterval {
        switch phase {
        case .working: return 30 * 60
        case .thinking: return 3 * 60
        case .queued: return 30 * 60
        case .needsAttention: return 24 * 60 * 60
        case .done: return 10 * 60
        case .error: return 24 * 60 * 60
        case .online: return 60 * 60
        case .idle: return 60 * 60
        case .offline: return 60 * 60
        }
    }

    private func normalizeFamily(_ raw: String?) -> AgentFamily? {
        guard let raw else { return nil }
        let value = raw.lowercased()
        if value.contains("claude_science") || value.contains("claudescience") || value.contains("claude science") || value.contains("operon") {
            return .claudeScience
        }
        if value.contains("codex") { return .codex }
        if value.contains("claude") { return .claude }
        return nil
    }

    private func normalizeSurface(_ raw: String?) -> AgentSurface? {
        guard let raw else { return .cli }
        let value = raw.lowercased()
        if value.contains("app") || value.contains("desktop") { return .app }
        if value.contains("runtime") || value.contains("server") || value.contains("service") || value.contains("kernel") { return .runtime }
        if value.contains("cli") || value.contains("terminal") || value.contains("code") { return .cli }
        return .cli
    }

    private func normalizePhase(_ raw: String?) -> AgentPhase? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "needs_attention", "needsattention", "attention", "approval", "permission", "input_required", "inputrequired", "blocked", "human":
            return .needsAttention
        case "working", "running", "active", "start", "started", "progress", "busy":
            return .working
        case "thinking", "think":
            return .thinking
        case "queued", "todo", "pending", "waiting":
            return .queued
        case "done", "complete", "completed", "success", "finished", "finish":
            return .done
        case "error", "failed", "failure":
            return .error
        case "online", "available":
            return .online
        case "idle":
            return .idle
        case "offline", "stopped":
            return .offline
        default:
            return nil
        }
    }

    private func normalizeEventPhase(_ event: AgentEvent) -> AgentPhase? {
        let rawEvent = (event.title ?? "") + " " + (event.message ?? "")
        let hookEvent = normalizeHookEventName(event)
        if hookEvent == "stop" || hookEvent == "sessionend" || hookEvent == "postinvocation" || hookEvent == "subagentstop" {
            return .idle
        }
        if hookEvent == "userpromptsubmit" {
            return .queued
        }
        if hookEvent == "permissionrequest" || hookEvent == "elicitation" {
            return .needsAttention
        }
        if hookEvent == "posttoolusefailure" {
            return .needsAttention
        }
        if rawEvent.contains("本轮结束") || rawEvent.contains("子任务结束") {
            return .idle
        }
        return normalizePhase(event.phase ?? event.status)
    }

    private func normalizeHookEventName(_ event: AgentEvent) -> String {
        (event.event ?? "")
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func readClaudeTaskSummary() -> ClaudeTaskSummary {
        let root = home.appendingPathComponent(".claude/tasks")
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ClaudeTaskSummary()
        }

        let decoder = JSONDecoder()
        let now = Date()
        var summary = ClaudeTaskSummary()

        for case let url as URL in enumerator {
            guard url.pathExtension == "json" else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard now.timeIntervalSince(modified) < 14 * 24 * 60 * 60 else { continue }
            guard let data = try? Data(contentsOf: url),
                  let task = try? decoder.decode(ClaudeTask.self, from: data) else {
                continue
            }

            let status = (task.status ?? "").lowercased()
            let title = task.activeForm ?? task.subject
            let isBlocked = !(task.blocks ?? []).isEmpty || !(task.blockedBy ?? []).isEmpty || status == "blocked"
            if isBlocked {
                summary.blockedCount += 1
                if summary.latestBlockedTitle == nil || modified > (summary.latestModified ?? .distantPast) {
                    summary.latestBlockedTitle = title
                }
            } else if status == "running" || status == "in_progress" || status == "active" {
                summary.runningCount += 1
                if summary.latestRunningTitle == nil || modified > (summary.latestModified ?? .distantPast) {
                    summary.latestRunningTitle = title
                }
            } else if status == "pending" || status == "todo" || status == "queued" {
                summary.pendingCount += 1
                if summary.latestPendingTitle == nil || modified > (summary.latestModified ?? .distantPast) {
                    summary.latestPendingTitle = title
                }
            }
            if status == "completed" && now.timeIntervalSince(modified) < 24 * 60 * 60 {
                summary.completedRecentCount += 1
                if summary.latestCompletedTitle == nil || modified > (summary.latestModified ?? .distantPast) {
                    summary.latestCompletedTitle = title
                }
            }
            if summary.latestModified == nil || modified > (summary.latestModified ?? .distantPast) {
                summary.latestModified = modified
                summary.latestStatus = status
            }
        }

        return summary
    }

    private func readCodexGoalSummary() -> CodexGoalSummary {
        let path = home.appendingPathComponent(".codex/sqlite/goals_1.sqlite").path
        guard FileManager.default.fileExists(atPath: path) else { return CodexGoalSummary() }

        let sql = """
        select status, replace(replace(objective, char(10), ' '), '|', '/'), updated_at_ms
        from thread_goals
        order by updated_at_ms desc
        limit 50;
        """
        let output = runCommand(
            executable: "/usr/bin/sqlite3",
            arguments: ["file:\(path)?mode=ro&immutable=1", sql]
        )

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var summary = CodexGoalSummary()
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3, let updatedMs = Int64(parts[2]) else { continue }
            let status = parts[0].lowercased()
            let title = parts[1]
            let modified = Date(timeIntervalSince1970: TimeInterval(updatedMs) / 1000)
            if summary.latestModified == nil || modified > (summary.latestModified ?? .distantPast) {
                summary.latestModified = modified
            }
            switch status {
            case "blocked", "usage_limited", "budget_limited":
                summary.blockedCount += 1
                if summary.latestBlockedTitle == nil { summary.latestBlockedTitle = title }
            case "active":
                // Active goals can persist while a thread is idle, so only treat
                // recently-updated active goals as real work.
                if nowMs - updatedMs <= 10 * 60 * 1000 {
                    summary.activeCount += 1
                    if summary.latestActiveTitle == nil { summary.latestActiveTitle = title }
                }
            case "complete":
                if nowMs - updatedMs <= 60 * 60 * 1000 {
                    summary.completedRecentCount += 1
                    if summary.latestCompletedTitle == nil { summary.latestCompletedTitle = title }
                }
            default:
                break
            }
        }
        return summary
    }

    private func readClaudeScienceSummary(rows: [ProcessRow]) -> ClaudeScienceSummary {
        guard let path = claudeScienceDatabasePath() else {
            var summary = ClaudeScienceSummary()
            summary.kernelCount = claudeScienceKernelRows(from: rows).count
            return summary
        }

        let sql = """
        select status,
               replace(replace(coalesce(nullif(name, ''), nullif(task_summary, ''), nullif(agent_name, ''), id), char(10), ' '), '|', '/'),
               replace(replace(coalesce(nullif(agent_name, ''), id), char(10), ' '), '|', '/'),
               updated_at
        from frames
        where parent_frame_id is null
        order by updated_at desc
        limit 120;
        """
        let output = runCommand(
            executable: "/usr/bin/sqlite3",
            arguments: ["file:\(path)?mode=ro&immutable=1", sql]
        )

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var summary = ClaudeScienceSummary()
        summary.kernelCount = claudeScienceKernelRows(from: rows).count

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 3).map(String.init)
            guard parts.count == 4, let updatedMs = Int64(parts[3]) else { continue }
            let status = parts[0].lowercased()
            let rawTitle = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let agentName = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = scienceTitle(rawTitle, fallback: agentName)
            let modified = Date(timeIntervalSince1970: TimeInterval(updatedMs) / 1000)
            if summary.latestModified == nil || modified > (summary.latestModified ?? .distantPast) {
                summary.latestModified = modified
            }

            switch status {
            case "blocked", "needs_attention", "error", "failed":
                summary.awaitingCount += 1
                if summary.latestAwaitingTitle == nil { summary.latestAwaitingTitle = title }
            case "awaiting_user_response":
                summary.queuedCount += 1
                if summary.latestQueuedTitle == nil { summary.latestQueuedTitle = title }
            case "processing", "running", "in_progress", "executing":
                if nowMs - updatedMs <= 30 * 60 * 1000 {
                    summary.processingCount += 1
                    if summary.latestProcessingTitle == nil { summary.latestProcessingTitle = title }
                }
            case "queued", "pending":
                summary.queuedCount += 1
                if summary.latestQueuedTitle == nil { summary.latestQueuedTitle = title }
            case "completed", "complete", "succeeded", "success":
                if nowMs - updatedMs <= 60 * 60 * 1000 {
                    summary.completedRecentCount += 1
                    if summary.latestCompletedTitle == nil { summary.latestCompletedTitle = title }
                }
            default:
                break
            }
        }

        return summary
    }

    private func claudeScienceDatabasePath() -> String? {
        let activeOrgURL = home.appendingPathComponent(".claude-science/active-org.json")
        if let data = try? Data(contentsOf: activeOrgURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let org = json["org_uuid"] as? String {
            let path = home.appendingPathComponent(".claude-science/orgs/\(org)/operon-cli.db").path
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        let orgRoot = home.appendingPathComponent(".claude-science/orgs")
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: orgRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls
            .map { $0.appendingPathComponent("operon-cli.db") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            .first?
            .path
    }

    private func scienceTitle(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return fallback.isEmpty ? "Science frame" : fallback
        }
        return trimmed
    }

    private func runAppleScript(_ source: String) -> String {
        let arguments = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { ["-e", String($0)] }
        return runCommand(executable: "/usr/bin/osascript", arguments: arguments)
    }

    private func runCommand(executable: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

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

struct IslandView: View {
    @ObservedObject var monitor: AgentMonitor
    var onExpandedChange: (Bool) -> Void = { _ in }
    var onSnapshotAction: (AgentSnapshot) -> Void = { _ in }
    @StateObject private var expansion = IslandExpansionController()
    @State private var pulse = false
    @State private var orbit = false
    @State private var previousPhaseByID: [String: AgentPhase] = [:]
    @State private var copiedSnapshotID: String?

    private var expanded: Bool {
        expansion.expanded
    }

    private var spotlightSnapshot: AgentSnapshot? {
        expansion.spotlightSnapshot
    }

    private var activeSnapshots: [AgentSnapshot] {
        monitor.snapshots.filter { $0.phase != .offline }
    }

    private var displaySnapshots: [AgentSnapshot] {
        expanded ? monitor.snapshots : Array(activeSnapshots.prefix(3))
    }

    private var screenVisibleSize: CGSize {
        NSScreen.main?.visibleFrame.size ?? CGSize(width: 900, height: 700)
    }

    private var capsuleWidth: CGFloat {
        let preferred: CGFloat = expanded ? 560 : 430
        let minimum: CGFloat = expanded ? 360 : 300
        let available = max(260, screenVisibleSize.width - IslandPanelSizing.screenInset * 2 - 48)
        return min(preferred, max(minimum, available))
    }

    private var rowsMaxHeight: CGFloat {
        let spotlightHeight: CGFloat = spotlightSnapshot == nil ? 0 : 58
        let availableCapsuleHeight = max(150, screenVisibleSize.height - IslandPanelSizing.screenInset * 2)
        let availableRows = availableCapsuleHeight - 81 - spotlightHeight
        return min(184, max(82, availableRows))
    }

    private var rowsViewportHeight: CGFloat {
        let visibleCount = min(max(displaySnapshots.count, 1), 4)
        let base = CGFloat(visibleCount) * 34 + CGFloat(max(visibleCount - 1, 0)) * 8
        let preferred = displaySnapshots.count > 4 ? min(base + 16, 184) : base
        return min(preferred, rowsMaxHeight)
    }

    private var capsuleHeight: CGFloat {
        let preferred = expanded ? 81 + rowsViewportHeight + (spotlightSnapshot == nil ? 0 : 58) : 44
        return min(preferred, max(44, screenVisibleSize.height - IslandPanelSizing.screenInset * 2))
    }

    var body: some View {
        VStack(spacing: 0) {
            island
                .frame(width: capsuleWidth, height: capsuleHeight, alignment: .top)
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: expanded)
                .onHover { isHovering in
                    expansion.handleHoverChange(isHovering)
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 2)
        .onAppear {
            expansion.onExpandedChange = onExpandedChange
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                orbit = true
            }
        }
        .onChange(of: monitor.snapshots) { snapshots in
            handleSnapshotChanges(snapshots)
        }
        .onReceive(NotificationCenter.default.publisher(for: AgentIslandControlKeys.collapseRequested)) { _ in
            expansion.dismissByUser()
        }
        .onReceive(NotificationCenter.default.publisher(for: AgentIslandControlKeys.toggleRequested)) { _ in
            expansion.toggleFromHeader()
        }
    }

    private var island: some View {
        VStack(spacing: expanded ? 12 : 0) {
            header

            if expanded {
                Divider()
                    .overlay(Color.white.opacity(0.12))
                if let spotlightSnapshot {
                    SpotlightSummary(
                        snapshot: spotlightSnapshot,
                        pulse: pulse,
                        copied: copiedSnapshotID == spotlightSnapshot.id,
                        onOpen: {
                            openSnapshot(spotlightSnapshot)
                        },
                        onCopy: {
                            copySnapshotSummary(spotlightSnapshot)
                        },
                        onDismiss: {
                            expansion.dismissByUser()
                        }
                    )
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                rows
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, expanded ? 18 : 14)
        .padding(.vertical, expanded ? 14 : 8)
        .background(backgroundShape)
        .overlay(borderShape)
        .shadow(color: Color.black.opacity(0.35), radius: expanded ? 22 : 12, x: 0, y: 10)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                expansion.toggleFromHeader()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [.green, .orange, .cyan, .pink, .green],
                                    center: .center,
                                    angle: .degrees(orbit ? 360 : 0)
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 27, height: 27)
                            .opacity(monitor.activeCount > 0 ? 1 : 0.55)

                        Circle()
                            .fill(statusColor)
                            .frame(width: pulse && monitor.activeCount > 0 ? 12 : 9, height: pulse && monitor.activeCount > 0 ? 12 : 9)
                            .shadow(color: statusColor.opacity(0.8), radius: monitor.activeCount > 0 ? 8 : 2)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Agent Island")
                            .font(.system(size: expanded ? 13 : 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(monitor.headline)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.62))
                    }
                }
            }
            .buttonStyle(.plain)
            .help(expanded ? "收起 Agent Island" : "展开 Agent Island")

            Spacer(minLength: 8)

            compactBadges

            if monitor.activeCount > 0 {
                ActivityBars(color: statusColor)
                    .frame(width: 38, height: 20)
            } else {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            if expanded {
                Button {
                    expansion.dismissByUser()
                } label: {
                    Image(systemName: spotlightSnapshot == nil ? "chevron.up" : "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help(spotlightSnapshot == nil ? "收起 Agent Island" : "关闭本次提示")
            }
        }
        .frame(height: 28)
    }

    private var compactBadges: some View {
        HStack(spacing: -2) {
            ForEach(activeSnapshots.prefix(5)) { snapshot in
                Button {
                    openSnapshot(snapshot)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 24, height: 24)
                        Circle()
                            .fill(snapshot.family.tint)
                            .frame(width: 17, height: 17)
                            .overlay {
                                Image(systemName: snapshot.surface.icon)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.black.opacity(0.82))
                            }
                        }
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("点击跳转到 \(snapshot.title): \(snapshot.phase.label)")
            }
        }
    }

    private var rows: some View {
        ScrollView(.vertical, showsIndicators: displaySnapshots.count > 4) {
            VStack(spacing: 8) {
                ForEach(displaySnapshots) { snapshot in
                    AgentRow(
                        snapshot: snapshot,
                        pulse: pulse,
                        copied: copiedSnapshotID == snapshot.id,
                        onOpen: {
                            openSnapshot(snapshot)
                        },
                        onCopy: {
                            copySnapshotSummary(snapshot)
                        }
                    )
                    .help("点击跳转到 \(snapshot.title)")
                }
            }
            .padding(.vertical, 1)
        }
        .frame(height: rowsViewportHeight)
    }

    private func openSnapshot(_ snapshot: AgentSnapshot) {
        onSnapshotAction(snapshot)
        expansion.dismissAfterSnapshotAction()
    }

    private func copySnapshotSummary(_ snapshot: AgentSnapshot) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AgentSnapshotSummary.text(for: snapshot), forType: .string)
        withAnimation(.easeInOut(duration: 0.12)) {
            copiedSnapshotID = snapshot.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedSnapshotID == snapshot.id {
                withAnimation(.easeInOut(duration: 0.12)) {
                    copiedSnapshotID = nil
                }
            }
        }
    }

    private func handleSnapshotChanges(_ snapshots: [AgentSnapshot]) {
        defer {
            previousPhaseByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0.phase) })
        }

        guard !previousPhaseByID.isEmpty else { return }
        guard let snapshot = snapshots.first(where: shouldSpotlight) else { return }
        let previous = previousPhaseByID[snapshot.id]
        guard previous != nil, previous != snapshot.phase else { return }
        expansion.showSpotlight(snapshot, duration: autoSpotlightDuration(for: snapshot))
    }

    private func shouldSpotlight(_ snapshot: AgentSnapshot) -> Bool {
        switch snapshot.phase {
        case .needsAttention, .queued, .done, .error, .working, .thinking:
            return true
        case .online, .idle, .offline:
            return false
        }
    }

    private func autoSpotlightDuration(for snapshot: AgentSnapshot) -> TimeInterval {
        switch snapshot.phase {
        case .done:
            return 4
        case .needsAttention, .error:
            return 9
        case .queued, .working, .thinking:
            return 5
        case .online, .idle, .offline:
            return 0
        }
    }

    private var statusColor: Color {
        if monitor.attentionCount > 0 { return .orange }
        if monitor.activeCount > 0 { return .green }
        if monitor.thinkingCount > 0 { return .cyan }
        if monitor.queuedCount > 0 { return .yellow }
        if monitor.doneCount > 0 { return .blue }
        return Color.white.opacity(0.42)
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: expanded ? 28 : 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.92),
                        Color(red: 0.06, green: 0.07, blue: 0.08).opacity(0.91)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: expanded ? 28 : 22, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .blendMode(.screen)
            }
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: expanded ? 28 : 22, style: .continuous)
            .stroke(Color.white.opacity(expanded ? 0.15 : 0.1), lineWidth: 1)
    }
}

struct AgentRow: View {
    var snapshot: AgentSnapshot
    var pulse: Bool
    var copied: Bool = false
    var onOpen: () -> Void = {}
    var onCopy: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onOpen()
            } label: {
                mainContent
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if snapshot.hasQuickActions {
                quickActions
            }

            phaseBadge
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(hovering ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
    }

    private var mainContent: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(snapshot.family.tint.opacity(0.18))
                    .frame(width: 31, height: 31)
                Image(systemName: snapshot.surface.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(snapshot.family.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snapshot.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    rowBadges
                }

                Text(detailText)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var quickActions: some View {
        HStack(spacing: 4) {
            Button {
                onCopy()
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(copied ? .green : Color.white.opacity(0.72))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(copied ? 0.13 : 0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help(copied ? "已复制摘要" : "复制推进摘要")

            Button {
                onOpen()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("打开对应会话")
        }
    }

    private var phaseBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.phase.icon)
                .font(.system(size: 10, weight: .bold))
            Text(snapshot.phase.label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(phaseColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(phaseColor.opacity(snapshot.phase == .offline ? 0.08 : 0.14), in: Capsule())
        .overlay {
            if snapshot.phase == .working || snapshot.phase == .needsAttention {
                Capsule()
                    .stroke(phaseColor.opacity(pulse ? 0.18 : 0.45), lineWidth: 1)
            }
        }
    }

    private var phaseColor: Color {
        switch snapshot.phase {
        case .needsAttention: return .orange
        case .working: return .green
        case .thinking: return .cyan
        case .queued: return .yellow
        case .done: return .blue
        case .error: return .red
        case .online: return Color.white.opacity(0.62)
        case .idle: return Color.white.opacity(0.54)
        case .offline: return Color.white.opacity(0.28)
        }
    }

    private var detailText: String {
        guard let lastUpdated = snapshot.lastUpdated else { return snapshot.detail }
        let age = max(0, Date().timeIntervalSince(lastUpdated))
        let label: String
        if age < 8 {
            label = "刚刚"
        } else if age < 60 {
            label = "\(Int(age)) 秒前"
        } else if age < 60 * 60 {
            label = "\(Int(age / 60)) 分钟前"
        } else if age < 24 * 60 * 60 {
            label = "\(Int(age / 3600)) 小时前"
        } else {
            return snapshot.detail
        }
        return "\(snapshot.detail) · \(label)"
    }

    @ViewBuilder
    private var rowBadges: some View {
        if snapshot.blockedCount > 0 {
            CountBadge(value: snapshot.blockedCount, color: .orange)
        }
        if snapshot.runningCount > 0 {
            CountBadge(value: snapshot.runningCount, color: .green)
        }
        if snapshot.pendingCount > 0 {
            CountBadge(value: snapshot.pendingCount, color: .yellow)
        }
        if snapshot.completedCount > 0 {
            CountBadge(value: snapshot.completedCount, color: .blue)
        }
    }
}

struct SpotlightSummary: View {
    var snapshot: AgentSnapshot
    var pulse: Bool
    var copied: Bool = false
    var onOpen: () -> Void = {}
    var onCopy: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(phaseColor.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: snapshot.phase.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(phaseColor)
                    .scaleEffect(pulse && (snapshot.phase == .working || snapshot.phase == .needsAttention) ? 1.08 : 1.0)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(snapshot.phase.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(phaseColor)
                    Text(snapshot.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(snapshot.detail)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if snapshot.hasQuickActions {
                HStack(spacing: 5) {
                    Button {
                        onCopy()
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(copied ? .green : Color.white.opacity(0.74))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(copied ? 0.13 : 0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(copied ? "已复制摘要" : "复制推进摘要")

                    Button {
                        onOpen()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.74))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("打开对应会话")
                }
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭本次提示")
        }
        .frame(height: 46)
        .padding(.horizontal, 8)
        .background(phaseColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(phaseColor.opacity(0.16), lineWidth: 1)
        }
    }

    private var phaseColor: Color {
        switch snapshot.phase {
        case .needsAttention: return .orange
        case .working: return .green
        case .thinking: return .cyan
        case .queued: return .yellow
        case .done: return .blue
        case .error: return .red
        case .online: return Color.white.opacity(0.62)
        case .idle: return Color.white.opacity(0.54)
        case .offline: return Color.white.opacity(0.28)
        }
    }
}

struct CountBadge: View {
    var value: Int
    var color: Color

    var body: some View {
        Text("\(value)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.black.opacity(0.86))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color, in: Capsule())
    }
}

struct ActivityBars: View {
    var color: Color
    @State private var animate = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color.opacity(0.86))
                    .frame(width: 4, height: animate ? CGFloat([10, 17, 7, 15, 11][index]) : CGFloat([16, 7, 14, 8, 18][index]))
                    .animation(.easeInOut(duration: 0.52 + Double(index) * 0.08).repeatForever(autoreverses: true), value: animate)
            }
        }
        .onAppear { animate = true }
    }
}

private enum IslandPanelSizing {
    static let screenInset: CGFloat = 16
    static let topGap: CGFloat = 4
    private static let collapsedHeight: CGFloat = 58
    private static let expandedHeight: CGFloat = 326

    static func size(expanded: Bool, on screen: NSScreen?) -> NSSize {
        let preferredWidth = CGFloat(expanded ? AgentSettingsStore.workingWidth : AgentSettingsStore.idleWidth)
        guard let screen else {
            return NSSize(width: preferredWidth, height: expanded ? expandedHeight : collapsedHeight)
        }

        let visible = screen.visibleFrame
        let maxWidth = max(280, visible.width - screenInset * 2)
        let minWidth = min(maxWidth, expanded ? 420 : 340)
        let width = max(minWidth, min(preferredWidth, maxWidth))

        let desiredHeight = expanded ? expandedHeight : collapsedHeight
        let maxHeight = max(collapsedHeight, visible.height - screenInset * 2)
        let height = min(desiredHeight, maxHeight)

        return NSSize(width: width, height: height)
    }
}

// Adapted from DevIsland's notch placement model (MIT, Copyright (c) 2026 nangchang).
// It prefers the physical notch center when macOS exposes auxiliary top areas, then
// falls back to the display center on non-notched displays.
private enum NotchPlacement {
    static let horizontalOffset: CGFloat = -10

    static func collectionBehavior(showInFullScreenApps: Bool = true) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary]
        if showInFullScreenApps {
            behavior.insert(.fullScreenAuxiliary)
        }
        return behavior
    }

    static func hasNotch(on screen: NSScreen) -> Bool {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return false
        }
        return !leftArea.isEmpty && !rightArea.isEmpty
    }

    static func notchCenterX(on screen: NSScreen) -> CGFloat {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea,
              !leftArea.isEmpty, !rightArea.isEmpty else {
            return round(screen.frame.midX)
        }

        let mid = (leftArea.maxX + rightArea.minX) / 2
        if mid < screen.frame.minX || mid > screen.frame.maxX {
            return round(screen.frame.minX + mid)
        }

        return round(mid)
    }

    static func frame(for panelSize: NSSize, on screen: NSScreen) -> NSRect {
        let centerX = notchCenterX(on: screen)
        let visible = screen.visibleFrame
        let desiredX = centerX - panelSize.width / 2 + horizontalOffset
        let minX = visible.minX + IslandPanelSizing.screenInset
        let maxX = visible.maxX - panelSize.width - IslandPanelSizing.screenInset
        let x: CGFloat
        if maxX >= minX {
            x = min(max(desiredX, minX), maxX)
        } else {
            x = visible.midX - panelSize.width / 2
        }

        let preferredY = visible.maxY - panelSize.height - IslandPanelSizing.topGap
        let minY = visible.minY + IslandPanelSizing.screenInset
        let y = max(preferredY, minY)

        return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Copied from pi-island's macOS host strategy (MIT, Copyright (c) 2026 phun333):
    // AppKit otherwise tries to pull borderless panels out of the menu-bar/notch area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

extension NSScreen {
    // Copied from DevIsland's NSScreen helper (MIT, Copyright (c) 2026 nangchang).
    var displayId: UInt32 {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = AgentMonitor()
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: AgentSettingsWindowController?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var didStart = false
    private var isExpanded = false

    private var dataRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-island")
    }

    private var projectRoot: URL {
        if let override = ProcessInfo.processInfo.environment["AGENT_ISLAND_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if FileManager.default.fileExists(atPath: current.appendingPathComponent("scripts/install-hooks").path) {
            return current
        }
        let bundleRoot = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: bundleRoot.appendingPathComponent("scripts/install-hooks").path) {
            return bundleRoot
        }
        return current
    }

    private var scriptsRoot: URL {
        if let resources = Bundle.main.resourceURL {
            let packagedScripts = resources.appendingPathComponent("scripts")
            if FileManager.default.fileExists(atPath: packagedScripts.appendingPathComponent("install-hooks").path) {
                return packagedScripts
            }
        }
        return projectRoot.appendingPathComponent("scripts")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        setupStatusItem()
        setupKeyMonitors()
        islandLog("ui started")

        DispatchQueue.main.async { [weak self] in
            self?.monitor.start()
            islandLog("monitor started")
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: AgentIslandSettingsKeys.settingsChanged,
            object: nil
        )
        islandLog("app started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
    }

    private func setupPanel() {
        let initialSize = IslandPanelSizing.size(expanded: false, on: NSScreen.main)
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = NotchPlacement.collectionBehavior(showInFullScreenApps: true)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none

        let hostingView = NSHostingView(rootView: IslandView(
            monitor: monitor,
            onExpandedChange: { [weak self] expanded in
                self?.setExpanded(expanded)
            },
            onSnapshotAction: { snapshot in
                AgentLauncher.focus(snapshot)
            }
        ))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        self.panel = panel
        positionPanel(animate: false)
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.panel?.orderFrontRegardless()
            self?.positionPanel(animate: false)
        }
        islandLog("panel setup frame=\(panel.frame)")
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "Agent Island")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        let toggleItem = NSMenuItem(title: "Toggle Island", action: #selector(toggleIslandFromMenu), keyEquivalent: "n")
        toggleItem.keyEquivalentModifierMask = [.option]
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem(title: "Show Island", action: #selector(showIsland), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Island", action: #selector(hideIsland), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Status Folder", action: #selector(openStatusFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Events Log", action: #selector(openEventsLog), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clear Status Events", action: #selector(clearStatusEvents), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reinstall Hooks", action: #selector(reinstallHooks), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy Diagnostics Report", action: #selector(copyDiagnosticsReport), keyEquivalent: "d"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Notification Settings", action: #selector(openNotificationSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Login Items Settings", action: #selector(openLoginItemsSettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func setupKeyMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isOptionN(event) == true {
                self?.toggleIsland()
                return nil
            }
            if event.keyCode == 53, self?.isExpanded == true {
                NotificationCenter.default.post(name: AgentIslandControlKeys.collapseRequested, object: nil)
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isOptionN(event) == true {
                self?.toggleIsland()
                return
            }
            guard event.keyCode == 53, self?.isExpanded == true else { return }
            NotificationCenter.default.post(name: AgentIslandControlKeys.collapseRequested, object: nil)
        }
    }

    private func isOptionN(_ event: NSEvent) -> Bool {
        guard event.keyCode == 45 else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.option)
            && !flags.contains(.command)
            && !flags.contains(.control)
    }

    private func positionPanel(animate: Bool = false) {
        guard let panel, let screen = NSScreen.main else { return }
        let size = IslandPanelSizing.size(expanded: isExpanded, on: screen)
        let frame = NotchPlacement.frame(for: size, on: screen)
        panel.setFrame(frame, display: true, animate: animate)
        islandLog("position display=\(screen.displayId) notched=\(NotchPlacement.hasNotch(on: screen)) screen=\(screen.frame) visible=\(screen.visibleFrame) panel=\(panel.frame)")
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        positionPanel(animate: true)
    }

    @objc private func screenChanged() {
        positionPanel(animate: false)
    }

    @objc private func settingsChanged() {
        positionPanel(animate: true)
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = AgentSettingsWindowController(
                scriptsRoot: scriptsRoot,
                reinstallHooks: { [weak self] in self?.reinstallHooks() },
                copyDiagnostics: { [weak self] in self?.copyDiagnosticsReport() }
            )
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showIsland() {
        panel?.orderFrontRegardless()
    }

    @objc private func hideIsland() {
        panel?.orderOut(nil)
    }

    @objc private func toggleIslandFromMenu() {
        toggleIsland()
    }

    private func toggleIsland() {
        if panel?.isVisible != true {
            panel?.orderFrontRegardless()
            positionPanel(animate: false)
        }
        NotificationCenter.default.post(name: AgentIslandControlKeys.toggleRequested, object: nil)
    }

    @objc private func refreshNow() {
        monitor.refreshAsync()
        islandLog("manual refresh requested")
    }

    @objc private func openStatusFolder() {
        try? FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dataRoot)
    }

    @objc private func openEventsLog() {
        try? FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let url = dataRoot.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func clearStatusEvents() {
        try? FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let url = dataRoot.appendingPathComponent("events.jsonl")
        try? Data().write(to: url)
        monitor.refreshAsync()
        islandLog("status events cleared")
    }

    @objc private func reinstallHooks() {
        let script = scriptsRoot.appendingPathComponent("install-hooks")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            islandLog("reinstall hooks failed missing script=\(script.path)")
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, "--all"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                islandLog("reinstall hooks exit=\(process.terminationStatus)")
            } catch {
                islandLog("reinstall hooks failed error=\(error.localizedDescription)")
            }
        }
    }

    @objc private func copyDiagnosticsReport() {
        let script = scriptsRoot.appendingPathComponent("agent-island-diagnostics")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            islandLog("diagnostics failed missing script=\(script.path)")
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path]

            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error

            do {
                try process.run()
                let outputData = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = error.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let report = String(data: outputData, encoding: .utf8) ?? ""
                let stderr = String(data: errorData, encoding: .utf8) ?? ""
                let finalReport = stderr.isEmpty ? report : report + "\n\n## stderr\n" + stderr

                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finalReport, forType: .string)
                    islandLog("diagnostics copied exit=\(process.terminationStatus) bytes=\(finalReport.utf8.count)")
                }
            } catch {
                islandLog("diagnostics failed error=\(error.localizedDescription)")
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openNotificationSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }

    @objc private func openLoginItemsSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    private func openSystemSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.finishLaunching()
delegate.start()
app.run()
