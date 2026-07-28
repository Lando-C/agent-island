// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import Combine
import Foundation

enum OnboardingRequirement: String, Codable {
    case required
    case optional

    var label: String {
        switch self {
        case .required: return "基础要求"
        case .optional: return "可选集成"
        }
    }
}

struct OnboardingChecklistItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let requirement: OnboardingRequirement
    let systemImage: String
}

final class OnboardingChecklistStore: ObservableObject {
    static let shared = OnboardingChecklistStore()
    static let seenKey = "agentIsland.onboarding.seen.v1"
    static let completedKey = "agentIsland.onboarding.completed.v1"

    static let items = [
        OnboardingChecklistItem(
            id: "local-only",
            title: "确认本地数据边界",
            detail: "基础状态展示无需授予系统权限；Agent Island 不上传对话，也不会删除 Claude/Codex 原始 transcript。",
            requirement: .required,
            systemImage: "lock.shield"
        ),
        OnboardingChecklistItem(
            id: "provider-hooks",
            title: "安装所用 CLI 的 Hook",
            detail: "仅在使用 Claude Code/Codex CLI 时需要，用于可靠地接收状态和审批事件；不用对应 CLI 可跳过。",
            requirement: .optional,
            systemImage: "link"
        ),
        OnboardingChecklistItem(
            id: "accessibility",
            title: "辅助功能权限",
            detail: "仅用于精确返回 Claude App 会话；状态监控和普通 App 激活不依赖它。",
            requirement: .optional,
            systemImage: "cursorarrow.motionlines"
        ),
        OnboardingChecklistItem(
            id: "notifications",
            title: "通知权限",
            detail: "仅用于离开刘海时接收系统通知；岛内状态和审批仍可正常工作。",
            requirement: .optional,
            systemImage: "bell"
        ),
        OnboardingChecklistItem(
            id: "web-bridge",
            title: "Browser Bridge",
            detail: "仅在需要网页会话辅助状态时启用；它是非权威信号，不影响 CLI/App 主链路。",
            requirement: .optional,
            systemImage: "globe"
        )
    ]

    @Published private(set) var completed: Set<String>
    private let defaults: UserDefaults

    var hasSeenChecklist: Bool { defaults.bool(forKey: Self.seenKey) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completed = Set(defaults.stringArray(forKey: Self.completedKey) ?? [])
    }

    func markSeen() {
        defaults.set(true, forKey: Self.seenKey)
    }

    func setCompleted(_ id: String, _ value: Bool) {
        guard Self.items.contains(where: { $0.id == id }) else { return }
        if value {
            completed.insert(id)
        } else {
            completed.remove(id)
        }
        defaults.set(Array(completed).sorted(), forKey: Self.completedKey)
    }

    func isCompleted(_ id: String) -> Bool {
        completed.contains(id)
    }
}
