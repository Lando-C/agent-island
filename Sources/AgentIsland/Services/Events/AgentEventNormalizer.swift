// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

/// Converts provider-specific event vocabulary into Agent Island's stable
/// family, surface, and phase model.
///
/// Keep this layer pure: it is shared by event ingestion and fixture tests and
/// must not probe processes, mutate stores, or infer transport health.
enum AgentEventNormalizer {
    static func family(from raw: String?) -> AgentFamily? {
        guard let raw else { return nil }
        let value = raw.lowercased()
        if value.contains("claude_science")
            || value.contains("claudescience")
            || value.contains("claude science")
            || value.contains("operon") {
            return .claudeScience
        }
        if value.contains("codex") { return .codex }
        if value.contains("claude") { return .claude }
        return nil
    }

    static func surface(from raw: String?) -> AgentSurface {
        guard let raw else { return .cli }
        let value = raw.lowercased()
        if value.contains("app") || value.contains("desktop") { return .app }
        if value.contains("runtime")
            || value.contains("server")
            || value.contains("service")
            || value.contains("kernel") {
            return .runtime
        }
        if value.contains("cli") || value.contains("terminal") || value.contains("code") {
            return .cli
        }
        return .cli
    }

    static func phase(from raw: String?) -> AgentPhase? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "needs_attention", "needsattention", "attention", "approval", "permission",
             "input_required", "inputrequired", "blocked", "human":
            return .needsAttention
        case "working", "running", "active", "start", "started", "progress", "busy":
            return .working
        case "thinking", "think":
            return .thinking
        case "queued", "todo", "pending", "waiting":
            return .queued
        case "done", "complete", "completed", "success", "finished", "finish":
            return .done
        case "error", "failed", "failure":
            return .error
        case "online":
            return .online
        case "available", "installed":
            return .available
        case "idle":
            return .idle
        case "offline", "stopped":
            return .offline
        default:
            return nil
        }
    }

    static func phase(for event: AgentEvent) -> AgentPhase? {
        let rawEvent = (event.title ?? "") + " " + (event.message ?? "")
        let hookEvent = hookEventName(for: event)
        if hookEvent == "stop"
            || hookEvent == "sessionend"
            || hookEvent == "postinvocation"
            || hookEvent == "subagentstop" {
            return .idle
        }
        if hookEvent == "userpromptsubmit" {
            return .queued
        }
        if hookEvent == "permissionrequest"
            || hookEvent == "elicitation"
            || hookEvent == "posttoolusefailure" {
            return .needsAttention
        }
        if rawEvent.contains("本轮结束") || rawEvent.contains("子任务结束") {
            return .idle
        }
        return phase(from: event.phase ?? event.status)
    }

    static func hookEventName(for event: AgentEvent) -> String {
        (event.event ?? "")
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
