// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func browserBridgeProtocolFixture() -> Bool {
    let v1 = BrowserBridgeProtocol.normalized(source: "chatgpt", phase: "needs_attention")
    let v2 = BrowserBridgeProtocol.normalized(source: "Claude Web", phase: "working")
    let codex = BrowserBridgeProtocol.normalized(source: "Codex OpenAI Web", phase: "idle")
    let first = BrowserBridgeProtocol.fallbackSession(
        family: "chatgpt",
        url: "https://chatgpt.com/c/example"
    )
    let second = BrowserBridgeProtocol.fallbackSession(
        family: "chatgpt",
        url: "https://chatgpt.com/c/example"
    )
    return BrowserBridgeProtocol.accepts(version: 1)
        && BrowserBridgeProtocol.accepts(version: 2)
        && !BrowserBridgeProtocol.accepts(version: 3)
        && v1?.family == "chatgpt"
        && v1?.phase == "needs_attention"
        && v2?.family == "claude"
        && v2?.phase == "working"
        && codex?.family == "codex"
        && BrowserBridgeProtocol.normalized(source: "unknown", phase: "working") == nil
        && BrowserBridgeProtocol.normalized(source: "codex", phase: "invented") == nil
        && first == second
        && first.hasPrefix("web-")
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Browser bridge protocol")
struct BrowserBridgeProtocolTests {
    @Test("Accepts compatible versions and normalizes only supported status frames")
    func protocolNormalization() {
        #expect(browserBridgeProtocolFixture())
    }
}
#elseif canImport(XCTest)
final class BrowserBridgeProtocolTests: XCTestCase {
    func testAcceptsCompatibleVersionsAndNormalizesOnlySupportedStatusFrames() {
        XCTAssertTrue(browserBridgeProtocolFixture())
    }
}
#endif
