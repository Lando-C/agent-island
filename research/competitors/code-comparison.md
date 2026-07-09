# Agent Island 代码级竞品对比

日期：2026-07-09  
复制源码目录：[code-study](research/competitors/code-study)

补充迁移决策表：[structure-function-matrix.md](research/competitors/structure-function-matrix.md)

## 本次实际复制的代码

### 可复用许可证代码

| 项目 | License | 已复制重点 | 本地路径 |
| --- | --- | --- | --- |
| pi-island | MIT | macOS native host、companion、socket、extension lifecycle、HTML capsule | [permissive/pi-island](research/competitors/code-study/permissive/pi-island) |
| DevIsland | MIT | approval proxy、provider adapter、hook socket、session store、terminal focus、notch window | [permissive/DevIsland](research/competitors/code-study/permissive/DevIsland) |
| AgentBro | Apache-2.0 | Tauri hook server、session store、Codex/Claude adapters、terminal jump、React notch UI | [permissive/AgentBro](research/competitors/code-study/permissive/AgentBro) |
| Ping Island | Apache-2.0 | Hook socket、SessionStore、Codex app-server、terminal focus、tmux、notch UI/window | [permissive/PingIsland](research/competitors/code-study/permissive/PingIsland) |

### GPL 隔离参考代码

| 项目 | License | 已复制重点 | 本地路径 |
| --- | --- | --- | --- |
| BoringNotch | GPL-3.0 | hover、gesture、screen UUID、notch space、view coordinator | [gpl-reference/BoringNotch](research/competitors/code-study/gpl-reference/BoringNotch) |

GPL 代码已经复制，但只放在 `gpl-reference`，不被 `Package.swift` 引用。要直接进产品，需要接受 GPL 分发义务。

## 当前 Agent Island 代码现状

当前主实现基本集中在一个文件：

- [main.swift](Sources/AgentIsland/main.swift)

关键结构：

- `AgentPhase`：[main.swift](Sources/AgentIsland/main.swift:72)
- `AgentSnapshot`：[main.swift](Sources/AgentIsland/main.swift:122)
- `AgentLauncher.focus`：[main.swift](Sources/AgentIsland/main.swift:221)
- `AgentMonitor`：[main.swift](Sources/AgentIsland/main.swift:544)
- `IslandView`：[main.swift](Sources/AgentIsland/main.swift:1657)
- `AppDelegate`/panel：[main.swift](Sources/AgentIsland/main.swift:2261)

优点：

- 单文件，容易快速迭代。
- 已经覆盖 Codex、Claude、Claude Science、ChatGPT App/Web 的初步探测。
- 已经有 `events.jsonl` 外部事件入口。
- UI 和打包简单。

主要问题：

- Provider 逻辑、状态机、UI、窗口定位、跳转逻辑都在一个文件里，后续难以扩展。
- `AgentSnapshot` 是结果模型，但缺少 append-only event ledger 和 reducer。
- 当前 hooks 只是 status-only，没有完整 request/response 生命周期，因此无法像 DevIsland/Ping Island 那样直接处理 approval/question。
- 跳转是 best-effort focus，没有统一 `JumpTarget` 模型。
- ChatGPT App/Web 依赖 UI 推断，缺少 browser extension/app watcher 的更稳定事件源。

## pi-island 对比

核心文件：

- [index.ts](research/competitors/code-study/permissive/pi-island/pi-extension/index.ts)
- [companion.mjs](research/competitors/code-study/permissive/pi-island/pi-extension/companion.mjs)
- [island-host.swift](research/competitors/code-study/permissive/pi-island/hosts/macos/island-host.swift)
- [AGENT.md](research/competitors/code-study/permissive/pi-island/AGENT.md)

pi-island 的设计是三段式：

```text
agent extension
  -> companion daemon
  -> native host window
  -> WebView HTML capsule
```

关键代码点：

- `toolToIsland()` 把工具名映射成 UI 状态：[index.ts](research/competitors/code-study/permissive/pi-island/pi-extension/index.ts:156)
- `activeToolCount` 作为工作中判断：[index.ts](research/competitors/code-study/permissive/pi-island/pi-extension/index.ts:206)
- tool start/end 后用 active count 回到 thinking/done，而不是看进程在线。
- companion 负责多 session rows 和 idle exit。
- Swift host 负责高层级窗口、notch/floating geometry、WebView IPC。

