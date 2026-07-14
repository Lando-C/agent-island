// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

struct CodexBrokerThread: Decodable, Equatable {
    var id: String?
    var sessionId: String?
    var name: String?
    var preview: String?
    var cwd: String?
    var path: String?
    var source: String?
    var statusType: String?
    var updatedAt: Double?
    var createdAt: Double?
    var approvalMode: String?
    var turnCount: Int?
    var lastTurnId: String?
    var lastTurnStatus: String?
    var lastTurnStartedAt: Double?
    var lastTurnCompletedAt: Double?
    var lastTurnDurationMs: Double?
    var lastUserText: String?
    var lastAgentText: String?
    var lastWorkLabel: String?
    var lastItemType: String?
    var lastItemStatus: String?
    var activeItemCount: Int?
    var failedItemCount: Int?
    var readError: String?
}
