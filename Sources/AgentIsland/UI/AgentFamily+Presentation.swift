// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import SwiftUI

extension AgentFamily {
    var tint: Color {
        switch self {
        case .codex: return Color(red: 0.18, green: 0.78, blue: 0.47)
        case .claude: return Color(red: 0.93, green: 0.55, blue: 0.22)
        case .claudeScience: return Color(red: 0.37, green: 0.68, blue: 1.0)
        case .chatgpt: return Color(red: 0.10, green: 0.74, blue: 0.60)
        }
    }
}
