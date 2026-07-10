// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Combine
import Foundation

enum PendingRequestKind: String, Codable {
    case permission
    case input
}

enum PendingRequestStatus: String, Codable {
    case pending
    case allowed
    case denied
    case answered
    case failed
}

enum PendingRequestDecision {
    case allow
    case deny
    case answer(String)
}

struct PendingRequest: Identifiable, Equatable {
    var id: String
    var family: AgentFamily
    var surface: AgentSurface
    var kind: PendingRequestKind
    var status: PendingRequestStatus
    var sessionID: String?
    var requestID: String?
    var title: String
    var detail: String
    var tool: String?
    var toolInputSummary: String?
    var toolRisk: String?
    var toolRiskReason: String?
    var question: String?
    var options: [String]
    var canRespondInline: Bool
    var createdAt: Date
    var updatedAt: Date
    var responseMessage: String?

    var isPending: Bool {
        status == .pending
    }

    var canApproveInline: Bool {
        canRespondInline && kind == .permission
    }

    var canAnswerInline: Bool {
        canRespondInline && kind == .input
    }
}

struct HookSocketRequest: Decodable {
    var type: String?
    var source: String?
    var surface: String?
    var event: String?
    var status: String?
    var title: String?
    var message: String?
    var session: String?
    var rawSession: String?
    var primarySession: String?
    var parentSession: String?
    var requestID: String?
    var tool: String?
    var toolInputSummary: String?
    var toolRisk: String?
    var toolRiskReason: String?
    var question: String?
    var options: [String]?
    var responseSchema: String?
    var ts: Double?

    enum CodingKeys: String, CodingKey {
        case type, source, surface, event, status, title, message, session, tool, question, options, ts
        case rawSession = "raw_session"
        case primarySession = "primary_session"
        case parentSession = "parent_session"
        case requestID = "request_id"
        case toolInputSummary = "tool_input_summary"
        case toolRisk = "tool_risk"
        case toolRiskReason = "tool_risk_reason"
        case responseSchema = "response_schema"
    }

