# Agent Island 竞品源码结构与功能效果矩阵

日期：2026-07-09  
源码复制区：[code-study](research/competitors/code-study)  
旧版代码级报告：[code-comparison.md](research/competitors/code-comparison.md)

## 结论先行

当前最值得引入的不是另一个通用 Notch UI，而是一个更真实的 **Agent Session 状态层**。

建议顺序：

| 优先级 | 目标 | 最适合参考/复用的项目 | 原因 |
| --- | --- | --- | --- |
| P0 | 让“工作中/完成/待人处理”真实 | Ping Island + pi-island | Ping 有完整 `SessionStore`/`SessionPhase`，pi-island 的 `activeToolCount` 最直接解决“进程在线不等于工作中” |
| P0 | 多会话能看出哪个是哪个 | Ping Island + AgentBro | 两者都以 session 为核心，而不是以 app/CLI 聚合为主 |
| P1 | 点击准确跳回窗口/终端/tmux | Ping Island + DevIsland + AgentBro | Ping/Dev 是 Swift 可迁移，AgentBro 覆盖 Rust 侧 edge cases |
| P1 | Codex App 真实状态 | Ping Island + AgentBro | 都有 `CodexAppServerMonitor` 思路，比只看 app-server 进程更可靠 |
| P2 | Claude/Codex approval 和 AskUserQuestion 闭环 | DevIsland + Ping Island | DevIsland 的 approval proxy 边界清晰，Ping 的 UI/状态更接近最终产品 |
| P2 | 完成/等待时灵动岛展开、可关闭、可再次进入 | Ping Island + AgentBro | Ping 有 completion queue/manual attention，AgentBro UI 组件边界清楚 |
| P3 | 刘海屏、多屏、hover/gesture 细节 | Ping Island + BoringNotch clean-room 重写 | Ping 可直接参考，BoringNotch 是 GPL，只能隔离参考 |

工程判断：先不要整块复制任何大文件。先把我们的单文件实现拆出 `Models / State / Providers / Focus / UI`，再按模块迁移。否则继续往 [main.swift](Sources/AgentIsland/main.swift) 里堆逻辑，会继续出现 Codex CLI/App、Claude CLI/App 互相误判的问题。

## 本地源码规模

| 项目 | 本地路径 | License 区域 | 文件数 | 大小 | 主要语言 | 迁移策略 |
| --- | --- | --- | ---: | ---: | --- | --- |
| pi-island | [permissive/pi-island](research/competitors/code-study/permissive/pi-island) | MIT，可复用 | 14 | 213 KB | TypeScript, mjs, Swift, C# | 复制状态生命周期思想，少量代码可直接移植；不迁移 WebView UI |
| DevIsland | [permissive/DevIsland](research/competitors/code-study/permissive/DevIsland) | MIT，可复用 | 24 | 277 KB | Swift | 可直接抽取/改造 approval、normalizer、terminal focus |
| AgentBro | [permissive/AgentBro](research/competitors/code-study/permissive/AgentBro) | Apache-2.0，可复用 | 23 | 675 KB | Rust, TSX | 不直接引入技术栈；翻译后端状态和 terminal edge cases，复刻 UI 边界 |
| Ping Island | [permissive/PingIsland](research/competitors/code-study/permissive/PingIsland) | Apache-2.0，可复用 | 23 | 793 KB | Swift | 最值得作为目标架构参考；分模块迁移，避免整块搬入 |
| BoringNotch | [gpl-reference/BoringNotch](research/competitors/code-study/gpl-reference/BoringNotch) | GPL-3.0，隔离参考 | 10 | 116 KB | Swift | 不直接复制进产品；只 clean-room 重写屏幕/手势模式 |

我们的当前结构：

| 项目 | 文件 | 行数 | 当前问题 |
| --- | --- | ---: | --- |
| Agent Island | [Sources/AgentIsland/main.swift](Sources/AgentIsland/main.swift) | 2891 | 状态、provider、UI、窗口、跳转都在一个文件，继续扩展会放大误判和交互问题 |

## 工作目录结构对比

### 当前 Agent Island

```text
Sources/AgentIsland/
  main.swift
```

实际包含：

