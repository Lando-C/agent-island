// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Testing)
import Testing
@testable import AgentIsland

@Suite("Claude App session index")
struct ClaudeAppSessionIndexTests {
    @Test("Nested metadata resolves CLI session and prefers newest duplicate")
    func nestedMetadataResolvesNewestDuplicate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let older = root.appendingPathComponent("account/project/older.json")
        let newer = root.appendingPathComponent("account/project/newer.json")
        try FileManager.default.createDirectory(at: older.deletingLastPathComponent(), withIntermediateDirectories: true)

        let sessionID = "70266e98-3300-4871-8ec4-8edba1ee8a24"
        try metadata(sessionID: sessionID, title: "Old", activity: 100).write(to: older)
        try metadata(sessionID: sessionID, title: "New", activity: 200).write(to: newer)

        let result = ClaudeAppSessionIndex.load(roots: [root], matching: [sessionID])
        #expect(result[sessionID]?.title == "New")
        #expect(result[sessionID]?.sessionId == "local_new")
    }

    @Test("Original App session wins over resume-import duplicate")
    func originalSessionWinsOverResumeImport() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("account/project", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let sessionID = "70266e98-3300-4871-8ec4-8edba1ee8a24"
        let original: [String: Any] = [
            "sessionId": "local_6564d6f2-43c6-4c04-8739-0882b4728a07",
            "cliSessionId": sessionID,
            "cwd": "/tmp/project",
            "title": "New session",
            "lastActivityAt": 100
        ]
        let imported: [String: Any] = [
            "sessionId": "local_\(sessionID)",
            "cliSessionId": sessionID,
            "cwd": "/tmp/project",
            "lastActivityAt": 1_000
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: folder.appendingPathComponent("original.json"))
        try JSONSerialization.data(withJSONObject: imported).write(to: folder.appendingPathComponent("imported.json"))

        let result = ClaudeAppSessionIndex.load(roots: [root], matching: [sessionID])
        #expect(result[sessionID]?.sessionId == "local_6564d6f2-43c6-4c04-8739-0882b4728a07")
    }

    @Test("Generic title includes workspace and short identity")
    func genericTitleIncludesWorkspaceAndShortIdentity() {
        let info = ClaudeAppSessionInfo(
            sessionId: "local_1",
            cliSessionId: "70266e98-3300-4871-8ec4-8edba1ee8a24",
            cwd: "/Users/example/FDA2.0",
            title: "New session",
            lastFocusedAt: nil,
            lastActivityAt: nil
        )

        #expect(ClaudeAppSessionIndex.displayTitle(for: info) == "FDA2.0 · New session · 70266e98")
    }

    private func metadata(sessionID: String, title: String, activity: Double) -> Data {
        let json: [String: Any] = [
            "sessionId": "local_\(title.lowercased())",
            "cliSessionId": sessionID,
            "cwd": "/tmp/project",
            "title": title,
            "lastActivityAt": activity
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }
}
#endif
