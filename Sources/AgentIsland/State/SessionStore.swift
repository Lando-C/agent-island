// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

struct ResolvedAgentEvent {
    var family: AgentFamily
    var surface: AgentSurface
    var session: String
    var event: AgentEvent
    var hookEvent: String
    var normalizedPhase: AgentPhase
    var ts: Double
}

enum SessionPhase {
    case idle
    case working
    case thinking
    case waitingApproval
    case waitingInput
    case queued
    case completed
    case error

    var agentPhase: AgentPhase {
        switch self {
        case .idle:
            return .idle
        case .working:
            return .working
        case .thinking:
            return .thinking
        case .waitingApproval, .waitingInput:
            return .needsAttention
        case .queued:
            return .queued
        case .completed:
            return .done
        case .error:
            return .error
        }
    }
}

enum SessionRetentionPolicy {
    static func maxAge(for phase: AgentPhase) -> TimeInterval {
        switch phase {
        case .working:
            return 30 * 60
        case .thinking:
            return 90
        case .queued:
            return 10 * 60
        case .needsAttention, .error:
            return 12 * 60 * 60
        case .done:
            return 10 * 60
        case .online, .idle, .available, .offline:
            return 60 * 60
        }
    }
}

struct AgentSessionStore {
    private struct SessionAccumulator {
        var family: AgentFamily
        var surface: AgentSurface
        var session: String
        var latestEvent: AgentEvent?
        var latestHookEvent = ""
        var latestTs: Double = 0
        var activeToolCounts: [String: Int] = [:]
        var pendingAttentionEvent: AgentEvent?
        var pendingAttentionTs: Double = 0
        var pendingAttentionKind: SessionPhase = .waitingApproval
        var lastToolEvent: AgentEvent?
        var lastToolHookEvent = ""
        var lastToolTs: Double = 0
        var lastActiveEvent: AgentEvent?
        var lastActiveTs: Double = 0
        var terminalEvent: AgentEvent?
        var terminalPhase: SessionPhase?
        var terminalTs: Double = 0
        var queuedEvent: AgentEvent?
        var queuedTs: Double = 0

        var activeToolCount: Int {
            activeToolCounts.values.reduce(0, +)
        }

        mutating func apply(_ resolved: ResolvedAgentEvent) {
            family = resolved.family
            surface = preferredSurface(current: surface, incoming: resolved.surface)
            latestEvent = resolved.event
            latestHookEvent = resolved.hookEvent
            latestTs = resolved.ts

            switch resolved.hookEvent {
            case "pretooluse", "beforetool", "preinvocation":
                incrementTool(resolved.event.tool)
                clearAttention()
                lastToolEvent = resolved.event
                lastToolHookEvent = resolved.hookEvent
                lastToolTs = resolved.ts
                lastActiveEvent = resolved.event
                lastActiveTs = resolved.ts
            case "posttooluse", "afteragent":
                decrementTool(resolved.event.tool)
                clearAttention()
                lastToolEvent = resolved.event
                lastToolHookEvent = resolved.hookEvent
                lastToolTs = resolved.ts
            case "posttoolusefailure", "permissionrequest", "elicitation":
                decrementTool(resolved.event.tool)
                pendingAttentionEvent = resolved.event
                pendingAttentionTs = resolved.ts
                pendingAttentionKind = resolved.hookEvent == "elicitation" ? .waitingInput : .waitingApproval
                lastToolEvent = resolved.event
                lastToolHookEvent = resolved.hookEvent
                lastToolTs = resolved.ts
            case "userpromptsubmit", "sessionstart", "startup", "init":
                clearAttention()
                queuedEvent = resolved.event
                queuedTs = resolved.ts
            case "stop", "sessionend", "postinvocation", "subagentstop":
                activeToolCounts.removeAll()
                clearAttention()
                terminalEvent = resolved.event
                terminalPhase = .completed
                terminalTs = resolved.ts
            case "stopfailure":
                activeToolCounts.removeAll()
                pendingAttentionEvent = resolved.event
                pendingAttentionTs = resolved.ts
                pendingAttentionKind = .error
            default:
                applyPhaseFallback(resolved)
            }
        }

        mutating private func applyPhaseFallback(_ resolved: ResolvedAgentEvent) {
            switch resolved.normalizedPhase {
            case .needsAttention:
                pendingAttentionEvent = resolved.event
                pendingAttentionTs = resolved.ts
                pendingAttentionKind = .waitingApproval
            case .error:
                pendingAttentionEvent = resolved.event
                pendingAttentionTs = resolved.ts
                pendingAttentionKind = .error
            case .working:
                lastToolEvent = resolved.event
                lastToolHookEvent = resolved.hookEvent
                lastToolTs = resolved.ts
            case .queued:
                queuedEvent = resolved.event
                queuedTs = resolved.ts
            case .done:
                terminalEvent = resolved.event
                terminalPhase = .completed
                terminalTs = resolved.ts
            case .thinking, .online, .idle, .available, .offline:
                break
            }
        }

