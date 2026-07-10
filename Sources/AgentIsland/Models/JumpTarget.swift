// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

struct TerminalJumpTarget: Equatable {
    var appName: String?
    var bundleID: String?
    var pid: Int?
    var tty: String?
    var cwd: String?
    var windowID: String?
    var tabIndex: String?
    var sessionIdentifier: String?
    var title: String?
}

struct TmuxJumpTarget: Equatable {
    var pane: String?
    var socket: String?
    var client: String?
    var terminal: TerminalJumpTarget
}

struct ClaudeAppJumpTarget: Equatable {
    var cliSessionID: String
    var localSessionID: String
    var title: String?
    var cwd: String?
}

enum JumpTarget: Equatable {
    case url(String)
    case process(pid: Int)
    case terminal(TerminalJumpTarget)
    case tmux(TmuxJumpTarget)
    case claudeApp(ClaudeAppJumpTarget)
    case app(bundleID: String, fallbackPath: String?)
    case chatGPTWeb
}
