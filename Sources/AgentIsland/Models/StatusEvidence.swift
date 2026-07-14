// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

/// Explains how a displayed state was obtained. A state source is deliberately
/// visible so process discovery is never mistaken for an engine confirmation.
enum StatusEvidence: String, Codable, Equatable {
    case hook
    case appTranscript
    case broker
    case webBridge
    case processProbe
    case heuristic

    var label: String {
        switch self {
        case .hook: return "实时 Hook"
        case .appTranscript: return "App 记录"
        case .broker: return "App Server"
        case .webBridge: return "网页桥接"
        case .processProbe: return "进程探测"
        case .heuristic: return "启发式"
        }
    }

    var isAuthoritative: Bool {
        switch self {
        case .hook, .appTranscript, .broker:
            return true
        case .webBridge, .processProbe, .heuristic:
            return false
        }
    }
}
