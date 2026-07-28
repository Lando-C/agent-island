// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private let browserBridgeFixtureExpectations: [(name: String, disposition: BrowserBridgeDisposition)] = [
    ("browser-bridge-chatgpt-v3", .accepted(family: "chatgpt", phase: "working")),
    ("browser-bridge-claude-v3", .accepted(family: "claude", phase: "idle")),
    ("browser-bridge-codex-v3", .accepted(family: "codex", phase: "needs_attention")),
    (
        "browser-bridge-selector-drift-v3",
        .degraded(
            family: "chatgpt",
            reason: "Provider page no longer matches selector profile chatgpt-web-2026-07"
        )
    )
]

private func browserBridgeFixtureReplayError(
    name: String,
    expected: BrowserBridgeDisposition
) -> String? {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
        return "Missing fixture \(name).json"
    }
    guard let data = try? Data(contentsOf: url),
          let payload = try? JSONDecoder().decode(BrowserBridgePayload.self, from: data) else {
        return "Malformed fixture \(name).json"
    }
    let disposition = BrowserBridgeProtocol.evaluate(payload)
    guard disposition == expected else {
        return "Unexpected disposition for \(name): \(disposition)"
    }
    return nil
}

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
        && BrowserBridgeProtocol.accepts(version: 3)
        && !BrowserBridgeProtocol.accepts(version: 4)
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

private func browserBridgeVersionDriftFixture() -> Bool {
    let legacyWithoutProvenance = Data("""
    {
      "version": 2,
      "source": "chatgpt",
      "phase": "idle"
    }
    """.utf8)
    let unsupportedVersion = Data("""
    {
      "version": 4,
      "source": "chatgpt",
      "phase": "idle",
      "detector_version": "0.4.0",
      "selector_profile": "chatgpt-web-2026-10",
      "selector_state": "verified"
    }
    """.utf8)
    let mismatchedDetector = Data("""
    {
      "version": 3,
      "source": "claude",
      "phase": "idle",
      "detector_version": "0.2.0",
      "selector_profile": "claude-web-2026-07",
      "selector_state": "verified"
    }
    """.utf8)
    guard let legacy = try? JSONDecoder().decode(BrowserBridgePayload.self, from: legacyWithoutProvenance),
          let unsupported = try? JSONDecoder().decode(BrowserBridgePayload.self, from: unsupportedVersion),
          let mismatch = try? JSONDecoder().decode(BrowserBridgePayload.self, from: mismatchedDetector) else {
        return false
    }
    return BrowserBridgeProtocol.evaluate(legacy) == .degraded(
        family: "chatgpt",
        reason: "Browser Bridge v2 lacks selector provenance; update the extension to v3"
    ) && BrowserBridgeProtocol.evaluate(unsupported) == .degraded(
        family: "chatgpt",
        reason: "Unsupported Browser Bridge protocol v4; expected v1-v3"
    ) && BrowserBridgeProtocol.evaluate(mismatch) == .degraded(
        family: "claude",
        reason: "Browser detector version mismatch; expected 0.3.0"
    )
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Browser bridge protocol")
struct BrowserBridgeProtocolTests {
    @Test("Accepts compatible versions and normalizes only supported status frames")
    func protocolNormalization() {
        #expect(browserBridgeProtocolFixture())
    }

    @Test("Replays redacted provider selector fixtures")
    func fixtureReplay() {
        for fixture in browserBridgeFixtureExpectations {
            if let error = browserBridgeFixtureReplayError(
                name: fixture.name,
                expected: fixture.disposition
            ) {
                Issue.record(error)
            }
        }
    }

    @Test("Reports protocol and detector version drift as degraded")
    func versionDrift() {
        #expect(browserBridgeVersionDriftFixture())
    }
}
#elseif canImport(XCTest)
final class BrowserBridgeProtocolTests: XCTestCase {
    func testAcceptsCompatibleVersionsAndNormalizesOnlySupportedStatusFrames() {
        XCTAssertTrue(browserBridgeProtocolFixture())
    }

    func testReplaysRedactedProviderSelectorFixtures() {
        for fixture in browserBridgeFixtureExpectations {
            XCTAssertNil(
                browserBridgeFixtureReplayError(
                    name: fixture.name,
                    expected: fixture.disposition
                )
            )
        }
    }

    func testReportsProtocolAndDetectorVersionDriftAsDegraded() {
        XCTAssertTrue(browserBridgeVersionDriftFixture())
    }
}
#endif
