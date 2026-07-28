// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private struct TerminalCapabilityFixture {
    var name: String
    var target: TerminalJumpTarget
    var snapshot: TerminalFocusCapabilitySnapshot
    var expected: TerminalFocusPrecision
}

private func terminalTarget(
    tty: String? = nil,
    cwd: String? = nil,
    windowID: String? = nil,
    sessionIdentifier: String? = nil
) -> TerminalJumpTarget {
    TerminalJumpTarget(
        appName: "WezTerm",
        bundleID: "com.github.wez.wezterm",
        pid: nil,
        tty: tty,
        cwd: cwd,
        windowID: windowID,
        tabIndex: nil,
        sessionIdentifier: sessionIdentifier,
        title: nil
    )
}

private let terminalCapabilityFixtures = [
    TerminalCapabilityFixture(
        name: "missing helper",
        target: terminalTarget(tty: "/dev/ttys010", sessionIdentifier: "42"),
        snapshot: TerminalFocusCapabilitySnapshot(
            helperAvailable: false,
            metadataFresh: true,
            candidates: [
                TerminalFocusCandidate(stableID: "42", tty: "/dev/ttys010", cwd: "/tmp/project")
            ],
            fallbackAvailable: true
        ),
        expected: .fallback
    ),
    TerminalCapabilityFixture(
        name: "multiple windows with unique stable identity",
        target: terminalTarget(sessionIdentifier: "42"),
        snapshot: TerminalFocusCapabilitySnapshot(
            helperAvailable: true,
            metadataFresh: true,
            candidates: [
                TerminalFocusCandidate(stableID: "41", tty: "/dev/ttys009", cwd: "/tmp/project"),
                TerminalFocusCandidate(stableID: "42", tty: "/dev/ttys010", cwd: "/tmp/project")
            ],
            fallbackAvailable: true
        ),
        expected: .exact
    ),
    TerminalCapabilityFixture(
        name: "multiple windows with ambiguous CWD",
        target: terminalTarget(cwd: "/tmp/project"),
        snapshot: TerminalFocusCapabilitySnapshot(
            helperAvailable: true,
            metadataFresh: true,
            candidates: [
                TerminalFocusCandidate(stableID: "41", tty: "/dev/ttys009", cwd: "/tmp/project"),
                TerminalFocusCandidate(stableID: "42", tty: "/dev/ttys010", cwd: "/tmp/project/")
            ],
            fallbackAvailable: true
        ),
        expected: .fallback
    ),
    TerminalCapabilityFixture(
        name: "unique normalized TTY context",
        target: terminalTarget(tty: "ttys010"),
        snapshot: TerminalFocusCapabilitySnapshot(
            helperAvailable: true,
            metadataFresh: true,
            candidates: [
                TerminalFocusCandidate(stableID: "41", tty: "/dev/ttys009", cwd: "/tmp/other"),
                TerminalFocusCandidate(stableID: "42", tty: "/dev/ttys010", cwd: "/tmp/project")
            ],
            fallbackAvailable: true
        ),
        expected: .context
    ),
    TerminalCapabilityFixture(
        name: "stale metadata",
        target: terminalTarget(tty: "/dev/ttys010", sessionIdentifier: "42"),
        snapshot: TerminalFocusCapabilitySnapshot(
            helperAvailable: true,
            metadataFresh: false,
            candidates: [
                TerminalFocusCandidate(stableID: "42", tty: "/dev/ttys010", cwd: "/tmp/project")
            ],
            fallbackAvailable: true
        ),
        expected: .fallback
    ),
    TerminalCapabilityFixture(
        name: "no helper and no application fallback",
        target: terminalTarget(sessionIdentifier: "42"),
        snapshot: TerminalFocusCapabilitySnapshot(
            helperAvailable: false,
            metadataFresh: true,
            candidates: [],
            fallbackAvailable: false
        ),
        expected: .unavailable
    )
]

private func verifyTerminalCapabilityFixtures() -> [String] {
    terminalCapabilityFixtures.compactMap { fixture in
        let actual = TerminalFocusCapabilityResolver.resolve(
            target: fixture.target,
            snapshot: fixture.snapshot
        ).precision
        return actual == fixture.expected
            ? nil
            : "\(fixture.name): expected \(fixture.expected.rawValue), got \(actual.rawValue)"
    }
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Terminal focus capabilities")
struct TerminalFocusCapabilityTests {
    @Test("Offline capability fixtures preserve exact/context/fallback guarantees")
    func capabilityFixtures() {
        #expect(verifyTerminalCapabilityFixtures().isEmpty)
    }

    @Test("Ambiguous stable identities never claim an exact target")
    func ambiguousStableIdentityFallsBack() {
        let resolution = TerminalFocusCapabilityResolver.resolve(
            target: terminalTarget(sessionIdentifier: "42"),
            snapshot: TerminalFocusCapabilitySnapshot(
                helperAvailable: true,
                metadataFresh: true,
                candidates: [
                    TerminalFocusCandidate(stableID: "42", tty: "/dev/ttys010", cwd: "/tmp/a"),
                    TerminalFocusCandidate(stableID: "42", tty: "/dev/ttys011", cwd: "/tmp/b")
                ],
                fallbackAvailable: true
            )
        )

        #expect(resolution.precision == .fallback)
        #expect(resolution.candidate == nil)
    }
}
#elseif canImport(XCTest)
final class TerminalFocusCapabilityTests: XCTestCase {
    func testOfflineCapabilityFixturesPreserveGuarantees() {
        XCTAssertTrue(verifyTerminalCapabilityFixtures().isEmpty)
    }

    func testAmbiguousStableIdentitiesNeverClaimExactTarget() {
        let resolution = TerminalFocusCapabilityResolver.resolve(
            target: terminalTarget(sessionIdentifier: "42"),
            snapshot: TerminalFocusCapabilitySnapshot(
                helperAvailable: true,
                metadataFresh: true,
                candidates: [
                    TerminalFocusCandidate(stableID: "42", tty: "/dev/ttys010", cwd: "/tmp/a"),
                    TerminalFocusCandidate(stableID: "42", tty: "/dev/ttys011", cwd: "/tmp/b")
                ],
                fallbackAvailable: true
            )
        )

        XCTAssertEqual(resolution.precision, .fallback)
        XCTAssertNil(resolution.candidate)
    }
}
#endif
