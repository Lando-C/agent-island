// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Darwin
import Foundation

/// Persistent Codex Desktop broker client. Unlike the polling probe, this keeps
/// the JSON-RPC connection alive so server requests retain their response ID.
final class CodexBrokerClient {
    private let store: PendingRequestStore
    private let queue = DispatchQueue(label: "local.agent-island.codex-broker", qos: .userInitiated)
    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var buffer = Data()
    private var reconnectWorkItem: DispatchWorkItem?
    private var rpcIDsByPendingID: [String: Any] = [:]

    init(store: PendingRequestStore) {
        self.store = store
        store.addDecisionHandler { [weak self] request, decision in
            guard request.family == .codex,
                  request.responseSchema?.hasPrefix("codex_app_server_") == true else { return }
            self?.queue.async {
                self?.respond(to: request, decision: decision)
            }
        }
    }

    func start() {
        queue.async { [weak self] in self?.connect() }
    }

    func stop() {
        queue.sync {
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            disconnect(scheduleReconnect: false)
        }
    }

    private func connect() {
        guard fd < 0 else { return }
        let candidates = Self.discoverBrokerSockets()
        guard !candidates.isEmpty else {
            scheduleReconnect()
            return
        }
        var connection: (fd: Int32, path: String)?
        for path in candidates {
            if let socketFD = Self.connectSocket(path: path) {
                connection = (socketFD, path)
                break
            }
        }
        guard let connection else {
            scheduleReconnect()
            return
        }
        let socketFD = connection.fd
        let path = connection.path

        let flags = fcntl(socketFD, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(socketFD, F_SETFL, flags | O_NONBLOCK) }
        var noSigpipe: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
        fd = socketFD

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { close(socketFD) }
        readSource = source
        source.resume()

        send([
            "id": "agent-island-initialize",
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "Agent Island", "title": "Agent Island", "version": "0.1.0"],
                "capabilities": ["experimentalApi": true, "requestAttestation": false]
            ]
        ])
        send(["method": "initialized", "params": [:]])
        islandLog("codex broker connected path=\(path)")
    }

    private func readAvailable() {
        guard fd >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = recv(fd, &bytes, bytes.count, 0)
            if count > 0 {
                buffer.append(bytes, count: count)
                drainLines()
            } else if count == 0 {
                disconnect(scheduleReconnect: true)
                return
            } else if errno == EINTR {
                continue
            } else if errno == EWOULDBLOCK || errno == EAGAIN {
                return
            } else {
                disconnect(scheduleReconnect: true)
                return
            }
        }
    }

    private func drainLines() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            handle(json)
        }
    }

    private func handle(_ json: [String: Any]) {
        guard let method = json["method"] as? String,
              let rawID = json["id"], !(rawID is NSNull) else { return }
        let params = json["params"] as? [String: Any] ?? [:]
        let id = Self.stringify(rawID)

        let schema: String
        let event: String
        switch method {
        case "item/tool/requestUserInput":
            schema = "codex_app_server_user_input"
            event = "requestUserInput"
        case "item/commandExecution/requestApproval":
            schema = "codex_app_server_command_approval"
            event = "PermissionRequest"
        case "item/fileChange/requestApproval":
            schema = "codex_app_server_file_approval"
            event = "PermissionRequest"
        case "item/permissions/requestApproval":
            schema = "codex_app_server_permissions_approval"
            event = "PermissionRequest"
        default:
            return
        }

        let questions = Self.parseQuestions(params["questions"] as? [[String: Any]] ?? [])
        let command = (params["command"] as? [String])?.joined(separator: " ")
        let question = questions.first?.prompt
        let detail = question
            ?? (params["reason"] as? String)
            ?? command
            ?? (params["grantRoot"] as? String)
            ?? "Codex 正在等待你的决定"
        let permissionsJSON = (try? JSONSerialization.data(withJSONObject: params["permissions"] ?? [:]))
            .flatMap { String(data: $0, encoding: .utf8) }
        let request = HookSocketRequest(
            type: "codex_app_server",
            source: "codex",
            surface: "app",
            event: event,
            status: "needs_attention",
            title: nil,
            message: detail,
            session: params["threadId"] as? String,
            rawSession: nil,
            primarySession: nil,
            parentSession: nil,
            requestID: id,
            tool: method,
            toolInputSummary: command ?? detail,
            toolRisk: nil,
            toolRiskReason: nil,
            question: question,
            options: questions.first?.options,
            questions: questions,
            responseSchema: schema,
            toolInputJSON: permissionsJSON,
            requestedSchemaJSON: nil,
            ts: Date().timeIntervalSince1970
        )
        let pendingID = request.pendingID
        rpcIDsByPendingID[pendingID] = rawID
        DispatchQueue.main.async { [weak self] in
            _ = self?.store.upsert(socketRequest: request)
        }
        islandLog("codex broker request method=\(method) thread=\(request.logicalSessionID ?? "nil") id=\(id)")
    }

    private func respond(to request: PendingRequest, decision: PendingRequestDecision) {
        guard let rawID = rpcIDsByPendingID[request.id] else {
            DispatchQueue.main.async { [weak self] in
                self?.store.markFailed(id: request.id, message: "Codex 请求已失效")
            }
            return
        }
        let result: [String: Any]
        switch request.responseSchema {
        case "codex_app_server_user_input":
            guard case .answer(let answers) = decision else { return }
            result = Self.userInputResponsePayload(answers)
        case "codex_app_server_command_approval", "codex_app_server_file_approval":
            result = ["decision": Self.isAllowed(decision) ? "accept" : "decline"]
        case "codex_app_server_permissions_approval":
            let permissions = Self.jsonObject(request.toolInputJSON) ?? [:]
            result = Self.isAllowed(decision)
                ? ["permissions": permissions, "scope": "turn"]
                : ["permissions": [:], "scope": "turn"]
        default:
            return
        }
        if send(["id": rawID, "result": result]) {
            rpcIDsByPendingID.removeValue(forKey: request.id)
            islandLog("codex broker responded request=\(request.id)")
        }
    }

    @discardableResult
    private func send(_ object: [String: Any]) -> Bool {
        guard fd >= 0,
              let data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        var payload = data
        payload.append(0x0A)
        let ok = payload.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.send(fd, base.advanced(by: offset), raw.count - offset, 0)
                if count > 0 { offset += count }
                else if count < 0 && errno == EINTR { continue }
                else { return false }
            }
            return true
        }
        if !ok { disconnect(scheduleReconnect: true) }
        return ok
    }

    private func disconnect(scheduleReconnect: Bool) {
        let expiredRequestIDs = Array(rpcIDsByPendingID.keys)
        let hadReadSource = readSource != nil
        readSource?.cancel()
        readSource = nil
        if fd >= 0, !hadReadSource { close(fd) }
        fd = -1
        buffer.removeAll(keepingCapacity: true)
        rpcIDsByPendingID.removeAll()
        if !expiredRequestIDs.isEmpty {
            DispatchQueue.main.async { [weak self] in
                for id in expiredRequestIDs {
                    self?.store.markFailed(id: id, message: "Codex 连接已断开，请在原窗口处理")
                }
            }
        }
        if scheduleReconnect { self.scheduleReconnect() }
    }

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private static func parseQuestions(_ raw: [[String: Any]]) -> [PendingQuestion] {
        raw.compactMap { item in
            guard let prompt = item["question"] as? String, !prompt.isEmpty else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
            return PendingQuestion(
                id: (item["id"] as? String) ?? prompt,
                header: item["header"] as? String,
                prompt: prompt,
                options: options,
                multiSelect: item["multiSelect"] as? Bool ?? false,
                isSecret: item["isSecret"] as? Bool ?? false
            )
        }
    }

    private static func discoverBrokerSockets() -> [String] {
        let roots = [NSTemporaryDirectory(), "/tmp"]
        var candidates: [(Date, String)] = []
        for root in Set(roots) {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasPrefix("cxc-") {
                let path = URL(fileURLWithPath: root).appendingPathComponent(entry).appendingPathComponent("broker.sock").path
                guard FileManager.default.fileExists(atPath: path) else { continue }
                let date = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
                candidates.append((date, path))
            }
        }
        return candidates.sorted { $0.0 > $1.0 }.map(\.1)
    }

    private static func connectSocket(path: String) -> Int32? {
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(socketFD)
            return nil
        }
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { target in
                for (index, byte) in bytes.enumerated() { target[index] = CChar(bitPattern: byte) }
                target[bytes.count] = 0
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(socketFD)
            return nil
        }
        return socketFD
    }

    private static func stringify(_ value: Any) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return String(describing: value)
    }

    static func userInputResponsePayload(_ answers: [String: [String]]) -> [String: Any] {
        ["answers": answers.reduce(into: [String: Any]()) { output, entry in
            output[entry.key] = ["answers": entry.value]
        }]
    }

    private static func isAllowed(_ decision: PendingRequestDecision) -> Bool {
        if case .allow = decision { return true }
        return false
    }

    private static func jsonObject(_ text: String?) -> [String: Any]? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
