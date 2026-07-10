// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Foundation

struct ClaudeAppSessionInfo: Decodable, Equatable {
    var sessionId: String
    var cliSessionId: String?
    var cwd: String?
    var title: String?
    var lastFocusedAt: Double?
    var lastActivityAt: Double?
}

enum ClaudeAppSessionIndex {
    static func load(
        roots: [URL],
        matching cliSessionIDs: Set<String>
    ) -> [String: ClaudeAppSessionInfo] {
        guard !cliSessionIDs.isEmpty else { return [:] }

        let decoder = JSONDecoder()
        var result: [String: ClaudeAppSessionInfo] = [:]

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension == "json" {
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                      (values.fileSize ?? 0) <= 512_000,
                      let data = try? Data(contentsOf: url),
                      let info = try? decoder.decode(ClaudeAppSessionInfo.self, from: data),
                      let cliSessionID = info.cliSessionId,
                      cliSessionIDs.contains(cliSessionID) else {
                    continue
                }

                if let current = result[cliSessionID] {
                    result[cliSessionID] = preferred(current, info, cliSessionID: cliSessionID)
                } else {
                    result[cliSessionID] = info
                }
            }
        }
        return result
    }

    static func displayTitle(for info: ClaudeAppSessionInfo) -> String {
        let rawTitle = info.title.map(AgentText.singleLine)
        let workspace = info.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        let genericTitles = Set(["new session", "untitled", "resume"])

        if let rawTitle,
           !rawTitle.isEmpty,
           !genericTitles.contains(rawTitle.lowercased()),
           let title = AgentText.meaningfulConversationTitle(rawTitle) {
            return title
        }

        let sessionSuffix = info.cliSessionId.map { String($0.prefix(8)) }
        return [workspace, rawTitle, sessionSuffix]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    private static func recency(_ info: ClaudeAppSessionInfo) -> Double {
        max(info.lastActivityAt ?? 0, info.lastFocusedAt ?? 0)
    }

    private static func preferred(
        _ lhs: ClaudeAppSessionInfo,
        _ rhs: ClaudeAppSessionInfo,
        cliSessionID: String
    ) -> ClaudeAppSessionInfo {
        let lhsScore = identityScore(lhs, cliSessionID: cliSessionID)
        let rhsScore = identityScore(rhs, cliSessionID: cliSessionID)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        return recency(lhs) >= recency(rhs) ? lhs : rhs
    }

    private static func identityScore(_ info: ClaudeAppSessionInfo, cliSessionID: String) -> Int {
        var score = 0
        // `claude://resume` creates local_<cli-id> imports. Prefer Claude's original
        // random local session so focusing never selects an accidental duplicate.
        if info.sessionId != "local_\(cliSessionID)" { score += 2 }
        if let title = info.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 1
        }
        return score
    }
}
