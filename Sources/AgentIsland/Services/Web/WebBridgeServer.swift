// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Darwin
import Foundation

struct BrowserBridgePayload: Decodable {
    var version: Int
    var source: String
    var sessionID: String?
    var title: String?
    var phase: String
    var detail: String?
    var url: String?

    enum CodingKeys: String, CodingKey {
        case version, source, title, phase, detail, url
        case sessionID = "session_id"
    }
}

enum BrowserBridgeProtocol {
    static func accepts(version: Int) -> Bool {
        version == 1 || version == 2
    }

    static func normalized(source: String, phase: String) -> (family: String, phase: String)? {
        let sourceValue = source.lowercased()
        let family: String
        if sourceValue.contains("codex") {
            family = "codex"
        } else if sourceValue.contains("claude") {
            family = "claude"
        } else if sourceValue.contains("chatgpt") || sourceValue.contains("openai") {
            family = "chatgpt"
        } else {
            return nil
        }

        let phaseValue = phase.lowercased().replacingOccurrences(of: "_", with: "")
        switch phaseValue {
        case "working", "thinking", "queued", "done", "needsattention", "idle", "online":
            return (family, phase.lowercased())
        default:
            return nil
        }
    }

    static func fallbackSession(family: String, url: String?) -> String {
        guard let url, !url.isEmpty else { return "web-\(family)" }
        return "web-\(stableIdentifier(url))"
    }

    private static func stableIdentifier(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

/// Receives minimal status frames from the optional browser extension.
/// It binds only to loopback and requires a per-install bearer token.
final class WebBridgeServer {
    static let port: UInt16 = 27583
    static let healthID = "web-bridge"

    private let root: URL
    private let health: TransportHealthStore
    private let queue = DispatchQueue(label: "local.agent-island.web-bridge", qos: .userInitiated)
    private let onEvent: () -> Void
    private var socketFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    init(
        root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-island"),
        health: TransportHealthStore = .shared,
        onEvent: @escaping () -> Void = {}
    ) {
        self.root = root
        self.health = health
        self.onEvent = onEvent
    }

    deinit { stop() }

    var pairingToken: String {
        let url = root.appendingPathComponent("web-bridge-token")
        if let token = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), token.count >= 32 {
            return token
        }
        let token = randomToken()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? token.write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, S_IRUSR | S_IWUSR)
        return token
    }

    func start() {
        _ = pairingToken
        health.markAttempt(id: Self.healthID, name: "Browser Web Bridge", endpoint: endpoint)
        queue.async { [weak self] in self?.startOnQueue() }
    }

    func stop() {
        queue.sync {
            acceptSource?.cancel()
            acceptSource = nil
            if socketFD >= 0 { close(socketFD) }
            socketFD = -1
            health.markFailure(id: Self.healthID, name: "Browser Web Bridge", state: .disabled, endpoint: endpoint, error: "Stopped")
        }
    }

    private var endpoint: String { "http://127.0.0.1:\(Self.port)/v1/events" }

    private func startOnQueue() {
        guard socketFD < 0 else { return }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            health.markFailure(id: Self.healthID, name: "Browser Web Bridge", endpoint: endpoint, error: "socket failed")
            return
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        let currentFlags = fcntl(fd, F_GETFL, 0)
        if currentFlags >= 0 {
            _ = fcntl(fd, F_SETFL, currentFlags | O_NONBLOCK)
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(Self.port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, SOMAXCONN) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            health.markFailure(id: Self.healthID, name: "Browser Web Bridge", endpoint: endpoint, error: message)
            return
        }
        socketFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        source.setCancelHandler { close(fd) }
        acceptSource = source
        source.resume()
        health.markConnected(id: Self.healthID, name: "Browser Web Bridge", protocolVersion: "agent-island-web/v1", endpoint: endpoint)
        islandLog("web bridge started endpoint=\(endpoint)")
    }

