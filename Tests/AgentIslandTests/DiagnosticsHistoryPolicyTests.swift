// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func diagnosticsHistoryPolicyFailure() -> String? {
    let entries = [
        DiagnosticsHistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            recordedAt: Date(timeIntervalSince1970: 2),
            transportID: "codex-broker",
            transportName: "Codex App Server",
            state: .failed,
            protocolVersion: "jsonrpc/2",
            endpoint: "http://127.0.0.1:8765/v1/events",
            failure: "connection refused"
        ),
        DiagnosticsHistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            recordedAt: Date(timeIntervalSince1970: 1),
            transportID: "web-bridge",
            transportName: "Browser Web Bridge",
            state: .connected,
            protocolVersion: "browser-bridge-v3",
            endpoint: "ws://127.0.0.1:9123/events",
            failure: nil
        )
    ]

    let exactTransport = DiagnosticsHistoryPolicy.filter(
        entries,
        using: DiagnosticsHistoryFilter(transportID: "CODEX-BROKER")
    )
    guard exactTransport.map(\.id) == [entries[0].id] else {
        return "transport filtering was not exact and case-insensitive"
    }

    let combined = DiagnosticsHistoryPolicy.filter(
        entries,
        using: DiagnosticsHistoryFilter(
            state: .failed,
            query: "Codex refused JSONRPC"
        )
    )
    guard combined.map(\.id) == [entries[0].id] else {
        return "state and multi-term text filtering did not compose"
    }

    let noMatch = DiagnosticsHistoryPolicy.filter(
        entries,
        using: DiagnosticsHistoryFilter(state: .connected, query: "failure")
    )
    guard noMatch.isEmpty else {
        return "text filtering ignored the state constraint"
    }
    return nil
}

private func diagnosticsHistoryExportFailure() -> String? {
    let unsafe = DiagnosticsHistoryEntry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        recordedAt: Date(timeIntervalSince1970: 3),
        transportID: "token_secret123",
        transportName: "Codex API_KEY=top-secret",
        state: .degraded,
        protocolVersion: "Bearer raw-protocol-token",
        endpoint: "https://alice:password@example.com/events?token=raw-query-token",
        failure: "Bearer raw-failure-token at /Users/alice/private/project"
    )

    let outputs: [String]
    do {
        outputs = [
            try DiagnosticsHistoryPolicy.export([unsafe], format: .json),
            try DiagnosticsHistoryPolicy.export([unsafe], format: .text)
        ]
    } catch {
        return "export unexpectedly failed: \(error)"
    }

    guard DiagnosticsHistoryPolicy.filter(
        [unsafe],
        using: DiagnosticsHistoryFilter(query: "top-secret")
    ).isEmpty else {
        return "text filtering exposed a value removed by the privacy projection"
    }

    for output in outputs {
        guard output.contains("<redacted>") else {
            return "export did not retain an explicit redaction marker"
        }
        for secret in [
            "top-secret",
            "raw-protocol-token",
            "raw-query-token",
            "raw-failure-token",
            "secret123",
            "alice",
            "password",
            "private/project"
        ] where output.localizedCaseInsensitiveContains(secret) {
            return "export leaked \(secret)"
        }
    }

    guard outputs[0].contains("\"schemaVersion\" : 1"),
          outputs[0].contains("\"privacy\" : \"redacted transport metadata only\""),
          outputs[0].contains("\"transportID\" : \"redacted\""),
          outputs[1].hasPrefix("Agent Island Diagnostics History\n"),
          outputs[1].hasSuffix("\n") else {
        return "export format contract was unstable"
    }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-island-diagnostics-export-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("history.json")
        guard FileManager.default.createFile(
            atPath: destination.path,
            contents: Data("old".utf8),
            attributes: [.posixPermissions: 0o644]
        ) else {
            return "failed to create replacement export fixture"
        }
        try DiagnosticsHistoryPolicy.export([unsafe], format: .json, to: destination)
        let permissions = (
            try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions]
                as? NSNumber
        )?.intValue
        guard permissions == 0o600 else {
            return "file export was not private from replacement onward"
        }
        let persisted = try String(contentsOf: destination, encoding: .utf8)
        guard persisted == outputs[0], !persisted.contains("old") else {
            return "file export did not replace the previous document"
        }
    } catch {
        return "private file export failed: \(error)"
    }
    return nil
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Test("diagnostics history filters compose")
func diagnosticsHistoryFiltersCompose() {
    #expect(diagnosticsHistoryPolicyFailure() == nil)
}

@Test("diagnostics history exports remain redacted")
func diagnosticsHistoryExportsRemainRedacted() {
    #expect(diagnosticsHistoryExportFailure() == nil)
}
#elseif canImport(XCTest)
final class DiagnosticsHistoryPolicyTests: XCTestCase {
    func testDiagnosticsHistoryFiltersCompose() {
        XCTAssertNil(diagnosticsHistoryPolicyFailure())
    }

    func testDiagnosticsHistoryExportsRemainRedacted() {
        XCTAssertNil(diagnosticsHistoryExportFailure())
    }
}
#endif
