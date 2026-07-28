// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func withBrokerFixture<T>(_ body: (URL) throws -> T) throws -> T {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-island-broker-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    return try body(root)
}

private func createBrokerFixture(root: URL, name: String, modified: Date) throws -> String {
    let directory = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let socket = directory.appendingPathComponent("broker.sock")
    _ = FileManager.default.createFile(atPath: socket.path, contents: Data())
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: socket.path)
    return socket.path
}

private func discoveryFixtureIsValid() throws -> Bool {
    try withBrokerFixture { root in
        let older = try createBrokerFixture(
            root: root,
            name: "cxc-older",
            modified: Date(timeIntervalSince1970: 100)
        )
        let newer = try createBrokerFixture(
            root: root,
            name: "cxc-newer",
            modified: Date(timeIntervalSince1970: 200)
        )
        _ = try createBrokerFixture(
            root: root,
            name: "not-codex",
            modified: Date(timeIntervalSince1970: 300)
        )

        let override = root.appendingPathComponent("explicit.sock").path
        let paths = CodexBrokerEndpoint.candidates(
            overridePath: override,
            temporaryRoots: [root.path, root.path],
            fileManager: .default
        )
        return paths == [override, newer, older]
    }
}

private func connectionFixtureIsValid() -> Bool {
    var attempts: [String] = []
    let connection = CodexBrokerEndpoint.connectFirst(
        candidates: ["/first", "/second", "/third"],
        onAttempt: { attempts.append($0) },
        connector: { $0 == "/second" ? 42 : nil }
    )
    return attempts == ["/first", "/second"]
        && connection?.path == "/second"
        && connection?.fileDescriptor == 42
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Codex broker endpoint")
struct CodexBrokerEndpointTests {
    @Test("Explicit override stays first and filesystem candidates are newest-first")
    func discoveryOrder() throws {
        #expect(try discoveryFixtureIsValid())
    }

    @Test("Connection attempts stop at the first accepted endpoint")
    func firstConnectionWins() {
        #expect(connectionFixtureIsValid())
    }
}
#elseif canImport(XCTest)
final class CodexBrokerEndpointTests: XCTestCase {
    func testDiscoveryOrderAndDeduplication() throws {
        XCTAssertTrue(try discoveryFixtureIsValid())
    }

    func testConnectionAttemptsStopAtFirstSuccess() {
        XCTAssertTrue(connectionFixtureIsValid())
    }
}
#endif
