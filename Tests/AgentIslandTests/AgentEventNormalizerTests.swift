// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Agent event normalizer")
struct AgentEventNormalizerTests {
    @Test("Provider aliases map to stable families")
    func familyAliases() {
        #expect(AgentEventNormalizer.family(from: "codex-cli") == .codex)
        #expect(AgentEventNormalizer.family(from: "Claude Desktop") == .claude)
        #expect(AgentEventNormalizer.family(from: "operon") == .claudeScience)
        #expect(AgentEventNormalizer.family(from: "unknown") == nil)
    }

    @Test("Surface aliases preserve conservative CLI fallback")
    func surfaceAliases() {
        #expect(AgentEventNormalizer.surface(from: "desktop") == .app)
        #expect(AgentEventNormalizer.surface(from: "kernel-service") == .runtime)
        #expect(AgentEventNormalizer.surface(from: "terminal") == .cli)
        #expect(AgentEventNormalizer.surface(from: nil) == .cli)
        #expect(AgentEventNormalizer.surface(from: "unknown") == .cli)
    }

    @Test("Hook lifecycle overrides provider status")
    func hookLifecycleOverridesStatus() {
        #expect(AgentEventNormalizer.phase(for: event(name: "Permission_Request", status: "working")) == .needsAttention)
        #expect(AgentEventNormalizer.phase(for: event(name: "user-prompt-submit", status: "idle")) == .queued)
        #expect(AgentEventNormalizer.phase(for: event(name: "Subagent_Stop", status: "working")) == .idle)
        #expect(AgentEventNormalizer.phase(for: event(name: "PostToolUseFailure", status: "error")) == .needsAttention)
    }

    @Test("Provider status aliases retain existing phase semantics")
    func phaseAliases() {
        #expect(AgentEventNormalizer.phase(from: "input_required") == .needsAttention)
        #expect(AgentEventNormalizer.phase(from: "busy") == .working)
        #expect(AgentEventNormalizer.phase(from: "waiting") == .queued)
        #expect(AgentEventNormalizer.phase(from: "finished") == .done)
        #expect(AgentEventNormalizer.phase(from: "failed") == .error)
        #expect(AgentEventNormalizer.phase(from: "unexpected") == nil)
    }

    private func event(name: String, status: String) -> AgentEvent {
        AgentEvent(status: status, event: name)
    }
}
#elseif canImport(XCTest)
final class AgentEventNormalizerTests: XCTestCase {
    func testFamilyAliases() {
        XCTAssertEqual(AgentEventNormalizer.family(from: "codex-cli"), .codex)
        XCTAssertEqual(AgentEventNormalizer.family(from: "Claude Desktop"), .claude)
        XCTAssertEqual(AgentEventNormalizer.family(from: "operon"), .claudeScience)
        XCTAssertNil(AgentEventNormalizer.family(from: "unknown"))
    }

    func testSurfaceAliases() {
        XCTAssertEqual(AgentEventNormalizer.surface(from: "desktop"), .app)
        XCTAssertEqual(AgentEventNormalizer.surface(from: "kernel-service"), .runtime)
        XCTAssertEqual(AgentEventNormalizer.surface(from: "terminal"), .cli)
        XCTAssertEqual(AgentEventNormalizer.surface(from: nil), .cli)
        XCTAssertEqual(AgentEventNormalizer.surface(from: "unknown"), .cli)
    }

    func testHookLifecycleOverridesStatus() {
        XCTAssertEqual(AgentEventNormalizer.phase(for: event(name: "Permission_Request", status: "working")), .needsAttention)
        XCTAssertEqual(AgentEventNormalizer.phase(for: event(name: "user-prompt-submit", status: "idle")), .queued)
        XCTAssertEqual(AgentEventNormalizer.phase(for: event(name: "Subagent_Stop", status: "working")), .idle)
        XCTAssertEqual(AgentEventNormalizer.phase(for: event(name: "PostToolUseFailure", status: "error")), .needsAttention)
    }

    func testPhaseAliases() {
        XCTAssertEqual(AgentEventNormalizer.phase(from: "input_required"), .needsAttention)
        XCTAssertEqual(AgentEventNormalizer.phase(from: "busy"), .working)
        XCTAssertEqual(AgentEventNormalizer.phase(from: "waiting"), .queued)
        XCTAssertEqual(AgentEventNormalizer.phase(from: "finished"), .done)
        XCTAssertEqual(AgentEventNormalizer.phase(from: "failed"), .error)
        XCTAssertNil(AgentEventNormalizer.phase(from: "unexpected"))
    }

    private func event(name: String, status: String) -> AgentEvent {
        AgentEvent(status: status, event: name)
    }
}
#endif
