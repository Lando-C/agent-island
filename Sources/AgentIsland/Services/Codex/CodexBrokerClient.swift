// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Darwin
import Foundation

/// The single long-lived JSON-RPC transport for Codex Desktop. It handles both
/// interactive server requests and thread/list/read state on one initialized
/// connection, so status and approvals cannot disagree about the active broker.
final class CodexBrokerClient {
    private typealias RPCCompletion = (Result<Any, Error>) -> Void

    private let store: PendingRequestStore
    private let conversations: ConversationStore
    private let health: TransportHealthStore
    private let queue = DispatchQueue(label: "local.agent-island.codex-broker", qos: .userInitiated)
    private let cacheLock = NSLock()
    private var fd: Int32 = -1
    private var endpoint: String?
    private var readSource: DispatchSourceRead?
    private var refreshTimer: DispatchSourceTimer?
    private var buffer = Data()
    private var reconnectWorkItem: DispatchWorkItem?
    private var rpcIDsByPendingID: [String: Any] = [:]
    private var rpcCompletions: [String: RPCCompletion] = [:]
    private var nextRPCID = 1
    private var cachedThreads: [CodexBrokerThread] = []
    private var isRefreshingThreads = false

    init(
        store: PendingRequestStore,
        conversations: ConversationStore = .shared,
        health: TransportHealthStore = .shared
    ) {
        self.store = store
        self.conversations = conversations
        self.health = health
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
            disconnect(scheduleReconnect: false, reason: "Stopped")
            health.markFailure(
                id: TransportHealthStore.codexBrokerID,
                name: "Codex App Server",
                state: .disabled,
                endpoint: endpoint,
                error: "Stopped"
            )
        }
    }

    func latestThreadsSnapshot() -> [CodexBrokerThread] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedThreads
    }

    func refreshThreads() {
        queue.async { [weak self] in self?.refreshThreadsOnQueue() }
    }

    private func connect() {
        guard fd < 0 else { return }
        let candidates = Self.discoverBrokerSockets()
        guard !candidates.isEmpty else {
            health.markFailure(
                id: TransportHealthStore.codexBrokerID,
                name: "Codex App Server",
                state: .unavailable,
                error: "No Codex broker socket found"
            )
            scheduleReconnect()
            return
        }

        var connection: (fd: Int32, path: String)?
        for path in candidates {
            health.markAttempt(id: TransportHealthStore.codexBrokerID, name: "Codex App Server", endpoint: path)
            if let socketFD = Self.connectSocket(path: path) {
                connection = (socketFD, path)
                break
            }
        }
        guard let connection else {
            health.markFailure(
                id: TransportHealthStore.codexBrokerID,
                name: "Codex App Server",
                state: .unavailable,
                endpoint: candidates.first,
                error: "Broker sockets exist but none accepted a connection"
            )
            scheduleReconnect()
            return
        }

        let flags = fcntl(connection.fd, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(connection.fd, F_SETFL, flags | O_NONBLOCK) }
        var noSigpipe: Int32 = 1
        setsockopt(connection.fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
        fd = connection.fd
        endpoint = connection.path

        let source = DispatchSource.makeReadSource(fileDescriptor: connection.fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { close(connection.fd) }
        readSource = source
        source.resume()

        request(
            method: "initialize",
            params: [
                "clientInfo": ["name": "Agent Island", "title": "Agent Island", "version": "0.2.0"],
                "capabilities": ["experimentalApi": true, "requestAttestation": false]
            ],
            timeout: 5
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                let version = Self.protocolVersion(from: value) ?? "codex-app-server/jsonrpc"
                self.health.markConnected(
                    id: TransportHealthStore.codexBrokerID,
                    name: "Codex App Server",
                    protocolVersion: version,
                    endpoint: self.endpoint
                )
                _ = self.send(["method": "initialized", "params": [:]])
                self.startRefreshTimer()
                self.refreshThreadsOnQueue()
                islandLog("codex broker connected path=\(self.endpoint ?? "unknown") protocol=\(version)")
            case .failure(let error):
                self.disconnect(scheduleReconnect: true, reason: "Initialize failed: \(error.localizedDescription)")
            }
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 8, repeating: 8)
        timer.setEventHandler { [weak self] in self?.refreshThreadsOnQueue() }
        refreshTimer = timer
        timer.resume()
    }

    private func refreshThreadsOnQueue() {
        guard fd >= 0, !isRefreshingThreads else { return }
        isRefreshingThreads = true
        request(
            method: "thread/list",
            params: ["archived": false, "limit": 80, "sortKey": "updated_at"],
            timeout: 5
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                let root = value as? [String: Any] ?? [:]
                let data = root["data"] as? [[String: Any]] ?? []
                let threads = data.map(Self.compactThread)
                self.replaceCachedThreads(threads)
                self.health.markConnected(
                    id: TransportHealthStore.codexBrokerID,
                    name: "Codex App Server",
                    endpoint: self.endpoint,
                    event: true
                )
                self.readThreadDetailsSequentially(threads, index: 0, remaining: 8)
            case .failure(let error):
                self.isRefreshingThreads = false
                self.health.markFailure(
                    id: TransportHealthStore.codexBrokerID,
                    name: "Codex App Server",
                    state: .degraded,
                    endpoint: self.endpoint,
                    error: "thread/list: \(error.localizedDescription)"
                )
            }
        }
    }

    private func readThreadDetailsSequentially(
        _ threads: [CodexBrokerThread],
        index: Int,
        remaining: Int
    ) {
        guard index < threads.count, remaining > 0 else {
            isRefreshingThreads = false
            return
        }
        let thread = threads[index]
        guard let threadID = thread.id, !threadID.isEmpty, !Self.isAuxiliary(thread) else {
            readThreadDetailsSequentially(threads, index: index + 1, remaining: remaining)
            return
        }

        request(
            method: "thread/read",
            params: ["threadId": threadID, "includeTurns": true],
            timeout: 5
        ) { [weak self] result in
            guard let self else { return }
            var nextThreads = threads
            switch result {
            case .success(let value):
                let root = value as? [String: Any] ?? [:]
                let rawThread = root["thread"] as? [String: Any] ?? root
                if !rawThread.isEmpty {
                    self.conversations.ingestCodexThread(rawThread)
                    nextThreads[index] = Self.merge(base: thread, detail: Self.compactThread(rawThread))
                    self.replaceCachedThreads(nextThreads)
                }
            case .failure(let error):
                nextThreads[index].readError = error.localizedDescription
                self.replaceCachedThreads(nextThreads)
            }
            self.readThreadDetailsSequentially(nextThreads, index: index + 1, remaining: remaining - 1)
        }
    }

    private func replaceCachedThreads(_ threads: [CodexBrokerThread]) {
        cacheLock.lock()
        cachedThreads = threads
        cacheLock.unlock()
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
                disconnect(scheduleReconnect: true, reason: "Connection closed by Codex")
                return
            } else if errno == EINTR {
                continue
            } else if errno == EWOULDBLOCK || errno == EAGAIN {
                return
            } else {
                disconnect(scheduleReconnect: true, reason: String(cString: strerror(errno)))
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
        if let method = json["method"] as? String {
            health.markEvent(id: TransportHealthStore.codexBrokerID, name: "Codex App Server")
            if let rawID = json["id"], !(rawID is NSNull) {
                handleServerRequest(method: method, rawID: rawID, params: json["params"] as? [String: Any] ?? [:])
            } else if method.hasPrefix("thread/") || method.hasPrefix("turn/") || method.hasPrefix("item/") {
                queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.refreshThreadsOnQueue() }
            }
            return
        }

        guard let rawID = json["id"], !(rawID is NSNull) else { return }
        let id = Self.stringify(rawID)
        guard let completion = rpcCompletions.removeValue(forKey: id) else { return }
        if let error = json["error"] as? [String: Any] {
            completion(.failure(Self.rpcError(error)))
        } else {
            completion(.success(json["result"] ?? [:]))
        }
    }

    private func handleServerRequest(method: String, rawID: Any, params: [String: Any]) {
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

        let id = Self.stringify(rawID)
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
        rpcIDsByPendingID[request.pendingID] = rawID
        conversations.ingestHookRequest(request)
        DispatchQueue.main.async { [weak self] in
            _ = self?.store.upsert(socketRequest: request)
        }
        islandLog("codex broker request method=\(method) thread=\(request.logicalSessionID ?? "nil") id=\(id)")
    }

    private func request(
        method: String,
        params: [String: Any],
        timeout: TimeInterval,
        completion: @escaping RPCCompletion
    ) {
        let id = "agent-island-\(nextRPCID)"
        nextRPCID += 1
        rpcCompletions[id] = completion
        guard send(["id": id, "method": method, "params": params]) else {
            if let unresolved = rpcCompletions.removeValue(forKey: id) {
                unresolved(.failure(Self.error("Unable to send \(method)")))
            }
            return
        }
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, let completion = self.rpcCompletions.removeValue(forKey: id) else { return }
            completion(.failure(Self.error("Timeout waiting for \(method)")))
        }
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
        if !ok { disconnect(scheduleReconnect: true, reason: "Socket write failed") }
        return ok
    }

    private func disconnect(scheduleReconnect: Bool, reason: String) {
        let expiredRequestIDs = Array(rpcIDsByPendingID.keys)
        let completions = rpcCompletions.values
        rpcCompletions.removeAll()
        refreshTimer?.cancel()
        refreshTimer = nil
        isRefreshingThreads = false
        let hadReadSource = readSource != nil
        readSource?.cancel()
        readSource = nil
        if fd >= 0, !hadReadSource { close(fd) }
        fd = -1
        buffer.removeAll(keepingCapacity: true)
        rpcIDsByPendingID.removeAll()
        let error = Self.error(reason)
        for completion in completions { completion(.failure(error)) }
        if !expiredRequestIDs.isEmpty {
            DispatchQueue.main.async { [weak self] in
                for id in expiredRequestIDs {
                    self?.store.markFailed(id: id, message: "Codex 连接已断开，请在原窗口处理")
                }
            }
        }
        health.markFailure(
            id: TransportHealthStore.codexBrokerID,
            name: "Codex App Server",
            state: scheduleReconnect ? .failed : .disabled,
            endpoint: endpoint,
            error: reason
        )
        if scheduleReconnect { self.scheduleReconnect() }
    }

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private static func compactThread(_ raw: [String: Any]) -> CodexBrokerThread {
        let status = raw["status"] as? [String: Any] ?? [:]
        var thread = CodexBrokerThread(
            id: raw["id"] as? String,
            sessionId: raw["sessionId"] as? String,
            name: raw["name"] as? String,
            preview: raw["preview"] as? String,
            cwd: raw["cwd"] as? String,
            path: raw["path"] as? String,
            source: raw["source"] as? String ?? raw["threadSource"] as? String,
            statusType: status["type"] as? String,
            updatedAt: number(raw["updatedAt"]),
            createdAt: number(raw["createdAt"]),
            approvalMode: raw["approvalMode"] as? String ?? raw["approval_mode"] as? String,
            turnCount: nil,
            lastTurnId: nil,
            lastTurnStatus: nil,
            lastTurnStartedAt: nil,
            lastTurnCompletedAt: nil,
            lastTurnDurationMs: nil,
            lastUserText: nil,
            lastAgentText: nil,
            lastWorkLabel: nil,
            lastItemType: nil,
            lastItemStatus: nil,
            activeItemCount: nil,
            failedItemCount: nil,
            readError: nil
        )
        let turns = raw["turns"] as? [[String: Any]] ?? []
        thread.turnCount = turns.count
        guard let turn = turns.last else { return thread }
        thread.lastTurnId = turn["id"] as? String
        thread.lastTurnStatus = turn["status"] as? String
        thread.lastTurnStartedAt = number(turn["startedAt"])
        thread.lastTurnCompletedAt = number(turn["completedAt"])
        thread.lastTurnDurationMs = number(turn["durationMs"])

        let activeStatuses = Set(["running", "in_progress", "inprogress", "pending", "started", "streaming", "queued"])
        let failedStatuses = Set(["failed", "failure", "error"])
        var activeCount = 0
        var failedCount = 0
        for item in turn["items"] as? [[String: Any]] ?? [] {
            let type = item["type"] as? String ?? ""
            let status = (item["status"] as? String ?? "").lowercased()
            if activeStatuses.contains(status) { activeCount += 1 }
            if failedStatuses.contains(status) { failedCount += 1 }
            if type == "userMessage" {
                thread.lastUserText = contentText(item["content"]) ?? thread.lastUserText
            } else if type == "agentMessage" {
                thread.lastAgentText = compactText(item["text"]) ?? thread.lastAgentText
            } else if let label = itemLabel(item) {
                thread.lastWorkLabel = label
            }
            if !type.isEmpty { thread.lastItemType = type }
            if !status.isEmpty { thread.lastItemStatus = status }
        }
        thread.activeItemCount = activeCount
        thread.failedItemCount = failedCount
        return thread
    }

    private static func merge(base: CodexBrokerThread, detail: CodexBrokerThread) -> CodexBrokerThread {
        var result = base
        result.sessionId = detail.sessionId ?? result.sessionId
        result.name = detail.name ?? result.name
        result.preview = detail.preview ?? result.preview
        result.cwd = detail.cwd ?? result.cwd
        result.path = detail.path ?? result.path
        result.source = detail.source ?? result.source
        result.statusType = detail.statusType ?? result.statusType
        result.updatedAt = detail.updatedAt ?? result.updatedAt
        result.createdAt = detail.createdAt ?? result.createdAt
        result.approvalMode = detail.approvalMode ?? result.approvalMode
        result.turnCount = detail.turnCount ?? result.turnCount
        result.lastTurnId = detail.lastTurnId ?? result.lastTurnId
        result.lastTurnStatus = detail.lastTurnStatus ?? result.lastTurnStatus
        result.lastTurnStartedAt = detail.lastTurnStartedAt ?? result.lastTurnStartedAt
        result.lastTurnCompletedAt = detail.lastTurnCompletedAt ?? result.lastTurnCompletedAt
        result.lastTurnDurationMs = detail.lastTurnDurationMs ?? result.lastTurnDurationMs
        result.lastUserText = detail.lastUserText ?? result.lastUserText
        result.lastAgentText = detail.lastAgentText ?? result.lastAgentText
        result.lastWorkLabel = detail.lastWorkLabel ?? result.lastWorkLabel
        result.lastItemType = detail.lastItemType ?? result.lastItemType
        result.lastItemStatus = detail.lastItemStatus ?? result.lastItemStatus
        result.activeItemCount = detail.activeItemCount ?? result.activeItemCount
        result.failedItemCount = detail.failedItemCount ?? result.failedItemCount
        result.readError = detail.readError ?? result.readError
        return result
    }

    private static func itemLabel(_ item: [String: Any]) -> String? {
        switch item["type"] as? String {
        case "commandExecution":
            let command = item["command"] ?? item["cmd"]
            return compactText(command.map { "Command: \($0)" } ?? "Command execution", limit: 120)
        case "fileChange":
            let count = (item["changes"] as? [Any])?.count
            return count.map { "File changes: \($0)" } ?? "File changes"
        case "toolCall":
            let name = item["name"] as? String ?? item["toolName"] as? String
            return compactText(name.map { "Tool: \($0)" } ?? "Tool call", limit: 120)
        default:
            return nil
        }
    }

    private static func contentText(_ value: Any?) -> String? {
        if let text = value as? String { return compactText(text) }
        guard let blocks = value as? [[String: Any]] else { return compactText(value) }
        let parts = blocks.compactMap { $0["text"] as? String ?? $0["content"] as? String }
        return compactText(parts.joined(separator: " "))
    }

    private static func compactText(_ value: Any?, limit: Int = 240) -> String? {
        guard let value else { return nil }
        let text: String
        if let value = value as? String {
            text = value
        } else if JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let value = String(data: data, encoding: .utf8) {
            text = value
        } else {
            text = String(describing: value)
        }
        let cleaned = text.replacingOccurrences(of: "\t", with: " ").split(separator: " ").joined(separator: " ")
        guard !cleaned.isEmpty else { return nil }
        return cleaned.count < limit ? cleaned : String(cleaned.prefix(max(1, limit - 1))) + "…"
    }

    private static func isAuxiliary(_ thread: CodexBrokerThread) -> Bool {
        let text = [thread.name, thread.preview, thread.path]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return text.contains("codex companion task:")
            || text.contains("run a stop-gate review")
            || text.contains("<compact_output_contract>")
            || text.contains("previous claude turn")
            || text.contains("stop-gate review")
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
                isSecret: item["isSecret"] as? Bool ?? false,
                allowsOther: item["isOther"] as? Bool
            )
        }
    }

    private static func discoverBrokerSockets() -> [String] {
        var candidates: [(Date, String)] = []
        if let override = ProcessInfo.processInfo.environment["AGENT_ISLAND_CODEX_BROKER_SOCKET"], !override.isEmpty {
            candidates.append((.distantFuture, override))
        }
        let roots = [NSTemporaryDirectory(), "/tmp"]
        for root in Set(roots) {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasPrefix("cxc-") {
                let path = URL(fileURLWithPath: root).appendingPathComponent(entry).appendingPathComponent("broker.sock").path
                guard FileManager.default.fileExists(atPath: path) else { continue }
                let date = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
                candidates.append((date, path))
            }
        }
        var seen = Set<String>()
        return candidates.sorted { $0.0 > $1.0 }.compactMap { _, path in
            guard seen.insert(path).inserted else { return nil }
            return path
        }
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

    static func userInputResponsePayload(_ answers: [String: [String]]) -> [String: Any] {
        ["answers": answers.reduce(into: [String: Any]()) { output, entry in
            output[entry.key] = ["answers": entry.value]
        }]
    }

    private static func protocolVersion(from value: Any) -> String? {
        guard let root = value as? [String: Any] else { return nil }
        if let version = root["protocolVersion"] as? String { return version }
        if let server = root["serverInfo"] as? [String: Any] {
            let name = server["name"] as? String
            let version = server["version"] as? String
            return [name, version].compactMap { $0 }.joined(separator: "/").nilIfEmpty
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func stringify(_ value: Any) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return String(describing: value)
    }

    private static func isAllowed(_ decision: PendingRequestDecision) -> Bool {
        if case .allow = decision { return true }
        return false
    }

    private static func jsonObject(_ text: String?) -> [String: Any]? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func rpcError(_ payload: [String: Any]) -> Error {
        error(payload["message"] as? String ?? String(describing: payload))
    }

    private static func error(_ message: String) -> Error {
        NSError(domain: "AgentIsland.CodexBroker", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
