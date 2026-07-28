// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private let codexBrokerFixtureNames = [
    "codex-request-user-input",
    "codex-command-approval",
    "codex-file-approval",
    "codex-permissions-approval"
]

private func codexBrokerFixtureReplayError(_ name: String) -> String? {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
        return "Missing fixture \(name).json"
    }
    guard let data = try? Data(contentsOf: url),
          let fixture = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let frame = fixture["request"] as? [String: Any],
          let method = frame["method"] as? String,
          let rawID = frame["id"],
          let params = frame["params"] as? [String: Any],
          let expected = fixture["expected"] as? [String: Any],
          let expectedRequest = expected["mappedRequest"] as? [String: Any],
          let expectedResponse = expected["response"] as? [String: Any],
          let decisionJSON = fixture["decision"] as? [String: Any],
          let decision = fixtureDecision(decisionJSON) else {
        return "Malformed fixture \(name).json"
    }

    guard let request = CodexBrokerProtocol.request(
        fromServerMethod: method,
        rawID: rawID,
        params: params,
        now: Date(timeIntervalSince1970: 1_700_000_000)
    ) else {
        return "Protocol rejected valid fixture \(name)"
    }

    let mappedRequest = requestProjection(request)
    guard jsonObjectsEqual(mappedRequest, expectedRequest) else {
        return "Mapped request mismatch for \(name): \(canonicalJSON(mappedRequest))"
    }

    guard let response = CodexBrokerProtocol.responsePayload(
        responseSchema: request.responseSchema,
        toolInputJSON: request.toolInputJSON,
        decision: decision
    ) else {
        return "Protocol did not produce a response for \(name)"
    }
    guard jsonObjectsEqual(response, expectedResponse) else {
        return "Response mismatch for \(name): \(canonicalJSON(response))"
    }
    return nil
}

private func fixtureDecision(_ json: [String: Any]) -> PendingRequestDecision? {
    switch json["type"] as? String {
    case "allow":
        return .allow
    case "deny":
        return .deny
    case "answer":
        guard let rawAnswers = json["answers"] as? [String: Any] else { return nil }
        var answers: [String: [String]] = [:]
        for (id, value) in rawAnswers {
            guard let values = value as? [String] else { return nil }
            answers[id] = values
        }
        return .answer(answers)
    default:
        return nil
    }
}

private func requestProjection(_ request: HookSocketRequest) -> [String: Any] {
    var output: [String: Any] = [
        "type": request.type ?? "",
        "source": request.source ?? "",
        "surface": request.surface ?? "",
        "event": request.event ?? "",
        "status": request.status ?? "",
        "message": request.message ?? "",
        "session": request.session ?? "",
        "requestId": request.requestID ?? "",
        "tool": request.tool ?? "",
        "toolInputSummary": request.toolInputSummary ?? "",
        "responseSchema": request.responseSchema ?? ""
    ]
    if let question = request.question {
        output["question"] = question
    }
    if let options = request.options {
        output["options"] = options
    }
    if let questions = request.questions, !questions.isEmpty {
        output["questions"] = questions.map { question -> [String: Any] in
            var projected: [String: Any] = [
                "id": question.id,
                "header": question.header ?? "",
                "prompt": question.prompt,
                "options": question.options,
                "multiSelect": question.multiSelect,
                "isSecret": question.isSecret
            ]
            if let allowsOther = question.allowsOther {
                projected["allowsOther"] = allowsOther
            }
            return projected
        }
    }
    if let toolInputJSON = request.toolInputJSON,
       let data = toolInputJSON.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) {
        output["toolInput"] = object
    }
    return output
}

private func jsonObjectsEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    canonicalJSON(lhs) == canonicalJSON(rhs)
}

private func canonicalJSON(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
        return String(describing: value)
    }
    return text
}

private func codexBrokerRejectsUnsupportedShapes() -> Bool {
    let missingRequiredFields = CodexBrokerProtocol.request(
        fromServerMethod: "item/commandExecution/requestApproval",
        rawID: "missing-fields",
        params: ["threadId": "thread-redacted"]
    )
    let malformedQuestion = CodexBrokerProtocol.request(
        fromServerMethod: "item/tool/requestUserInput",
        rawID: "bad-question",
        params: [
            "threadId": "thread-redacted",
            "turnId": "turn-redacted",
            "itemId": "item-redacted",
            "questions": [["id": "scope", "header": "Scope"]]
        ]
    )
    let invalidPermissionAllow = CodexBrokerProtocol.responsePayload(
        responseSchema: "codex_app_server_permissions_approval",
        toolInputJSON: "not-json",
        decision: .allow
    )
    let mismatchedApprovalDecision = CodexBrokerProtocol.responsePayload(
        responseSchema: "codex_app_server_command_approval",
        toolInputJSON: nil,
        decision: .answer(["scope": ["Current task"]])
    )

    return missingRequiredFields == nil
        && malformedQuestion == nil
        && invalidPermissionAllow == nil
        && mismatchedApprovalDecision == nil
        && CodexBrokerProtocol.request(
            fromServerMethod: "item/unknown/requestApproval",
            rawID: 1,
            params: [:]
        ) == nil
        && CodexBrokerProtocol.responsePayload(
            responseSchema: "unknown_schema",
            toolInputJSON: nil,
            decision: .allow
        ) == nil
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Codex broker protocol fixtures")
struct CodexBrokerProtocolTests {
    @Test("Replays redacted app-server request and response fixtures")
    func fixtureReplay() {
        for name in codexBrokerFixtureNames {
            if let error = codexBrokerFixtureReplayError(name) {
                Issue.record(error)
            }
        }
    }

    @Test("Rejects unknown or malformed protocol shapes")
    func rejectsUnsupportedShapes() {
        #expect(codexBrokerRejectsUnsupportedShapes())
    }
}
#elseif canImport(XCTest)
final class CodexBrokerProtocolTests: XCTestCase {
    func testFixtureReplay() {
        for name in codexBrokerFixtureNames {
            XCTAssertNil(codexBrokerFixtureReplayError(name))
        }
    }

    func testRejectsUnsupportedShapes() {
        XCTAssertTrue(codexBrokerRejectsUnsupportedShapes())
    }
}
#endif