| 代码区域 | 入口 | 当前作用 | 缺口 |
| --- | --- | --- | --- |
| 状态枚举 | `AgentPhase` | 在线/工作中/待处理/完成/异常 | 不能表达 pending approval、AskUserQuestion、completion ready、manual attention 的差别 |
| 快照模型 | `AgentSnapshot` | UI 展示的 agent 行 | 聚合偏 surface，不够 session-first |
| 事件入口 | `AgentEvent` + `events.jsonl` | Claude/Codex bridge 写入事件 | 缺 append-only event ledger 和 reducer |
| 监控器 | `AgentMonitor` | ps/db/AX/events 混合刷新 | 推断层和真实事件层耦合 |
| 跳转 | `AgentLauncher.focus` | 尝试打开/激活 app 或终端 | 缺 `JumpTarget`，tmux/window/browser tab 不够稳定 |
| UI | `IslandView` | 灵动岛展示和交互 | hover 展开/自动展开/完成提示缺统一交互状态机 |

### pi-island

```text
permissive/pi-island/
  pi-extension/
    index.ts
    companion.mjs
    island.html.mjs
    socket-path.mjs
    platform.mjs
  hosts/
    macos/island-host.swift
```

| 目录/文件 | 功能效果 | 对我们的价值 | 复用方式 |
| --- | --- | --- | --- |
| [pi-extension/index.ts](research/competitors/code-study/permissive/pi-island/pi-extension/index.ts) | 监听 agent extension 生命周期，维护 `activeToolCount`，把 tool start/end 映射成 island rows | 直接解决“在线不代表工作中”；工作状态应来自活跃工具数和 hook 生命周期 | 复制思想，按 Swift reducer 重写 |
| [pi-extension/companion.mjs](research/competitors/code-study/permissive/pi-island/pi-extension/companion.mjs) | daemon/socket 中转，多 session rows | 可作为未来 browser extension/CLI bridge 中转模式 | 暂不引入 Node companion；保留 Python bridge + Swift socket |
| [pi-extension/island.html.mjs](research/competitors/code-study/permissive/pi-island/pi-extension/island.html.mjs) | HTML capsule 动画和 row upsert/remove | 动画生命周期可参考 | 不建议迁移 WebView UI |
| `hosts/macos` | 原生透明窗口 + WebView | notch window 的 host 经验 | 只参考窗口层，不改 UI 技术栈 |

### DevIsland

```text
permissive/DevIsland/DevIsland/
  Approval/
  Bridge/
  Provider/
  Session/
  Terminal/
  UI/
```

| 目录 | 关键文件 | 功能效果 | 对我们的价值 | 复用方式 |
| --- | --- | --- | --- | --- |
| `Approval/` | [ApprovalProxyController.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Approval/ApprovalProxyController.swift), [ApprovalPolicyEngine.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Approval/ApprovalPolicyEngine.swift), [SQLiteApprovalStore.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Approval/SQLiteApprovalStore.swift) | 拦截 approval/question，排队、展示、返回 allow/deny/updatedInput | 用户说的“allow 不是异常，是需要人推进”应该用这类 pending request 模型表达 | P2 引入；先不要自动审批 |
| `Bridge/` | [HookSocketServer.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Bridge/HookSocketServer.swift), [HookEventNormalizer.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Bridge/HookEventNormalizer.swift), [HookResponse.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Bridge/HookResponse.swift) | socket 接收 hook，并归一化 provider payload | 我们需要把 `events.jsonl`、socket、Codex app-server、ChatGPT probe 汇到统一事件模型 | P1 可先复制/改小版 status-only socket |
| `Provider/` | [ProviderAdapter.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Provider/ProviderAdapter.swift), Claude/Codex/Gemini handlers | UI 决策和 provider 输出格式分离 | 避免 UI 里写 Claude/Codex 的 JSON 差异 | P2 引入 |
| `Session/` | [SessionStore.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Session/SessionStore.swift), [SessionTypes.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Session/SessionTypes.swift) | session/pending/terminal context | 可用于小型 session store 设计 | P0/P1 参考，但 Ping 更完整 |
| `Terminal/` | [TerminalFocuser.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Terminal/TerminalFocuser.swift) | iTerm/Terminal/Ghostty/tmux/IDE 回跳 | 解决“点击某个会话跳不回去” | P1 直接迁移/改造 |
| `UI/` | NotchView/NotchWindowController | approval UI + notch window | 可参考窗口定位和 pending 展示 | UI 只借边界，不整块搬 |

### Ping Island

```text
permissive/PingIsland/PingIsland/
  Core/
  Models/
  Services/
    Codex/
    Hooks/
    State/
    Tmux/
    Window/
  UI/
    Views/
    Window/
```

