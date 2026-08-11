// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Darwin
import Foundation
import Security

struct BrowserBridgePayload: Decodable {
    var version: Int
    var source: String
    var sessionID: String?
    var title: String?
    var phase: String
    var detail: String?
    var url: String?
    var detectorVersion: String?
    var selectorProfile: String?
    var selectorState: String?

    enum CodingKeys: String, CodingKey {
        case version, source, title, phase, detail, url
        case sessionID = "session_id"
        case detectorVersion = "detector_version"
        case selectorProfile = "selector_profile"
        case selectorState = "selector_state"
    }
}

enum BrowserBridgeDisposition: Equatable {
    case accepted(family: String, phase: String)
    case degraded(family: String?, reason: String)
    case rejected(reason: String)
}

enum BrowserBridgeProtocol {
    static let currentVersion = 3
    static let detectorVersion = "0.3.0"
    static let selectorProfiles = [
        "chatgpt": "chatgpt-web-2026-07",
        "claude": "claude-web-2026-07",
        "codex": "codex-web-2026-07"
    ]

    static func accepts(version: Int) -> Bool {
        (1...currentVersion).contains(version)
    }

    static func normalized(source: String, phase: String) -> (family: String, phase: String)? {
        guard let family = family(source: source) else { return nil }

        let phaseValue = phase.lowercased().replacingOccurrences(of: "_", with: "")
        switch phaseValue {
        case "working", "thinking", "queued", "done", "needsattention", "idle", "online":
            return (family, phase.lowercased())
        default:
            return nil
        }
    }

    static func evaluate(_ payload: BrowserBridgePayload) -> BrowserBridgeDisposition {
        guard accepts(version: payload.version) else {
            return .degraded(
                family: family(source: payload.source),
                reason: "Unsupported Browser Bridge protocol v\(payload.version); expected v1-v\(currentVersion)"
            )
        }
        guard let normalized = normalized(source: payload.source, phase: payload.phase) else {
            return .rejected(reason: "Unsupported Browser Bridge source or phase")
        }

        // v1/v2 remain decodable so Diagnostics can explain the upgrade. They
        // cannot prove which provider-specific selector contract produced the
        // status, so they must not update session truth.
        guard payload.version >= 3 else {
            return .degraded(
                family: normalized.family,
                reason: "Browser Bridge v\(payload.version) lacks selector provenance; update the extension to v\(currentVersion)"
            )
        }
        guard payload.detectorVersion == detectorVersion else {
            return .degraded(
                family: normalized.family,
                reason: "Browser detector version mismatch; expected \(detectorVersion)"
            )
        }
        guard let expectedProfile = selectorProfiles[normalized.family],
              payload.selectorProfile == expectedProfile else {
            return .degraded(
                family: normalized.family,
                reason: "Unrecognized \(normalized.family) selector profile"
            )
        }
        guard payload.selectorState == "verified" else {
            return .degraded(
                family: normalized.family,
                reason: "Provider page no longer matches selector profile \(expectedProfile)"
            )
        }
        return .accepted(family: normalized.family, phase: normalized.phase)
    }

    static func fallbackSession(family: String, url: String?) -> String {
        guard let url, !url.isEmpty else { return "web-\(family)" }
        return "web-\(stableIdentifier(url))"
    }