和我们的差异：

| 维度 | 当前 Agent Island | pi-island |
| --- | --- | --- |
| 事件源 | ps/log/db/Accessibility 混合轮询 | agent extension lifecycle |
| 多 session | 聚合成 snapshots | 每 session 一 row |
| “正在工作” | phase 推断 | active tool count |
| UI runtime | SwiftUI 原生 | Swift host + HTML/CSS |
| 架构复杂度 | 低 | 中 |

可复制吸收：

- `activeToolCount` 思路应该进入我们的 hook event reducer。
- `agent_end -> done -> retract` 的完成生命周期比现在更清晰。
- companion 模式值得用于未来 browser/remote bridge，但当前 Swift app 可以先不引入 Node companion。
- `~/.pi/pi-island.json` 这种独立配置文件思路可用于 `~/.agent-island/config.json`。

不建议复制：

- WebView HTML capsule。我们现在 SwiftUI 足够，改 WebView 会增加复杂度。

## DevIsland 对比

核心文件：

- [ApprovalPolicyEngine.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Approval/ApprovalPolicyEngine.swift)
- [ApprovalProxyController.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Approval/ApprovalProxyController.swift)
- [HookEventNormalizer.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Bridge/HookEventNormalizer.swift)
- [HookSocketServer.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Bridge/HookSocketServer.swift)
- [ProviderAdapter.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Provider/ProviderAdapter.swift)
- [SessionStore.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Session/SessionStore.swift)
- [TerminalFocuser.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/Terminal/TerminalFocuser.swift)
- [NotchWindowController.swift](research/competitors/code-study/permissive/DevIsland/DevIsland/UI/NotchWindowController.swift)

DevIsland 的强项是 approval proxy：

```text
CLI hook stdin
  -> bridge envelope
  -> HookSocketServer
  -> HookEventNormalizer
  -> ApprovalProxyController
  -> ProviderAdapter
  -> CLI-specific stdout JSON
```

关键差异：

| 维度 | 当前 Agent Island | DevIsland |
| --- | --- | --- |
| hook 角色 | status-only，永远 pass-through | approval proxy，可返回 allow/deny/updatedInput |
| provider 适配 | 简化在 Python bridge 和 Swift monitor 中 | `ProviderAdapter` + per-provider handler |
| 状态存储 | 读 `events.jsonl` 近期事件 | SQLite rules/session/hook_events/decisions |
| 用户输入 | 只显示状态 | PendingRequest 队列持有 response closure |
| AskUserQuestion | 没有完整回复链 | 可在 UI 回答并返回 updatedInput |

可复制吸收：

- `HookEventNormalizer` 的 provider event 归一化边界。
- `ProviderAdapter` 的输出分层：UI 只产生决策，adapter 负责转为 Claude/Codex/Gemini JSON。
- `ApprovalPolicyEngine` 的规则优先级：persistent deny > session deny > persistent allow > session allow > prompt。
- SQLite append-only `hook_events` 和 `approval_decisions` 适合我们后续状态真实性。

建议改造方案：

1. 先保留现有 `agent-island-bridge.py` status-only。
2. 新增 Swift 原生 `HookSocketServer`，但先只接收事件，不直接接管审批。
3. 新增 `NormalizedHookEvent` 和 `SessionStore`。
4. 第二阶段再做 approval response path，避免一次性替换现有 hooks 导致误批准/误拒绝。

## Ping Island 对比

核心文件：

- [SessionPhase.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Models/SessionPhase.swift)
- [SessionState.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Models/SessionState.swift)
- [SessionEvent.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Models/SessionEvent.swift)
- [SessionStore.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/State/SessionStore.swift)
- [ToolEventProcessor.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/State/ToolEventProcessor.swift)
- [HookSocketServer.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Hooks/HookSocketServer.swift)
- [CodexAppServerMonitor.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Codex/CodexAppServerMonitor.swift)
- [TerminalSessionFocuser.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/Services/Window/TerminalSessionFocuser.swift)
- [NotchView.swift](research/competitors/code-study/permissive/PingIsland/PingIsland/UI/Views/NotchView.swift)

Ping Island 是最值得对齐的目标架构。

它比 DevIsland 更像最终产品：

