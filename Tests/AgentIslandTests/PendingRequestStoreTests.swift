// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Combine
import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func pendingStoreFixture() -> (store: PendingRequestStore, snapshot: AgentSnapshot) {
    let store = PendingRequestStore()
    let request = HookSocketRequest(
        type: nil,
        source: "claude",
        surface: "cli",
        event: "PermissionRequest",
        status: nil,
        title: "Claude 请求允许 Read",
        message: nil,
        session: "session-1",
        rawSession: nil,
        primarySession: nil,
        parentSession: nil,
        requestID: "request-1",
        tool: "Read",
        toolInputSummary: "path: README.md",
        toolRisk: "safe_read",
        toolRiskReason: nil,
        question: nil,
        options: nil,
        responseSchema: "claude_permission_request",
        ts: nil
    )
    _ = store.upsert(socketRequest: request)

    var snapshot = AgentSnapshot.empty(.claude, .cli)
    snapshot.sessionID = "session-1"
    snapshot.requestID = "request-1"
    return (store, snapshot)
}

private func claudeQuestionFixture() -> PendingRequest {
    let store = PendingRequestStore()
    let question = PendingQuestion(
        id: "framework",
        header: "Framework",
        prompt: "Which framework?",
        options: ["React", "Vue"],
        multiSelect: false,
        isSecret: false,
        allowsOther: true
    )
    return store.upsert(socketRequest: HookSocketRequest(
        type: "hook_request",
        source: "claude",
        surface: "cli",
        event: "AskUserQuestion",
        status: "needs_attention",
        title: nil,
        message: nil,
        session: "session-question",
        rawSession: nil,
        primarySession: nil,
        parentSession: nil,
        requestID: "question-1",
        tool: "AskUserQuestion",
        toolInputSummary: nil,
        toolRisk: nil,
        toolRiskReason: nil,
        question: question.prompt,
        options: question.options,
        questions: [question],
        responseSchema: "claude_pre_tool_ask_user_question",
        toolInputJSON: #"{"questions":[{"question":"Which framework?","header":"Framework","options":[{"label":"React"},{"label":"Vue"}],"multiSelect":false}]}"#,
        requestedSchemaJSON: nil,
        ts: nil
    ))
}

private func claudeQuestionResponseIsValid() -> Bool {
    let request = claudeQuestionFixture()
    guard let data = HookSocketServer.responseData(
        for: request,
        decision: .answer(["framework": ["React"]])
    ), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let output = root["hookSpecificOutput"] as? [String: Any],
       output["hookEventName"] as? String == "PreToolUse",
       output["permissionDecision"] as? String == "allow",
       let input = output["updatedInput"] as? [String: Any],
       let answers = input["answers"] as? [String: String] else {
        return false
    }
    return answers["Which framework?"] == "React" && input["questions"] != nil
}

private func codexQuestionResponseIsValid() -> Bool {
    let payload = CodexBrokerClient.userInputResponsePayload([
        "framework": ["SwiftUI"],
        "targets": ["macOS", "Linux"]
    ])
    guard let answers = payload["answers"] as? [String: Any],
          let framework = answers["framework"] as? [String: [String]],
          let targets = answers["targets"] as? [String: [String]] else { return false }
    return framework["answers"] == ["SwiftUI"] && targets["answers"] == ["macOS", "Linux"]
}

private func pendingDecisionIsDeliveredOnce() -> Bool {
    let fixture = pendingStoreFixture()
    guard let request = fixture.store.requests.first else { return false }
    var decisions = 0
    fixture.store.addDecisionHandler { _, _ in decisions += 1 }
    fixture.store.allow(request)
    fixture.store.allow(request)
    return decisions == 1 && fixture.store.requests.first?.status == .allowed
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Pending request store")
struct PendingRequestStoreTests {
    @Test("Lookup does not publish during rendering")
    func requestLookupDoesNotPublishDuringViewRendering() {
        let fixture = pendingStoreFixture()
        var publishCount = 0
        let cancellable = fixture.store.objectWillChange.sink { publishCount += 1 }

        #expect(fixture.store.request(for: fixture.snapshot)?.id == "claude::request-1")
        #expect(publishCount == 0)

        withExtendedLifetime(cancellable) {}
    }

    @Test("Claude AskUserQuestion response preserves questions and writes answers")
    func claudeAskUserQuestionResponse() {
        #expect(claudeQuestionResponseIsValid())
    }


    @Test("Codex requestUserInput response groups answers by question ID")
    func codexRequestUserInputResponse() {
        #expect(codexQuestionResponseIsValid())
    }


    @Test("A pending request is delivered only once")
    func pendingDecisionDeliveredOnce() {
        #expect(pendingDecisionIsDeliveredOnce())
    }
}
#elseif canImport(XCTest)
final class PendingRequestStoreTests: XCTestCase {
    func testRequestLookupDoesNotPublishDuringViewRendering() {
        let fixture = pendingStoreFixture()
        var publishCount = 0
        let cancellable = fixture.store.objectWillChange.sink { publishCount += 1 }

        XCTAssertEqual(fixture.store.request(for: fixture.snapshot)?.id, "claude::request-1")
        XCTAssertEqual(publishCount, 0)

        withExtendedLifetime(cancellable) {}
    }


    func testClaudeAskUserQuestionResponsePreservesInput() {
        XCTAssertTrue(claudeQuestionResponseIsValid())
    }


    func testCodexRequestUserInputResponseGroupsAnswers() {
        XCTAssertTrue(codexQuestionResponseIsValid())
    }


    func testPendingDecisionIsDeliveredOnlyOnce() {
        XCTAssertTrue(pendingDecisionIsDeliveredOnce())
    }
}
#endif
