// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
import Testing
#elseif canImport(XCTest)
import XCTest
#endif
@testable import AgentIsland

private func localDataSecurityFixture() -> String? {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-island-local-data-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let state = root.appendingPathComponent("state.json")

    do {
        try LocalDataSecurity.writePrivate(Data("one".utf8), to: state)
        try LocalDataSecurity.appendPrivate(Data("-two".utf8), to: state)
        guard try LocalDataSecurity.readPrivateString(state) == "one-two" else {
            return "private read/write round trip failed"
        }

        let rootMode = (try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue
        let fileMode = (try FileManager.default.attributesOfItem(atPath: state.path)[.posixPermissions] as? NSNumber)?.intValue
        guard rootMode == 0o700 else { return "private directory mode was \(rootMode ?? -1)" }
        guard fileMode == 0o600 else { return "private file mode was \(fileMode ?? -1)" }

        let target = root.appendingPathComponent("target")
        try Data("unchanged".utf8).write(to: target)
        let link = root.appendingPathComponent("linked-state")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        do {
            try LocalDataSecurity.writePrivate(Data("replaced".utf8), to: link)
            return "private write followed a symbolic link"
        } catch {}
        do {
            _ = try LocalDataSecurity.readPrivate(link)
            return "private read followed a symbolic link"
        } catch {}
        guard try String(contentsOf: target, encoding: .utf8) == "unchanged" else {
            return "symbolic-link target was modified"
        }
    } catch {
        return "local data fixture failed: \(error.localizedDescription)"
    }
    return nil
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Local data security")
struct LocalDataSecurityTests {
    @Test("Owner-only state rejects symbolic-link targets")
    func privateStateBoundary() {
        #expect(localDataSecurityFixture() == nil)
    }
}
#elseif canImport(XCTest)
final class LocalDataSecurityTests: XCTestCase {
    func testPrivateStateBoundary() {
        XCTAssertNil(localDataSecurityFixture())
    }
}
#endif
