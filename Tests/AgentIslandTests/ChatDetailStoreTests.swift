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

private func codexTranscriptActivityFixture() -> Bool {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let log = """
    {"type":"event_msg","payload":{"type":"task_started"}}
    {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Refactor the status detector"}]}}
    {"type":"response_item","payload":{"type":"custom_tool_call","name":"exec"}}
    """
    guard let activity = CodexTranscriptProbe.activity(
        sessionID: "70266e98-3300-4871-8ec4-8edba1ee8a24",
        data: Data(log.utf8),
        modified: now,
        now: now
    ) else { return false }
    return activity.phase == .working
        && activity.title == "Refactor the status detector"
        && activity.detail == "工具: exec"
}

private func claudeAppAuditActivityFixture() -> Bool {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let info = ClaudeAppSessionInfo(
        sessionId: "local_70266e98-3300-4871-8ec4-8edba1ee8a24",
        cliSessionId: "70266e98-3300-4871-8ec4-8edba1ee8a24",
        cwd: "/tmp/claude-app-workspace",
        title: "Review Agent Island status accuracy",
        lastFocusedAt: nil,
        lastActivityAt: now.timeIntervalSince1970 * 1000
    )
    let log = """
    {"type":"user","message":{"content":"Review the status detector"}}
    {"type":"system","subtype":"status","status":"requesting"}
    """
    guard let activity = ClaudeAppAuditProbe.activity(
        info: info,
        data: Data(log.utf8),
        modified: now,
        now: now
    ) else { return false }
    return activity.phase == .working
        && activity.title == "Review Agent Island status accuracy"
        && activity.detail == "正在执行"
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

    @Test("Codex app-server transcript reports an active tool call")
    func codexTranscriptActivity() {
        #expect(codexTranscriptActivityFixture())
    }

    @Test("Claude app audit reports an active local-agent request")
    func claudeAppAuditActivity() {
        #expect(claudeAppAuditActivityFixture())
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

    func testCodexTranscriptActivity() {
        XCTAssertTrue(codexTranscriptActivityFixture())
    }

    func testClaudeAppAuditActivity() {
        XCTAssertTrue(claudeAppAuditActivityFixture())
    }
}
#endif
