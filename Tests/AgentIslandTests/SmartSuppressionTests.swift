// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func chatGPTPageClassifierFixture() -> Bool {
    SmartSuppression.isChatGPTPage("ChatGPT\nhttps://chatgpt.com/c/123")
        && SmartSuppression.isChatGPTPage("Conversation\nhttps://chat.openai.com/c/456")
        && !SmartSuppression.isChatGPTPage("GitHub\nhttps://github.com/Lando-C/agent-island")
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Smart suppression")
struct SmartSuppressionTests {
    @Test("Only ChatGPT browser pages qualify")
    func onlyChatGPTPagesQualify() {
        #expect(chatGPTPageClassifierFixture())
    }
}
#elseif canImport(XCTest)
final class SmartSuppressionTests: XCTestCase {
    func testOnlyChatGPTBrowserPagesQualify() {
        XCTAssertTrue(chatGPTPageClassifierFixture())
    }
}
#endif
