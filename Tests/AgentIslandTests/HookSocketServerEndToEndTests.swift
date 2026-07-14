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

private func hookSocketApprovalRoundTrip() -> String? {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-island-hook-\(UUID().uuidString)", isDirectory: true)
    // Unix-domain paths are capped near 104 bytes on macOS. XCTest temporary
    // roots on hosted runners can exceed that before adding the socket name.
    let socketPath = "/tmp/ai-hook-\(UUID().uuidString.prefix(8)).sock"
    defer { try? FileManager.default.removeItem(at: root) }

    let store = PendingRequestStore()
    let health = TransportHealthStore(outputURL: root.appendingPathComponent("transport.json"))
    let stateQueue = DispatchQueue(label: "local.agent-island.hook-test-state")
    let server = HookSocketServer(
        store: store,
        health: health,
        socketPath: socketPath,
        callbackQueue: stateQueue
    )
    server.start()
    guard waitUntil(timeout: 2, condition: { FileManager.default.fileExists(atPath: socketPath) }) else {
        server.stop()
        return "listener socket was not created"
    }

    let response = LockedData()
    let request = Data(#"{"source":"claude","surface":"cli","event":"PermissionRequest","session":"socket-session","request_id":"socket-request","tool":"Read","tool_input_summary":"path: README.md","response_schema":"claude_permission_request","ts":1800000000}"#.utf8)
    let client = DispatchQueue.global(qos: .userInitiated)
    client.async {
        guard let fd = connectUnixSocket(socketPath) else { return }
        defer { close(fd) }
        _ = request.withUnsafeBytes { send(fd, $0.baseAddress, request.count, 0) }
        // The production bridge half-closes after its one JSON frame. The
        // server then keeps the read side open while the approval is pending.
        _ = shutdown(fd, SHUT_WR)
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = recv(fd, &buffer, buffer.count, 0)
        if count > 0 { response.set(Data(buffer.prefix(count))) }
    }

    let pending = waitUntil(timeout: 2, condition: {
        stateQueue.sync { store.requests.first?.id == "claude::socket-request" }
    }) ? stateQueue.sync { store.requests.first } : nil
    guard let pending else {
        server.stop()
        return "pending request did not reach the store"
    }
    stateQueue.sync { store.allow(pending) }
    let completed = waitUntil(timeout: 2, condition: { !response.value.isEmpty })
    server.stop()

    guard completed,
          let rootJSON = try? JSONSerialization.jsonObject(with: response.value) as? [String: Any],
          let output = rootJSON["hookSpecificOutput"] as? [String: Any],
          let decision = output["decision"] as? [String: String] else {
        let status = stateQueue.sync { store.requests.first?.status.rawValue ?? "missing" }
        return "no socket response after allow; store status=\(status)"
    }
    guard decision["behavior"] == "allow" else { return "response did not contain allow decision" }
    guard stateQueue.sync(execute: { store.requests.first?.status == .allowed }) else {
        return "store did not retain allowed status"
    }
    return nil
}

private func hookSocketQuestionRoundTrip() -> String? {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-island-question-\(UUID().uuidString)", isDirectory: true)
    let socketPath = "/tmp/ai-question-\(UUID().uuidString.prefix(8)).sock"
    defer { try? FileManager.default.removeItem(at: root) }

    let store = PendingRequestStore()
    let health = TransportHealthStore(outputURL: root.appendingPathComponent("transport.json"))
    let stateQueue = DispatchQueue(label: "local.agent-island.question-test-state")
    let server = HookSocketServer(
        store: store,
        health: health,
        socketPath: socketPath,
        callbackQueue: stateQueue
    )
    server.start()
    guard waitUntil(timeout: 2, condition: { FileManager.default.fileExists(atPath: socketPath) }) else {
        server.stop()
        return "question listener socket was not created"
    }

    let response = LockedData()
    let request = Data(#"{"source":"claude","surface":"cli","event":"PreToolUse","session":"socket-session","request_id":"question-request","question":"Choose scope","questions":[{"id":"scope","prompt":"Choose scope","options":["Current task","All tasks"],"multiSelect":false,"isSecret":false,"allowsOther":true}],"tool_input_json":"{\"questions\":[{\"question\":\"Choose scope\"}]}","response_schema":"claude_pre_tool_ask_user_question","ts":1800000000}"#.utf8)
    DispatchQueue.global(qos: .userInitiated).async {
        guard let fd = connectUnixSocket(socketPath) else { return }
        defer { close(fd) }
        _ = request.withUnsafeBytes { send(fd, $0.baseAddress, request.count, 0) }
        _ = shutdown(fd, SHUT_WR)
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = recv(fd, &buffer, buffer.count, 0)
        if count > 0 { response.set(Data(buffer.prefix(count))) }
    }

    let pending = waitUntil(timeout: 2, condition: {
        stateQueue.sync { store.requests.first?.id == "claude::question-request" }
    }) ? stateQueue.sync { store.requests.first } : nil
    guard let pending else {
        server.stop()
        return "question request did not reach the store"
    }
    stateQueue.sync { store.answer(pending, answers: ["scope": ["Current task"]]) }
    let completed = waitUntil(timeout: 2, condition: { !response.value.isEmpty })
    server.stop()

    guard completed,
          let rootJSON = try? JSONSerialization.jsonObject(with: response.value) as? [String: Any],
          let output = rootJSON["hookSpecificOutput"] as? [String: Any],
          output["permissionDecision"] as? String == "allow",
          let updatedInput = output["updatedInput"] as? [String: Any],
          let answers = updatedInput["answers"] as? [String: String],
          answers["Choose scope"] == "Current task" else {
        return "question answer did not return the expected PreToolUse payload"
    }
    guard stateQueue.sync(execute: { store.requests.first?.status == .answered }) else {
        return "store did not retain answered status"
    }
    return nil
}

private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}

private func connectUnixSocket(_ path: String) -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
        close(fd)
        return nil
    }
    let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = CChar(bitPattern: byte) }
            buffer[bytes.count] = 0
        }
    }
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        close(fd)
        return nil
    }
    return fd
}

private final class LockedData {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Data) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}

#if canImport(Testing) && !AGENT_ISLAND_USE_XCTEST
@Suite("Hook socket approval delivery")
struct HookSocketServerEndToEndTests {
    @Test("Claude approval returns a response through the live socket")
    func approvalRoundTrip() {
        #expect(hookSocketApprovalRoundTrip() == nil)
    }

    @Test("Claude question answers return through the live socket")
    func questionRoundTrip() {
        #expect(hookSocketQuestionRoundTrip() == nil)
    }
}
#elseif canImport(XCTest)
final class HookSocketServerEndToEndTests: XCTestCase {
    func testClaudeApprovalReturnsResponseThroughLiveSocket() {
        XCTAssertNil(hookSocketApprovalRoundTrip())
    }

    func testClaudeQuestionAnswersReturnThroughLiveSocket() {
        XCTAssertNil(hookSocketQuestionRoundTrip())
    }
}
#endif
