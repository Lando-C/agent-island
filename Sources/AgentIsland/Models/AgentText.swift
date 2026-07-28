// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

enum AgentText {
    static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compact(_ value: String, limit: Int) -> String {
        let cleaned = cleanConversationTitle(value)
        guard cleaned.count > limit else { return cleaned }
        let end = cleaned.index(cleaned.startIndex, offsetBy: max(1, limit - 1))
        return String(cleaned[..<end]) + "…"
    }

    static func meaningfulConversationTitle(_ value: String) -> String? {
        let cleaned = cleanConversationTitle(value)
        guard cleaned != "未命名对话", !isInternalTaskText(cleaned) else { return nil }
        return cleaned
    }

    static func isInternalTaskText(_ value: String) -> Bool {
        let text = singleLine(value).lowercased()
        if text.isEmpty { return true }
        if text.contains("<task-notification") { return true }
        if text.contains("<task-id>") { return true }
        if text.contains("</task-notification>") { return true }
        if text.contains("<observed_from_primary_session") { return true }
        if text.contains("</observed_from_primary_session>") { return true }
        if text.contains("<system-reminder") { return true }
        if text.contains("hello memory agent") { return true }
        if text.contains("you are a claude-mem") { return true }
        if text.contains("memory processing continued") { return true }
        if text.contains("this session is being continued from a previous conversation") {
            return true
        }
        if text == "null" || text == "none" { return true }
        return false
    }

    static func cleanConversationTitle(_ value: String) -> String {
        var cleaned = singleLine(value)
        if cleaned.hasPrefix("Codex Companion Task:") {
            cleaned = cleaned.replacingOccurrences(
                of: "Codex Companion Task:",
                with: "Companion review:"
            )
        }
        if isInternalTaskText(cleaned) {
            return "未命名对话"
        }
        if cleaned.hasPrefix("<task> Run a stop-gate review")
            || cleaned.contains("Run a stop-gate review of the previous Claude turn") {
            return "Stop-gate review"
        }
        if cleaned.hasPrefix("<task>") {
            cleaned = cleaned.replacingOccurrences(of: "<task>", with: "")
        }
        cleaned = cleaned
            .replacingOccurrences(of: "</task>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "未命名对话" : cleaned
    }
}