| 目录 | 关键文件 | 功能效果 | 对我们的价值 | 复用方式 |
| --- | --- | --- | --- | --- |
| `Models/` | [SessionPhase.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Models/SessionPhase.swift), [SessionState.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Models/SessionState.swift), [SessionEvent.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Models/SessionEvent.swift) | 明确表达 processing、pending permission、waiting input、completion、manual attention | 状态真实性的核心 | P0 优先迁移精简版 |
| `Services/State/` | [SessionStore.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/State/SessionStore.swift), [ToolEventProcessor.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/State/ToolEventProcessor.swift) | actor reducer，把 hook/tool/session 事件变成稳定状态 | 最适合替代当前散落推断 | P0 参考架构，不整文件复制 |
| `Services/Hooks/` | [HookSocketServer.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Hooks/HookSocketServer.swift) | 多 provider hook socket | 比我们的 status-only bridge 更完整 | P1 精简迁移 |
| `Services/Codex/` | [CodexAppServerMonitor.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Codex/CodexAppServerMonitor.swift), [CodexRolloutParser.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Codex/CodexRolloutParser.swift) | 连接 Codex app-server，thread 级 pending/response/live sync | 解决 Codex App 被误标成 Codex CLI 的根问题之一 | P1/P2 迁移 |
| `Services/Tmux/` | [TmuxController.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Tmux/TmuxController.swift), [TmuxSessionMatcher.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Tmux/TmuxSessionMatcher.swift) | tmux pane/session 匹配和跳转 | CLI 场景必需 | P1 迁移 |
| `Services/Window/` | [TerminalSessionFocuser.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Window/TerminalSessionFocuser.swift), [WindowFocuser.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Window/WindowFocuser.swift) | 精确找回 terminal/app/IDE window | 点击跳转的主参考 | P1 迁移 |
| `Core/` | [NotchGeometry.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Core/NotchGeometry.swift), [ScreenNotchMetrics.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Core/ScreenNotchMetrics.swift) | 刘海屏/非刘海屏/多屏 geometry | 解决被 macOS 菜单栏/刘海遮挡 | P1 迁移 |
| `UI/Views/` | [NotchView.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/UI/Views/NotchView.swift), [SessionListView.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/UI/Views/SessionListView.swift), [SessionCompletionNotificationView.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/UI/Views/SessionCompletionNotificationView.swift) | completion queue、manual attention、session list、通知展开 | 解决“完成后展开太久/不能关闭/hover 抖动” | P1/P2 参考交互重写 |

### AgentBro

```text
permissive/AgentBro/
  src-tauri/src/
    agents/
    hooks/
    terminal/
    platform/
  src/components/notch/
```

| 目录 | 关键文件 | 功能效果 | 对我们的价值 | 复用方式 |
| --- | --- | --- | --- | --- |
| `src-tauri/src/hooks/` | [server.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/hooks/server.rs), [session_store.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/hooks/session_store.rs), [tool_processor.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/hooks/tool_processor.rs) | Rust hook server、pending permission/question/plan、active tools、任务列表 | edge case 和测试价值高 | 翻译状态字段/测试用例，不引 Rust |
| `src-tauri/src/agents/` | [claude_code.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/agents/claude_code.rs), [codex.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/agents/codex.rs), [codex_app_server.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/agents/codex_app_server.rs) | provider 检测和 app-server 处理 | 用来补 provider edge cases | 翻译，不直接复制 |
| `src-tauri/src/terminal/` | [jump.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/terminal/jump.rs), [tmux.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/terminal/tmux.rs), [process_tree.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/terminal/process_tree.rs) | terminal/tmux/process tree 跳转 | 解决跳转不准 | 翻译为 Swift `Focus/` |
| `src/components/notch/` | [CollapsedBar.tsx](research/competitors/code-study/permissive/AgentBro/src/components/notch/CollapsedBar.tsx), [HoverList.tsx](research/competitors/code-study/permissive/AgentBro/src/components/notch/HoverList.tsx), [ApprovalBar.tsx](research/competitors/code-study/permissive/AgentBro/src/components/notch/ApprovalBar.tsx), [CompletionPanel.tsx](research/competitors/code-study/permissive/AgentBro/src/components/notch/CompletionPanel.tsx), [NotchPanel.tsx](research/competitors/code-study/permissive/AgentBro/src/components/notch/NotchPanel.tsx) | UI 组件边界清晰 | 我们的 SwiftUI 也应拆成这些概念 | 用 SwiftUI 复刻组件边界 |