    var normalizedEvent: String {
        (event ?? "")
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    var family: AgentFamily {
        let raw = (source ?? "").lowercased()
        if raw.contains("codex") { return .codex }
        if raw.contains("claude") { return .claude }
        return .claude
    }

    var agentSurface: AgentSurface {
        AgentSurface(rawValue: surface ?? "") ?? .cli
    }

    var logicalSessionID: String? {
        [primarySession, parentSession, session, rawSession]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var kind: PendingRequestKind {
        switch normalizedEvent {
        case "permissionrequest", "posttoolusefailure":
            return .permission
        default:
            return .input
        }
    }

    var canRespondInline: Bool {
        responseSchema == "claude_permission_request"
    }

    var pendingID: String {
        if let requestID, !requestID.isEmpty {
            return "\(family.rawValue)::\(requestID)"
        }
        let sessionPart = logicalSessionID ?? "global"
        let toolPart = tool ?? normalizedEvent
        let tsPart = Int((ts ?? Date().timeIntervalSince1970) * 1000)
        return "\(family.rawValue)::\(sessionPart)::\(normalizedEvent)::\(toolPart)::\(tsPart)"
    }
}

final class PendingRequestStore: ObservableObject {
    @Published private(set) var requests: [PendingRequest] = []

    var onDecision: ((PendingRequest, PendingRequestDecision) -> Void)?

    private let retention: TimeInterval = 10 * 60

    var pendingCount: Int {
        requests.filter(\.isPending).count
    }

    var firstPendingPermission: PendingRequest? {
        requests.first { $0.isPending && $0.canApproveInline }
    }

    func upsert(socketRequest: HookSocketRequest) -> PendingRequest {
        let now = Date()
        let request = PendingRequest(
            id: socketRequest.pendingID,
            family: socketRequest.family,
            surface: socketRequest.agentSurface,
            kind: socketRequest.kind,
            status: .pending,
            sessionID: socketRequest.logicalSessionID,
            requestID: socketRequest.requestID,
            title: PendingRequestStore.title(for: socketRequest),
            detail: PendingRequestStore.detail(for: socketRequest),
            tool: emptyToNil(socketRequest.tool),
            toolInputSummary: emptyToNil(socketRequest.toolInputSummary),
            toolRisk: emptyToNil(socketRequest.toolRisk),
            toolRiskReason: emptyToNil(socketRequest.toolRiskReason),
            question: emptyToNil(socketRequest.question),
            options: socketRequest.options ?? [],
            canRespondInline: socketRequest.canRespondInline,
            createdAt: now,
            updatedAt: now,
            responseMessage: nil
        )
        upsert(request)
        return request
    }

    func upsert(_ request: PendingRequest) {
        prune(now: Date())
        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            var next = request
            next.createdAt = requests[index].createdAt
            requests[index] = next
        } else {
            requests.append(request)
        }
        sortRequests()
    }

    func request(for snapshot: AgentSnapshot) -> PendingRequest? {
        if let requestID = snapshot.requestID, !requestID.isEmpty {
            let key = "\(snapshot.family.rawValue)::\(requestID)"
            if let match = requests.first(where: { $0.id == key }) {
                return match
            }
        }
        guard let sessionID = snapshot.sessionID else { return nil }
        return requests.first {
            $0.family == snapshot.family
                && $0.sessionID == sessionID
                && $0.status == .pending
        }
    }

    func allow(_ request: PendingRequest) {
        decide(request, decision: .allow, status: .allowed, message: "已允许")
    }

    func deny(_ request: PendingRequest) {
        decide(request, decision: .deny, status: .denied, message: "已拒绝")
    }

    func answer(_ request: PendingRequest, text: String) {
        decide(request, decision: .answer(text), status: .answered, message: "已回复")
    }

    func markFailed(id: String, message: String) {
        update(id: id, status: .failed, message: message)
    }

    func markResponded(id: String, status: PendingRequestStatus, message: String) {
        update(id: id, status: status, message: message)
    }

    @discardableResult
    func allowFirstPendingPermission() -> Bool {
        guard let request = firstPendingPermission else { return false }
        allow(request)
        return true
    }

    @discardableResult
    func denyFirstPendingPermission() -> Bool {
        guard let request = firstPendingPermission else { return false }
        deny(request)
        return true
    }

    func prune(now: Date) {
        let retained = requests.filter { request in
            !(request.status != .pending && now.timeIntervalSince(request.updatedAt) > retention)
        }
        guard retained.count != requests.count else { return }
        requests = retained
    }

    private func decide(
        _ request: PendingRequest,
        decision: PendingRequestDecision,
        status: PendingRequestStatus,
        message: String
    ) {
        update(id: request.id, status: status, message: message)
        onDecision?(request, decision)
    }

    private func update(id: String, status: PendingRequestStatus, message: String) {
        guard let index = requests.firstIndex(where: { $0.id == id }) else { return }
        requests[index].status = status
        requests[index].updatedAt = Date()
        requests[index].responseMessage = message
        sortRequests()
    }

    private func sortRequests() {
        requests.sort {
            if $0.status == .pending, $1.status != .pending { return true }
            if $0.status != .pending, $1.status == .pending { return false }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private static func title(for request: HookSocketRequest) -> String {
        let family = request.family.displayName
        switch request.kind {
        case .permission:
            if let tool = emptyToNil(request.tool) {
                return "\(family) 请求允许 \(tool)"
            }
            return "\(family) 请求权限"
        case .input:
            return "\(family) 等待输入"
        }
    }

    private static func detail(for request: HookSocketRequest) -> String {
        switch request.kind {
        case .permission:
            let base = request.toolInputSummary ?? request.message ?? request.title ?? "等待允许或拒绝"
            return AgentText.compact(base, limit: 140)
        case .input:
            let base = request.question ?? request.message ?? request.title ?? "等待你选择或回复"
            return AgentText.compact(base, limit: 140)
        }
    }
}

private func emptyToNil(_ value: String?) -> String? {
    guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
        return nil
    }
    return text
}
