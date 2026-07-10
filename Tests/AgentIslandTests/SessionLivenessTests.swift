// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
@testable import AgentIsland

private let livenessSessionID = "70266e98-3300-4871-8ec4-8edba1ee8a24"

private func livenessEvent(pid: Int?, ts: Double) -> AgentEvent {
    AgentEvent(
        agent: "claude",
        family: nil,
        surface: "app",
        channel: nil,
        status: "working",
        phase: nil,
        title: nil,
        message: nil,
        session: livenessSessionID,
        tool: "Read",
        event: "PreToolUse",
        pid: pid,
        cwd: "/tmp/project",
        terminalApp: nil,
        terminalBundleID: nil,
        terminalTTY: nil,
        terminalWindowID: nil,
        terminalTabIndex: nil,
        terminalSessionID: nil,
        terminalTmuxPane: nil,
        terminalTmuxSocket: nil,
        terminalTmuxClient: nil,
        rawSession: nil,
        primarySession: nil,
        parentSession: nil,
        transcriptPath: nil,
        requestID: nil,
        toolInputSummary: nil,
        toolRisk: nil,
        toolRiskReason: nil,
        autoApprovalEligible: nil,
        ts: ts
    )
}

private func livenessRollup(
    pid: Int?,
    phase: AgentPhase = .working,
    ts: Double
) -> AgentEventRollup {
    AgentEventRollup(
        family: .claude,
        surface: .app,
        session: livenessSessionID,
        displayEvent: livenessEvent(pid: pid, ts: ts),
        displayPhase: phase,
        displayTs: ts,
        workingCount: phase == .working ? 1 : 0,
        thinkingCount: 0,
        attentionCount: phase == .needsAttention ? 1 : 0,
        queuedCount: 0,
        doneCount: phase == .done ? 1 : 0
    )
}

@Suite("Session liveness")
struct SessionLivenessTests {
    @Test("Missing owner PID expires active session after grace")
    func missingOwnerPIDExpiresActiveSessionAfterGrace() {
        let now = 1_800_000_000.0
        let rollup = livenessRollup(pid: 42, ts: now - 31)
        let rows = [ProcessRow(pid: 99, ppid: 1, command: "/bin/zsh")]

        #expect(SessionLiveness.verdict(for: rollup, processRows: rows, now: now) == .dead)
    }

    @Test("Process scan failure stays conservative")
    func processScanFailureStaysConservative() {
        let now = 1_800_000_000.0
        let rollup = livenessRollup(pid: 42, ts: now - 300)

        #expect(SessionLiveness.verdict(for: rollup, processRows: [], now: now) == .unknown)
    }

    @Test("Grace period avoids racing a newly emitted event")
    func gracePeriodAvoidsRacingNewEvent() {
        let now = 1_800_000_000.0
        let rollup = livenessRollup(pid: 42, ts: now - 10)
        let rows = [ProcessRow(pid: 99, ppid: 1, command: "/bin/zsh")]

        #expect(SessionLiveness.verdict(for: rollup, processRows: rows, now: now) == .unknown)
    }

    @Test("Claude resume marker survives a changed event PID")
    func claudeResumeMarkerSurvivesChangedEventPID() {
        let now = 1_800_000_000.0
        let rollup = livenessRollup(pid: 42, ts: now - 120)
        let rows = [
            ProcessRow(
                pid: 777,
                ppid: 1,
                command: "/Applications/Claude.app/Contents/Helpers/disclaimer --resume \(livenessSessionID)"
            )
        ]

        #expect(SessionLiveness.verdict(for: rollup, processRows: rows, now: now) == .live)
    }

    @Test("Reused PID from another app is not treated as the agent")
    func reusedPIDFromAnotherAppIsDead() {
        let now = 1_800_000_000.0
        let rollup = livenessRollup(pid: 42, ts: now - 120)
        let rows = [ProcessRow(pid: 42, ppid: 1, command: "/Applications/Safari.app/Contents/MacOS/Safari")]

        #expect(SessionLiveness.verdict(for: rollup, processRows: rows, now: now) == .dead)
    }

    @Test("Completed outcome remains visible after its process exits")
    func completedOutcomeDoesNotRequireOwner() {
        let now = 1_800_000_000.0
        let rollup = livenessRollup(pid: 42, phase: .done, ts: now - 60)
        let rows = [ProcessRow(pid: 99, ppid: 1, command: "/bin/zsh")]

        #expect(SessionLiveness.shouldRetain(rollup, processRows: rows, now: now))
    }
}
#elseif canImport(XCTest)
import XCTest
@testable import AgentIsland