### BoringNotch

```text
gpl-reference/BoringNotch/boringNotch/
  ContentView.swift
  BoringViewCoordinator.swift
  extensions/
  managers/
  observers/
```

| 文件/目录 | 功能效果 | 对我们的价值 | 复用边界 |
| --- | --- | --- | --- |
| [BoringViewCoordinator.swift](research/competitors/code-study/gpl-reference/BoringNotch/boringNotch/BoringViewCoordinator.swift) | 统一管理 expanded/sneak peek/timers | hover 展开抖动可参考 | GPL，不直接复制 |
| [NSScreen+UUID.swift](research/competitors/code-study/gpl-reference/BoringNotch/boringNotch/extensions/NSScreen+UUID.swift) | 多屏幕 UUID 偏好 | 多屏兼容 | clean-room 重写 |
| [PanGesture.swift](research/competitors/code-study/gpl-reference/BoringNotch/boringNotch/extensions/PanGesture.swift), `DragDetector` | 手势/拖拽/滚动区域识别 | 展开/关闭交互 | clean-room 重写 |
| `NotchSpaceManager` | notch 占位空间/布局协调 | 刘海和菜单栏避让 | clean-room 重写 |

## 功能效果矩阵

| 功能/效果 | 当前 Agent Island | pi-island | DevIsland | Ping Island | AgentBro | BoringNotch | 推荐结论 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 在线检测 | 有，基于进程/app/server | 较弱 | 较弱 | 有 | 有 | 无 | 在线只能做 fallback，不能等于工作中 |
| 真正工作中 | 混合推断，仍会误判 | `activeToolCount` 很强 | hook/pending 中等 | `SessionStore + ToolEventProcessor` 强 | `active_tools + phase` 强 | 无 | P0 引入 active tool reducer |
| 本轮完成 | 有，但偶尔不真实 | agent_end/done 生命周期清楚 | 有 session close/approval pass | completion ready/queue 强 | completion panel 强 | 无 | P0 用 session lifecycle 改造完成判断 |
| 需要人处理 | 现在会误显示异常/待处理 | 基础 | approval/question 最强 | pending/manual attention 强 | pending permission/question/plan 强 | 无 | P1/P2 改为 pending request，不归类异常 |
| 多会话身份 | 已补 thread/session 标题，但仍聚合 | 每 session row | session-first | session-first | session-first | 无 | P0 UI 和状态都改成 session-first |
| Codex App 状态 | 有 DB/app-server 推断 | 无 | provider 层有 Codex hook | `CodexAppServerMonitor` 强 | `codex_app_server.rs` 强 | 无 | P1 引入 Codex app-server thread 级同步 |
| Codex CLI 状态 | 有 | 无 | 有 | 有 | 有 | 无 | 用 hook lifecycle 替代进程推断 |
| Claude App/CLI 区分 | 已做进程祖先修正，但还要完善 | 无 | Claude hook 强 | Claude hook 强 | Claude hook 强 | 无 | 继续用 ancestry + hook pid + session target |
| Claude Science | 当前有初步探测 | 无 | 无 | provider 可扩展 | provider 可扩展 | 无 | 放到 provider registry，不写死在 UI |
| ChatGPT App | AX/UI 推断，不稳定 | 无 | 无 | 无明显强项 | 无明显强项 | 无 | 竞品弱点；我们需要单独做 App/Browser probe |
| ChatGPT Web | 浏览器 tab 推断弱 | 无 | 无 | 无 | 无 | 无 | 差异化功能，应做浏览器 extension/content script |
| 点击跳转 App | best-effort | host 级别 | 有 | 有 | 有 | 无 | P1 统一 `JumpTarget` |
| 点击跳转 CLI/tmux | 不稳定 | 无 | `TerminalFocuser` 强 | `TerminalSessionFocuser + Tmux` 强 | `jump.rs + tmux.rs` 强 | 无 | P1 引入 terminal/tmux focuser |
| hover 展开 | 有，但会重复展开/抖动 | HTML 动画 | 基础 | 有 attention/completion 状态路由 | React 组件清楚 | 手势经验强 | P1 需要 `ExpansionController` |
| 完成后自动展开 | 有，但过久/不可控 | done/retract 清楚 | 基础 | completion queue 强 | completion panel 强 | sneak peek timer 可参考 | 增加“短暂展开 + close + 已读”状态 |
| 上下滑动列表 | 已修过，但可继续优化 | row list | session list | session list 强 | hover list 强 | 无 | 用固定高度 scroll container |
| 多屏/刘海避让 | 有基础，但仍会遮挡 | host 有经验 | notch window | `ScreenNotchMetrics` 强 | display.rs | 强但 GPL | P1 引 Ping geometry，Boring clean-room |
| 持久化审计 | `events.jsonl` 简单 | 配置文件 | SQLite 强 | session store 内存 + logs | store + tests | 无 | P2 审批/状态事件落 SQLite |
| 打包开源 | SwiftPM 简单 | 多 host | native Swift | package/docs 较成熟 | Tauri 复杂 | GPL 风险 | 保持 SwiftPM，补 release scripts |