    private func acceptClients() {
        while true {
            let client = accept(socketFD, nil, nil)
            if client < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return
            }
            queue.async { [weak self] in self?.handle(client: client) }
        }
    }

    private func handle(client: Int32) {
        defer { close(client) }
        let clientFlags = fcntl(client, F_GETFL, 0)
        if clientFlags >= 0 {
            _ = fcntl(client, F_SETFL, clientFlags & ~O_NONBLOCK)
        }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard let request = readRequest(client) else {
            writeResponse(400, "invalid request", to: client)
            return
        }
        guard request.method == "POST", request.path == "/v1/events" else {
            writeResponse(404, "not found", to: client)
            return
        }
        guard request.authorization == "Bearer \(pairingToken)" else {
            health.markFailure(id: Self.healthID, name: "Browser Web Bridge", state: .degraded, endpoint: endpoint, error: "Rejected unauthenticated browser event")
            writeResponse(401, "unauthorized", to: client)
            return
        }
        guard let payload = try? JSONDecoder().decode(BrowserBridgePayload.self, from: request.body),
              BrowserBridgeProtocol.accepts(version: payload.version),
              let normalized = BrowserBridgeProtocol.normalized(source: payload.source, phase: payload.phase) else {
            writeResponse(422, "invalid event", to: client)
            return
        }
        append(payload: payload, family: normalized.family, phase: normalized.phase)
        health.markEvent(id: Self.healthID, name: "Browser Web Bridge")
        writeResponse(202, "accepted", to: client)
        DispatchQueue.main.async { [onEvent] in onEvent() }
    }

    private func append(payload: BrowserBridgePayload, family: String, phase: String) {
        let session = payload.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = BrowserBridgeProtocol.fallbackSession(family: family, url: payload.url)
        let frame: [String: Any] = [
            "agent": family,
            "surface": "web",
            "status": phase,
            "session": (session?.isEmpty == false ? session! : fallback),
            "title": compact(payload.title, limit: 120),
            "message": compact(payload.detail, limit: 180),
            "origin": "web_bridge",
            "event": "web_status",
            "ts": Date().timeIntervalSince1970
        ]
        guard JSONSerialization.isValidJSONObject(frame),
              let data = try? JSONSerialization.data(withJSONObject: frame),
              let line = String(data: data, encoding: .utf8) else { return }
        let url = root.appendingPathComponent("events.jsonl")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((line + "\n").utf8))
        } else {
            try? Data((line + "\n").utf8).write(to: url, options: .atomic)
        }
    }

    private func readRequest(_ fd: Int32) -> (method: String, path: String, authorization: String?, body: Data)? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        var expectedBodyLength: Int?
        while data.count < 131_072 {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { return nil }
            data.append(buffer, count: count)
            guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { continue }
            let header = String(data: data[..<headerRange.lowerBound], encoding: .utf8) ?? ""
            let lines = header.components(separatedBy: "\r\n")
            guard let requestLine = lines.first?.split(separator: " "), requestLine.count >= 2 else { return nil }
            if expectedBodyLength == nil {
                expectedBodyLength = lines.dropFirst().first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") }
                    ?? 0
            }
            let bodyStart = headerRange.upperBound
            guard let expectedBodyLength, data.count >= bodyStart + expectedBodyLength else { continue }
            let authorization = lines.dropFirst().first { $0.lowercased().hasPrefix("authorization:") }
                .flatMap { $0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) }
            return (String(requestLine[0]), String(requestLine[1]), authorization, Data(data[bodyStart..<(bodyStart + expectedBodyLength)]))
        }
        return nil
    }

    private func writeResponse(_ status: Int, _ text: String, to fd: Int32) {
        let body = Data(text.utf8)
        let response = "HTTP/1.1 \(status) \(text)\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        _ = send(fd, response, response.utf8.count, 0)
        _ = body.withUnsafeBytes { send(fd, $0.baseAddress, body.count, 0) }
    }

    private func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func compact(_ value: String?, limit: Int) -> String {
        let text = value?.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(text.prefix(limit))
    }
}
