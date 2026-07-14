// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

enum SessionLivenessVerdict: Equatable {
    case live
    case unknown
    case dead
}

enum SessionLiveness {
    static let processExitGrace: TimeInterval = 30

    static func shouldRetain(
        _ rollup: AgentEventRollup,
        processRows: [ProcessRow],
        terminalLiveness: TerminalLivenessSnapshot = .unknown,
        now: Double
    ) -> Bool {
        verdict(
            for: rollup,
            processRows: processRows,
            terminalLiveness: terminalLiveness,
            now: now
        ) != .dead
    }

    static func verdict(
        for rollup: AgentEventRollup,
        processRows: [ProcessRow],
        terminalLiveness: TerminalLivenessSnapshot = .unknown,
        now: Double
    ) -> SessionLivenessVerdict {
        guard let phase = rollup.displayPhase,
              phaseRequiresLiveOwner(phase),
              let family = rollup.family,
              let surface = rollup.surface,
              let session = rollup.session,
              let event = rollup.displayEvent else {
            return .unknown
        }

        let age = max(0, now - rollup.displayTs)
        if age <= processExitGrace {
            return .unknown
        }
        let processProbeSucceeded = terminalLiveness.processProbeSucceeded || !processRows.isEmpty
        guard processProbeSucceeded else {
            return .unknown
        }

        let processMap = processRows.reduce(into: [Int: ProcessRow]()) { result, row in
            result[row.pid] = row
        }

        if hasExactSessionProcess(
            family: family,
            session: session,
            processRows: processRows,
            processMap: processMap
        ) {
            return .live
        }

        var hasOwnerIdentity = false
        if let pid = event.pid {
            hasOwnerIdentity = true
            if processMap[pid] != nil {
                let commands = commandChain(startingAt: pid, processMap: processMap)
                if commandsMatch(family: family, surface: surface, commands: commands) {
                    return .live
                }
            }
        }

        var candidateTTYs = Set<String>()
        if let tty = normalizedTTY(event.terminalTTY) {
            hasOwnerIdentity = true
            candidateTTYs.insert(tty)
        }

        if let paneID = event.terminalTmuxPane, !paneID.isEmpty {
            hasOwnerIdentity = true
            if terminalLiveness.tmuxProbeSucceeded {
                guard let pane = terminalLiveness.pane(id: paneID, socket: event.terminalTmuxSocket),
                      !pane.isDead else {
                    return .dead
                }
                if let tty = normalizedTTY(pane.tty) { candidateTTYs.insert(tty) }
            }
        }

        if !candidateTTYs.isEmpty {
            let rowsOnTarget = processRows.filter { row in
                guard let tty = normalizedTTY(row.tty) else { return false }
                return candidateTTYs.contains(tty)
            }
            if rowsOnTarget.contains(where: { row in
                commandsMatch(
                    family: family,
                    surface: surface,
                    commands: commandChain(startingAt: row.pid, processMap: processMap)
                )
            }) {
                return .live
            }
        }

        return hasOwnerIdentity ? .dead : .unknown
    }

    private static func phaseRequiresLiveOwner(_ phase: AgentPhase) -> Bool {
        switch phase {
        case .working, .thinking, .queued, .needsAttention, .online, .idle:
            return true
        case .done, .error, .available, .offline:
            return false
        }
    }

    private static func hasExactSessionProcess(
        family: AgentFamily,
        session: String,
        processRows: [ProcessRow],
        processMap: [Int: ProcessRow]
    ) -> Bool {
        guard family == .claude, UUID(uuidString: session) != nil else { return false }
        let spacedMarker = "--resume \(session)"
        let equalsMarker = "--resume=\(session)"
        return processRows.contains { row in
            guard row.command.contains(spacedMarker) || row.command.contains(equalsMarker) else {
                return false
            }
            return !isClaudeObserverChain(commandChain(startingAt: row.pid, processMap: processMap))
        }
    }

    private static func commandChain(
        startingAt pid: Int,
        processMap: [Int: ProcessRow]
    ) -> [String] {
        var current = pid
        var visited = Set<Int>()
        var commands: [String] = []

        for _ in 0..<10 {
            guard current > 1,
                  visited.insert(current).inserted,
                  let row = processMap[current] else {
                break
            }
            commands.append(row.command.lowercased())
            guard let parent = row.ppid, parent != current else { break }
            current = parent
        }
        return commands
    }

    private static func normalizedTTY(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "?", value != "??", value != "-" else { return nil }
        return value.hasPrefix("/dev/") ? value : "/dev/\(value)"
    }

    private static func commandsMatch(
        family: AgentFamily,
        surface: AgentSurface,
        commands: [String]
    ) -> Bool {
        if family == .claude, isClaudeObserverChain(commands) {
            return false
        }
        switch family {
        case .codex:
            let app = commands.contains(where: isCodexAppCommand)
            let cli = commands.contains(where: isCodexCLICommand)
            return surface == .app ? app : surface == .cli ? cli && !app : app || cli
        case .claude:
            let app = commands.contains(where: isClaudeAppCommand)
            let cli = commands.contains(where: isClaudeCLICommand)
            return surface == .app ? app : surface == .cli ? cli && !app : app || cli
        case .claudeScience:
            return commands.contains { $0.contains("claude science.app") || $0.contains("operon") }
        case .chatgpt:
            return commands.contains {
                $0.contains("chatgpt classic.app")
                    || $0.contains("com.openai.chat")
                    || $0.contains("chatgpt atlas.app")
            }
        }
    }

    private static func isClaudeObserverChain(_ commands: [String]) -> Bool {
        commands.contains { command in
            command.contains("/.claude-mem/observer-sessions")
                || (command.contains("claude-mem") && command.contains("worker-service"))
        }
    }

    private static func isCodexAppCommand(_ command: String) -> Bool {
        command.contains("/applications/codex.app/")
            || command.contains("/applications/chatgpt.app/")
            || command.contains("/library/application support/codex/")
            || command.contains(" codex app-server")
    }

    private static func isCodexCLICommand(_ command: String) -> Bool {
        guard command.contains("codex"), !isCodexAppCommand(command) else { return false }
        return command.contains("/bin/codex") || command.contains(" codex ")
    }

    private static func isClaudeAppCommand(_ command: String) -> Bool {
        command.contains("/applications/claude.app/")
            || command.contains("/library/application support/claude/claude-code/")
    }

    private static func isClaudeCLICommand(_ command: String) -> Bool {
        guard !isClaudeAppCommand(command) else { return false }
        return command.contains("/bin/claude ")
            || command.hasSuffix("/bin/claude")
            || command.contains(" claude --")
    }
}
