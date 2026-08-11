// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Darwin
import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func withBrokerFixture<T>(_ body: (URL) throws -> T) throws -> T {
    // Keep the fixture below macOS's Unix-domain socket path limit even when
    // XCTest provides a long hosted-runner temporary directory.
    let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("ai-broker-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: root) }
    return try body(root)
}

private func createBrokerFixture(root: URL, name: String, modified: Date) throws -> String {
    let directory = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let socket = directory.appendingPathComponent("broker.sock")
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    defer { close(descriptor) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(socket.path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
        throw POSIXError(.ENAMETOOLONG)
    }
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { target in
            for (index, byte) in bytes.enumerated() {
                target[index] = CChar(bitPattern: byte)
            }
            target[bytes.count] = 0
        }
    }
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
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

        let override = try createBrokerFixture(
            root: root,
            name: "explicit",
            modified: Date(timeIntervalSince1970: 50)
        )
        let regularDirectory = root.appendingPathComponent("cxc-regular")
        try FileManager.default.createDirectory(at: regularDirectory, withIntermediateDirectories: true)
        let regular = regularDirectory.appendingPathComponent("broker.sock")
        _ = FileManager.default.createFile(atPath: regular.path, contents: Data())
        let symlinkDirectory = root.appendingPathComponent("cxc-symlink")
        try FileManager.default.createDirectory(at: symlinkDirectory, withIntermediateDirectories: true)
        let symlink = symlinkDirectory.appendingPathComponent("broker.sock")
        try FileManager.default.createSymbolicLink(atPath: symlink.path, withDestinationPath: newer)
        let paths = CodexBrokerEndpoint.candidates(
            overridePath: override,
            temporaryRoots: [root.path, root.path],
            fileManager: .default
        )
        return paths == [override, newer, older]
            && CodexBrokerEndpoint.isTrustedSocket(newer)
            && !CodexBrokerEndpoint.isTrustedSocket(regular.path)
            && !CodexBrokerEndpoint.isTrustedSocket(symlink.path)
            && !CodexBrokerEndpoint.isTrustedSocket(newer, effectiveUID: geteuid() &+ 1)
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
