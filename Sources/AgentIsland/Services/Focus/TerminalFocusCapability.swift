// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

/// The strongest terminal location guarantee that can be made from a capability
/// probe. Callers must not present `.exact` or `.context` unless the target was
/// resolved against fresh, unambiguous terminal metadata.
enum TerminalFocusPrecision: String, Equatable {
    case exact
    case context
    case fallback
    case unavailable
}

/// A terminal pane/window observed by an optional terminal-specific helper.
///
/// `stableID` is the helper's pane, window, tab, or session identifier. TTY and
/// CWD are weaker context evidence and are only usable when they select exactly
/// one candidate.
struct TerminalFocusCandidate: Equatable {
    var stableID: String?
    var tty: String?
    var cwd: String?
}

/// An offline description of the capabilities available for one focus attempt.
///
/// This model intentionally contains no AppKit or process calls, so provider
/// adapters and tests can use the same conservative exact/context/fallback
/// policy without depending on which terminal applications are installed.
struct TerminalFocusCapabilitySnapshot: Equatable {
    var helperAvailable: Bool
    var metadataFresh: Bool
    var candidates: [TerminalFocusCandidate]
    var fallbackAvailable: Bool
}

struct TerminalFocusResolution: Equatable {
    var precision: TerminalFocusPrecision
    var candidate: TerminalFocusCandidate?
    var reason: String
}

enum TerminalFocusCapabilityResolver {
    static func resolve(
        target: TerminalJumpTarget,
        snapshot: TerminalFocusCapabilitySnapshot
    ) -> TerminalFocusResolution {
        guard snapshot.helperAvailable else {
            return fallback(snapshot, reason: "terminal helper unavailable")
        }
        guard snapshot.metadataFresh else {
            return fallback(snapshot, reason: "terminal metadata is stale")
        }

        if let stableID = normalized(target.sessionIdentifier) ?? normalized(target.windowID) {
            let matches = snapshot.candidates.filter {
                normalized($0.stableID) == stableID
            }
            if matches.count == 1 {
                return TerminalFocusResolution(
                    precision: .exact,
                    candidate: matches[0],
                    reason: "unique stable terminal identity"
                )
            }
            if matches.count > 1 {
                return fallback(snapshot, reason: "stable terminal identity is ambiguous")
            }
        }

        if let tty = normalizedTTY(target.tty) {
            let matches = snapshot.candidates.filter {
                normalizedTTY($0.tty) == tty
            }
            if matches.count == 1 {
                return TerminalFocusResolution(
                    precision: .context,
                    candidate: matches[0],
                    reason: "unique terminal TTY"
                )
            }
            if matches.count > 1 {
                return fallback(snapshot, reason: "terminal TTY is ambiguous")
            }
        }

        if let cwd = normalizedPath(target.cwd) {
            let matches = snapshot.candidates.filter {
                normalizedPath($0.cwd) == cwd
            }
            if matches.count == 1 {
                return TerminalFocusResolution(
                    precision: .context,
                    candidate: matches[0],
                    reason: "unique terminal working directory"
                )
            }
            if matches.count > 1 {
                return fallback(snapshot, reason: "terminal working directory is ambiguous")
            }
        }

        return fallback(snapshot, reason: "target terminal context was not observed")
    }

    private static func fallback(
        _ snapshot: TerminalFocusCapabilitySnapshot,
        reason: String
    ) -> TerminalFocusResolution {
        TerminalFocusResolution(
            precision: snapshot.fallbackAvailable ? .fallback : .unavailable,
            candidate: nil,
            reason: reason
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func normalizedTTY(_ value: String?) -> String? {
        guard let value = normalized(value) else { return nil }
        if value.hasPrefix("/dev/") { return value }
        if value.hasPrefix("tty") { return "/dev/\(value)" }
        return "/dev/tty\(value)"
    }

    private static func normalizedPath(_ value: String?) -> String? {
        guard let value = normalized(value) else { return nil }
        if value == "/" { return value }
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }
}
