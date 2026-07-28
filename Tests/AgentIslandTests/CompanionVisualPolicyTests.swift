// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
@testable import AgentIsland

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing

@Suite("Companion visual policy")
struct CompanionVisualPolicyTests {
    @Test("Every family has a distinct identity glyph and palette")
    func familyIdentity() {
        let policies = AgentFamily.allCases.map {
            CompanionVisualPolicy.resolve(family: $0, surface: .cli, phase: .working)
        }
        #expect(Set(policies.map(\.familyGlyph)).count == AgentFamily.allCases.count)
        #expect(Set(policies.map(\.familyPalette)).count == AgentFamily.allCases.count)
    }

    @Test("Only active phases receive ambient motion")
    func motionEligibility() {
        let working = policy(.working)
        let thinking = policy(.thinking)
        #expect(working.motion == .breathe)
        #expect(thinking.motion == .breathe)

        for phase in passivePhases {
            #expect(policy(phase).motion == .none)
        }
    }

    @Test("Attention, success, and failure remain visually distinct")
    func semanticTones() {
        #expect(policy(.needsAttention).stateTone == .attention)
        #expect(policy(.done).stateTone == .success)
        #expect(policy(.error).stateTone == .failure)
        #expect(policy(.queued).stateTone == .waiting)
    }

    @Test("Policy exposes a compact accessible hierarchy")
    func labels() {
        let visual = CompanionVisualPolicy.resolve(
            family: .claudeScience,
            surface: .app,
            phase: .needsAttention
        )
        #expect(visual.identityLabel == "Claude Science · App")
        #expect(visual.stateLabel == "需处理")
        #expect(!visual.stateSummary.isEmpty)
        #expect(!visual.phaseGlyph.isEmpty)
    }

    private var passivePhases: [AgentPhase] {
        [.needsAttention, .queued, .done, .error, .online, .idle, .available, .offline]
    }

    private func policy(_ phase: AgentPhase) -> CompanionVisualPolicy {
        .resolve(family: .codex, surface: .cli, phase: phase)
    }
}
#elseif canImport(XCTest)
import XCTest

final class CompanionVisualPolicyTests: XCTestCase {
    func testFamilyIdentity() {
        let policies = AgentFamily.allCases.map {
            CompanionVisualPolicy.resolve(family: $0, surface: .cli, phase: .working)
        }
        XCTAssertEqual(Set(policies.map(\.familyGlyph)).count, AgentFamily.allCases.count)
        XCTAssertEqual(Set(policies.map(\.familyPalette)).count, AgentFamily.allCases.count)
    }

    func testMotionEligibility() {
        XCTAssertEqual(policy(.working).motion, .breathe)
        XCTAssertEqual(policy(.thinking).motion, .breathe)
        let passive: [AgentPhase] = [
            .needsAttention, .queued, .done, .error, .online, .idle, .available, .offline
        ]
        for phase in passive {
            XCTAssertEqual(policy(phase).motion, .none)
        }
    }

    func testSemanticTones() {
        XCTAssertEqual(policy(.needsAttention).stateTone, .attention)
        XCTAssertEqual(policy(.done).stateTone, .success)
        XCTAssertEqual(policy(.error).stateTone, .failure)
        XCTAssertEqual(policy(.queued).stateTone, .waiting)
    }

    private func policy(_ phase: AgentPhase) -> CompanionVisualPolicy {
        .resolve(family: .codex, surface: .cli, phase: phase)
    }
}
#endif
