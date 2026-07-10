// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Combine
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
}
#endif
