// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

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
    case available
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
        case .available: return "已安装"
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
        case .available: return 8
        case .offline: return 9
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
        case .available: return "shippingbox"
        case .offline: return "minus"
        }
    }
}

enum AgentIslandControlKeys {
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
    var evidence: StatusEvidence

    var surfaceID: String { "\(family.rawValue)-\(surface.rawValue)" }
    var id: String {
        guard let sessionID, !sessionID.isEmpty else { return surfaceID }
        return "\(surfaceID)-\(sessionID)"
    }

    var hasQuickActions: Bool {
        switch phase {
        case .needsAttention, .queued, .done, .error:
            return true
        case .working, .thinking, .online, .idle, .available, .offline:
            return false
        }
    }

    func isDisplayEquivalent(to other: AgentSnapshot) -> Bool {
        var lhs = self
        var rhs = other
        lhs.lastUpdated = nil
        rhs.lastUpdated = nil
        return lhs == rhs
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
            lastUpdated: nil,
            evidence: .heuristic
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
    var rawSession: String?
    var primarySession: String?
    var parentSession: String?
    var transcriptPath: String?
    var requestID: String?
    var toolInputSummary: String?
    var toolRisk: String?
    var toolRiskReason: String?
    var autoApprovalEligible: Bool?
    var origin: String?
    var ts: Double?

    private enum CodingKeys: String, CodingKey {
        case agent, family, surface, channel, status, phase, title, message, session, tool, event, pid, cwd, ts, origin
        case terminalApp = "terminal_app"
        case terminalBundleID = "terminal_bundle_id"
        case terminalTTY = "terminal_tty"
        case terminalWindowID = "terminal_window_id"
        case terminalTabIndex = "terminal_tab_index"
        case terminalSessionID = "terminal_session_id"
        case terminalTmuxPane = "terminal_tmux_pane"
        case terminalTmuxSocket = "terminal_tmux_socket"
        case terminalTmuxClient = "terminal_tmux_client"
        case rawSession = "raw_session"
        case primarySession = "primary_session"
        case parentSession = "parent_session"
        case transcriptPath = "transcript_path"
        case requestID = "request_id"
        case toolInputSummary = "tool_input_summary"
        case toolRisk = "tool_risk"
        case toolRiskReason = "tool_risk_reason"
        case autoApprovalEligible = "auto_approval_eligible"
    }
}

enum AgentEventLogDecoder {
    static func decodeChunk(_ text: String) -> (events: [AgentEvent], fragment: String) {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let fragment: String
        if text.hasSuffix("\n") {
            fragment = ""
        } else {
            fragment = lines.popLast().map(String.init) ?? ""
        }

        let decoder = JSONDecoder()
        let events = lines.compactMap { line -> AgentEvent? in
            guard !line.isEmpty,
                  let data = String(line).data(using: .utf8) else {
                return nil
            }
            return try? decoder.decode(AgentEvent.self, from: data)
        }
        return (events, fragment)
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
        case .online, .idle, .available, .offline:
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