private let xctLivenessSessionID = "70266e98-3300-4871-8ec4-8edba1ee8a24"

private func xctLivenessEvent(pid: Int?, ts: Double) -> AgentEvent {
    AgentEvent(
        agent: "claude",
        family: nil,
        surface: "app",
        channel: nil,
        status: "working",
        phase: nil,
        title: nil,
        message: nil,
        session: xctLivenessSessionID,
        tool: "Read",
        event: "PreToolUse",
        pid: pid,
        cwd: "/tmp/project",
        terminalApp: nil,
        terminalBundleID: nil,
        terminalTTY: nil,
        terminalWindowID: nil,
        terminalTabIndex: nil,
        terminalSessionID: nil,
        terminalTmuxPane: nil,
        terminalTmuxSocket: nil,
        terminalTmuxClient: nil,
        rawSession: nil,
        primarySession: nil,
        parentSession: nil,
        transcriptPath: nil,
        requestID: nil,
        toolInputSummary: nil,
        toolRisk: nil,
        toolRiskReason: nil,
        autoApprovalEligible: nil,
        ts: ts
    )
}

private func xctLivenessRollup(
    pid: Int?,
    phase: AgentPhase = .working,
    ts: Double
) -> AgentEventRollup {
    AgentEventRollup(
        family: .claude,
        surface: .app,
        session: xctLivenessSessionID,
        displayEvent: xctLivenessEvent(pid: pid, ts: ts),
        displayPhase: phase,
        displayTs: ts,
        workingCount: phase == .working ? 1 : 0,
        thinkingCount: 0,
        attentionCount: phase == .needsAttention ? 1 : 0,
        queuedCount: 0,
        doneCount: phase == .done ? 1 : 0
    )
}

final class SessionLivenessTests: XCTestCase {
    func testMissingOwnerPIDExpiresActiveSessionAfterGrace() {
        let now = 1_800_000_000.0
        let rollup = xctLivenessRollup(pid: 42, ts: now - 31)
        let rows = [ProcessRow(pid: 99, ppid: 1, command: "/bin/zsh")]
        XCTAssertEqual(SessionLiveness.verdict(for: rollup, processRows: rows, now: now), .dead)
    }

    func testProcessScanFailureStaysConservative() {
        let now = 1_800_000_000.0
        let rollup = xctLivenessRollup(pid: 42, ts: now - 300)
        XCTAssertEqual(SessionLiveness.verdict(for: rollup, processRows: [], now: now), .unknown)
    }

    func testGracePeriodAvoidsRacingNewEvent() {
        let now = 1_800_000_000.0
        let rollup = xctLivenessRollup(pid: 42, ts: now - 10)
        let rows = [ProcessRow(pid: 99, ppid: 1, command: "/bin/zsh")]
        XCTAssertEqual(SessionLiveness.verdict(for: rollup, processRows: rows, now: now), .unknown)
    }

    func testClaudeResumeMarkerSurvivesChangedEventPID() {
        let now = 1_800_000_000.0
        let rollup = xctLivenessRollup(pid: 42, ts: now - 120)
        let rows = [ProcessRow(
            pid: 777,
            ppid: 1,
            command: "/Applications/Claude.app/Contents/Helpers/disclaimer --resume \(xctLivenessSessionID)"
        )]
        XCTAssertEqual(SessionLiveness.verdict(for: rollup, processRows: rows, now: now), .live)
    }

    func testReusedPIDFromAnotherAppIsDead() {
        let now = 1_800_000_000.0
        let rollup = xctLivenessRollup(pid: 42, ts: now - 120)
        let rows = [ProcessRow(pid: 42, ppid: 1, command: "/Applications/Safari.app/Contents/MacOS/Safari")]
        XCTAssertEqual(SessionLiveness.verdict(for: rollup, processRows: rows, now: now), .dead)
    }

    func testCompletedOutcomeDoesNotRequireOwner() {
        let now = 1_800_000_000.0
        let rollup = xctLivenessRollup(pid: 42, phase: .done, ts: now - 60)
        let rows = [ProcessRow(pid: 99, ppid: 1, command: "/bin/zsh")]
        XCTAssertTrue(SessionLiveness.shouldRetain(rollup, processRows: rows, now: now))
    }
}
#endif