## 可引入/复用清单

| 优先级 | 要引入的能力 | 来源文件 | 复制方式 | 预期效果 | 风险 |
| --- | --- | --- | --- | --- | --- |
| P0 | `SessionPhase` 精细状态 | Ping [SessionPhase.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Models/SessionPhase.swift), AgentBro [session_store.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/hooks/session_store.rs) | 直接迁移 Swift 思路，字段精简 | `needsAttention`、`waitingInput`、`approvalPending`、`completed` 不再混淆 | 需要改 UI 文案映射 |
| P0 | active tool count reducer | pi-island [index.ts](research/competitors/code-study/permissive/pi-island/pi-extension/index.ts), Ping [ToolEventProcessor.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/State/ToolEventProcessor.swift) | Swift 重写 | 进程在线不再被误判为工作中；tool start/end 才决定工作态 | hook 缺事件时需要 fallback |
| P0 | `SessionStore` actor reducer | Ping [SessionStore.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/State/SessionStore.swift) | 不整文件复制，抽最小版 | 多会话和状态变化可预测 | Ping 文件 4963 行，直接搬会过重 |
| P0 | session-first UI 数据 | Ping [SessionState.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Models/SessionState.swift), AgentBro UI | Swift 模型重写 | 多个 Codex/Claude 会话能看出哪个对话 | 需要兼容现有 `AgentSnapshot` |
| P1 | `HookSocketServer` | DevIsland [HookSocketServer.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Bridge/HookSocketServer.swift), Ping [HookSocketServer.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Hooks/HookSocketServer.swift) | 先复制/精简 status-only | 减少文件轮询延迟，为 approval 闭环铺路 | socket 生命周期/权限要处理 |
| P1 | Hook event normalizer | DevIsland [HookEventNormalizer.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Bridge/HookEventNormalizer.swift), Ping [SessionEvent.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Models/SessionEvent.swift) | Swift 合并重写 | Claude/Codex/Gemini/ChatGPT 事件进入统一模型 | provider edge cases 多 |
| P1 | Codex app-server monitor | Ping [CodexAppServerMonitor.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Codex/CodexAppServerMonitor.swift), AgentBro [codex_app_server.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/agents/codex_app_server.rs) | 以 Ping 为主迁移 | Codex App/CLI 区分更真实，thread pending 更准 | Codex app-server 协议会变化 |
| P1 | terminal/tmux jump | Ping [TerminalSessionFocuser.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Window/TerminalSessionFocuser.swift), DevIsland [TerminalFocuser.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Terminal/TerminalFocuser.swift), AgentBro [jump.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/terminal/jump.rs) | Swift 迁移 + edge case 对照 | 点击某个会话能跳回对应 terminal/tmux pane | AppleScript/AX 权限 |
| P1 | notch geometry/multi-screen | Ping [ScreenNotchMetrics.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Core/ScreenNotchMetrics.swift), [NotchGeometry.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Core/NotchGeometry.swift) | 可直接迁移改造 | 兼容刘海屏、外接屏、不同尺寸 Mac | 需要真机截图验证 |
| P1 | hover/auto-expand controller | Ping [NotchView.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/UI/Views/NotchView.swift), BoringNotch GPL 参考 | SwiftUI 重写，不复制 GPL | 防止 hover 多次触发、完成提示可关闭 | 交互需要细调 |
| P2 | approval proxy | DevIsland `Approval/`, Ping pending handling | 迁移前先做 status-only socket | allow/deny/AskUserQuestion 变成“需要推进”，不是异常 | 不能默认自动批准 |
| P2 | completion notification queue | Ping [SessionCompletionNotificationView.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/UI/Views/SessionCompletionNotificationView.swift), AgentBro [CompletionPanel.tsx](research/competitors/code-study/permissive/AgentBro/src/components/notch/CompletionPanel.tsx) | SwiftUI 重写 | 完成后短暂展开、可关闭、已读后不反复打扰 | 需要和 hover 点击不冲突 |
| P2 | UI 组件边界 | AgentBro [src/components/notch](research/competitors/code-study/permissive/AgentBro/src/components/notch), Ping `UI/Views` | SwiftUI 重写 | `CollapsedBar`、`SessionList`、`AttentionCard`、`CompletionCard` 分离 | 纯重构，短期视觉变化有限 |
| P3 | screen UUID/gesture | BoringNotch [extensions](research/competitors/code-study/gpl-reference/BoringNotch/boringNotch/extensions) | clean-room 重写 | 多屏偏好和手势更稳 | GPL，不可直接复制 |

