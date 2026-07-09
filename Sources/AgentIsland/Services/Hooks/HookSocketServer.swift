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
    private let queue = DispatchQueue(label: "local.agent-island.hook-socket", qos: .userInitiated)
    private let maxPayloadSize = 1_048_576
    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var pendingConnections: [String: PendingConnection] = [:]

    init(store: PendingRequestStore) {
        self.store = store
        self.store.onDecision = { [weak self] request, decision in
            self?.respond(to: request, decision: decision)
        }
    }

    deinit {
        stop()
    }

    func start() {
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
            unlink(Self.socketPath)
        }
    }

    private func startOnQueue() {
        guard serverSocket < 0 else { return }
        do {
            let url = URL(fileURLWithPath: Self.socketPath)
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
            let pathBytes = Array(Self.socketPath.utf8)
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
            chmod(Self.socketPath, S_IRUSR | S_IWUSR)

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
            islandLog("hook socket started path=\(Self.socketPath)")
        } catch {
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

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                close(fd)
                return
            }
            let pending = self.store.upsert(socketRequest: request)
            self.queue.async {
                if pending.canRespondInline, pending.kind == .permission {
                    self.pendingConnections[pending.id] = PendingConnection(
                        fd: fd,
                        request: pending,
                        receivedAt: Date()
                    )
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

            guard let data = self.responseData(for: pending.request, decision: decision) else {
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

    private func responseData(for request: PendingRequest, decision: PendingRequestDecision) -> Data? {
        guard request.family == .claude, request.kind == .permission else { return nil }
        let behavior: String
        switch decision {
        case .allow:
            behavior = "allow"
        case .deny:
            behavior = "deny"
        case .answer:
            return nil
        }

        let payload: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": behavior
                ]
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
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