- 多 agent provider matrix。
- HookSocketServer 接收多种 hook payload。
- `SessionStore` 是 actor，做真实状态 reducer。
- `SessionPhase` 明确区分 pending、manual attention、completion、processing。
- `CodexAppServerMonitor` 处理 Codex App live thread。
- `TerminalSessionFocuser` 处理终端/tmux/IDE 回跳。
- Notch UI 里有 pending sessions、completion notification、manual attention 变化处理。

和我们的差异：

| 维度 | 当前 Agent Island | Ping Island |
| --- | --- | --- |
| 状态模型 | `AgentPhase` 简短枚举 | `SessionPhase` + `SessionState` 细粒度 |
| 并发模型 | `AgentMonitor` class + timer refresh | `actor SessionStore` |
| Codex App | app-server 是否在线 + goal DB 推断 | app-server WebSocket/thread 级同步 |
| 任务完成 | snapshot phase 推断 | completion ready/notification/session phase |
| 跳转 | bundle/host process best effort | terminal session focuser + tmux + window finder |
| UI 触发 | `onChange(snapshot)` spotlight | pending/completion/manual attention 专门处理 |

可复制吸收：

- `SessionPhase` 的状态细分思路。
- `SessionEvent.isAskUserQuestionRequest` 这类 provider-specific helper。
- `SessionStore` actor 模式。
- `CodexAppServerMonitor` 作为 Codex App 真实状态来源。
- `TerminalSessionFocuser` 的 jump-back 策略。
- Notch UI 不要只 hover 展开，而要按 attention/completion 状态路由展开。

风险：

- Ping Island 的 `SessionStore.swift` 很大，不能盲目整文件搬进来。应该提炼我们需要的状态机和 provider helpers。
- 它支持的 provider 很多，一次复制会引入大量边界情况。建议从 Claude/Codex/ChatGPT 三个主线先做。

## AgentBro 对比

核心文件：

- [hooks/server.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/hooks/server.rs)
- [hooks/session_store.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/hooks/session_store.rs)
- [agents/claude_code.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/agents/claude_code.rs)
- [agents/codex.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/agents/codex.rs)
- [agents/codex_app_server.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/agents/codex_app_server.rs)
- [terminal/jump.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/terminal/jump.rs)
- [terminal/tmux.rs](research/competitors/code-study/permissive/AgentBro/src-tauri/src/terminal/tmux.rs)
- [NotchPanel.tsx](research/competitors/code-study/permissive/AgentBro/src/components/notch/NotchPanel.tsx)
- [HoverList.tsx](research/competitors/code-study/permissive/AgentBro/src/components/notch/HoverList.tsx)
- [ApprovalBar.tsx](research/competitors/code-study/permissive/AgentBro/src/components/notch/ApprovalBar.tsx)

AgentBro 的强项是“工作台”和 provider 覆盖：

- Rust backend 把 agent detection、hook server、session store、terminal jump 分开。
- React UI 把 collapsed、hover list、approval bar、completion panel 分开。
- Hook server 有大量 provider edge cases。
- `session_store.rs` 已有 `SessionPhase` 和丰富状态字段。

和我们的差异：

| 维度 | 当前 Agent Island | AgentBro |
| --- | --- | --- |
| 技术栈 | SwiftPM/AppKit/SwiftUI | Tauri/Rust/React |
| UI 分层 | 一个 SwiftUI view | 多 React component |
| provider 管理 | 函数式探测 | per-agent module |
| hooks | Python bridge | Rust server |
| skills/MCP 管理 | 无 | 完整工作台 |

可复制吸收：

- 不建议复制 UI 技术栈，但可以复制组件边界：CollapsedBar、HoverList、ApprovalBar、CompletionPanel。
- Rust provider 逻辑不能直接进 Swift，但可以作为 event schema 和 edge-case 参考。
- `terminal/jump.rs` 和 `tmux.rs` 的场景覆盖值得翻译成 Swift。

## BoringNotch 对比

核心文件：

