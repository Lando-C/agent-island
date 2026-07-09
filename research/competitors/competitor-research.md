# Agent Island 竞品调研

调研日期：2026-07-09  
本地目录：`research/competitors`

## 结论先行

Agent Island 不应该做成另一个通用 Mac 灵动岛。通用灵动岛市场已经有 BoringNotch、NotchNook、MediaMate、DynamicNotch、SuperIsland 这类产品，它们的优势是音乐、HUD、文件架、系统事件、动画和商业包装。我们的机会在更窄但更刚需的方向：**AI Agent Operations Island**。

核心定位应该是：

- 不是显示“在线”，而是判断 agent 的真实工作状态。
- 不是只弹通知，而是把“需要人推进”的审批、问题、计划确认、allow/deny、继续输入作为一等状态。
- 不是只看 Claude，而是统一 Claude Code、Codex CLI/App、ChatGPT App/Web、Gemini、Cursor、OpenCode、Pi、Qwen、Kimi 等 agent。
- 不是只展示任务，而是点一下能跳回对应终端、Codex/Claude/ChatGPT 窗口、浏览器 tab、tmux pane 或 IDE。
- 不是只靠进程检测，而是融合 hooks、session JSONL、app server、browser/app accessibility、terminal/tmux metadata、OpenTelemetry/token/quota 数据。

最值得参考的开源项目：

