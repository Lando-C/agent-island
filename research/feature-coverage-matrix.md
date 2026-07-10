# Agent Island 功能覆盖矩阵

日期：2026-07-10

## 本轮引入的参考源码

| 项目 | 本地路径 | 许可证/集成策略 | 本轮可复用结论 |
| --- | --- | --- | --- |
| Vibe Notch | `research/competitors/repos/new-20260709/vibe-notch` | Apache-2.0，可参考/复用架构 | hook socket、permission approval、chat history、tmux target、terminal visibility、notch geometry 都和我们方向一致 |
| MioIsland | `research/competitors/repos/new-20260709/MioIsland` | 本地快照未发现 LICENSE；仅参考，不直接并入开源主线源码 | HookSocketServer、CodexHookInstaller、HookHealthCheck、QuickReply、ProcessTree、Cmux、Sound/Theme/Customization 方向有价值 |
| Ping Island / DevIsland / AgentBro | `research/competitors/code-study/permissive` | permissive 区可参考；GPL 隔离区继续 clean-room | terminal/tmux 精确跳转的优先级应是 `tmux pane > tty > cwd/title > app activation` |

## 当前覆盖状态

| 功能 | 当前状态 | 代码位置 | 说明 / 下一步 |
| --- | --- | --- | --- |
| 刘海屏实时会话状态 | 部分完成 | `Sources/AgentIsland/main.swift`, `Sources/AgentIsland/State/SessionStore.swift` | 已区分 working/thinking/needs attention/done/online/idle/available/offline；`available` 只表示已安装，不再冒充在线；还需把 compaction、warning 作为内部 phase 明确化 |
| 状态真实性 | 部分完成 | `SessionStore.swift`, `scripts/codex-broker-probe` | active tool count、Codex broker/thread read 已接；仍需 rollout fallback、Claude App 多窗口会话绑定 |
| 点击跳转到 Codex App thread | 已完成基础 | `JumpTarget.url`, `codex://threads/{id}` | 已验证 open URL；多窗口仍依赖 Codex 自己路由 |
| ChatGPT App / Web 检测与跳转 | 部分完成 | `JumpTarget.chatGPTWeb`, `focusChatGPTWeb()` | 能聚焦 ChatGPT web tab/app；回答是否完成仍需浏览器 DOM/AX 状态探针 |
| Terminal / tmux 跳转 | 本轮完成基础 | `JumpTarget.terminal/.tmux`, `TerminalFocuser.swift`, `agent-island-bridge.py` | hook 写入 tty/tmux/app；点击优先 tmux pane，其次 iTerm/Terminal tty；Ghostty/Warp/WezTerm/kitty 已有 fallback，待深度优化 |
| Ghostty / Warp / WezTerm / kitty / cmux / Kaku | 部分完成 | `TerminalFocuser.swift` | Ghostty 已按 cwd/title 尝试，WezTerm 已按 pane/cwd/tty 尝试，kitty 已按 window/cwd 尝试；Warp/cmux/Kaku 仍先激活 app，后续迁移 Mio/AgentBro 深度实现 |
| 旧会话展示收敛 | 已完成基础 | `SessionRetentionPolicy`, broker visible filtering | done 10 分钟、idle/available 1 小时、waiting/error 12 小时后退出面板，broker 过滤内部线程；仍需 transcript fallback 和进程级僵尸检测 |
| 自动收起 / hover 抑制 | 已完成基础 | `IslandExpansionController.swift` | 已解决 hover 重复展开、spotlight 可关闭、手动展开不被 timer 关掉 |
| 完成/等待状态自动展开 | 已完成基础 | `IslandExpansionController.swift`, `IslandView.handleSnapshotChanges` | 已有 spotlight；还需 completion queue 和“稍后提醒/关闭本条”更细交互 |
| Hook 安装 Claude / Codex CLI | 已完成基础 | `scripts/install-hooks`, `scripts/agent-island-bridge.py` | Claude `~/.claude/settings.json` 和 Codex `~/.codex/hooks.json` status-only；下一步加诊断 UI 一键修复 |
| Claude Science | 已完成基础 | `makeClaudeScienceApp`, `makeClaudeScienceRuntime` | 已展示 app/runtime；需要更细的任务状态来源 |
| 权限审批 allow/deny | 部分完成 | `PendingRequestStore.swift`, `HookSocketServer.swift`, `agent-island-bridge.py` | Claude `PermissionRequest` 已可在岛内 allow/deny，并保留风险边界；Codex response schema 仍需验证后才能写回 |
| Codex request_user_input / 交互提问 | 部分完成 | `PendingRequestStore.swift`, `HookSocketServer.swift`, `IslandView` | 问题和选项已结构化显示并可复制；直接提交仍等待各引擎 response schema 验证 |
| 小窗快速推进 | 已完成基础 | `IslandView`, `AgentRow`, `SpotlightSummary`, `AgentSnapshotSummary` | 需处理/待推进/完成/异常行和 spotlight 已有“复制推进摘要 / 打开对应会话”；仍未做 allow/deny 和 request_user_input 写回 |
| 聊天记录 / 工具调用详情 | 部分完成 | broker compact details、conversation preview | 还不是完整详情页；下一步引入 hook-driven `ChatMessage` / `ToolCall` 存储 |
| 智能抑制 | 未完成 | 无 | 需要先有 `isSessionFrontmost`，不是简单 terminal frontmost；可参考 Vibe `TerminalVisibilityDetector` / DevIsland frontmost check |
| 僵尸检测 | 未完成 | 无 | 参考 Mio `ProcessLivenessChecker`，定期检查 pid/terminal/tmux pane；退出则标 ended |
| 声音提示 | 未完成 | 无 | 参考 Vibe `SoundSelector` / Mio `SoundManager`；默认关闭，按 start/done/approval/error 配置 |
| 离岛模式 / 浮动宠物 | 未完成 | 无 | 可放 P3；先不要影响核心状态准确性和点击跳转 |
| 动态吉祥物 / 多状态动画 | 未完成 | 无 | 可复用 Mio 的角色/主题思路，但不应先于状态/审批 |
| 刘海宽度设置 | 已完成基础 | `IslandPanelSizing`, `Sources/AgentIsland/UI/SettingsWindow.swift` | 已有待机/工作宽度设置并持久化；下一步是按屏幕保存和硬件刘海模式 |
| 开机自启 | 已完成基础 | `LaunchAtLoginController`, `SettingsWindow.swift` | 已有设置开关；公开发布前需在签名/notarization 下复测 |
| 设置页重构 / 诊断面板 | 已完成基础 | `Sources/AgentIsland/UI/SettingsWindow.swift` | 已有外观、系统、安全、诊断、路线五个 tab；下一步改为结构化诊断项和一键修复按钮 |
| 诊断导出 / 一键修复 | 已完成基础 | `scripts/agent-island-diagnostics`, `scripts/install-hooks`, `SettingsWindow.swift`, status menu | 已有菜单复制、设置页运行/复制、权限设置入口、Hook repair；下一步区分必需 FAIL、可修复 WARN、可选 capability |
| 全局快捷键 / Escape / approval 快捷键 | 已完成基础 | `AgentIslandControlKeys`, `AppDelegate.setupKeyMonitors`, `IslandView` | Escape 关闭、Option-N 切换；聚焦灵动岛时 ⌘Y/⌘N 可处理首个内联 Claude 审批请求 |
| 生产代码回归测试 | 已完成基础 | `Tests/AgentIslandTests`, `scripts/test-swift`, `.github/workflows/ci.yml` | 8 个 Swift 测试直接覆盖生产 `SessionStore`、`PendingRequestStore`、JSONL chunk 解码和 snapshot redraw 等价性；下一步补 broker fixture、跳转器和窗口级 UI 自动化 |
| 常驻性能 / 低功耗动效 | 已完成基础 | `AgentMonitor`, `AgentEventLogDecoder`, `ActivityBars` | Hook 日志增量读取、磁盘/浏览器 fallback 分层节流、仅语义变化发布 snapshot；动效从 60 fps repeatForever 改为低频离散更新并支持 Reduce Motion；活跃任务实测 45 秒平均约 8.5% CPU |
| 自动审批 | 部分完成 | `agent-island-bridge.py`, `docs/PRODUCT_BLUEPRINT.md` | 默认关闭；只读工具可 opt-in 自动通过 Claude PermissionRequest；危险工具永不自动通过；Codex 仍 status-only |

## 下一轮推荐顺序

1. `TerminalFocuser` 深化：Ghostty cwd/title、Warp sqlite tab、WezTerm pane env、kitty remote control、cmux surface、Kaku CLI。
2. Codex approval / request_user_input response schema 验证：从可见、可复制推进到可靠写回。
3. 快速推进第二版：对已验证 schema 直接提交选项；未验证引擎继续只复制/跳转。
4. 诊断页第二版：把纯文本报告升级成结构化可修复项，区分必需失败和可选能力缺口。
5. 进程级僵尸检测：pid/tmux pane/terminal target 不存在则 ended；时间过期策略只作为后备线。
6. 离岛/吉祥物/声音/宽度设置作为体验层，等状态和跳转稳定后推进。
