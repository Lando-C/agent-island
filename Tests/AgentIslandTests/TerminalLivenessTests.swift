// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
@testable import AgentIsland

@Suite("Terminal liveness")
struct TerminalLivenessTests {
    @Test("An alive tmux pane without an agent process is not retained")
    func alivePaneWithoutAgentExpiresSession() {
        let now = 1_800_000_000.0
        var rollup = livenessRollup(pid: 42, ts: now - 90)
        rollup.surface = .cli
        var event = rollup.displayEvent!
        event.terminalTTY = "/dev/ttys007"
        event.terminalTmuxPane = "%9"
        event.terminalTmuxSocket = "/tmp/tmux-501/default"
        rollup.displayEvent = event

        let rows = [ProcessRow(pid: 99, ppid: 1, tty: "/dev/ttys007", command: "/bin/zsh")]
        let terminal = TerminalLivenessSnapshot(
            processProbeSucceeded: true,
            activeTTYs: ["/dev/ttys007"],
            tmuxInstalled: true,
            tmuxProbeSucceeded: true,
            tmuxPanes: [TmuxPaneState(
                paneID: "%9",
                socket: "/tmp/tmux-501/default",
                tty: "/dev/ttys007",
                pid: 99,
                isDead: false
            )]
        )

        #expect(SessionLiveness.verdict(
            for: rollup,
            processRows: rows,
            terminalLiveness: terminal,
            now: now
        ) == .dead)
    }

    @Test("Matching Codex or Claude process on the exact pane TTY stays live")
    func matchingAgentOnPaneTTYStaysLive() {
        let now = 1_800_000_000.0
        var rollup = livenessRollup(pid: 42, ts: now - 90)
        rollup.surface = .cli
        var event = rollup.displayEvent!
        event.terminalTTY = "/dev/ttys008"
        event.terminalTmuxPane = "%10"
        rollup.displayEvent = event

        let rows = [ProcessRow(
            pid: 701,
            ppid: 99,
            tty: "/dev/ttys008",
            command: "/usr/local/bin/claude --print status"
        )]
        let terminal = TerminalLivenessSnapshot(
            processProbeSucceeded: true,
            activeTTYs: ["/dev/ttys008"],
            tmuxInstalled: true,
            tmuxProbeSucceeded: true,
            tmuxPanes: [TmuxPaneState(
                paneID: "%10",
                socket: nil,
                tty: "/dev/ttys008",
                pid: 99,
                isDead: false
            )]
        )

        #expect(SessionLiveness.verdict(
            for: rollup,
            processRows: rows,
            terminalLiveness: terminal,
            now: now
        ) == .live)
    }
}
#endif