- [ContentView.swift](research/competitors/code-study/gpl-reference/BoringNotch/boringNotch/ContentView.swift)
- [BoringViewCoordinator.swift](research/competitors/code-study/gpl-reference/BoringNotch/boringNotch/BoringViewCoordinator.swift)
- [NSScreen+UUID.swift](research/competitors/code-study/gpl-reference/BoringNotch/boringNotch/extensions/NSScreen+UUID.swift)
- [MouseTracker.swift](research/competitors/code-study/gpl-reference/BoringNotch/boringNotch/extensions/MouseTracker.swift)
- [PanGesture.swift](research/competitors/code-study/gpl-reference/BoringNotch/boringNotch/extensions/PanGesture.swift)
- [NotchSpaceManager.swift](research/competitors/code-study/gpl-reference/BoringNotch/boringNotch/managers/NotchSpaceManager.swift)

BoringNotch 的价值是 UI/window 经验，不是 agent 逻辑。

可参考：

- hover 用 `Task` 延迟和取消，避免抖动。
- screen preference 使用 UUID。
- gesture/down/up 和 drag detector 分离。
- coordinator 统一管理 sneak peek、expanding view、HUD replacement。

不能直接吸收：

- GPL 源码不能直接复制进我们的 `Sources`，除非项目接受 GPL。
- 具体动画/手势实现可以重新设计同等功能，但不要逐行移植。

## 代码吸收建议

### 第一批可以直接重构进产品

目标：解决状态真实性和点击跳转，而不是先重做视觉。

建议新增 Swift 文件：

```text
Sources/AgentIsland/
  Models/
    NormalizedEvent.swift
    SessionPhase.swift
    SessionState.swift
    JumpTarget.swift
  Providers/
    ProviderKind.swift
    ClaudeProviderAdapter.swift
    CodexProviderAdapter.swift
    ChatGPTProviderAdapter.swift
  State/
    SessionStore.swift
    ToolEventReducer.swift
  Hooks/
    HookSocketServer.swift
  Window/
    TerminalFocuser.swift
    BrowserTabFocuser.swift
    AppFocuser.swift
```

来源映射：

- `NormalizedEvent` 参考 DevIsland `HookEventNormalizer` + Ping Island `SessionEvent`。
- `SessionPhase` 参考 Ping Island `SessionPhase`，保留我们中文状态映射。
- `SessionStore` 参考 Ping Island actor，但先实现 Claude/Codex/ChatGPT 最小集。
- `HookSocketServer` 参考 DevIsland，更小更安全。
- `TerminalFocuser` 参考 Ping Island + AgentBro jump/tmux。
- UI component 边界参考 AgentBro，但用 SwiftUI 重写。

### 第二批再做 approval/reply

等状态 reducer 稳定后，再接管 hook response：

- Claude `PermissionRequest` -> allow/deny。
- Claude `AskUserQuestion` -> updatedInput。
- Codex `PermissionRequest` -> allow/deny。
- Gemini `BeforeTool` -> allow/deny。

这里必须加“安全默认”：

- bridge 不可用时 pass-through 到原 agent。
- 默认不自动批准。
- 所有审批决策落 SQLite/event log。
- UI 超时策略要明确：deny、pass、或回到终端原生流程。

### 第三批做 ChatGPT App/Web

竞品里这块都偏弱，应该作为差异化：

- Browser extension/content script 提供 `streaming/idle/needs_input` 事件。
- ChatGPT App 用 Accessibility 低置信度推断。
- 状态显示必须标注 confidence。

## 需要避免的复制方式

不要把这些大文件整块塞进当前 app：

- Ping Island `SessionStore.swift`：太大，provider edge cases 太多。
- AgentBro `hooks/server.rs`：Rust/Tauri，不适合直接迁移。
- BoringNotch GPL 文件：不能进入 product build。
- pi-island WebView UI：会推翻当前 SwiftUI 架构，收益不够。

## 下一步具体实现优先级

1. 从 `main.swift` 拆 `AgentPhase`/`AgentSnapshot` 到 models。
2. 新增 `SessionPhase`，把 `needsAttention` 和 `error` 完全分离。
3. 新增 `NormalizedEvent`，让 `events.jsonl` 和 hooks 都进入同一个 reducer。
4. 新增 `SessionStore`，先支持 active tool count、completion grace、stale timeout。
5. 把 `AgentMonitor.refresh()` 改为：进程/db/accessibility snapshot + session store snapshot merge。
6. 新增 `JumpTarget`，替代当前 `AgentLauncher.focus(snapshot)` 的分散判断。
7. 再把 island UI 分成 `CollapsedHeader`、`SessionList`、`AttentionCard`、`CompletionCard`。
