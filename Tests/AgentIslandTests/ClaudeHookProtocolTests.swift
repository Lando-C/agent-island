// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private let claudeHookFixtureNames = [
    "claude-permission-request-2.1.191",
    "claude-ask-user-question-2.1.191",
    "claude-elicitation-2.1.191"
]

private func claudeHookFixtureReplayError(_ name: String) -> String? {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let fixture = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          fixture["provider"] as? String == "Claude Code",
          let providerVersion = fixture["providerVersion"] as? String,
          !providerVersion.isEmpty,
          let provenance = fixture["provenance"] as? [String: Any],
          provenance["kind"] as? String == "documentation-derived-and-local-version-pinned",
          let normalized = fixture["normalizedRequest"] as? [String: Any],
          let decisions = fixture["decisions"] as? [[String: Any]],
          let normalizedData = try? JSONSerialization.data(withJSONObject: normalized),
          let socketRequest = try? JSONDecoder().decode(HookSocketRequest.self, from: normalizedData) else {
        return "Malformed fixture \(name).json"
    }

    let store = PendingRequestStore()
    let request = store.upsert(socketRequest: socketRequest)
    guard request.family == .claude,
          request.canRespondInline,
          request.responseSchema?.hasPrefix("claude_") == true else {
        return "Fixture \(name) did not map to a supported Claude request"
    }

    for decisionFixture in decisions {
        guard let decision = claudeFixtureDecision(decisionFixture),
              let expected = decisionFixture["expectedResponse"],
              let responseData = HookSocketServer.responseData(for: request, decision: decision),
              let response = try? JSONSerialization.jsonObject(with: responseData) else {
            return "Fixture \(name) produced no response for \(decisionFixture["type"] ?? "unknown")"
        }
        guard NSDictionary(dictionary: response as? [String: Any] ?? [:]).isEqual(to: expected as? [AnyHashable: Any] ?? [:]) else {
            return "Fixture \(name) response mismatch for \(decisionFixture["type"] ?? "unknown")"
        }
    }
    return nil
}

private func claudeFixtureDecision(_ fixture: [String: Any]) -> PendingRequestDecision? {
    switch fixture["type"] as? String {
    case "allow":
        return .allow
    case "deny":
        return .deny
    case "answer":
        guard let raw = fixture["answers"] as? [String: Any] else { return nil }
        var answers: [String: [String]] = [:]
        for (key, value) in raw {
            guard let values = value as? [String] else { return nil }
            answers[key] = values
        }
        return .answer(answers)
    default:
        return nil
    }
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Claude hook protocol fixtures")
struct ClaudeHookProtocolTests {
    @Test("Provider-version fixtures replay through production response encoding")
    func fixtureReplay() {
        for name in claudeHookFixtureNames {
            #expect(claudeHookFixtureReplayError(name) == nil)
        }
    }
}
#elseif canImport(XCTest)
final class ClaudeHookProtocolTests: XCTestCase {
    func testProviderVersionFixturesReplayThroughProductionResponseEncoding() {
        for name in claudeHookFixtureNames {
            XCTAssertNil(claudeHookFixtureReplayError(name))
        }
    }
}
#endif
