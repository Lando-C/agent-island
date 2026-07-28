// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

/// Pure mapping for the interactive portion of the Codex app-server protocol.
/// Keeping this outside the socket client lets recorded JSON-RPC frames exercise
/// exactly the same request and response rules without needing a live broker.
enum CodexBrokerProtocol {
    static func request(
        fromServerMethod method: String,
        rawID: Any,
        params: [String: Any],
        now: Date = Date()
    ) -> HookSocketRequest? {
        let schema: String
        let event: String
        let questions: [PendingQuestion]
        let permissionsJSON: String?

        guard nonEmptyString(params["threadId"]) != nil,
              nonEmptyString(params["turnId"]) != nil,
              nonEmptyString(params["itemId"]) != nil else { return nil }

        switch method {
        case "item/tool/requestUserInput":
            guard let rawQuestions = params["questions"] as? [[String: Any]],
                  let parsedQuestions = parseQuestions(rawQuestions) else { return nil }
            schema = "codex_app_server_user_input"
            event = "requestUserInput"
            questions = parsedQuestions
            permissionsJSON = nil
        case "item/commandExecution/requestApproval":
            guard params["startedAtMs"] as? NSNumber != nil else { return nil }
            schema = "codex_app_server_command_approval"
            event = "PermissionRequest"
            questions = []
            permissionsJSON = nil
        case "item/fileChange/requestApproval":
            guard params["startedAtMs"] as? NSNumber != nil else { return nil }
            schema = "codex_app_server_file_approval"
            event = "PermissionRequest"
            questions = []
            permissionsJSON = nil
        case "item/permissions/requestApproval":
            guard params["startedAtMs"] as? NSNumber != nil,
                  nonEmptyString(params["cwd"]) != nil,
                  let permissions = params["permissions"] as? [String: Any],
                  let encodedPermissions = jsonString(permissions) else { return nil }
            schema = "codex_app_server_permissions_approval"
            event = "PermissionRequest"
            questions = []
            permissionsJSON = encodedPermissions
        default:
            return nil
        }

        let command = commandText(params["command"])
        let question = questions.first?.prompt
        let detail = question
            ?? (params["reason"] as? String)
            ?? command
            ?? (params["grantRoot"] as? String)
            ?? (params["cwd"] as? String)
            ?? "Codex 正在等待你的决定"

        return HookSocketRequest(
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
            requestID: stringify(rawID),
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
            ts: now.timeIntervalSince1970
        )
    }

    static func responsePayload(
        responseSchema: String?,
        toolInputJSON: String?,
        decision: PendingRequestDecision
    ) -> [String: Any]? {
        switch responseSchema {
        case "codex_app_server_user_input":
            guard case .answer(let answers) = decision else { return nil }
            return userInputResponsePayload(answers)
        case "codex_app_server_command_approval", "codex_app_server_file_approval":
            switch decision {
            case .allow:
                return ["decision": "accept"]
            case .deny:
                return ["decision": "decline"]
            case .answer:
                return nil
            }
        case "codex_app_server_permissions_approval":
            switch decision {
            case .allow:
                guard let permissions = jsonObject(toolInputJSON) else { return nil }
                return ["permissions": permissions, "scope": "turn"]
            case .deny:
                return ["permissions": [:], "scope": "turn"]
            case .answer:
                return nil
            }
        default:
            return nil
        }
    }

    static func userInputResponsePayload(_ answers: [String: [String]]) -> [String: Any] {
        ["answers": answers.reduce(into: [String: Any]()) { output, entry in
            output[entry.key] = ["answers": entry.value]
        }]
    }

    private static func parseQuestions(_ raw: [[String: Any]]) -> [PendingQuestion]? {
        guard !raw.isEmpty else { return nil }
        var questions: [PendingQuestion] = []
        for item in raw {
            guard let id = nonEmptyString(item["id"]),
                  let header = nonEmptyString(item["header"]),
                  let prompt = nonEmptyString(item["question"]) else { return nil }

            var options: [String] = []
            if let rawOptions = item["options"], !(rawOptions is NSNull) {
                guard let optionItems = rawOptions as? [[String: Any]] else { return nil }
                for option in optionItems {
                    guard let label = nonEmptyString(option["label"]),
                          nonEmptyString(option["description"]) != nil else { return nil }
                    options.append(label)
                }
            }

            questions.append(PendingQuestion(
                id: id,
                header: header,
                prompt: prompt,
                options: options,
                multiSelect: item["multiSelect"] as? Bool ?? false,
                isSecret: item["isSecret"] as? Bool ?? false,
                allowsOther: item["isOther"] as? Bool ?? false
            ))
        }
        return questions
    }

    private static func commandText(_ value: Any?) -> String? {
        if let command = value as? String, !command.isEmpty { return command }
        if let command = value as? [String], !command.isEmpty { return command.joined(separator: " ") }
        return nil
    }

    private static func jsonString(_ value: Any?) -> String? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func jsonObject(_ text: String?) -> [String: Any]? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private static func stringify(_ value: Any) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return String(describing: value)
    }

}