    private static func family(source: String) -> String? {
        let sourceValue = source.lowercased()
        if sourceValue.contains("codex") {
            return "codex"
        } else if sourceValue.contains("claude") {
            return "claude"
        } else if sourceValue.contains("chatgpt") || sourceValue.contains("openai") {
            return "chatgpt"
        }
        return nil
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

struct WebBridgeHTTPRequest {
    var method: String
    var path: String
    var authorization: String?
    var body: Data
}

enum WebBridgeHTTPRequestParseResult {
    case incomplete
    case rejected
    case complete(WebBridgeHTTPRequest)
}

enum WebBridgeHTTPRequestParser {
    static let maximumHeaderSize = 16_384
    static let maximumBodySize = 65_536
    static let maximumRequestSize = maximumHeaderSize + maximumBodySize + 4

    static func parse(_ data: Data) -> WebBridgeHTTPRequestParseResult {
        guard data.count <= maximumRequestSize else { return .rejected }
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maximumHeaderSize ? .rejected : .incomplete
        }
        guard headerRange.lowerBound <= maximumHeaderSize,
              let header = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return .rejected
        }

        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first?.split(separator: " "),
              requestLine.count == 3,
              requestLine[2] == "HTTP/1.1" || requestLine[2] == "HTTP/1.0" else {
            return .rejected
        }

        let contentLengthHeaders = lines.dropFirst().filter {
            $0.lowercased().hasPrefix("content-length:")
        }
        guard contentLengthHeaders.count == 1,
              let rawLength = contentLengthHeaders[0]
                .split(separator: ":", maxSplits: 1)
                .last?
                .trimmingCharacters(in: .whitespaces),
              let contentLength = Int(rawLength),
              (0...maximumBodySize).contains(contentLength) else {
            return .rejected
        }

        let bodyStart = headerRange.upperBound
        guard bodyStart <= data.count,
              contentLength <= maximumRequestSize - bodyStart else {
            return .rejected
        }
        guard data.count - bodyStart >= contentLength else { return .incomplete }
        guard data.count - bodyStart == contentLength else { return .rejected }

        let transferEncodingHeaders = lines.dropFirst().filter {
            $0.lowercased().hasPrefix("transfer-encoding:")
        }
        guard transferEncodingHeaders.isEmpty else { return .rejected }

        let authorizationHeaders = lines.dropFirst().filter {
            $0.lowercased().hasPrefix("authorization:")
        }
        guard authorizationHeaders.count <= 1 else { return .rejected }
        let authorization = authorizationHeaders.first?
            .split(separator: ":", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespaces)

        return .complete(WebBridgeHTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            authorization: authorization,
            body: Data(data[bodyStart..<(bodyStart + contentLength)])
        ))
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
    private let tokenLock = NSLock()
    private let onEvent: () -> Void
    private var socketFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var cachedPairingToken: String?

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

    var pairingToken: String? {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        if let cachedPairingToken { return cachedPairingToken }

        let url = root.appendingPathComponent("web-bridge-token")
        do {
            try LocalDataSecurity.ensurePrivateDirectory(at: root)
            if let token = try? LocalDataSecurity.readPrivateString(url, maximumBytes: 256)
                .trimmingCharacters(in: .whitespacesAndNewlines), Self.isValidToken(token) {
                cachedPairingToken = token
                return token
            }

            let token = try randomToken()
            try LocalDataSecurity.writePrivate(token, to: url)
            cachedPairingToken = token
            return token
        } catch {
            islandLog("web bridge token unavailable error=\(error.localizedDescription)")
            return nil
        }
    }