        private mutating func incrementTool(_ rawTool: String?) {
            let tool = normalizedTool(rawTool)
            activeToolCounts[tool, default: 0] += 1
        }

        private mutating func decrementTool(_ rawTool: String?) {
            let tool = normalizedTool(rawTool)
            if let count = activeToolCounts[tool], count > 1 {
                activeToolCounts[tool] = count - 1
            } else {
                activeToolCounts.removeValue(forKey: tool)
            }
        }

        private mutating func clearAttention() {
            pendingAttentionEvent = nil
            pendingAttentionTs = 0
        }

        private func normalizedTool(_ rawTool: String?) -> String {
            let value = rawTool?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value! : "__tool__"
        }

        private func preferredSurface(current: AgentSurface, incoming: AgentSurface) -> AgentSurface {
            if current == incoming { return current }
            if current == .app || incoming == .app { return .app }
            if current == .runtime || incoming == .runtime { return .runtime }
            return incoming
        }

        func rollup(now: Double) -> AgentEventRollup? {
            guard let latestEvent else { return nil }

            let phaseInfo = currentPhase(now: now)
            guard now - phaseInfo.ts <= SessionRetentionPolicy.maxAge(for: phaseInfo.phase) else { return nil }

            var rollup = AgentEventRollup(
                family: family,
                surface: surface,
                session: session,
                displayEvent: phaseInfo.event,
                displayPhase: phaseInfo.phase,
                displayTs: phaseInfo.ts,
                workingCount: phaseInfo.phase == .working ? max(1, activeToolCount) : 0,
                thinkingCount: phaseInfo.phase == .thinking ? 1 : 0,
                attentionCount: phaseInfo.phase == .needsAttention || phaseInfo.phase == .error ? 1 : 0,
                queuedCount: phaseInfo.phase == .queued ? 1 : 0,
                doneCount: phaseInfo.phase == .done ? 1 : 0
            )
            if rollup.displayEvent == nil {
                rollup.displayEvent = latestEvent
                rollup.displayPhase = .idle
                rollup.displayTs = latestTs
            }
            return rollup
        }

        private func currentPhase(now: Double) -> (phase: AgentPhase, event: AgentEvent, ts: Double) {
            if let pendingAttentionEvent,
               now - pendingAttentionTs <= SessionRetentionPolicy.maxAge(for: pendingAttentionKind.agentPhase) {
                return (pendingAttentionKind.agentPhase, pendingAttentionEvent, pendingAttentionTs)
            }

            if activeToolCount > 0, let event = lastToolEvent {
                return (.working, lastActiveEvent ?? event, lastActiveTs > 0 ? lastActiveTs : lastToolTs)
            }

            if let terminalEvent,
               let terminalPhase,
               now - terminalTs <= SessionRetentionPolicy.maxAge(for: terminalPhase.agentPhase) {
                return (terminalPhase.agentPhase, terminalEvent, terminalTs)
            }

            if let event = lastToolEvent,
               lastToolHookEvent == "posttooluse",
               now - lastToolTs <= SessionRetentionPolicy.maxAge(for: .thinking) {
                return (.thinking, event, lastToolTs)
            }

            if let queuedEvent,
               now - queuedTs <= SessionRetentionPolicy.maxAge(for: .queued) {
                return (.queued, queuedEvent, queuedTs)
            }

            return (.idle, latestEvent ?? terminalEvent ?? queuedEvent ?? lastToolEvent!, latestTs)
        }
    }

    static func rollups(from events: [ResolvedAgentEvent], now: Double) -> [String: AgentEventRollup] {
        var sessions: [String: SessionAccumulator] = [:]
        for resolved in events.sorted(by: { $0.ts < $1.ts }) {
            let key = "\(resolved.family.rawValue)::\(resolved.session)"
            var accumulator = sessions[key] ?? SessionAccumulator(
                family: resolved.family,
                surface: resolved.surface,
                session: resolved.session
            )
            accumulator.apply(resolved)
            sessions[key] = accumulator
        }

        var result: [String: AgentEventRollup] = [:]
        for accumulator in sessions.values {
            guard let rollup = accumulator.rollup(now: now),
                  let family = rollup.family,
                  let surface = rollup.surface,
                  let session = rollup.session else {
                continue
            }
            result["\(family.rawValue)-\(surface.rawValue)-\(session)"] = rollup
        }
        return result
    }
}