1. [Ping Island](https://github.com/erha19/ping-island) - 最接近我们的完整竞品，覆盖多 agent、审批、问答、跳回窗口、SSH remote、Codex app-server。
2. [AgentBro](https://github.com/shirenchuang/agentbro) - 与我们产品意图高度接近，Tauri + React + Rust，本地工作台、hook doctor、skills/agent 管理、宠物模式。
3. [DevIsland](https://github.com/nangchang/DevIsland) - 小星但架构非常对口，Swift 原生 approval proxy、SQLite 规则、hook normalizer、provider adapter。
4. [pi-island](https://github.com/phun333/pi-island) - 小而完整，展示了一个清晰的 extension -> companion -> native host -> WebView capsule 架构。
5. [BoringNotch](https://github.com/TheBoredTeam/boring.notch) - 通用灵动岛里星标很高，动画、notch/window、多屏/HUD/文件架值得参考，但 GPL-3.0 不能直接复制进非 GPL 项目。
6. [ClaudeBar](https://github.com/tddworks/ClaudeBar)、[TokenBar](https://github.com/Nanako0129/TokenBar)、[AI Token Monitor](https://github.com/soulduse/ai-token-monitor)、[Claude Code Usage Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) - 状态置信度、token/quota、rate limit、usage snapshots 值得作为我们“真实工作状态”的补充信号。

## 本地拉取状态

GitHub codeload 当时速度很慢，部分大仓库超时。已经落地和可检查的内容如下：

| 状态 | 仓库 | 本地路径 | 说明 |
| --- | --- | --- | --- |
| 完整源码快照 | TheBoredTeam/boring.notch | `research/competitors/repos/TheBoredTeam__boring.notch` | tarball 完整解包，有 `.agent-island-source.txt` |
| 完整源码快照 | phun333/pi-island | `research/competitors/repos/phun333__pi-island` | tarball 完整解包，有 `.agent-island-source.txt` |
| 部分快照 | shirenchuang/agentbro | `research/competitors/repos/shirenchuang__agentbro` | 下载超时，但 README、架构图、截图、license 可用 |
| Git 快照可读 | nangchang/DevIsland | `research/competitors/repos/nangchang__DevIsland-git` | checkout 不完整，但可用 `git show HEAD:<path>` 读取 README/docs |
| 元数据 | 28 个候选仓库 | `research/competitors/metadata.jsonl` | GitHub API 搜索结果，按 stars 排序 |

其余项目使用 GitHub 文件读取补齐 README 和架构信息。下载失败主要是网络吞吐和 codeload 超时，不是项目不可访问。

## 高星候选排序

星数来自本地保存的 GitHub API 元数据 `metadata.jsonl`，时间点为 2026-07-09。

| 排名 | 仓库 | Stars | 语言 | License | 相关性 |
| --- | --- | ---: | --- | --- | --- |
| 1 | [anthropics/claude-code](https://github.com/anthropics/claude-code) | 136,913 | Python | NOASSERTION | 上游 agent，不是竞品，但 hook/status 生态核心 |
| 2 | [hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) | 49,546 | Python | NOASSERTION | 生态索引 |
| 3 | [musistudio/claude-code-router](https://github.com/musistudio/claude-code-router) | 35,700 | TypeScript | MIT | Claude routing/usage 生态 |
| 4 | [jordanbaird/Ice](https://github.com/jordanbaird/Ice) | 28,756 | Swift | GPL-3.0 | 菜单栏管理，不是直接竞品 |
| 5 | [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) | 9,982 | Swift | GPL-3.0 | 通用灵动岛，高参考价值 |
| 6 | [stonerl/Thaw](https://github.com/stonerl/Thaw) | 8,429 | Swift | GPL-3.0 | macOS 菜单栏/系统体验 |
| 7 | [Maciek-roboblog/Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) | 8,411 | Python | MIT | usage/quota/status 快照 |
| 8 | [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) | 2,856 | Swift | GPL-3.0 | 通用灵动岛 |
| 9 | [tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar) | 1,296 | Swift | NOASSERTION | 多 provider quota 监控 |
| 10 | [erha19/ping-island](https://github.com/erha19/ping-island) | 953 | Swift | Apache-2.0 | 最接近我们的直接竞品 |
| 11 | [hoangsonww/Claude-Code-Agent-Monitor](https://github.com/hoangsonww/Claude-Code-Agent-Monitor) | 776 | TypeScript | MIT | Dashboard/Kanban/hook monitor |
| 12 | [chongdashu/cc-statusline](https://github.com/chongdashu/cc-statusline) | 621 | TypeScript | MIT | Claude statusline 字段设计 |
| 13 | [shobhit99/SuperIsland](https://github.com/shobhit99/SuperIsland) | 602 | Swift | NOASSERTION | 通用灵动岛 + extension |
| 14 | [crissNb/Dynamic-Island-Sketchybar](https://github.com/crissNb/Dynamic-Island-Sketchybar) | 527 | Shell | MIT | SketchyBar 视觉参考 |
| 15 | [MioMioOS/MioIsland](https://github.com/MioMioOS/MioIsland) | 511 | Swift | NOASSERTION | AI agent notch + iPhone sync |
| 16 | [rz1989s/claude-code-statusline](https://github.com/rz1989s/claude-code-statusline) | 462 | Shell | MIT | 高度可配置 statusline |
| 17 | [ColeMurray/claude-code-otel](https://github.com/ColeMurray/claude-code-otel) | 462 | Makefile | MIT | OpenTelemetry/Grafana 可观测性 |
| 18 | [mrkai77/DynamicNotchKit](https://github.com/mrkai77/DynamicNotchKit) | 430 | Swift | MIT | notch UI kit，可复用窗口抽象 |
| 19 | [Ido-Levi/claude-code-tamagotchi](https://github.com/Ido-Levi/claude-code-tamagotchi) | 430 | TypeScript | MIT | AI companion/pet 方向 |
| 20 | [jackson-storm/DynamicNotch](https://github.com/jackson-storm/DynamicNotch) | 428 | Swift | GPL-3.0 | 通用灵动岛/动画参考 |
| 21 | [soulduse/ai-token-monitor](https://github.com/soulduse/ai-token-monitor) | 269 | TypeScript | NOASSERTION | Claude/Codex/OpenCode token monitor |
| 22 | [shirenchuang/agentbro](https://github.com/shirenchuang/agentbro) | 184 | Rust | Apache-2.0 | 直接竞品，agent workspace |
| 23 | [AryanRogye/ComfyNotch](https://github.com/AryanRogye/ComfyNotch) | 145 | Swift | MIT | 通用 notch |
| 24 | [Nanako0129/TokenBar](https://github.com/Nanako0129/TokenBar) | 130 | Swift | MIT | 多 agent token/quota 监控 |
| 25 | [maddada/agent-manager-x](https://github.com/maddada/agent-manager-x) | 70 | Swift | NOASSERTION | agent 管理方向 |
| 26 | [phun333/pi-island](https://github.com/phun333/pi-island) | 25 | Swift | MIT | 小而完整的 agent island 架构 |
| 27 | [nangchang/DevIsland](https://github.com/nangchang/DevIsland) | 4 | Swift | MIT | 小星但架构高度可借鉴 |

## 竞品分组

### 1. 通用 Mac 灵动岛 / notch 产品

代表：

- [BoringNotch](https://github.com/TheBoredTeam/boring.notch)
- [DynamicNotch](https://github.com/jackson-storm/DynamicNotch)
- [SuperIsland](https://github.com/shobhit99/SuperIsland)
- [DynamicNotchKit](https://github.com/mrkai77/DynamicNotchKit)
- 商业产品 [NotchNook](https://lo.cafe/notchnook)、[MediaMate](https://wouter01.github.io/MediaMate/)

它们验证了市场愿意接受 Mac 顶部 notch/capsule 形态，但主要场景是：

- Now Playing / 媒体控制
- 音量、亮度、键盘背光 HUD replacement
- 文件 shelf / AirDrop / downloads
- Calendar / Weather / Notifications
- 系统状态、锁屏、屏幕录制、VPN、蓝牙、Focus
- 动画、手势、trackpad swipe、iOS Dynamic Island 仿真

对 Agent Island 的意义：

- 我们不应该用通用功能作为主卖点，否则会被成熟产品压住。
- 需要吸收它们的工程细节：notch 检测、安全区、多显示器、窗口层级、click-through/interactive 切换、缩放、低功耗、动画降级、签名更新。
- 视觉上可以更克制：agent 工具需要长时间挂着，不能像营销 demo 一样频繁打扰。

### 2. AI coding agent 灵动岛 / 本地工作台

代表：

- [Ping Island](https://github.com/erha19/ping-island)
- [AgentBro](https://github.com/shirenchuang/agentbro)
- [DevIsland](https://github.com/nangchang/DevIsland)
- [MioIsland](https://github.com/MioMioOS/MioIsland)
- [pi-island](https://github.com/phun333/pi-island)

这些项目和我们的目标最接近。共同模式：

```text
Agent hook / extension / app-server
  -> bridge / socket / companion
  -> event normalizer
  -> session store
  -> attention queue
  -> notch surface / menu bar / floating buddy
  -> action response / focus jump
```

关键发现：

- “正在工作”应该由事件流判断：tool start/end、assistant streaming、active tool count、last event time、session lifecycle。
- “完成”必须来自明确的 agent_end/Stop/session end/turn completion，且没有活跃工具，并经过短暂 grace window。
- “需要处理”是正常状态，不是异常。PermissionRequest、AskUserQuestion、ExitPlanMode、Elicitation、allow/deny、计划审批都应该显示为 `waiting_user` 或 `attention`。
- “在线”只能表示 bridge/app/进程可达，不代表工作中。
- 最强体验是直接在 island 内批准、拒绝、回答、快速回复，然后必要时跳回原窗口。

### 3. Token / quota / usage monitor

代表：

- [ClaudeBar](https://github.com/tddworks/ClaudeBar)
- [TokenBar](https://github.com/Nanako0129/TokenBar)
- [AI Token Monitor](https://github.com/soulduse/ai-token-monitor)
- [Claude Code Usage Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)
- [cc-statusline](https://github.com/chongdashu/cc-statusline)
- [claude-code-statusline](https://github.com/rz1989s/claude-code-statusline)

它们不是灵动岛竞品，但能补强 Agent Island 的状态准确性：

- 从本地 JSONL/session logs 获取 token、cost、model、cache hit、messages、session time。
- 识别 5-hour/weekly/monthly plan window 和 reset time。
- 区分 official、local_estimate、experimental、unknown 的置信度。
- 提供 `--write-state`、JSON snapshot、compact output 给外部 GUI 消费。
- 在不联网、不代理、不读取敏感内容的前提下给出 usage 统计。

对我们来说，usage/quota 不是主界面主角，但应该作为每个任务的附加状态：

- 当前会话是否接近限额。
- 是否因为 rate limit 停住。
- token burn rate 是否异常。
- completion 后显示任务消耗。
- dashboard 里能按 provider/project/model 追踪。

### 4. Observability / dashboard

代表：

- [Claude-Code-Agent-Monitor](https://github.com/hoangsonww/Claude-Code-Agent-Monitor)
- [claude-code-otel](https://github.com/ColeMurray/claude-code-otel)

这些产品不像灵动岛轻量，但适合参考数据模型：

- session、agent、events、tool calls、status、Kanban。
- hook handler -> SQLite/backend -> WebSocket -> React dashboard。
- OpenTelemetry collector -> Prometheus/Loki -> Grafana。
- tool_result、api_error、tool_decision、api_request、cost、token 组成完整运行事实。

对我们来说，应该避免做大而重的 dashboard 作为第一屏，但内部数据模型可以借鉴：

- event ledger 作为真相源。
- 每个 event 只 append，不覆盖。
- SessionStore 基于 event reducer 生成 UI snapshot。
- UI snapshot 可以给灵动岛、菜单栏、日志页、导出接口共用。

## 重点项目分析

### Ping Island

来源：[GitHub](https://github.com/erha19/ping-island)

定位：macOS menu bar / notch surface for AI coding sessions。

支持：

- Claude Code
- Codex App + Codex CLI
- Gemini CLI
- Hermes Agent
- Pi Agent
- Qwen Code
- Kimi CLI
- OpenClaw
- OpenCode
- Cursor
- Qoder
- CodeBuddy / WorkBuddy
- GitHub Copilot

核心功能：

- attention-first UI：默认紧凑，只有需要审批、输入、review、intervention 时展开。
- act from notch：approve/deny/reply。
- one-click return：回到 iTerm2、Ghostty、Terminal、tmux、IDE。
- SSH terminal support：远程 bridge，远程 hooks 指回本机 island。
- Codex hook + app-server sync：同时支持 Codex CLI hooks 和 Codex app-server live thread。
- session summaries、completion popups、usage snapshots。
- mascot、sound pack、detached buddy。
- signed/notarized release、Sparkle、Homebrew cask。

我们应该学习：

- 把 attention queue 作为核心，而不是通知列表。
- 每个 provider 分两层：ingress adapter + capabilities。
- 跳转能力必须是产品的一等功能。
- Codex App 不能只通过进程判断，需要 app-server/thread sync 或 rollout parsing fallback。
- remote SSH 是高价值能力，因为很多 agent 跑在远程 dev machine。

我们可以差异化：

- 更准确覆盖 ChatGPT App/Web。
- 明确将 `waiting_user`、`running`、`completed`、`stale`、`blocked` 做成状态机，并在 UI 文案上避免“异常/已完成”误判。
- 更细的完成大纲：完成时自动展开显示最后 tool summary、changed files、next action。

### AgentBro

来源：[GitHub](https://github.com/shirenchuang/agentbro)

定位：AI 编程 Agent 的 macOS 灵动岛 + 本地控制台。

技术：

- Tauri
- React
- Rust
- 本地 hook server：Unix socket `/tmp/agentbro-<uid>.sock` 或 TCP `127.0.0.1:17894`

核心功能：

- 灵动岛浮窗：compact、hover、expanded、detail。
- 即时处理：权限请求、问题、计划审批、完成提醒、回复卡片。
- 快速回复：不切回终端也能输入。
- 任务感知：工具调用、subagent、任务摘要、token/rate limit。
- Agent 管理：扫描 CLI/App 安装状态、版本、路径、hooks、skills、MCP、plugins。
- Skill center / Skill packs。
- Hook doctor。
- SSH remote。
- Webhook 通知。
- pet mode / pet market。

我们应该学习：

- hook doctor 非常重要。用户第一天最容易卡在权限、hooks、路径、socket、Full Disk Access、Accessibility。
- Agent 管理可以变成设置页的强功能：不要让用户自己找 Claude/Codex/Gemini 的配置文件。
- 技能、MCP、插件、路径状态可以作为“workspace health”显示。
- Tauri/Rust 方案有跨平台潜力，但我们当前 Swift 原生 app 更适合 macOS notch/window/Accessibility。

许可证：

- Apache-2.0，理论上可复用代码，但需要保留 NOTICE/License。考虑到我们已有 Swift 原生架构，建议参考思路，不直接混入 Tauri 代码。

### DevIsland

来源：[GitHub](https://github.com/nangchang/DevIsland)

定位：Swift 原生 macOS notch app，支持 Claude Code、Codex CLI、Gemini CLI 的活动和审批请求。

架构：

```text
CLI Hook
  -> devisland-bridge.sh
    -> HookSocketServer
      -> ApprovalProxyController
        -> ApprovalPolicyEngine
        -> ProviderAdapter
        -> UI decision when needed
      -> bridge response
```

模块边界：

- `HookSocketServer / HookIPCServer`：TCP + Unix domain socket listener。
- `ApprovalProxyController`：策略查找、DB 写入、response 编排。
- `ProviderAdapter`：把决策格式化成各 CLI 的 hook response JSON。
- `HookEventNormalizer`：跨 CLI 归一化事件名。
- `ApprovalPolicyEngine`：persistent deny > session deny > persistent allow > session allow > prompt。
- `SQLiteApprovalStore`：rules、session_cache、hook_events、decisions、pty_messages。
- SwiftUI windows：settings、approval rules、replay log、PTY transcript。

Provider 细节：

- Claude：`PermissionRequest` 是审批主事件；`AskUserQuestion`、`ExitPlanMode`、`Elicitation` 要在 UI 中处理并返回 updatedInput。
- Codex：`PermissionRequest` 是审批；`PreToolUse` 只做状态跟踪；Codex 没有原生 SessionEnd，需要根据同 terminal identity 的新 SessionStart 推断旧 Codex session 结束。
- Gemini：`BeforeTool` 是审批；如果返回 `{}` 则回到 Gemini 自己的审批逻辑。
- VS Code/Claude Desktop：通过环境变量、父进程链、bundle id 检测，并用正确 bundle id 激活。

我们应该学习：

- Bridge 只负责转发和补 terminal metadata，不碰 DB/策略/UI。
- ProviderAdapter 单独隔离，避免 UI 和 provider JSON 格式耦合。
- Approval cache 必须有 session 和 persistent 两级。
- 询问/allow 是正常的 `waiting_user`，不能标为异常。
- Codex 没有 SessionEnd 时要有推断策略和 stale timeout。

许可证：

- MIT，可复用，但建议保留 attribution，并优先吸收架构。

### pi-island

来源：[GitHub](https://github.com/phun333/pi-island)

本地源码：`research/competitors/repos/phun333__pi-island`

定位：pi coding agent 的 Dynamic-Island-style status capsule。

架构：

```text
pi extension
  -> companion.mjs
    -> Unix socket / Named pipe
      -> native host
        -> macOS Swift + WKWebView
        -> Windows C# + WebView2
          -> HTML/CSS capsule
```

关键实现：

- 每个 pi session 一个 row，多个终端会 stack 成一个 capsule。
- extension 监听 `session_start`、`before_agent_start`、`agent_start`、`message_update`、`tool_execution_start`、`tool_execution_end`、`agent_end`、`session_shutdown`。
- `toolToIsland()` 把 read/edit/write/bash/ls/grep/find 映射成 reading/editing/writing/running/searching。
- `activeToolCount` 判断是否仍在执行工具。
- `agent_end` 后 freeze elapsed timer，显示 done，5 秒后 retract。
- companion 在最后一个 client 断开后 6 秒自动退出。
- notch 检测用 macOS `safeAreaInsets.top`，并提供 `auto/normal/notch`。
- 用户配置存在 `~/.pi/pi-island.json`。

我们应该学习：

- 小型 companion 进程可以把多 session 统一到一个 UI，不需要每个 agent 自己创建窗口。
- 生命周期事件要有明确 reducer，不要仅靠 polling。
- active tool count 是“是否正在工作”的核心信号。
- done 不是永久状态，应转入 recent completed，再按时间折叠。
- notch mode、screen、scale 应该可热切换。

许可证：

- MIT，可直接借鉴实现模式。

### BoringNotch

来源：[GitHub](https://github.com/TheBoredTeam/boring.notch)

本地源码：`research/competitors/repos/TheBoredTeam__boring.notch`

定位：通用 macOS notch 体验，音乐控制、calendar、file shelf、AirDrop、HUD replacement、battery、downloads、gesture。

关键工程点：

- SwiftUI + AppKit。
- `BoringViewCoordinator` 是全局 UI 协调器，管理 current view、sneak peek、HUD replacement、screen preference。
- 用 `NSScreen.displayUUID` 持久化目标屏幕，比显示器名称可靠。
- Accessibility 授权变化会触发 HUD interceptor 启停。
- 有 `MediaKeyInterceptor`、XPC helper、mediaremote-adapter。
- `NotchSpaceManager` 用非常高的 window/space level 做置顶体验。
- Roadmap 包括 extension system、notifications、layout customization。
- 支持 Homebrew cask 和 DMG，但未签名/未 notarize，README 明确提示 quarantine 处理。

我们应该学习：

- 多显示器要使用稳定 UUID，不要只用 screen name。
- 权限 onboarding 必须明确：Accessibility、Apple Events、Full Disk Access、Automation、Screen Recording。
- HUD/notification 类短事件可以用 sneak peek 模型：短时展开，然后自动回收。
- 文件架/下载/HUD 可作为未来附加功能，但不是主目标。

许可证：

- GPL-3.0。不能把实现代码直接复制进非 GPL 项目。可以学习产品和架构，不建议复用源码。

### DynamicNotch / SuperIsland / DynamicNotchKit

来源：

- [DynamicNotch](https://github.com/jackson-storm/DynamicNotch)
- [SuperIsland](https://github.com/shobhit99/SuperIsland)
- [DynamicNotchKit](https://github.com/mrkai77/DynamicNotchKit)

可借鉴点：

- DynamicNotch：iOS Dynamic Island 风格动画、trackpad gestures、floating capsule fallback、Lottie、系统事件、temporary alerts。
- SuperIsland：模块化 `Modules/`、`ExtensionHost/`、JavaScriptCore sandboxed extensions、低功耗模式、auto updater、Homebrew packaging。
- DynamicNotchKit：把 notch window 抽象为 Swift package；自动处理 notch 与 non-notch Mac 的 fallback。

对 Agent Island：

- 可以考虑把我们内部的 island window manager 独立成模块，减少业务状态和窗口几何耦合。
- 不要过度复制动态岛动画。AI agent 场景要优先可读性、稳定布局、无误导状态。
- 可以加 reduced motion 和 low power modes，长时间监控时很重要。

许可证：

- DynamicNotch 是 GPL-3.0，只能参考。
- DynamicNotchKit 是 MIT，可复用但需确认兼容我们现有窗口实现。
- SuperIsland license 元数据不明确，谨慎。

### ClaudeBar / TokenBar / AI Token Monitor / Claude Code Usage Monitor

来源：

- [ClaudeBar](https://github.com/tddworks/ClaudeBar)
- [TokenBar](https://github.com/Nanako0129/TokenBar)
- [AI Token Monitor](https://github.com/soulduse/ai-token-monitor)
- [Claude Code Usage Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)

可借鉴点：

- 多 provider 配置和 enable/disable。
- session、weekly、model-specific quota。
- 状态阈值：healthy / warning / critical / depleted。
- 读取本地 JSONL，不代理请求、不上传数据。
- JSON snapshot/compact output 给外部 GUI 消费。
- official rate limit 与 local estimate 分开显示置信度。
- failed refresh 不要清空旧读数，应保留 last-known value 并显示 stale。
- Sparkle 自动更新、Homebrew cask、签名/公证。

对 Agent Island：

- 在每个 agent row 上显示简短 quota signal，而不是大 dashboard。
- 只有用户展开时显示 token/cost/detail。
- 状态判断里把 rate-limit/depleted 作为 `blocked_limit` 或 `waiting_limit_reset`，不要误报 completed。

### NotchNook / MediaMate / Vibe Island

来源：

- [NotchNook](https://lo.cafe/notchnook)
- [MediaMate](https://wouter01.github.io/MediaMate/)
- [MacStories review](https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/)
- [The Verge on NotchNook](https://www.theverge.com/2024/7/21/24202914/notchnook-mac-app-dynamic-island-iphone)

商业竞品说明：

- NotchNook 和 MediaMate 都证明 Mac notch / top-center overlay 是用户能理解的形态。
- 它们的商业包装较成熟：下载、定价、更新、视觉 demo、权限说明。
- 但它们不解决 AI agent 工作流；这是我们的差异化窗口。

对我们：

- 官网和 README 需要第一屏直接展示“谁需要我处理”，而不是只展示漂亮 capsule。
- 需要清晰说明隐私：本地 hook、本地日志、本地 JSONL，不上传代码/对话。
- 开源打包时要提供 signed/notarized 目标，不然普通用户会卡在 Gatekeeper。

## 真实状态判定方案

当前问题：“在线”“已完成”“1 项需要处理”都容易不真实。建议改成状态机和信号融合。

### 状态枚举

| 状态 | 英文 key | 解释 | UI 行为 |
| --- | --- | --- | --- |
| 在线空闲 | `idle_online` | bridge/app/server 可达，但无活跃任务 | 灰/低权重，不计入工作中 |
| 正在思考 | `thinking` | assistant streaming 或最近有 message_update，无工具运行 | 蓝/动态呼吸 |
| 正在执行工具 | `running_tool` | active tool count > 0 或 tool_start 未结束 | 绿/显示工具名和目标 |
| 等人处理 | `waiting_user` | permission/question/plan/allow/deny/input required | 高亮展开，允许直接处理 |
| 等外部资源 | `waiting_external` | rate limit、network、terminal required、browser login | 黄/显示原因和下一步 |
| 最近完成 | `completed_recent` | 明确 Stop/agent_end/turn completed 且无活跃工具 | 展开摘要，几秒后折叠 |
| 失败/异常 | `blocked_error` | tool failure、hook failure、bridge crash、permission denied by policy | 红/显示可操作修复 |
| 过期未知 | `stale_unknown` | heartbeat 超时或日志不再更新 | 灰黄/提示重连或跳回检查 |

### 关键规则

- `PermissionRequest`、`AskUserQuestion`、`ExitPlanMode`、`Elicitation`、Allow/Approve 是正常等待，不是异常。
- “完成”必须有明确完成事件，或满足 fallback：无活跃工具 + 无输出变化 + provider completion marker + grace window。
- “在线”不能计入“正在工作”。
- tool failure 不是 always 异常：如果 provider 随后继续运行，可作为 warning event；只有 session blocked 或 requires user action 才升红。
- stale 要显示置信度，不要假装完成。

### 建议 reducer

```text
raw events
  -> provider adapter
  -> normalized event
  -> append-only event ledger
  -> session reducer
  -> session snapshot
  -> island list / expanded card / menu dashboard
```

每个 session snapshot 至少包含：

- `provider`
- `sessionId`
- `threadId`
- `workspace`
- `terminalIdentity`
- `windowTarget`
- `state`
- `stateConfidence`
- `activeTool`
- `activeToolStartedAt`
- `pendingAction`
- `lastAssistantSummary`
- `changedFiles`
- `lastEventAt`
- `heartbeatAt`
- `quotaSignal`
- `jumpTarget`

## ChatGPT App/Web 检测建议

目前这些竞品对 ChatGPT App/Web 的覆盖较弱，这是可差异化点。

建议分三层实现：

### ChatGPT Web

优先方案：

- Chrome/Safari/Edge browser extension 或 AppleScript + Accessibility fallback。
- 通过 tab URL/title 定位 `chatgpt.com`。
- DOM 中检测 composer、send/stop button、streaming indicator、assistant message mutation。
- 如果用户已登录浏览器，可以通过 extension content script 不读取敏感正文，只发送状态：`streaming`、`idle`、`needs_input`、`last_message_updated_at`、`conversation_id`、`tab_id`。

状态判定：

- stop button 可见或 assistant message still mutating -> `thinking/running`
- send button enabled 且最后一条 assistant message stable -> `completed_recent`
- login wall / captcha / network error -> `waiting_external`
- tool/connector approval UI 可见 -> `waiting_user`

### ChatGPT App

可行方案：

- Accessibility API 读取窗口标题、button labels、AX hierarchy 中的 Stop/Send/Retry/Continue generating。
- AppleScript 激活 bundle id。
- NSWorkspace 监听 app launch/terminate。
- 辅助截图/OCR 作为最后 fallback，不作为默认路径。

注意：

- ChatGPT App 没有稳定公开 hook，因此状态置信度要比 Claude/Codex hooks 低。
- UI 文案要显示“推断完成/推断运行中”，避免像 hooks 一样绝对。

### 统一产品表现

ChatGPT row 应该标记来源：

- `ChatGPT Web · Chrome tab`
- `ChatGPT App · Window`
- `confidence: inferred`

点击跳转：

- Web：激活浏览器并切到 tab。
- App：激活 ChatGPT bundle id 和目标窗口。

## 点击跳转方案

竞品共同强调 one-click return。建议跳转目标统一为 `JumpTarget`：

```swift
enum JumpTarget {
  case app(bundleID: String, windowTitle: String?)
  case terminal(appBundleID: String, tty: String?, pid: Int?, cwd: String?)
  case tmux(session: String, window: String?, pane: String?)
  case browser(bundleID: String, tabID: String?, url: URL?)
  case codexThread(threadID: String)
  case fileURL(URL)
}
```

Provider adapter 负责补 metadata：

- hooks bridge 加 `cwd`、`tty`、`TERM_PROGRAM`、`TERM_SESSION_ID`、parent process chain。
- Codex App 保存 thread id / app-server id。
- Browser watcher 保存 tab id / URL。
- Terminal focus 用 app-specific strategy，不要只 `activate` 整个 app。

优先支持：

1. Codex desktop thread：调用 Codex app navigation。
2. Terminal/iTerm2/Ghostty/Terminal.app：按 tty/cwd/pid 找回 session。
3. tmux：按 session/window/pane select。
4. VS Code/Cursor：用 workspace root 打开并 focus terminal。
5. Chrome/Safari ChatGPT tab。

## UX 建议

### 顶部形态

- 避开 MacBook 刘海：使用 safe area/notch detection，non-notch/external display fallback 为 floating capsule。
- 多屏时按 display UUID 保存目标屏幕。
- 支持屏幕切换：primary / active / explicit display。
- 支持 notch offset 和 manual calibration。

### 列表行为

- 超过 4 个任务必须可滚动。
- “需要处理”和“正在执行”优先排序，“在线空闲”折叠。
- 列表高度根据屏幕尺寸和 notch 安全区限制。
- 完成/等待状态触发短展开，显示具体大纲和按钮。

### 动效

- `running_tool`：细微进度/呼吸，不要夸张。
- `waiting_user`：一次展开 + action highlight + 声音可选。
- `completed_recent`：展开显示完成摘要 4-8 秒，然后收起到 recent group。
- `blocked_error`：红色但只用于真正失败，不用于正常审批。
- 尊重 Reduce Motion。

### 状态文案

避免：

- “在线”代表正在工作。
- “已完成”代表 session 还在继续。
- “异常”代表正常 allow/permission。

建议：

- “空闲”
- “正在编辑 `foo.swift`”
- “等待你批准 Bash”
- “等待你回答问题”
- “刚完成：修改 3 个文件”
- “可能已停滞：8 分钟无事件”
- “需要检查终端”

## 开源/打包建议

要做成可开源、可打包的产品，建议补齐：

- Signed + notarized DMG。
- Sparkle auto-update。
- Homebrew cask。
- first launch onboarding：Accessibility、Automation、Full Disk Access、Screen Recording、browser extension。
- hook doctor：Claude/Codex/Gemini/ChatGPT browser bridge 的检测和修复。
- privacy page：本地处理、哪些文件被读、哪些网络请求可选。
- crash/log collection 默认关闭。
- release smoke tests：启动 app、hook event simulator、窗口截图、notch safe area、多屏。
- docs：provider matrix、capabilities matrix、troubleshooting。

## 许可证风险

| 项目 | License | 可否复制代码 | 建议 |
| --- | --- | --- | --- |
| BoringNotch | GPL-3.0 | 不建议 | 只学产品/架构，避免直接拷贝实现 |
| DynamicNotch | GPL-3.0 | 不建议 | 只参考动画/功能 |
| Ice/Thaw | GPL-3.0 | 不建议 | 不混入代码 |
| DevIsland | MIT | 可以，保留 license | 可参考/复用小模块 |
| pi-island | MIT | 可以，保留 license | 可复用架构模式 |
| DynamicNotchKit | MIT | 可以，保留 license | 可评估 UI/window manager |
| AgentBro | Apache-2.0 | 可以，保留 NOTICE/license | 参考 Tauri/Rust 工作台，不建议直接混入 Swift |
| Ping Island | Apache-2.0 | 可以，保留 NOTICE/license | 可参考 provider matrix/remote/focus |
| ClaudeBar / TokenBar 等 | MIT/不明 | 视具体 license | 优先参考数据模型 |

## 建议路线图

### P0：先把“不真实状态”修掉

- 建立 normalized event model 和 SessionStore。
- 把 `waiting_user` 从 error 中拆出来。
- 只有明确完成事件或可信 fallback 才显示 completed。
- 在线/空闲不计入工作中。
- 增加 stale/unknown 置信度。
- 修复点击跳转：统一 JumpTarget。
- 列表可滚动，超过 4 个不被盖住。
- notch safe area / screen size 自适应。

### P1：把 Agent Island 做成可用工作台

- Claude Code：PermissionRequest、AskUserQuestion、ExitPlanMode、Elicitation。
- Codex CLI/App：hooks + app-server/thread sync。
- ChatGPT App/Web：browser extension/Accessibility watcher。
- 完成/等待触发 island 展开，显示摘要和 action。
- token/quota signal 接入。
- Hook doctor 和 provider health。

### P2：做成可传播产品

- SSH remote bridge。
- sound packs / mascot / detached buddy 可选。
- Usage dashboard，不抢主界面。
- signed/notarized DMG + Sparkle + Homebrew。
- 官网第一屏展示“谁等我/谁完成了/点回窗口”。
- 开源文档和 provider adapter API。

## 对当前 Agent Island 的直接改造清单

1. 将当前任务模型从 `online/completed/error` 改成 `idle_online/thinking/running_tool/waiting_user/waiting_external/completed_recent/blocked_error/stale_unknown`。
2. 为每个 provider 增加 `stateConfidence`，hooks 为 high，logs/app-server 为 medium，Accessibility/browser 推断为 low/medium。
3. 所有 “PermissionRequest / Allow / AskUserQuestion / ExitPlanMode” 显示为 “等待你处理”，不要标红。
4. `completed` 必须等待 provider 完成事件；如果只有日志停止，显示“可能停滞”或“推断完成”。
5. 点击 row 调用 `JumpTarget`，而不是只打开 app。
6. 展开完成卡片显示：完成摘要、变更文件、最后工具、耗时、token/cost、回到窗口按钮。
7. 当 `waiting_user` 或 `completed_recent` 出现时，island 自动展开一次，但允许用户关闭/静音。
8. ChatGPT Web 先做 Chrome/Edge extension，Safari 后补；ChatGPT App 用 Accessibility 低置信度推断。
9. 把 local logs/session JSONL 解析做成后台 provider，不阻塞 UI。
10. Provider matrix 明确列出每个 agent 支持哪些能力：activity、approval、reply、completion、jump、quota、remote。

