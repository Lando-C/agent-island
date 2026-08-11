// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func appleScriptEscapingFixture() -> Bool {
    AppleScriptEscaping.literal("plain") == #""plain""#
        && AppleScriptEscaping.literal(#"a\b"c"#) == #""a\\b\"c""#
        && AppleScriptEscaping.literal("safe\nreturn do shell script \"id\"")
            == #""safe return do shell script \"id\"""#
        && AppleScriptEscaping.literal("a\r\tb\u{2028}c\u{2029}d\u{0000}")
            == #""a  b c d ""#
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("AppleScript escaping")
struct AppleScriptEscapingTests {
    @Test("Untrusted metadata cannot add AppleScript source lines")
    func metadataIsSingleLine() {
        #expect(appleScriptEscapingFixture())
    }
}
#elseif canImport(XCTest)
final class AppleScriptEscapingTests: XCTestCase {
    func testMetadataIsSingleLine() {
        XCTAssertTrue(appleScriptEscapingFixture())
    }
}
#endif
