// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func transcriptRouteFixture() -> Bool {
    let log = """
    {"session":"old","transcript_path":"/tmp/old.jsonl"}
    {"session":"target","transcript_path":"/tmp/missing.jsonl"}
    {"raw_session":"target","transcript_path":"/tmp/exact.jsonl"}
    """
    return ChatDetailStore.transcriptPath(
        inEventLog: log,
        sessionID: "target",
        fileExists: { $0 == "/tmp/exact.jsonl" }
    ) == "/tmp/exact.jsonl"
}

private func chatDedupFixture() -> Bool {
    let start = Date(timeIntervalSince1970: 100)
    let items = [
        ChatDetailItem(id: "response", role: .assistant, title: "Assistant", body: "Done", timestamp: start),
        ChatDetailItem(id: "event", role: .assistant, title: "Assistant", body: "Done", timestamp: start.addingTimeInterval(0.2)),
        ChatDetailItem(id: "later", role: .assistant, title: "Assistant", body: "Done", timestamp: start.addingTimeInterval(5))
    ]
    return ChatDetailStore.deduplicated(items).map(\.id) == ["response", "later"]
}

private func incrementalConversationFixture() -> Bool {
    let firstChunk = "{\"type\":\"user\",\"timestamp\":\"2026-07-14T10:00:00Z\",\"message\":{\"content\":\"Hello"
    let first = ConversationTranscriptParser.decodeChunk(
        firstChunk,
        family: .claude,
        startingLineNumber: 0
    )
    guard first.items.isEmpty, !first.fragment.isEmpty else { return false }
    let second = ConversationTranscriptParser.decodeChunk(
        first.fragment + " world\"}}\n",
        family: .claude,
        startingLineNumber: first.completeLineCount
    )
    return second.fragment.isEmpty
        && second.completeLineCount == 1
        && second.items.map(\.body) == ["Hello world"]
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Chat detail store")
struct ChatDetailStoreTests {
    @Test("Event transcript path wins without directory scanning")
    func eventTranscriptPath() {
        #expect(transcriptRouteFixture())
    }

    @Test("Near-simultaneous duplicate messages collapse")
    func duplicateMessagesCollapse() {
        #expect(chatDedupFixture())
    }

    @Test("Partial JSONL lines wait for completion before parsing")
    func partialLinesWaitForCompletion() {
        #expect(incrementalConversationFixture())
    }
}
#elseif canImport(XCTest)
final class ChatDetailStoreTests: XCTestCase {
    func testEventTranscriptPathWinsWithoutDirectoryScanning() {
        XCTAssertTrue(transcriptRouteFixture())
    }

    func testNearSimultaneousDuplicateMessagesCollapse() {
        XCTAssertTrue(chatDedupFixture())
    }

    func testPartialJSONLLinesWaitForCompletion() {
        XCTAssertTrue(incrementalConversationFixture())
    }
}
#endif