## 不建议直接引入的内容

| 内容 | 来源 | 不建议原因 | 替代方案 |
| --- | --- | --- | --- |
| 整个 Ping `SessionStore.swift` | Ping Island | 4963 行，provider 覆盖太宽，直接搬会带来大量未验证路径 | 抽出最小 reducer：session lifecycle、tool count、pending、completion |
| 整个 AgentBro Rust/Tauri 后端 | AgentBro | 技术栈不匹配，会把 SwiftPM app 变成 Tauri/Rust 架构 | 翻译状态模型和测试场景 |
| pi-island WebView capsule | pi-island | 我们已有 SwiftUI 原生 UI，WebView 会增加窗口/IPC/渲染复杂度 | 只借动画生命周期和 row upsert 思路 |
| DevIsland approval 自动接管 | DevIsland | 一旦 hook response 出错，会影响真实 Claude/Codex 工作流 | 先 status-only，再人工确认后启用 approval proxy |
| BoringNotch GPL Swift 文件 | BoringNotch | GPL-3.0 直接混入会影响开源许可证策略 | 隔离参考，按行为 clean-room 重写 |

## 建议目标目录结构

把当前 [main.swift](Sources/AgentIsland/main.swift) 拆成下面的产品结构，再逐步迁移竞品代码。

```text
Sources/AgentIsland/
  App/
    AgentIslandApp.swift
    AppDelegate.swift

  Models/
    AgentFamily.swift
    AgentSurface.swift
    SessionPhase.swift
    SessionState.swift
    SessionEvent.swift
    JumpTarget.swift

  Services/
    Events/
      EventLedger.swift
      HookEventNormalizer.swift
      ToolEventReducer.swift
      SessionStore.swift
    Providers/
      CodexAppMonitor.swift
      CodexThreadIndex.swift
      ClaudeProjectIndex.swift
      ClaudeScienceProbe.swift
      ChatGPTAppProbe.swift
      ChatGPTBrowserProbe.swift
    Hooks/
      HookSocketServer.swift
      BridgeInstaller.swift
    Focus/
      AgentLauncher.swift
      AppFocuser.swift
      TerminalFocuser.swift
      TmuxFocuser.swift
      BrowserFocuser.swift
    Screen/
      ScreenNotchMetrics.swift
      IslandGeometry.swift

  UI/
    IslandView.swift
    CollapsedBar.swift
    SessionListView.swift
    SessionRow.swift
    AttentionCard.swift
    CompletionCard.swift
    ExpansionController.swift
    Window/
      IslandPanelController.swift
```

对应竞品来源：

| 目标目录 | 来源 |
| --- | --- |
| `Models/SessionPhase.swift` | Ping `SessionPhase.swift` + AgentBro `SessionPhase` |
| `Models/SessionState.swift` | Ping `SessionState.swift` + AgentBro pending fields |
| `Services/Events/SessionStore.swift` | Ping actor reducer 精简版 |
| `Services/Events/ToolEventReducer.swift` | pi-island `activeToolCount` + Ping `ToolEventProcessor` |
| `Services/Hooks/HookSocketServer.swift` | DevIsland/Ping Swift socket |
| `Services/Providers/CodexAppMonitor.swift` | Ping `CodexAppServerMonitor` |
| `Services/Focus/TerminalFocuser.swift` | Ping/DevIsland Swift + AgentBro edge cases |
| `Services/Screen/ScreenNotchMetrics.swift` | Ping 可迁移，BoringNotch 只参考 |
| `UI/ExpansionController.swift` | Ping completion/manual attention + BoringNotch timing 思路 clean-room |

