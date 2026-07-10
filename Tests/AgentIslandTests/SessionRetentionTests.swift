// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

#if canImport(Testing)
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func permissionEvent(ts: Double) -> ResolvedAgentEvent {
    let event = AgentEvent(
        agent: "claude",
        family: nil,
        surface: "cli",
        channel: nil,
        status: "needs_attention",
        phase: nil,
        title: nil,
        message: nil,
        session: "retention-session",
        tool: "Bash",
        event: "PermissionRequest",
        pid: nil,
        cwd: nil,
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
    return ResolvedAgentEvent(
        family: .claude,
        surface: .cli,
        session: "retention-session",
        event: event,
        hookEvent: "permissionrequest",
        normalizedPhase: .needsAttention,
        ts: ts
    )
}

private func workingEvent(ts: Double) -> ResolvedAgentEvent {
    var resolved = permissionEvent(ts: ts)
    resolved.event.status = "working"
    resolved.event.event = "PreToolUse"
    resolved.event.tool = "Read"
    resolved.hookEvent = "pretooluse"
    resolved.normalizedPhase = .working
    return resolved
}

private func lifecycleEvent(name: String, phase: AgentPhase, ts: Double, pid: Int? = nil) -> ResolvedAgentEvent {
    var resolved = permissionEvent(ts: ts)
    resolved.event.status = phase.rawValue
    resolved.event.event = name
    resolved.event.pid = pid
    resolved.hookEvent = name.lowercased()
    resolved.normalizedPhase = phase
    return resolved
}

#if canImport(Testing)
@Suite("Session retention")
struct SessionRetentionTests {
    @Test("Waiting approval remains visible within twelve hours")
    func waitingApprovalIsVisibleWithinTwelveHours() {
        let now = 1_800_000_000.0
        let rollups = AgentSessionStore.rollups(
            from: [permissionEvent(ts: now - (12 * 60 * 60) + 1)],
            now: now
        )

        #expect(rollups.count == 1)
        #expect(rollups.values.first?.displayPhase == .needsAttention)
    }

    @Test("Waiting approval expires after twelve hours")
    func waitingApprovalExpiresAfterTwelveHours() {
        let now = 1_800_000_000.0
        let rollups = AgentSessionStore.rollups(
            from: [permissionEvent(ts: now - (12 * 60 * 60) - 1)],
            now: now
        )

        #expect(rollups.isEmpty)
    }

    @Test("Available means installed, not online")
    func availablePhaseMeansInstalledNotOnline() {
        #expect(AgentPhase.available.label == "已安装")
        #expect(AgentPhase.available != .online)
        #expect(AgentPhase.available.rank > AgentPhase.idle.rank)
    }

    @Test("New work clears an older attention state")
    func newWorkClearsOlderAttentionState() {
        let now = 1_800_000_000.0
        let rollups = AgentSessionStore.rollups(
            from: [permissionEvent(ts: now - 20), workingEvent(ts: now - 10)],
            now: now
        )

        #expect(rollups.values.first?.displayPhase == .working)
    }

    @Test("Timestamp-only snapshot updates do not redraw")
    func timestampOnlySnapshotUpdatesAreDisplayEquivalent() {
        var current = AgentSnapshot.empty(.claude, .app)
        var incoming = current
        current.lastUpdated = .distantPast
        incoming.lastUpdated = .distantFuture

        #expect(current.isDisplayEquivalent(to: incoming))
        incoming.detail = "state changed"
        #expect(!current.isDisplayEquivalent(to: incoming))
    }

    @Test("Start then end without work does not create a completed session")
    func noOpLifecycleDoesNotComplete() {
        let now = 1_800_000_000.0
        let rollups = AgentSessionStore.rollups(
            from: [
                lifecycleEvent(name: "SessionStart", phase: .queued, ts: now - 2),
                lifecycleEvent(name: "SessionEnd", phase: .done, ts: now - 1)
            ],
            now: now
        )

        #expect(rollups.isEmpty)
    }

    @Test("A user prompt followed by stop remains a real completion")
    func promptedLifecycleCompletes() {
        let now = 1_800_000_000.0
        let rollups = AgentSessionStore.rollups(
            from: [
                lifecycleEvent(name: "SessionStart", phase: .queued, ts: now - 3),
                lifecycleEvent(name: "UserPromptSubmit", phase: .queued, ts: now - 2),
                lifecycleEvent(name: "Stop", phase: .done, ts: now - 1)
            ],
            now: now
        )

        #expect(rollups.values.first?.displayPhase == .done)
    }

    @Test("No-op duplicate PID cannot replace the real session completion")
    func duplicatePIDDoesNotReplaceRealCompletion() {
        let now = 1_800_000_000.0
        let rollups = AgentSessionStore.rollups(
            from: [
                lifecycleEvent(name: "SessionStart", phase: .queued, ts: now - 6, pid: 10),
                lifecycleEvent(name: "UserPromptSubmit", phase: .queued, ts: now - 5, pid: 10),
                lifecycleEvent(name: "Stop", phase: .done, ts: now - 4, pid: 10),
                lifecycleEvent(name: "SessionStart", phase: .queued, ts: now - 2, pid: 20),
                lifecycleEvent(name: "SessionEnd", phase: .done, ts: now - 1, pid: 20)
            ],
            now: now
        )

        #expect(rollups.values.first?.displayPhase == .done)
        #expect(rollups.values.first?.displayEvent?.pid == 10)
    }

    @Test("New tool start clears an earlier completion")
    func newToolStartClearsCompletion() {
        let now = 1_800_000_000.0
        var preTool = workingEvent(ts: now - 1)
        preTool.hookEvent = "pretooluse"
        preTool.event.event = "PreToolUse"
        let rollups = AgentSessionStore.rollups(
            from: [
                lifecycleEvent(name: "Stop", phase: .done, ts: now - 5),
                preTool
            ],
            now: now
        )

        #expect(rollups.values.first?.displayPhase == .working)
    }

    @Test("New tool completion clears an earlier session completion")
    func newToolCompletionClearsCompletion() {
        let now = 1_800_000_000.0
        var postTool = workingEvent(ts: now - 1)
        postTool.hookEvent = "posttooluse"
        postTool.event.event = "PostToolUse"
        let rollups = AgentSessionStore.rollups(
            from: [
                lifecycleEvent(name: "Stop", phase: .done, ts: now - 5),
                postTool
            ],
            now: now
        )

        #expect(rollups.values.first?.displayPhase == .thinking)
    }
}
#elseif canImport(XCTest)
final class SessionRetentionTests: XCTestCase {
    func testWaitingApprovalIsVisibleWithinTwelveHours() {
        let now = 1_800_000_000.0
        let rollups = AgentSessionStore.rollups(
            from: [permissionEvent(ts: now - (12 * 60 * 60) + 1)],
            now: now
        )

        XCTAssertEqual(rollups.count, 1)
        XCTAssertEqual(rollups.values.first?.displayPhase, .needsAttention)
    }

    func testWaitingApprovalExpiresAfterTwelveHours() {
        let now = 1_800_000_000.0
        let rollups = AgentSessionStore.rollups(
            from: [permissionEvent(ts: now - (12 * 60 * 60) - 1)],
            now: now
        )

        XCTAssertTrue(rollups.isEmpty)
    }

    func testAvailablePhaseMeansInstalledNotOnline() {
        XCTAssertEqual(AgentPhase.available.label, "已安装")
        XCTAssertNotEqual(AgentPhase.available, .online)
        XCTAssertGreaterThan(AgentPhase.available.rank, AgentPhase.idle.rank)
    }

    func testNewWorkClearsOlderAttentionState() {
        let now = 1_800_000_000.0
        let rollups = AgentSessionStore.rollups(
            from: [permissionEvent(ts: now - 20), workingEvent(ts: now - 10)],
            now: now
        )

        XCTAssertEqual(rollups.values.first?.displayPhase, .working)
    }

    func testTimestampOnlySnapshotUpdatesAreDisplayEquivalent() {
        var current = AgentSnapshot.empty(.claude, .app)
        var incoming = current
        current.lastUpdated = .distantPast
        incoming.lastUpdated = .distantFuture

        XCTAssertTrue(current.isDisplayEquivalent(to: incoming))
        incoming.detail = "state changed"
        XCTAssertFalse(current.isDisplayEquivalent(to: incoming))
    }

    func testNoOpLifecycleDoesNotComplete() {
        let now = 1_800_000_000.0
        let rollups = AgentSessionStore.rollups(
            from: [
                lifecycleEvent(name: "SessionStart", phase: .queued, ts: now - 2),
                lifecycleEvent(name: "SessionEnd", phase: .done, ts: now - 1)
            ],
            now: now
        )
        XCTAssertTrue(rollups.isEmpty)
    }

    func testNewToolStartClearsCompletion() {
        let now = 1_800_000_000.0
        var preTool = workingEvent(ts: now - 1)
        preTool.hookEvent = "pretooluse"
        preTool.event.event = "PreToolUse"
        let rollups = AgentSessionStore.rollups(
            from: [
                lifecycleEvent(name: "Stop", phase: .done, ts: now - 5),
                preTool
            ],
            now: now
        )
        XCTAssertEqual(rollups.values.first?.displayPhase, .working)
    }
}
#endif
