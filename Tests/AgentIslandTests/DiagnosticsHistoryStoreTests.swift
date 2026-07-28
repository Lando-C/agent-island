// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func diagnosticsHistoryFailure() -> String? {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-island-history-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("history.json")
    let history = DiagnosticsHistoryStore(outputURL: url, limit: 3)

    var first = TransportHealthSnapshot.initial(id: "codex-broker", name: "Codex App Server")
    first.state = .failed
    first.protocolVersion = "jsonrpc/2"
    first.endpoint = "http://user:password@127.0.0.1:8765/v1/events?token=secret"
    first.failure = "Bearer abc123 failed at /Users/alice/private/project API_KEY=top-secret"
    history.record(first, at: Date(timeIntervalSince1970: 1))
    history.record(first, at: Date(timeIntervalSince1970: 2))

    var second = first
    second.state = .connecting
    second.failure = nil
    second.endpoint = "/tmp/private-session.sock"
    history.record(second, at: Date(timeIntervalSince1970: 3))

    var third = second
    third.state = .connected
    third.endpoint = "/Users/alice/secret-project"
    history.record(third, at: Date(timeIntervalSince1970: 4))

    var fourth = third
    fourth.state = .degraded
    fourth.endpoint = "http://user:password@127.0.0.1:8765/v1/events?token=secret"
    fourth.failure = "Bearer abc123 failed at /Users/alice/private/project and /tmp/raw-session.sock API_KEY=top-secret"
    history.record(fourth, at: Date(timeIntervalSince1970: 5))
    history.flushForTesting()

    let reloaded = DiagnosticsHistoryStore(outputURL: url, limit: 3)
    guard reloaded.entries.count == 3 else { return "history retention did not enforce its limit" }
    guard reloaded.entries.first?.state == .degraded,
          reloaded.entries.last?.state == .connecting else {
        return "history was not stored newest-first after reload"
    }
    guard reloaded.entries.first?.endpoint == "http://127.0.0.1:8765/v1/events",
          reloaded.entries.last?.endpoint == "/tmp/<redacted>" else {
        return "endpoints were not redacted"
    }
    guard reloaded.entries.first?.failure?.contains("<redacted>") == true else {
        return "failure summary did not retain a safe explanation"
    }

    let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    for secret in ["abc123", "top-secret", "alice", "secret-project", "private-session.sock", "raw-session.sock", "password"] {
        if raw.contains(secret) { return "persisted history leaked \(secret)" }
    }
    let permissions = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?
        .intValue
    guard permissions == 0o600 else {
        return "history file permissions were not restricted to 0600"
    }
    return nil
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Test("diagnostics history is bounded, deduplicated, and redacted")
func diagnosticsHistoryIsSafe() {
    #expect(diagnosticsHistoryFailure() == nil)
}
#elseif canImport(XCTest)
final class DiagnosticsHistoryStoreTests: XCTestCase {
    func testDiagnosticsHistoryIsSafe() {
        XCTAssertNil(diagnosticsHistoryFailure())
    }
}
#endif