## 分阶段迁移计划

| 阶段 | 做什么 | 交付效果 | 不做什么 |
| --- | --- | --- | --- |
| Phase 1 | 拆 `main.swift`，新增 `SessionEvent/SessionState/SessionStore/ToolEventReducer`，继续读现有 `events.jsonl` | 工作中/完成/待人处理开始基于 session event，不再主要基于在线状态 | 不接管 approval response |
| Phase 2 | 引入 Swift `HookSocketServer` status-only，Python bridge 同时写 socket + jsonl fallback | 状态延迟下降，事件模型统一 | 不自动 allow/deny |
| Phase 3 | 引入 `JumpTarget`、Terminal/tmux focuser、Codex app-server monitor | 点击某个会话跳回对应窗口；Codex App/CLI 区分更准 | 不做大 UI 改版 |
| Phase 4 | 重构 UI 为 collapsed/session/attention/completion，加入 close/acknowledge/hover debounce | 完成或待处理时自动短暂展开，可关闭，不会 hover 重复展开 | 不使用 WebView |
| Phase 5 | approval/question 闭环：Claude/Codex allow、deny、AskUserQuestion answer | `allow`/询问显示为“需要推进”，可以直接在岛上处理 | 不默认自动批准，不隐藏原终端流程 |
| Phase 6 | ChatGPT App/Web 独立 probe | ChatGPT 回答中/完成/等待用户输入更可靠 | 不把 AX 推断当高置信度真相 |

## 针对当前几个痛点的直接映射

| 用户看到的问题 | 应引入的模块 | 为什么 |
| --- | --- | --- |
| Codex App 工作却显示 Codex CLI | `SessionEvent.sourceProcess + AgentSurface + CodexAppMonitor` | 用事件 pid 祖先和 app-server thread，而不是只看工具名/进程名 |
| Claude App 被显示成 Claude CLI | `HookEventNormalizer + SessionTarget` | surface 必须来自实际 hook 进程链或 app session，不来自 provider 名称 |
| `allow` 显示异常 | `PendingRequest / approvalPending` | allow 是人工审批状态，不是 error |
| 已完成不真实 | `activeToolCount + completion grace + stale timeout` | 完成必须来自 tool/session lifecycle，不能只来自“近期没有新事件” |
| 多个会话看不出哪个是哪个 | `SessionState.title/project/threadId` | 每行显示 conversation title/project/session short id，而不是只显示 Codex/Claude |
| hover 展开两次/多次 | `ExpansionController` | hover、completion、manual attention、click pin 必须走一个状态机 |
| 完成后展开太久且不能关闭 | `CompletionNotificationQueue + acknowledge` | 完成提示应短暂出现，可关闭，已读后不重复 |
| 被刘海/菜单栏遮挡 | `ScreenNotchMetrics + IslandGeometry` | 按屏幕 notch/menu safe area 计算，而不是固定 top offset |
| 点击跳转不准 | `JumpTarget + TerminalFocuser + TmuxFocuser + AppFocuser` | 不同 agent surface 需要不同跳转策略 |
| ChatGPT App/Web 检测不准 | `ChatGPTAppProbe + BrowserProbe` | 竞品都弱，需单独建设；AX 只能低置信度 fallback |

## 推荐下一步

我建议下一步直接开始 Phase 1，而不是继续研究：

1. 把 `AgentPhase`/`AgentSnapshot`/`AgentEvent` 从 [main.swift](Sources/AgentIsland/main.swift) 拆到 `Models/`。
2. 新增 `SessionPhase`，状态至少包含：
   - `idle`
   - `working`
   - `waitingApproval`
   - `waitingInput`
   - `completed`
   - `blocked`
   - `error`
3. 新增 `ToolEventReducer`，把 active tool start/end 作为工作态主依据。
4. 新增 `SessionStore`，让 `events.jsonl` 先进入 reducer，再输出 UI snapshots。
5. 保持 UI 外观不大改，只把底层状态先换掉。

这样最直接修复当前“在线/完成/待处理不真实”的核心问题，也为后续点击跳转和 ChatGPT 检测留下正确结构。
