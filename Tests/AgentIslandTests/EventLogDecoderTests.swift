// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private let firstEventLine = #"{"agent":"claude","surface":"app","status":"working","session":"one","ts":1800000000}"#
private let secondEventLine = #"{"agent":"codex","surface":"cli","status":"done","session":"two","ts":1800000001}"#

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Event log decoder")
struct EventLogDecoderTests {
    @Test("Complete JSONL records decode together")
    func completeRecordsDecodeTogether() {
        let decoded = AgentEventLogDecoder.decodeChunk(firstEventLine + "\n" + secondEventLine + "\n")

        #expect(decoded.events.map(\.session) == ["one", "two"])
        #expect(decoded.fragment.isEmpty)
    }

    @Test("Partial trailing record waits for the next chunk")
    func partialTrailingRecordWaitsForNextChunk() {
        let splitIndex = secondEventLine.index(secondEventLine.startIndex, offsetBy: 28)
        let prefix = String(secondEventLine[..<splitIndex])
        let suffix = String(secondEventLine[splitIndex...])

        let firstChunk = AgentEventLogDecoder.decodeChunk(firstEventLine + "\n" + prefix)
        #expect(firstChunk.events.map(\.session) == ["one"])
        #expect(firstChunk.fragment == prefix)

        let secondChunk = AgentEventLogDecoder.decodeChunk(firstChunk.fragment + suffix + "\n")
        #expect(secondChunk.events.map(\.session) == ["two"])
        #expect(secondChunk.fragment.isEmpty)
    }
}
#elseif canImport(XCTest)
final class EventLogDecoderTests: XCTestCase {
    func testCompleteRecordsDecodeTogether() {
        let decoded = AgentEventLogDecoder.decodeChunk(firstEventLine + "\n" + secondEventLine + "\n")

        XCTAssertEqual(decoded.events.map(\.session), ["one", "two"])
        XCTAssertTrue(decoded.fragment.isEmpty)
    }

    func testPartialTrailingRecordWaitsForNextChunk() {
        let splitIndex = secondEventLine.index(secondEventLine.startIndex, offsetBy: 28)
        let prefix = String(secondEventLine[..<splitIndex])
        let suffix = String(secondEventLine[splitIndex...])

        let firstChunk = AgentEventLogDecoder.decodeChunk(firstEventLine + "\n" + prefix)
        XCTAssertEqual(firstChunk.events.map(\.session), ["one"])
        XCTAssertEqual(firstChunk.fragment, prefix)

        let secondChunk = AgentEventLogDecoder.decodeChunk(firstChunk.fragment + suffix + "\n")
        XCTAssertEqual(secondChunk.events.map(\.session), ["two"])
        XCTAssertTrue(secondChunk.fragment.isEmpty)
    }
}
#endif
