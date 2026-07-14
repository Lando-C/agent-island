// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func terminalForegroundPolicyFixture() -> Bool {
    let appOnly = TerminalJumpTarget(
        appName: "Ghostty",
        bundleID: "com.mitchellh.ghostty",
        pid: nil,
        tty: nil,
        cwd: nil,
        windowID: nil,
        tabIndex: nil,
        sessionIdentifier: nil,
        title: nil
    )
    let paneSpecific = TerminalJumpTarget(
        appName: "Ghostty",
        bundleID: "com.mitchellh.ghostty",
        pid: nil,
        tty: "/dev/ttys012",
        cwd: "/tmp/project",
        windowID: nil,
        tabIndex: nil,
        sessionIdentifier: nil,
        title: nil
    )
    let titleSpecific = TerminalJumpTarget(
        appName: "Warp",
        bundleID: "dev.warp.Warp-Stable",
        pid: nil,
        tty: nil,
        cwd: nil,
        windowID: nil,
        tabIndex: nil,
        sessionIdentifier: nil,
        title: "release task"
    )
    return TerminalFocuser.canConfirmAppOnlyForeground(appOnly)
        && !TerminalFocuser.canConfirmAppOnlyForeground(paneSpecific)
        && !TerminalFocuser.canConfirmAppOnlyForeground(titleSpecific)
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Terminal foreground policy")
struct TerminalForegroundPolicyTests {
    @Test("Specific terminal context is never inferred from app foreground alone")
    func specificContextNeedsVerification() {
        #expect(terminalForegroundPolicyFixture())
    }
}
#elseif canImport(XCTest)
final class TerminalForegroundPolicyTests: XCTestCase {
    func testSpecificTerminalContextIsNeverInferredFromAppForegroundAlone() {
        XCTAssertTrue(terminalForegroundPolicyFixture())
    }
}
#endif
