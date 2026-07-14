// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Darwin
import Foundation

final class HookSocketServer {
    static let socketPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".agent-island/hook.sock")
        .path

    private struct PendingConnection {
        var fd: Int32
        var request: PendingRequest
        var receivedAt: Date
    }

    private let store: PendingRequestStore
    private let conversations: ConversationStore
    private let health: TransportHealthStore
    private let socketPath: String
    private let callbackQueue: DispatchQueue
    private let queue = DispatchQueue(label: "local.agent-island.hook-socket", qos: .userInitiated)
    private let maxPayloadSize = 1_048_576
    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var pendingConnections: [String: PendingConnection] = [:]

    init(
        store: PendingRequestStore,
        conversations: ConversationStore = .shared,
        health: TransportHealthStore = .shared,
        socketPath: String = HookSocketServer.socketPath,
        callbackQueue: DispatchQueue = .main
    ) {
        self.store = store
        self.conversations = conversations
        self.health = health
        self.socketPath = socketPath
        self.callbackQueue = callbackQueue
        self.store.addDecisionHandler { [weak self] request, decision in
            guard request.family == .claude,
                  request.responseSchema?.hasPrefix("claude_") == true else { return }
            self?.respond(to: request, decision: decision)
        }
    }

    deinit {
        stop()
    }

    func start() {
        health.markAttempt(
            id: TransportHealthStore.hookSocketID,
            name: "Claude Hook Socket",
            endpoint: socketPath
        )
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.sync {
            if let acceptSource {
                acceptSource.cancel()
                self.acceptSource = nil
            } else if serverSocket >= 0 {
                close(serverSocket)
            }
            serverSocket = -1
            for pending in pendingConnections.values {
                close(pending.fd)
            }
            pendingConnections.removeAll()
            unlink(socketPath)
            health.markFailure(
                id: TransportHealthStore.hookSocketID,
                name: "Claude Hook Socket",
                state: .disabled,
                endpoint: socketPath,
                error: "Stopped"
            )
        }
    }

    private func startOnQueue() {
        guard serverSocket < 0 else { return }
        do {
            let url = URL(fileURLWithPath: socketPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try removeStaleSocket(at: url)

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

            var flags = fcntl(fd, F_GETFL, 0)
            if flags >= 0 {
                flags = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(socketPath.utf8)
            guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
                close(fd)
                throw POSIXError(.ENAMETOOLONG)
            }
            let sunPathCapacity = MemoryLayout.size(ofValue: address.sun_path)
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { buffer in
                    for (index, byte) in pathBytes.enumerated() {
                        buffer[index] = CChar(bitPattern: byte)
                    }
                    buffer[pathBytes.count] = 0
                }
            }

            let previousUmask = umask(mode_t(S_IRWXG | S_IRWXO))
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            let bindErrno = errno
            umask(previousUmask)

            guard bindResult == 0 else {
                close(fd)
                throw POSIXError(.init(rawValue: bindErrno) ?? .EIO)
            }
            chmod(socketPath, S_IRUSR | S_IWUSR)

            guard listen(fd, SOMAXCONN) == 0 else {
                let error = POSIXError(.init(rawValue: errno) ?? .EIO)
                close(fd)
                throw error
            }

            serverSocket = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptConnections()
            }
            source.setCancelHandler {
                close(fd)
            }
            acceptSource = source
            source.resume()
            health.markConnected(
                id: TransportHealthStore.hookSocketID,
                name: "Claude Hook Socket",
                protocolVersion: "hook-json/v1",
                endpoint: socketPath
            )
            islandLog("hook socket started path=\(socketPath)")
        } catch {
            health.markFailure(
                id: TransportHealthStore.hookSocketID,
                name: "Claude Hook Socket",
                endpoint: socketPath,
                error: error.localizedDescription
            )
            islandLog("hook socket start failed error=\(error.localizedDescription)")
        }
    }

    private func removeStaleSocket(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var statBuffer = stat()
        guard lstat(url.path, &statBuffer) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard (statBuffer.st_mode & S_IFMT) == S_IFSOCK else {
            throw POSIXError(.EEXIST)
        }
        try FileManager.default.removeItem(at: url)
    }

    private func acceptConnections() {
        while true {
            let clientFD = accept(serverSocket, nil, nil)
            if clientFD < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN { return }
                islandLog("hook socket accept failed errno=\(errno)")
                return
            }
            configureClient(clientFD)
            queue.async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private func configureClient(_ fd: Int32) {
        var timeout = timeval(tv_sec: 86_400, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
    }

    private func handleClient(_ fd: Int32) {
        guard let data = readPayload(from: fd),
              let request = try? JSONDecoder().decode(HookSocketRequest.self, from: data) else {
            sendFallbackAndClose(fd)
            return
        }

        conversations.ingestHookRequest(request)
        health.markEvent(id: TransportHealthStore.hookSocketID, name: "Claude Hook Socket")

        callbackQueue.async { [weak self] in
            guard let self else {
                close(fd)
                return
            }
            let pending = self.store.upsert(socketRequest: request)
            self.queue.async {
                self.prunePendingConnections(now: Date())
                if pending.canRespondInline {
                    let next = PendingConnection(
                        fd: fd,
                        request: pending,
                        receivedAt: Date()
                    )
                    if let existing = self.pendingConnections[pending.id],
                       Date().timeIntervalSince(existing.receivedAt) < 5 {
                        self.sendFallbackAndClose(fd)
                        islandLog("hook socket ignored simultaneous duplicate id=\(pending.id)")
                        return
                    }
                    if let stale = self.pendingConnections.updateValue(next, forKey: pending.id) {
                        self.sendFallbackAndClose(stale.fd)
                        islandLog("hook socket replaced stale duplicate id=\(pending.id)")
                    }
                    self.queue.asyncAfter(deadline: .now() + 30 * 60) { [weak self] in
                        self?.expireConnection(id: pending.id, fd: fd)
                    }
                    islandLog("hook socket pending id=\(pending.id) session=\(pending.sessionID ?? "nil")")
                } else {
                    self.sendFallbackAndClose(fd)
                    islandLog("hook socket observed unsupported request id=\(pending.id)")
                }
            }
        }
    }

    private func readPayload(from fd: Int32) -> Data? {
        var payload = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count > 0 {
                payload.append(buffer, count: count)
                if payload.count > maxPayloadSize {
                    close(fd)
                    return nil
                }
            } else if count == 0 {
                return payload.isEmpty ? nil : payload
            } else if errno == EINTR {
                continue
            } else {
                close(fd)
                return nil
            }
        }
    }

    private func respond(to request: PendingRequest, decision: PendingRequestDecision) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let pending = self.pendingConnections.removeValue(forKey: request.id) else {
                DispatchQueue.main.async {
                    self.store.markFailed(id: request.id, message: "请求已不在等待中")
                }
                return
            }

            guard let data = Self.responseData(for: pending.request, decision: decision) else {
                self.sendFallbackAndClose(pending.fd)
                DispatchQueue.main.async {
                    self.store.markFailed(id: request.id, message: "暂不支持该请求类型")
                }
                return
            }

            let ok = Self.sendAll(data, to: pending.fd)
            close(pending.fd)
            if !ok {
                DispatchQueue.main.async {
                    self.store.markFailed(id: request.id, message: "响应写入失败")
                }
            }
            islandLog("hook socket responded id=\(request.id) ok=\(ok)")
        }
    }

    static func responseData(for request: PendingRequest, decision: PendingRequestDecision) -> Data? {
        guard request.family == .claude else { return nil }
        let payload: [String: Any]?
        switch request.responseSchema {
        case "claude_permission_request":
            let behavior: String
            switch decision {
            case .allow: behavior = "allow"
            case .deny: behavior = "deny"
            case .answer: return nil
            }
            payload = [
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": ["behavior": behavior]
                ]
            ]

        case "claude_pre_tool_ask_user_question":
            switch decision {
            case .deny:
                payload = [
                    "hookSpecificOutput": [
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": "User declined from Agent Island"
                    ]
                ]
            case .answer(let answers):
                guard var updatedInput = Self.jsonObject(request.toolInputJSON) else { return nil }
                var mappedAnswers: [String: Any] = [:]
                for question in request.questions {
                    guard let values = answers[question.id], !values.isEmpty else { continue }
                    mappedAnswers[question.prompt] = values.joined(separator: ", ")
                }
                if mappedAnswers.isEmpty, let values = answers.values.first {
                    let prompt = request.question ?? request.questions.first?.prompt ?? "Answer"
                    mappedAnswers[prompt] = values.joined(separator: ", ")
                }
                updatedInput["answers"] = mappedAnswers
                payload = [
                    "hookSpecificOutput": [
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "allow",
                        "updatedInput": updatedInput
                    ]
                ]
            case .allow:
                return nil
            }

        case "claude_elicitation":
            switch decision {
            case .deny:
                payload = ["hookSpecificOutput": ["hookEventName": "Elicitation", "action": "decline"]]
            case .answer(let answers):
                let content = answers.reduce(into: [String: Any]()) { result, entry in
                    result[entry.key] = entry.value.count == 1 ? entry.value[0] : entry.value
                }
                payload = [
                    "hookSpecificOutput": [
                        "hookEventName": "Elicitation",
                        "action": "accept",
                        "content": content
                    ]
                ]
            case .allow:
                payload = ["hookSpecificOutput": ["hookEventName": "Elicitation", "action": "accept", "content": [:]]]
            }

        default:
            return nil
        }
        guard let payload else { return nil }
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    private static func jsonObject(_ text: String?) -> [String: Any]? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func prunePendingConnections(now: Date) {
        let expired = pendingConnections.filter { now.timeIntervalSince($0.value.receivedAt) > 30 * 60 }
        guard !expired.isEmpty else { return }
        for (id, pending) in expired {
            pendingConnections.removeValue(forKey: id)
            sendFallbackAndClose(pending.fd)
            DispatchQueue.main.async { [weak self] in
                self?.store.markFailed(id: id, message: "请求等待超时，请在原窗口处理")
            }
        }
    }

    private func expireConnection(id: String, fd: Int32) {
        guard let pending = pendingConnections[id], pending.fd == fd else { return }
        pendingConnections.removeValue(forKey: id)
        sendFallbackAndClose(fd)
        DispatchQueue.main.async { [weak self] in
            self?.store.markFailed(id: id, message: "请求等待超时，请在原窗口处理")
        }
    }

    private func sendFallbackAndClose(_ fd: Int32) {
        _ = Self.sendAll(Data("{}".utf8), to: fd)
        close(fd)
    }

    private static func sendAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            var offset = 0
            while offset < rawBuffer.count {
                let sent = send(fd, baseAddress.advanced(by: offset), rawBuffer.count - offset, 0)
                if sent > 0 {
                    offset += sent
                } else if sent < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }
}
