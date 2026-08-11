// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import Combine
import Foundation
import SwiftUI

private let islandLogLock = NSLock()

func islandLog(_ message: String) {
    islandLogLock.lock()
    defer { islandLogLock.unlock() }
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-island")
    let url = root.appendingPathComponent("agent-island.log")
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    if let data = line.data(using: .utf8) {
        try? LocalDataSecurity.appendPrivate(data, to: url)
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
        case .claudeApp(let target):
            return "Claude local=\(target.localSessionID) cli=\(target.cliSessionID)"
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

private enum PendingRequestSummary {
    static func text(for request: PendingRequest) -> String {
        var lines: [String] = []
        lines.append("Agent Island Pending Request")
        lines.append("Title: \(request.title)")
        lines.append("Agent: \(request.family.displayName)")
        lines.append("Surface: \(request.surface.displayName)")
        lines.append("Kind: \(request.kind.rawValue)")
        lines.append("Status: \(request.status.rawValue)")
        if !request.detail.isEmpty {
            lines.append("Detail: \(request.detail)")
        }
        if let sessionID = request.sessionID, !sessionID.isEmpty {
            lines.append("Session: \(sessionID)")
        }
        if let requestID = request.requestID, !requestID.isEmpty {
            lines.append("Request: \(requestID)")
        }
        if let tool = request.tool, !tool.isEmpty {
            lines.append("Tool: \(tool)")
        }
        if let toolInputSummary = request.toolInputSummary, !toolInputSummary.isEmpty {
            lines.append("Tool Input: \(toolInputSummary)")
        }
        if let toolRisk = request.toolRisk, !toolRisk.isEmpty {
            var risk = toolRisk
            if let reason = request.toolRiskReason, !reason.isEmpty {
                risk += " (\(reason))"
            }
            lines.append("Risk: \(risk)")
        }
        if let question = request.question, !question.isEmpty {
            lines.append("Question: \(question)")
        }
        if !request.options.isEmpty {
            lines.append("Options:")
            for option in request.options {
                lines.append("- \(option)")
            }
        }
        lines.append("Created: \(ISO8601DateFormatter().string(from: request.createdAt))")
        return lines.joined(separator: "\n")
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
    private var timer: Timer?
    private var isRefreshing = false
    private var lastSnapshotPublish = Date.distantPast
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let codexBrokerClient: CodexBrokerClient
    private var cachedChatGPTSummary = ChatGPTSummary()
    private var lastChatGPTScan = Date.distantPast
    private var cachedProcessRows: [ProcessRow] = []
    private var lastProcessScan = Date.distantPast
    private var lastProcessScanSuccess = Date.distantPast
    private var cachedTerminalLiveness = TerminalLivenessSnapshot.unknown
    private var lastTerminalLivenessScan = Date.distantPast
    private var cachedClaudeTaskSummary = ClaudeTaskSummary()
    private var lastClaudeTaskScan = Date.distantPast
    private var cachedClaudeAppAuditActivities: [ClaudeAppAuditActivity] = []
    private var lastClaudeAppAuditScan = Date.distantPast
    private var cachedCodexGoalSummary = CodexGoalSummary()
    private var lastCodexGoalScan = Date.distantPast
    private var cachedCodexTranscriptActivities: [CodexTranscriptActivity] = []
    private var lastCodexTranscriptScan = Date.distantPast
    private var cachedClaudeScienceSummary = ClaudeScienceSummary()
    private var lastClaudeScienceScan = Date.distantPast
    private var cachedDiskConversationInfo: [String: ConversationInfo] = [:]
    private var cachedClaudeAppSessions: [String: ClaudeAppSessionInfo] = [:]
    private var lastDiskConversationScan = Date.distantPast
    private var cachedRecentEvents: [AgentEvent] = []
    private var cachedEventLogSize: UInt64?
    private var cachedEventLogModificationDate: Date?
    private var cachedEventLogFragment = ""
    private var eventLogGeneration = 0
    private var cachedResolvedEvents: [ResolvedAgentEvent] = []
    private var cachedResolvedEventKeys: Set<String> = []
    private var cachedResolvedEventGeneration = -1
    private var pendingEventCacheEvents: [AgentEvent] = []
    private var eventCacheRequiresFullResolution = true
    private var chatGPTAppWasWorking = false
    private var chatGPTWebWasWorking = false
    private var chatGPTAppDoneUntil: Date?
    private var chatGPTWebDoneUntil: Date?
    private var transcriptWatcher: SessionDirectoryWatcher?

    init(codexBrokerClient: CodexBrokerClient) {
        self.codexBrokerClient = codexBrokerClient
    }

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
        startTranscriptWatcher()
        refreshAsync()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshAsync()
        }
    }

    private func startTranscriptWatcher() {
        let support = home.appendingPathComponent("Library/Application Support/Claude")
        transcriptWatcher = SessionDirectoryWatcher(paths: [
            home.appendingPathComponent(".codex/sessions").path,
            home.appendingPathComponent(".claude/projects").path,
            support.appendingPathComponent("local-agent-mode-sessions").path,
            support.appendingPathComponent("claude-code-sessions").path
        ]) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastCodexTranscriptScan = .distantPast
                self.lastClaudeAppAuditScan = .distantPast
                self.lastClaudeTaskScan = .distantPast
                self.lastDiskConversationScan = .distantPast
                self.refreshAsync()
            }
        }
        transcriptWatcher?.start()
    }

    func refreshAsync() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let next = self.collectSnapshots()
            DispatchQueue.main.async {
                let now = Date()
                let displayChanged = self.snapshots.count != next.count
                    || !zip(self.snapshots, next).allSatisfy { current, incoming in
                        current.isDisplayEquivalent(to: incoming)
                    }
                if displayChanged || now.timeIntervalSince(self.lastSnapshotPublish) >= 10 {
                    self.snapshots = next
                    self.lastSnapshotPublish = now
                }
                self.isRefreshing = false
            }
        }
    }

    private func collectSnapshots() -> [AgentSnapshot] {
        let rows = readProcessesCached()
        _ = readRecentAgentEvents()
        let terminalLiveness = readTerminalLivenessCached(rows: rows)
        let events = eventRollups(rows: rows, terminalLiveness: terminalLiveness)
        let claudeTasks = readClaudeTaskSummaryCached()
        let codexGoals = readCodexGoalSummaryCached()
        let codexBrokerThreads = readCodexBrokerThreads()
        let codexBroker = summarizeCodexBrokerThreads(codexBrokerThreads)
        let codexTranscriptActivities = readCodexTranscriptActivitiesCached()
        let claudeAppAuditActivities = readClaudeAppAuditActivitiesCached()
        let science = readClaudeScienceSummaryCached(rows: rows)
        let chatGPT = readChatGPTSummary()
        let conversations = readConversationInfo(codexBrokerThreads: codexBrokerThreads)
        let eventSnapshots = makeEventSnapshots(from: events, conversations: conversations)
        let transcriptSnapshots = makeCodexTranscriptSnapshots(codexTranscriptActivities, rows: rows)
        let claudeAuditSnapshots = makeClaudeAppAuditSnapshots(claudeAppAuditActivities, rows: rows)
        let eventSurfaceIDs = Set(eventSnapshots.map(\.surfaceID))
        let appEventSurfaceIDs = Set(eventSnapshots.filter { $0.surface == .app }.map { "\($0.family.rawValue)-\($0.surface.rawValue)" })

        let baseSnapshots = [
            makeCodexApp(rows: rows, goals: codexGoals, broker: codexBroker),
            makeCodexCLI(rows: rows),
            // Claude's on-disk task list is not a CLI activity signal. It may
            // outlive a session, so only show it while the desktop app owns it.
            makeClaudeApp(rows: rows, tasks: claudeAppRows(from: rows).isEmpty ? nil : claudeTasks),
            makeClaudeCLI(rows: rows),
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
            if snapshot.family == .codex,
               snapshot.surface == .app,
               !transcriptSnapshots.isEmpty {
                return false
            }
            if snapshot.family == .claude,
               snapshot.surface == .app,
               !claudeAuditSnapshots.isEmpty {
                return false
            }
            return true
        }

        let next = (eventSnapshots + transcriptSnapshots + claudeAuditSnapshots + fallbackSnapshots)
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
        TargetInspector.readProcesses()
    }

    private func readProcessesCached() -> [ProcessRow] {
        let now = Date()
        if now.timeIntervalSince(lastProcessScan) < 4 {
            return cachedProcessRows
        }
        lastProcessScan = now
        let rows = readProcesses()
        if !rows.isEmpty {
            cachedProcessRows = rows
            lastProcessScanSuccess = now
        } else if now.timeIntervalSince(lastProcessScanSuccess) >= 15 {
            cachedProcessRows = []
        }
        return cachedProcessRows
    }

    private func readTerminalLivenessCached(rows: [ProcessRow]) -> TerminalLivenessSnapshot {
        let now = Date()
        guard now.timeIntervalSince(lastTerminalLivenessScan) >= 4 else {
            return cachedTerminalLiveness
        }
        lastTerminalLivenessScan = now
        let sockets = Set(cachedRecentEvents.compactMap { event in
            event.terminalTmuxSocket?.isEmpty == false ? event.terminalTmuxSocket : nil
        })
        cachedTerminalLiveness = TargetInspector.readTerminalLiveness(
            processRows: rows,
            tmuxSockets: sockets
        )
        return cachedTerminalLiveness
    }

    private func makeCodexApp(rows: [ProcessRow], goals: CodexGoalSummary, broker: CodexBrokerSummary) -> AgentSnapshot {
        let appRows = rows.filter { row in
            isCodexAppProcess(row.command)
                && !row.command.contains("crashpad_handler")
        }
        let appServer = appRows.contains { $0.command.contains("codex app-server") }
        let mainAppPID = appRows.first { row in
            let command = row.command.lowercased()
            return command.contains("/applications/codex.app/contents/macos/codex")
                || command.contains("/applications/chatgpt.app/contents/macos/chatgpt")
        }?.pid
        var snapshot = AgentSnapshot.empty(.codex, .app)
        snapshot.evidence = broker.threadCount > 0 ? .broker : .processProbe
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
        snapshot.evidence = .processProbe
        if !cliRows.isEmpty {
            snapshot.phase = .online
            snapshot.detail = "Codex CLI 在线；hook 事件才算工作中"
            snapshot.targetPID = cliRows.first?.pid
            snapshot.pidCount = cliRows.count
            snapshot.lastUpdated = Date()
        } else if executableExists("codex") {
            snapshot.phase = .available
            snapshot.detail = "CLI 已安装，未检测到任务事件"
        }
        return snapshot
    }

    private func makeClaudeApp(rows: [ProcessRow], tasks: ClaudeTaskSummary?) -> AgentSnapshot {
        let appRows = claudeAppRows(from: rows)
        var snapshot = AgentSnapshot.empty(.claude, .app)
        snapshot.evidence = .processProbe
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

    private func readClaudeAppAuditActivitiesCached() -> [ClaudeAppAuditActivity] {
        let now = Date()
        if now.timeIntervalSince(lastClaudeAppAuditScan) >= 2 {
            cachedClaudeAppAuditActivities = ClaudeAppAuditProbe.recentActivities(
                root: home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions"),
                now: now
            )
            lastClaudeAppAuditScan = now
        }
        return cachedClaudeAppAuditActivities
    }

    private func makeClaudeAppAuditSnapshots(
        _ activities: [ClaudeAppAuditActivity],
        rows: [ProcessRow]
    ) -> [AgentSnapshot] {
        let appPID = claudeAppRows(from: rows).first?.pid
        return activities.map { activity in
            var snapshot = AgentSnapshot.empty(.claude, .app)
            snapshot.evidence = .appTranscript
            snapshot.sessionID = activity.cliSessionID
            snapshot.phase = activity.phase
            snapshot.title = "Claude App · \(activity.title)"
            snapshot.detail = [activity.detail, activity.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }]
                .compactMap { $0 }
                .joined(separator: " · ")
            snapshot.jumpTarget = .claudeApp(ClaudeAppJumpTarget(
                cliSessionID: activity.cliSessionID,
                localSessionID: activity.localSessionID,
                title: activity.title,
                cwd: activity.cwd
            ))
            snapshot.targetPID = appPID
            snapshot.lastUpdated = activity.lastUpdated
            switch activity.phase {
            case .working, .thinking:
                snapshot.runningCount = 1
            case .needsAttention, .error:
                snapshot.blockedCount = 1
            case .queued:
                snapshot.pendingCount = 1
            case .done:
                snapshot.completedCount = 1
            case .online, .idle, .available, .offline:
                break
            }
            return snapshot
        }
    }

    private func makeClaudeCLI(rows: [ProcessRow]) -> AgentSnapshot {
        let cliRows = rows.filter {
            isClaudeCLIProcess($0.command) && !isClaudeObserverProcess($0, in: rows)
        }

        var snapshot = AgentSnapshot.empty(.claude, .cli)
        snapshot.evidence = .processProbe
        if !cliRows.isEmpty {
            snapshot.phase = .online
            snapshot.detail = "Claude Code 进程在线；无活动任务信号"
            snapshot.targetPID = cliRows.first?.pid
            snapshot.pidCount = cliRows.count
        } else if executableExists("claude") {
            snapshot.phase = .available
            snapshot.detail = "CLI 已安装，未检测到任务事件"
        }
        if !cliRows.isEmpty {
            snapshot.targetPID = cliRows.first?.pid
            snapshot.pidCount = cliRows.count
        }

        return snapshot
    }

    private func isClaudeObserverProcess(_ row: ProcessRow, in rows: [ProcessRow]) -> Bool {
        let processMap = rows.reduce(into: [Int: ProcessRow]()) { result, candidate in
            result[candidate.pid] = candidate
        }
        var candidate: ProcessRow? = row
        var visited = Set<Int>()
        for _ in 0..<10 {
            guard let current = candidate, visited.insert(current.pid).inserted else { break }
            let command = current.command.lowercased()
            if command.contains("/.claude-mem/observer-sessions")
                || (command.contains("claude-mem") && command.contains("worker-service")) {
                return true
            }
            guard let parentPID = current.ppid, parentPID != current.pid else { break }
            candidate = processMap[parentPID]
        }
        return false
    }

    private func claudeAppRows(from rows: [ProcessRow]) -> [ProcessRow] {
        rows.filter { row in
            isClaudeAppProcess(row.command) && !row.command.contains("crashpad_handler")
        }
    }

    private func isCodexAppProcess(_ command: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.contains("/applications/codex.app/")
            || cmd.contains("/applications/chatgpt.app/")
            || cmd.contains("/library/application support/codex/")
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
            snapshot.phase = .available
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

    private func readChatGPTSummary() -> ChatGPTSummary {
        let now = Date()
        if now.timeIntervalSince(lastChatGPTScan) < 12 {
            return cachedChatGPTSummary
        }
        lastChatGPTScan = now

        var summary = ChatGPTSummary()
        let frontmost = frontmostProcessName()
        let chatGPTApps = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.openai.chat")
            .filter { !$0.isTerminated }
        if let app = chatGPTApps.first {
            summary.appPhase = .online
            summary.appDetail = "App 在线；未发现回答中信号"
            summary.appPID = Int(app.processIdentifier)
            summary.appPIDCount = chatGPTApps.count
            summary.appLastUpdated = now

            if app.isActive {
                let text = accessibilityText(forPID: app.processIdentifier)
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

        let probes = readBrowserProbes(frontmostProcessName: frontmost)
        let tabCount = probes.reduce(0) { $0 + $1.chatGPTTabCount }
        if tabCount > 0 {
            summary.webPhase = .online
            summary.webTabCount = tabCount
            summary.webPID = probes.first { $0.chatGPTTabCount > 0 }?.pid
            summary.webLastUpdated = now
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

    private func readBrowserProbes(frontmostProcessName: String?) -> [BrowserProbe] {
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
            let active = processName == frontmostProcessName
                ? activeBrowserTab(appName: appName, safari: isSafari)
                : (url: "", title: "")
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

    private func accessibilityText(forPID pid: pid_t) -> String {
        let source = """
        tell application "System Events"
            set matchingProcesses to every application process whose unix id is \(pid)
            if (count of matchingProcesses) is 0 then return ""
            set targetProcess to item 1 of matchingProcesses
            tell targetProcess
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
        let now = Date()
        if now.timeIntervalSince(lastDiskConversationScan) >= 30 {
            var diskResult = readCodexConversationInfo()
            let recentSessions = recentEventSessionIDs()
            let claude = readClaudeConversationInfo(sessionIDs: recentSessions[.claude] ?? [])
            diskResult.merge(claude) { current, _ in current }
            let claudeApp = readClaudeAppConversationInfo(sessionIDs: recentSessions[.claude] ?? [])
            diskResult.merge(claudeApp) { current, incoming in
                mergeConversationInfo(current: incoming, incoming: current)
            }
            cachedDiskConversationInfo = diskResult
            lastDiskConversationScan = now
        }

        var result = cachedDiskConversationInfo
        let broker = readCodexBrokerConversationInfo(threads: codexBrokerThreads)
        result.merge(broker) { current, incoming in
            mergeConversationInfo(current: current, incoming: incoming)
        }
        return result
    }

    private func readClaudeAppConversationInfo(sessionIDs: Set<String>) -> [String: ConversationInfo] {
        let support = home.appendingPathComponent("Library/Application Support/Claude")
        let roots = [
            support.appendingPathComponent("claude-code-sessions"),
            support.appendingPathComponent("local-agent-mode-sessions")
        ]
        let sessions = ClaudeAppSessionIndex.load(roots: roots, matching: sessionIDs)
        cachedClaudeAppSessions = sessions
        return sessions.reduce(into: [String: ConversationInfo]()) { result, pair in
            let (cliSessionID, info) = pair
            result[conversationKey(.claude, cliSessionID)] = ConversationInfo(
                title: ClaudeAppSessionIndex.displayTitle(for: info),
                workspace: info.cwd,
                preview: nil
            )
        }
    }

    private func readCodexBrokerThreads() -> [CodexBrokerThread] {
        codexBrokerClient.latestThreadsSnapshot()
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
        var result: [AgentFamily: Set<String>] = [:]
        for event in readRecentAgentEvents() {
            guard let family = AgentEventNormalizer.family(from: event.family ?? event.agent),
                  let session = event.session,
                  !session.isEmpty else {
                continue
            }
            guard !isAuxiliaryAgentEvent(event, family: family) else { continue }
            result[family, default: []].insert(logicalSessionID(for: event, fallback: session))
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

    private func logicalSessionID(for event: AgentEvent, fallback: String) -> String {
        for candidate in [event.primarySession, event.parentSession, observedSessionMarker(in: event)] {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return fallback
    }

    private func observedSessionMarker(in event: AgentEvent) -> String? {
        let text = [event.title, event.message, event.toolInputSummary]
            .compactMap { $0 }
            .joined(separator: " ")
        guard let range = text.range(of: #"<observed_from_primary_session[^>]*session=["']([^"']+)["']"#, options: [.regularExpression]) else {
            return nil
        }
        let match = String(text[range])
        guard let valueRange = match.range(of: #"session=["']([^"']+)["']"#, options: [.regularExpression]) else {
            return nil
        }
        let raw = String(match[valueRange])
            .replacingOccurrences(of: #"session=""#, with: "")
            .replacingOccurrences(of: #"session='"#, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return raw.isEmpty ? nil : raw
    }

    private func isAuxiliaryAgentEvent(_ event: AgentEvent, family: AgentFamily) -> Bool {
        guard family == .claude else { return false }
        let text = [
            event.cwd,
            event.transcriptPath,
            event.title,
            event.message,
            event.toolInputSummary,
            event.session,
            event.rawSession
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        guard !text.isEmpty else { return false }
        if text.contains("/.claude-mem/") { return true }
        if text.contains("--claude-mem") { return true }
        if text.contains("claude-mem") { return true }
        if text.contains("observer-sessions") { return true }
        if text.contains("<observed_from_primary_session") { return true }
        if text.contains("hello memory agent") { return true }
        return false
    }

    private func shouldSuppressAuxiliaryEvent(
        _ event: AgentEvent,
        family: AgentFamily,
        phase: AgentPhase
    ) -> Bool {
        // claude-mem observer sessions are service plumbing. Even an internal
        // permission/failure must not be presented as a user action item.
        _ = phase
        return isAuxiliaryAgentEvent(event, family: family)
    }

    private func eventRollups(
        rows: [ProcessRow],
        terminalLiveness: TerminalLivenessSnapshot
    ) -> [String: AgentEventRollup] {
        let now = Date().timeIntervalSince1970
        _ = readRecentAgentEvents()
        if cachedResolvedEventGeneration != eventLogGeneration {
            let processMap = rows.reduce(into: [Int: ProcessRow]()) { partial, row in
                partial[row.pid] = row
            }
            let rebuild = eventCacheRequiresFullResolution
            let events = rebuild ? cachedRecentEvents : pendingEventCacheEvents
            if rebuild {
                cachedResolvedEvents = []
                cachedResolvedEventKeys = []
            }

            for event in events {
                guard let family = AgentEventNormalizer.family(from: event.family ?? event.agent),
                      let phase = AgentEventNormalizer.phase(for: event) else {
                    continue
                }
                guard !shouldSuppressAuxiliaryEvent(event, family: family, phase: phase) else { continue }
                let rawSurface = AgentEventNormalizer.surface(from: event.surface ?? event.channel)
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
                let logicalSession = logicalSessionID(for: event, fallback: session)
                let hookEvent = AgentEventNormalizer.hookEventName(for: event)
                let resolved = ResolvedAgentEvent(
                    family: family,
                    surface: surface,
                    session: logicalSession,
                    event: event,
                    hookEvent: hookEvent,
                    normalizedPhase: phase,
                    ts: ts
                )
                let dedupeKey = resolvedEventDedupeKey(resolved)
                guard cachedResolvedEventKeys.insert(dedupeKey).inserted else { continue }
                cachedResolvedEvents.append(resolved)
            }

            if cachedResolvedEvents.count > 1200 {
                cachedResolvedEvents.removeFirst(cachedResolvedEvents.count - 1200)
                cachedResolvedEventKeys = Set(cachedResolvedEvents.map(resolvedEventDedupeKey))
            }
            cachedResolvedEventGeneration = eventLogGeneration
            pendingEventCacheEvents = []
            eventCacheRequiresFullResolution = false
        }

        let rollups = AgentSessionStore.rollups(from: cachedResolvedEvents, now: now)
        return rollups.filter { _, rollup in
            SessionLiveness.shouldRetain(
                rollup,
                processRows: rows,
                terminalLiveness: terminalLiveness,
                now: now
            )
        }
    }

    private func resolvedEventDedupeKey(_ resolved: ResolvedAgentEvent) -> String {
        [
            resolved.family.rawValue,
            resolved.surface.rawValue,
            resolved.session,
            resolved.hookEvent,
            resolved.event.tool ?? "",
            resolved.event.pid.map(String.init) ?? "",
            String(Int(resolved.ts * 1000))
        ].joined(separator: "\u{1F}")
    }

    private func readRecentAgentEvents() -> [AgentEvent] {
        let url = home.appendingPathComponent(".agent-island/events.jsonl")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modificationDate = attributes[.modificationDate] as? Date else {
            if cachedEventLogSize != nil || !cachedRecentEvents.isEmpty {
                cachedRecentEvents = []
                cachedEventLogSize = nil
                cachedEventLogModificationDate = nil
                cachedEventLogFragment = ""
                pendingEventCacheEvents = []
                eventCacheRequiresFullResolution = true
                eventLogGeneration += 1
            }
            return []
        }

        if cachedEventLogSize == size,
           cachedEventLogModificationDate == modificationDate {
            return cachedRecentEvents
        }

        if let previousSize = cachedEventLogSize,
           size > previousSize,
           let appendedText = readEventLogText(at: url, from: previousSize) {
            let decoded = AgentEventLogDecoder.decodeChunk(cachedEventLogFragment + appendedText)
            let appendedEvents = Array(decoded.events.suffix(1200))
            if !appendedEvents.isEmpty {
                cachedRecentEvents = Array((cachedRecentEvents + appendedEvents).suffix(1200))
                pendingEventCacheEvents = appendedEvents
                eventCacheRequiresFullResolution = false
                eventLogGeneration += 1
            }
            cachedEventLogFragment = decoded.fragment
            cachedEventLogSize = size
            cachedEventLogModificationDate = modificationDate
            return cachedRecentEvents
        }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return cachedRecentEvents
        }

        let decoded = AgentEventLogDecoder.decodeChunk(text)
        cachedRecentEvents = Array(decoded.events.suffix(1200))
        cachedEventLogFragment = decoded.fragment
        cachedEventLogSize = size
        cachedEventLogModificationDate = modificationDate
        pendingEventCacheEvents = cachedRecentEvents
        eventCacheRequiresFullResolution = true
        eventLogGeneration += 1
        return cachedRecentEvents
    }

    private func readEventLogText(at url: URL, from offset: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd() else { return "" }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
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
        session: String? = nil,
        conversations: [String: ConversationInfo]
    ) -> ConversationInfo? {
        let rawSession = session ?? event.session
        guard let rawSession, !rawSession.isEmpty else { return nil }
        let logicalSession = logicalSessionID(for: event, fallback: rawSession)
        return conversations[conversationKey(family, logicalSession)]
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

            let hookEvent = AgentEventNormalizer.hookEventName(for: event)
            let conversation = conversationInfo(for: event, family: family, session: session, conversations: conversations)
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
            snapshot.evidence = statusEvidence(for: event)

            switch phase {
            case .working:
                snapshot.runningCount = 1
            case .needsAttention, .error:
                snapshot.blockedCount = 1
            case .queued:
                snapshot.pendingCount = 1
            case .done:
                snapshot.completedCount = 1
            case .thinking, .online, .idle, .available, .offline:
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

    private func statusEvidence(for event: AgentEvent) -> StatusEvidence {
        switch event.origin?.lowercased() {
        case "web_bridge": return .webBridge
        case "hook", "agent_island_hook": return .hook
        default: return .hook
        }
    }

    private func jumpTarget(
        for event: AgentEvent,
        family: AgentFamily,
        surface: AgentSurface,
        session: String?
    ) -> JumpTarget? {
        if family == .claude,
           surface == .app,
           let session,
           let info = cachedClaudeAppSessions[session] {
            return .claudeApp(ClaudeAppJumpTarget(
                cliSessionID: session,
                localSessionID: info.sessionId,
                title: info.title,
                cwd: info.cwd
            ))
        }

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
        let hookEvent = AgentEventNormalizer.hookEventName(for: event)
        let conversation = conversationInfo(for: event, family: snapshot.family, session: snapshot.sessionID, conversations: conversations)

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
        SessionRetentionPolicy.maxAge(for: phase)
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
            // Task JSON is a persistent backlog, not a liveness signal. Without
            // a fresh write it cannot truthfully represent current work or a
            // currently actionable approval.
            guard now.timeIntervalSince(modified) < 30 * 60 else { continue }
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

    private func readClaudeTaskSummaryCached() -> ClaudeTaskSummary {
        let now = Date()
        if now.timeIntervalSince(lastClaudeTaskScan) >= 8 {
            cachedClaudeTaskSummary = readClaudeTaskSummary()
            lastClaudeTaskScan = now
        }
        return cachedClaudeTaskSummary
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

    private func readCodexGoalSummaryCached() -> CodexGoalSummary {
        let now = Date()
        if now.timeIntervalSince(lastCodexGoalScan) >= 8 {
            cachedCodexGoalSummary = readCodexGoalSummary()
            lastCodexGoalScan = now
        }
        return cachedCodexGoalSummary
    }

    private func readCodexTranscriptActivitiesCached() -> [CodexTranscriptActivity] {
        let now = Date()
        if now.timeIntervalSince(lastCodexTranscriptScan) >= 2 {
            let activities = CodexTranscriptProbe.recentActivities(
                root: home.appendingPathComponent(".codex/sessions"),
                now: now
            )
            let titles = readCodexThreadTitles(for: activities.map(\.sessionID))
            cachedCodexTranscriptActivities = activities.map { activity in
                guard let title = titles[activity.sessionID],
                      let meaningful = AgentText.meaningfulConversationTitle(title) else {
                    return activity
                }
                var enriched = activity
                enriched.title = AgentText.compact(meaningful, limit: 72)
                return enriched
            }
            lastCodexTranscriptScan = now
        }
        return cachedCodexTranscriptActivities
    }

    private func readCodexThreadTitles(for sessionIDs: [String]) -> [String: String] {
        let unique = Array(Set(sessionIDs.filter { !$0.isEmpty })).prefix(24)
        guard !unique.isEmpty else { return [:] }
        let database = home.appendingPathComponent(".codex/state_5.sqlite").path
        guard FileManager.default.fileExists(atPath: database) else { return [:] }
        let quotedIDs = unique.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ",")
        let sql = """
        select id, replace(replace(replace(title, char(10), ' '), char(13), ' '), '|', '/')
        from threads
        where id in (\(quotedIDs));
        """
        return runCommand(
            executable: "/usr/bin/sqlite3",
            arguments: ["file:\(database)?mode=ro&immutable=1", sql]
        )
        .split(separator: "\n")
        .reduce(into: [:]) { result, line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return }
            result[parts[0]] = parts[1]
        }
    }

    private func makeCodexTranscriptSnapshots(
        _ activities: [CodexTranscriptActivity],
        rows: [ProcessRow]
    ) -> [AgentSnapshot] {
        let targetPID = rows.first(where: { $0.command.lowercased().contains("codex app-server") })?.pid
        return activities.map { activity in
            var snapshot = AgentSnapshot.empty(.codex, .app)
            snapshot.evidence = .appTranscript
            snapshot.sessionID = activity.sessionID
            snapshot.phase = activity.phase
            snapshot.title = "Codex App · \(activity.title)"
            snapshot.detail = [activity.detail, activity.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }]
                .compactMap { $0 }
                .joined(separator: " · ")
            snapshot.jumpTarget = .url("codex://threads/\(activity.sessionID)")
            snapshot.targetPID = targetPID
            snapshot.lastUpdated = activity.lastUpdated
            switch activity.phase {
            case .working, .thinking:
                snapshot.runningCount = 1
            case .needsAttention, .error:
                snapshot.blockedCount = 1
            case .queued:
                snapshot.pendingCount = 1
            case .done:
                snapshot.completedCount = 1
            case .online, .idle, .available, .offline:
                break
            }
            return snapshot
        }
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

    private func readClaudeScienceSummaryCached(rows: [ProcessRow]) -> ClaudeScienceSummary {
        let now = Date()
        if now.timeIntervalSince(lastClaudeScienceScan) >= 8 {
            cachedClaudeScienceSummary = readClaudeScienceSummary(rows: rows)
            lastClaudeScienceScan = now
        }
        return cachedClaudeScienceSummary
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var monitor: AgentMonitor
    @ObservedObject var pendingRequests: PendingRequestStore
    var onExpandedChange: (Bool) -> Void = { _ in }
    var onSnapshotAction: (AgentSnapshot) -> Void = { _ in }
    var onSnapshotDetails: (AgentSnapshot) -> Void = { _ in }
    var onDetachRequested: () -> Void = {}
    @StateObject private var expansion = IslandExpansionController()
    @State private var pulse = false
    @State private var orbitAngle = 0.0
    @State private var previousPhaseByID: [String: AgentPhase] = [:]
    @State private var copiedSnapshotID: String?
    @State private var detachGestureTriggered = false
    private let motionTicker = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    private var expanded: Bool {
        expansion.expanded
    }

    private var spotlightSnapshot: AgentSnapshot? {
        expansion.spotlightSnapshot
    }

    private var activeSnapshots: [AgentSnapshot] {
        monitor.snapshots.filter { $0.phase != .offline && $0.phase != .available }
    }

    private var displaySnapshots: [AgentSnapshot] {
        expanded ? activeSnapshots : Array(activeSnapshots.prefix(3))
    }

    private var pendingOnlyRequests: [PendingRequest] {
        let attachedIDs = Set(displaySnapshots.compactMap { matchingPendingRequestID(for: $0) })
        return Array(pendingRequests.requests.filter { request in
            request.isPending && !attachedIDs.contains(request.id)
        }.prefix(4))
    }

    private var displayItemCount: Int {
        displaySnapshots.count + pendingOnlyRequests.count
    }

    private func matchingPendingRequestID(for snapshot: AgentSnapshot) -> String? {
        if let requestID = snapshot.requestID, !requestID.isEmpty {
            let key = "\(snapshot.family.rawValue)::\(requestID)"
            if pendingRequests.requests.contains(where: { $0.id == key }) {
                return key
            }
        }
        guard let sessionID = snapshot.sessionID else { return nil }
        return pendingRequests.requests.first {
            $0.family == snapshot.family
                && $0.sessionID == sessionID
                && $0.status == .pending
        }?.id
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
        let visibleCount = min(max(displayItemCount, 1), 4)
        let base = CGFloat(visibleCount) * 42 + CGFloat(max(visibleCount - 1, 0)) * 8
        let preferred = displayItemCount > 4 ? min(base + 16, 184) : base
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
        }
        .onReceive(motionTicker) { _ in
            guard !reduceMotion else { return }
            pulse.toggle()
            orbitAngle += 45
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
                        pendingRequest: pendingRequests.request(for: spotlightSnapshot),
                        pulse: pulse,
                        copied: copiedSnapshotID == spotlightSnapshot.id,
                        onOpen: {
                            openSnapshot(spotlightSnapshot)
                        },
                        onCopy: {
                            copySnapshotSummary(spotlightSnapshot)
                        },
                        onAllow: { request in
                            pendingRequests.allow(request)
                        },
                        onDeny: { request in
                            pendingRequests.deny(request)
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
        .simultaneousGesture(detachGesture)
    }

    private var detachGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 10))
            .onChanged { value in
                guard case .second(true, let drag?) = value,
                      drag.translation.height > 28,
                      !detachGestureTriggered else { return }
                detachGestureTriggered = true
                onDetachRequested()
            }
            .onEnded { _ in detachGestureTriggered = false }
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
                                    angle: .degrees(orbitAngle)
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 27, height: 27)
                            .opacity(monitor.activeCount > 0 ? 1 : 0.55)

                        Circle()
                            .fill(statusColor)
                            .frame(width: pulse && monitor.activeCount > 0 ? 12 : 9, height: pulse && monitor.activeCount > 0 ? 12 : 9)
                            .shadow(color: statusColor.opacity(0.8), radius: monitor.activeCount > 0 ? 8 : 2)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: pulse)
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
                        pendingRequest: pendingRequests.request(for: snapshot),
                        pulse: pulse,
                        copied: copiedSnapshotID == snapshot.id,
                        onOpen: {
                            openSnapshot(snapshot)
                        },
                        onCopy: {
                            copySnapshotSummary(snapshot)
                        },
                        onDetails: {
                            onSnapshotDetails(snapshot)
                        },
                        onAllow: { request in
                            pendingRequests.allow(request)
                        },
                        onDeny: { request in
                            pendingRequests.deny(request)
                        }
                    )
                    .help("点击跳转到 \(snapshot.title)")
                }

                ForEach(pendingOnlyRequests) { request in
                    PendingRequestCard(
                        request: request,
                        copied: copiedSnapshotID == request.id,
                        onAllow: { pendingRequests.allow(request) },
                        onDeny: { pendingRequests.deny(request) },
                        onCopy: { copyPendingRequest(request) },
                        onAnswer: { answers in
                            pendingRequests.answer(request, answers: answers)
                        }
                    )
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

    private func copyPendingRequest(_ request: PendingRequest, answer: String? = nil) {
        let text: String
        if let answer {
            text = answer
        } else {
            text = PendingRequestSummary.text(for: request)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.12)) {
            copiedSnapshotID = request.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedSnapshotID == request.id {
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
        guard !SmartSuppression.shouldSuppressSpotlight(for: snapshot) else {
            islandLog("spotlight suppressed frontmost session=\(snapshot.sessionID ?? snapshot.id) phase=\(snapshot.phase.rawValue)")
            return
        }
        expansion.showSpotlight(snapshot, duration: autoSpotlightDuration(for: snapshot))
    }

    private func shouldSpotlight(_ snapshot: AgentSnapshot) -> Bool {
        switch snapshot.phase {
        case .needsAttention, .queued, .done, .error, .working, .thinking:
            return true
        case .online, .idle, .available, .offline:
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
        case .online, .idle, .available, .offline:
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
    var pendingRequest: PendingRequest?
    var pulse: Bool
    var copied: Bool = false
    var onOpen: () -> Void = {}
    var onCopy: () -> Void = {}
    var onDetails: () -> Void = {}
    var onAllow: (PendingRequest) -> Void = { _ in }
    var onDeny: (PendingRequest) -> Void = { _ in }
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

            if snapshot.sessionID != nil {
                Button(action: onDetails) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("查看完整聊天与工具记录")
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

                Text("来源: \(snapshot.evidence.label)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(snapshot.evidence.isAuthoritative ? Color.white.opacity(0.38) : Color.orange.opacity(0.82))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var quickActions: some View {
        HStack(spacing: 4) {
            if let pendingRequest, pendingRequest.canApproveInline, pendingRequest.isPending {
                Button {
                    onAllow(pendingRequest)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(width: 22, height: 22)
                        .background(Color.green.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .help("允许本次请求")

                Button {
                    onDeny(pendingRequest)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 22, height: 22)
                        .background(Color.red.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .help("拒绝本次请求")
            }

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
        case .available: return Color.white.opacity(0.42)
        case .offline: return Color.white.opacity(0.28)
        }
    }

    private var detailText: String {
        if let pendingRequest, pendingRequest.isPending {
            return pendingRequest.detail
        }
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

struct PendingRequestCard: View {
    var request: PendingRequest
    var copied: Bool = false
    var onAllow: () -> Void = {}
    var onDeny: () -> Void = {}
    var onCopy: () -> Void = {}
    var onAnswer: ([String: [String]]) -> Void = { _ in }
    @State private var hovering = false
    @State private var selectedAnswers: [String: [String]] = [:]
    @State private var freeTextAnswers: [String: String] = [:]
    @State private var customAnswerQuestionIDs: Set<String> = []

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 31, height: 31)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(request.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if request.kind == .permission, let toolRisk = request.toolRisk, !toolRisk.isEmpty {
                        Text(toolRiskLabel(toolRisk))
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.86))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(riskColor(toolRisk), in: Capsule())
                    }
                }

                Text(request.detail)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineLimit(1)

                if request.kind == .input, request.canAnswerInline {
                    inputControls
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                if request.canApproveInline {
                    Button(action: onAllow) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                            .frame(width: 22, height: 22)
                            .background(Color.green.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("允许本次请求")

                    Button(action: onDeny) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 22, height: 22)
                            .background(Color.red.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("拒绝本次请求")
                }

                Button(action: onCopy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(copied ? .green : Color.white.opacity(0.72))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(copied ? 0.13 : 0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help(copied ? "已复制" : "复制请求摘要")
            }
        }
        .frame(maxWidth: .infinity, minHeight: request.kind == .input ? 62 : 42)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(hovering ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        }
        .onHover { hovering = $0 }
    }

    private var tint: Color {
        request.kind == .permission ? .orange : .cyan
    }

    private var icon: String {
        request.kind == .permission ? "hand.raised.fill" : "text.bubble.fill"
    }

    @ViewBuilder
    private var inputControls: some View {
        let questions = displayQuestions
        if questions.count == 1, let question = questions.first {
            if question.options.isEmpty {
                HStack(spacing: 5) {
                    freeTextField(for: question)
                    Button { submitFreeText(question) } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .disabled(normalizedFreeText(for: question).isEmpty)
                    .help("直接提交回复")
                }
            } else {
                optionButtons(for: question, submitsImmediately: !question.multiSelect)
                if customAnswerQuestionIDs.contains(question.id) {
                    freeTextField(for: question)
                }
                if question.multiSelect || customAnswerQuestionIDs.contains(question.id) {
                    submitAnswersButton
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(questions) { question in
                    Text(question.header ?? question.prompt)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineLimit(1)
                    if question.options.isEmpty || customAnswerQuestionIDs.contains(question.id) {
                        freeTextField(for: question)
                    }
                    if !question.options.isEmpty {
                        optionButtons(for: question, submitsImmediately: false)
                    }
                }
                submitAnswersButton
            }
        }
    }

    private var displayQuestions: [PendingQuestion] {
        if !request.questions.isEmpty { return request.questions }
        guard let prompt = request.question else { return [] }
        return [PendingQuestion(
            id: prompt,
            header: nil,
            prompt: prompt,
            options: request.options,
            multiSelect: false,
            isSecret: false,
            allowsOther: false
        )]
    }

    private func optionButtons(for question: PendingQuestion, submitsImmediately: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        customAnswerQuestionIDs.remove(question.id)
                        select(option, for: question)
                        if submitsImmediately { onAnswer([question.id: [option]]) }
                    } label: {
                        Text(option)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                (selectedAnswers[question.id]?.contains(option) == true ? Color.cyan.opacity(0.28) : Color.white.opacity(0.08)),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .help(submitsImmediately ? "直接提交该选项" : "选择该选项")
                }
                if question.allowsOther == true {
                    Button {
                        customAnswerQuestionIDs.insert(question.id)
                        selectedAnswers[question.id] = []
                    } label: {
                        Label("其他", systemImage: "pencil")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("输入自定义回答")
                }
            }
        }
    }

    private var submitAnswersButton: some View {
        Button {
            onAnswer(selectedAnswers)
        } label: {
            Label("提交回答", systemImage: "paperplane.fill")
                .font(.system(size: 9, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.cyan)
        .disabled(!hasAllRequiredAnswers)
    }

    @ViewBuilder
    private func freeTextField(for question: PendingQuestion) -> some View {
        let binding = Binding<String>(
            get: { freeTextAnswers[question.id] ?? "" },
            set: { value in
                freeTextAnswers[question.id] = value
                selectedAnswers[question.id] = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [value]
            }
        )
        Group {
            if question.isSecret {
                SecureField("输入回复", text: binding)
            } else {
                TextField("输入回复", text: binding)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 10))
        .padding(.horizontal, 7)
        .frame(height: 23)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        .onSubmit { submitFreeText(question) }
    }

    private var hasAllRequiredAnswers: Bool {
        !displayQuestions.isEmpty && displayQuestions.allSatisfy { selectedAnswers[$0.id]?.isEmpty == false }
    }

    private func select(_ option: String, for question: PendingQuestion) {
        if question.multiSelect {
            var values = selectedAnswers[question.id] ?? []
            if let index = values.firstIndex(of: option) { values.remove(at: index) } else { values.append(option) }
            selectedAnswers[question.id] = values
        } else {
            selectedAnswers[question.id] = [option]
        }
    }

    private func submitFreeText(_ question: PendingQuestion) {
        let text = normalizedFreeText(for: question)
        guard !text.isEmpty else { return }
        onAnswer([question.id: [text]])
    }

    private func normalizedFreeText(for question: PendingQuestion) -> String {
        (freeTextAnswers[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toolRiskLabel(_ risk: String) -> String {
        switch risk {
        case "safe_read": return "只读"
        case "dangerous": return "危险"
        case "write": return "写入"
        default: return risk
        }
    }

    private func riskColor(_ risk: String) -> Color {
        switch risk {
        case "safe_read": return .green
        case "dangerous": return .red
        case "write": return .orange
        default: return .yellow
        }
    }
}

struct SpotlightSummary: View {
    var snapshot: AgentSnapshot
    var pendingRequest: PendingRequest?
    var pulse: Bool
    var copied: Bool = false
    var onOpen: () -> Void = {}
    var onCopy: () -> Void = {}
    var onAllow: (PendingRequest) -> Void = { _ in }
    var onDeny: (PendingRequest) -> Void = { _ in }
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
                    if let pendingRequest, pendingRequest.canApproveInline, pendingRequest.isPending {
                        Button {
                            onAllow(pendingRequest)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green)
                                .frame(width: 22, height: 22)
                                .background(Color.green.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("允许本次请求")

                        Button {
                            onDeny(pendingRequest)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 22, height: 22)
                                .background(Color.red.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("拒绝本次请求")
                    }

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
        case .available: return Color.white.opacity(0.42)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color

    var body: some View {
        if reduceMotion {
            bars(tick: 0)
        } else {
            TimelineView(.periodic(from: .now, by: 0.32)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.32)
                bars(tick: tick)
            }
        }
    }

    private func bars(tick: Int) -> some View {
        let patterns: [[CGFloat]] = [
            [16, 7, 14, 8, 18],
            [10, 17, 7, 15, 11],
            [7, 12, 18, 9, 14],
            [13, 8, 11, 17, 7]
        ]
        let heights = patterns[tick % patterns.count]
        return HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color.opacity(0.86))
                    .frame(width: 4, height: heights[index])
            }
        }
    }
}

enum IslandPanelSizing {
    static let screenInset = PanelGeometryPolicy.screenInset
    static let topGap = PanelGeometryPolicy.topGap

    static func size(expanded: Bool, on screen: NSScreen?) -> NSSize {
        let preferredWidth = CGFloat(expanded ? AgentSettingsStore.workingWidth : AgentSettingsStore.idleWidth)
        return PanelGeometryPolicy.islandSize(
            expanded: expanded,
            preferredWidth: preferredWidth,
            visibleFrame: screen?.visibleFrame
        )
    }
}

// Adapted from DevIsland's notch placement model (MIT, Copyright (c) 2026 nangchang).
// It prefers the physical notch center when macOS exposes auxiliary top areas, then
// falls back to the display center on non-notched displays.
enum NotchPlacement {
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
        PanelGeometryPolicy.notchCenterX(
            screenFrame: screen.frame,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    }

    static func frame(for panelSize: NSSize, on screen: NSScreen) -> NSRect {
        PanelGeometryPolicy.notchFrame(
            panelSize: panelSize,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            horizontalOffset: horizontalOffset
        )
    }
}

final class IslandPanel: NSPanel {
    var returnToNotch: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Copied from pi-island's macOS host strategy (MIT, Copyright (c) 2026 phun333):
    // AppKit otherwise tries to pull borderless panels out of the menu-bar/notch area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isMovableByWindowBackground else {
            super.rightMouseDown(with: event)
            return
        }
        let menu = NSMenu()
        let item = NSMenuItem(title: "回到刘海", action: #selector(returnToNotchAction), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Agent Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        if let contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    @objc private func returnToNotchAction() {
        returnToNotch?()
    }
}

extension NSScreen {
    // Copied from DevIsland's NSScreen helper (MIT, Copyright (c) 2026 nangchang).
    var displayId: UInt32 {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pendingRequests = PendingRequestStore()
    private lazy var hookSocketServer = HookSocketServer(store: pendingRequests)
    private lazy var codexBrokerClient = CodexBrokerClient(store: pendingRequests)
    private lazy var monitor = AgentMonitor(codexBrokerClient: codexBrokerClient)
    private lazy var webBridgeServer = WebBridgeServer { [weak self] in self?.monitor.refreshAsync() }
    private lazy var islandViewModel = IslandViewModel(
        monitor: monitor,
        pendingRequests: pendingRequests
    )
    private lazy var panelCoordinator = PanelCoordinator(
        viewModel: islandViewModel,
        onSnapshotDetails: { [weak self] snapshot in self?.showChatDetails(snapshot) }
    )
    private var statusItem: NSStatusItem?
    private var settingsWindowController: AgentSettingsWindowController?
    private var chatDetailWindowControllers: [ChatDetailWindowController] = []
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var didStart = false

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
        panelCoordinator.start()
        setupStatusItem()
        setupKeyMonitors()
        hookSocketServer.start()
        codexBrokerClient.start()
        webBridgeServer.start()
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

        if !OnboardingChecklistStore.shared.hasSeenChecklist {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        hookSocketServer.stop()
        codexBrokerClient.stop()
        panelCoordinator.stop()
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
        menu.addItem(NSMenuItem(title: "Toggle Floating Mode", action: #selector(toggleFloatingMode), keyEquivalent: ""))
        let returnToNotchItem = NSMenuItem(
            title: "Return to Notch",
            action: #selector(returnToNotch),
            keyEquivalent: "n"
        )
        returnToNotchItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(returnToNotchItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Status Folder", action: #selector(openStatusFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Events Log", action: #selector(openEventsLog), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clear Status Events", action: #selector(clearStatusEvents), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reinstall Hooks", action: #selector(reinstallHooks), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy Diagnostics Report", action: #selector(copyDiagnosticsReport), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Create Redacted Support Bundle", action: #selector(createRedactedSupportBundle), keyEquivalent: ""))
        menu.addItem(.separator())
        let allowItem = NSMenuItem(title: "Allow First Pending Request", action: #selector(allowFirstPendingRequest), keyEquivalent: "y")
        allowItem.keyEquivalentModifierMask = [.command]
        menu.addItem(allowItem)
        let denyItem = NSMenuItem(title: "Deny First Pending Request", action: #selector(denyFirstPendingRequest), keyEquivalent: "n")
        denyItem.keyEquivalentModifierMask = [.command]
        menu.addItem(denyItem)
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
            if self?.isCommandOptionN(event) == true {
                self?.panelCoordinator.returnToNotch()
                return nil
            }
            if self?.handleApprovalShortcut(event) == true {
                return nil
            }
            if self?.isOptionN(event) == true {
                self?.toggleIsland()
                return nil
            }
            if event.keyCode == 53, self?.panelCoordinator.isExpanded == true {
                NotificationCenter.default.post(name: AgentIslandControlKeys.collapseRequested, object: nil)
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isCommandOptionN(event) == true {
                self?.panelCoordinator.returnToNotch()
                return
            }
            if self?.isOptionN(event) == true {
                self?.toggleIsland()
                return
            }
            guard event.keyCode == 53, self?.panelCoordinator.isExpanded == true else { return }
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

    private func isCommandOptionN(_ event: NSEvent) -> Bool {
        guard event.keyCode == 45 else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command)
            && flags.contains(.option)
            && !flags.contains(.control)
    }

    private func handleApprovalShortcut(_ event: NSEvent) -> Bool {
        guard panelCoordinator.isExpanded else { return false }
        if isCommandY(event) {
            return approveFirstPendingRequest()
        }
        if isCommandN(event) {
            return rejectFirstPendingRequest()
        }
        return false
    }

    private func isCommandY(_ event: NSEvent) -> Bool {
        guard event.keyCode == 16 else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command)
            && !flags.contains(.option)
            && !flags.contains(.control)
    }

    private func isCommandN(_ event: NSEvent) -> Bool {
        guard event.keyCode == 45 else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command)
            && !flags.contains(.option)
            && !flags.contains(.control)
    }

    @objc private func allowFirstPendingRequest() {
        _ = approveFirstPendingRequest()
    }

    @objc private func denyFirstPendingRequest() {
        _ = rejectFirstPendingRequest()
    }

    @discardableResult
    private func approveFirstPendingRequest() -> Bool {
        let handled = pendingRequests.allowFirstPendingPermission()
        if handled {
            islandLog("pending request approved from shortcut")
        }
        return handled
    }

    @discardableResult
    private func rejectFirstPendingRequest() -> Bool {
        let handled = pendingRequests.denyFirstPendingPermission()
        if handled {
            islandLog("pending request denied from shortcut")
        }
        return handled
    }

    @objc private func toggleFloatingMode() {
        panelCoordinator.toggleFloatingMode()
    }

    @objc private func returnToNotch() {
        panelCoordinator.returnToNotch()
    }

    @objc private func screenChanged() {
        panelCoordinator.screenChanged()
    }

    @objc private func settingsChanged() {
        panelCoordinator.applySettings()
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = AgentSettingsWindowController(
                monitor: monitor,
                scriptsRoot: scriptsRoot,
                reinstallHooks: { [weak self] in self?.reinstallHooks() },
                copyDiagnostics: { [weak self] in self?.copyDiagnosticsReport() },
                createSupportBundle: { [weak self] in self?.createRedactedSupportBundle() },
                copyWebBridgeToken: { [weak self] in self?.copyWebBridgeToken() }
            )
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func copyWebBridgeToken() {
        guard let pairingToken = webBridgeServer.pairingToken else {
            islandLog("web bridge pairing token copy failed")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingToken, forType: .string)
        islandLog("web bridge pairing token copied")
    }

    private func showChatDetails(_ snapshot: AgentSnapshot) {
        chatDetailWindowControllers.removeAll { $0.window?.isVisible != true }
        let controller = ChatDetailWindowController(snapshot: snapshot)
        chatDetailWindowControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showIsland() {
        panelCoordinator.show()
    }

    @objc private func hideIsland() {
        panelCoordinator.hide()
    }

    @objc private func toggleIslandFromMenu() {
        toggleIsland()
    }

    private func toggleIsland() {
        panelCoordinator.toggleIsland()
    }

    @objc private func refreshNow() {
        monitor.refreshAsync()
        islandLog("manual refresh requested")
    }

    @objc private func openStatusFolder() {
        try? LocalDataSecurity.ensurePrivateDirectory(at: dataRoot)
        NSWorkspace.shared.open(dataRoot)
    }

    @objc private func openEventsLog() {
        let url = dataRoot.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? LocalDataSecurity.writePrivate(Data(), to: url)
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func clearStatusEvents() {
        let url = dataRoot.appendingPathComponent("events.jsonl")
        try? LocalDataSecurity.writePrivate(Data(), to: url)
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

    @objc private func createRedactedSupportBundle() {
        let script = scriptsRoot.appendingPathComponent("agent-island-support-bundle")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            islandLog("support bundle failed missing script=\(script.path)")
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    if process.terminationStatus == 0, let path, !path.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        islandLog("redacted support bundle created path=\(path)")
                    } else {
                        islandLog("support bundle failed exit=\(process.terminationStatus)")
                    }
                }
            } catch {
                islandLog("support bundle failed error=\(error.localizedDescription)")
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