    func start() {
        guard pairingToken != nil else {
            health.markFailure(
                id: Self.healthID,
                name: "Browser Web Bridge",
                endpoint: endpoint,
                error: "Could not create an owner-only pairing token"
            )
            return
        }
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
        health.markConnected(
            id: Self.healthID,
            name: "Browser Web Bridge",
            protocolVersion: "agent-island-web/v1-v\(BrowserBridgeProtocol.currentVersion)",
            endpoint: endpoint
        )
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
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigpipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
        guard let request = readRequest(client) else {
            writeResponse(400, "invalid request", to: client)
            return
        }
        guard request.method == "POST", request.path == "/v1/events" else {
            writeResponse(404, "not found", to: client)
            return
        }
        guard let pairingToken,
              Self.constantTimeEqual(request.authorization, "Bearer \(pairingToken)") else {
            health.markFailure(id: Self.healthID, name: "Browser Web Bridge", state: .degraded, endpoint: endpoint, error: "Rejected unauthenticated browser event")
            writeResponse(401, "unauthorized", to: client)
            return
        }
        guard let payload = try? JSONDecoder().decode(BrowserBridgePayload.self, from: request.body) else {
            health.markFailure(
                id: Self.healthID,
                name: "Browser Web Bridge",
                state: .degraded,
                endpoint: endpoint,
                error: "Rejected malformed Browser Bridge event"
            )
            writeResponse(422, "invalid event", to: client)
            return
        }
        switch BrowserBridgeProtocol.evaluate(payload) {
        case let .accepted(family, phase):
            append(payload: payload, family: family, phase: phase)
            health.markConnected(
                id: Self.healthID,
                name: "Browser Web Bridge",
                protocolVersion: protocolLabel(payload),
                endpoint: endpoint,
                event: true
            )
            writeResponse(202, "accepted", to: client)
            DispatchQueue.main.async { [onEvent] in onEvent() }
        case let .degraded(_, reason):
            // A selector/profile mismatch is transport evidence, not session
            // evidence. Keep the last trustworthy event instead of converting
            // "unknown" into a false idle or approval state.
            health.markFailure(
                id: Self.healthID,
                name: "Browser Web Bridge",
                state: .degraded,
                endpoint: endpoint,
                error: reason
            )
            writeResponse(202, "degraded", to: client)
        case let .rejected(reason):
            health.markFailure(
                id: Self.healthID,
                name: "Browser Web Bridge",
                state: .degraded,
                endpoint: endpoint,
                error: reason
            )
            writeResponse(422, "invalid event", to: client)
        }
    }

    private func protocolLabel(_ payload: BrowserBridgePayload) -> String {
        var values = ["agent-island-web/v\(payload.version)"]
        if let detectorVersion = payload.detectorVersion {
            values.append("detector/\(detectorVersion)")
        }
        if let selectorProfile = payload.selectorProfile {
            values.append(selectorProfile)
        }
        return values.joined(separator: " · ")
    }

    private func append(payload: BrowserBridgePayload, family: String, phase: String) {
        let session = compact(
            payload.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
            limit: 200
        )
        let fallback = BrowserBridgeProtocol.fallbackSession(family: family, url: payload.url)
        let frame: [String: Any] = [
            "agent": family,
            "surface": "web",
            "status": phase,
            "session": session.isEmpty ? fallback : session,
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
        try? LocalDataSecurity.appendPrivate(Data((line + "\n").utf8), to: url)
    }

    private func readRequest(_ fd: Int32) -> WebBridgeHTTPRequest? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count <= WebBridgeHTTPRequestParser.maximumRequestSize {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { return nil }
            data.append(buffer, count: count)
            switch WebBridgeHTTPRequestParser.parse(data) {
            case .incomplete:
                continue
            case .rejected:
                return nil
            case .complete(let request):
                return request
            }
        }
        return nil
    }

    private func writeResponse(_ status: Int, _ text: String, to fd: Int32) {
        let body = Data(text.utf8)
        let response = "HTTP/1.1 \(status) \(text)\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        sendAll(Data(response.utf8), to: fd)
        sendAll(body, to: fd)
    }

    private func sendAll(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = send(fd, baseAddress.advanced(by: offset), bytes.count - offset, 0)
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }

    private func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ left: String?, _ right: String) -> Bool {
        guard let leftData = left?.data(using: .utf8),
              let rightData = right.data(using: .utf8),
              leftData.count == rightData.count else { return false }
        return zip(leftData, rightData).reduce(UInt8(0)) { difference, pair in
            difference | (pair.0 ^ pair.1)
        } == 0
    }

    private static func isValidToken(_ token: String) -> Bool {
        token.count == 64 && token.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
        }
    }

    private func compact(_ value: String?, limit: Int) -> String {
        let text = value?.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(text.prefix(limit))
    }
}
