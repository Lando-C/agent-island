# Agent Island Product Blueprint

日期：2026-07-09

> 实现状态已于 2026-07-14 同步。原始规划中标为“待做”的部分已有推进；请以
> `README.md`、`docs/ROADMAP.md` 和运行中的 Diagnostics 为准。这里保留的是
> 产品原则与参考架构，不作为实时功能清单。

## 定位

Agent Island 不是通用 Dynamic Island，也不是单一 Claude/Codex mascot。它应该是：

> AI Agent Operations Island：准确知道哪些 AI agent 正在工作、哪些完成了、哪些需要人批准/回复、哪些卡住了，并且能一键回到对应窗口、线程、终端 pane 或浏览器 tab。

优先级判断：

1. 状态真实性优先于动效。
2. 精准跳转优先于漂亮列表。
3. 诊断可见优先于“它没反应但不知道为什么”。
4. 自动审批是信任功能，不是单纯效率功能。
5. 离岛、吉祥物、声音属于信息设计层，应该建立在准确状态和清晰边界之上。

## 参考项目整合

| 项目 | 本地路径 | 可直接参考的模块 | 集成策略 |
| --- | --- | --- | --- |
| Vibe Notch | `research/competitors/repos/new-20260709/vibe-notch` | HookSocketServer、HookInstaller、ChatHistoryManager、SessionStore、ToolEventProcessor、TmuxTargetFinder、TerminalVisibilityDetector、NotchGeometry、SoundSelector | Apache-2.0，可参考/复用结构；保留 NOTICE |
| MioIsland | `research/competitors/repos/new-20260709/MioIsland` | TerminalJumper、CodexHookInstaller、HookHealthCheck、AskUserQuestionView、QuestionResponder、ProcessLivenessChecker、SoundManager、NotchCustomization | CC BY-NC 4.0；只做参考，不直接混入开源主线源码 |
| Ping Island | `research/competitors/code-study/permissive/PingIsland` | Codex app-server/broker、TerminalSessionFocuser、tmux controller、notch geometry | 可做架构迁移；保持我们自己的 API |
| DevIsland | `research/competitors/code-study/permissive/DevIsland` | TerminalContext、TerminalFocuser、Approval/Elicitation 状态、display target | 可 clean-room 迁移身份模型 |
| AgentBro | `research/competitors/code-study/permissive/AgentBro` | Rust terminal jump、Warp sqlite、kitty/WezTerm/Kaku/cmux 路由、session store 边界 | 可翻译关键策略，不复制 GPL 隔离代码 |

## 功能覆盖策略

### P0：必须准确

| 功能 | 目标 | 当前状态 |
| --- | --- | --- |
| Hook 实时状态 | Claude Code / Codex CLI 通过 hook 推送状态 | 已有 `scripts/install-hooks` 和 `agent-island-bridge.py` |
| Codex App 状态 | 通过 broker/thread read 提取可见线程和 last turn | 已有 `codex-broker-probe` |
| App / Web / CLI 区分 | 不能把 App 工作误报成 CLI | 已用进程链、真实 bundle 路径和 terminal metadata 区分；当前 `com.openai.codex` 安装于 `ChatGPT.app` 也可识别 |
| Waiting / Approval / Done | 等待人推进不能显示异常；完成不能长期霸屏 | 已有 SessionStore + PendingRequestStore + ExpansionController；无工作证据的空生命周期不再产生假完成 |
| 旧会话收敛 | 超过 12h idle/waiting 不占列表 | 已按 phase TTL 收敛：thinking 90s、done 10min、working 30min、waiting/error 12h |
| 僵尸检测 | pid/tmux pane/terminal 不存在时标 ended | PID/进程树/Claude `--resume` 已接入；独立 tmux pane/terminal 探针待补 |

### P1：必须能回去

| 跳转目标 | 目标 | 当前状态 |
| --- | --- | --- |
| Codex App thread | `codex://threads/{threadId}` | 已接入 |
| Claude App session | `cliSessionId -> localSessionId`，唯一标签/当前路由精确聚焦 | 已接入；需要 Accessibility，缺权限时只激活 App、不随机跳 |
| ChatGPT Web | 聚焦 Chrome/Safari ChatGPT tab | 已有基础 |
| iTerm2 / Terminal | 优先 windowID + tabIndex，再按 tty/session 选 tab | 已接入 |
| tmux | 按 pane/socket/client 切 pane | 已接入 |
| Ghostty | 按 cwd/title 找 terminal | 已接入基础 |
| WezTerm / kitty | 按 pane/window/cwd/tty | 已接入基础 |
| Warp / cmux / Kaku | 精确 workspace/pane | 待深化 |

### P2：必须可排障

诊断页或菜单诊断至少覆盖 9 项：

1. App 是否运行在 `/Applications`。
2. Hook bridge 是否存在且可执行。
3. Claude Code hook 是否安装。
4. Codex CLI hook 和 hooks feature 是否启用。
5. Events log 是否有新事件。
6. Apple Events / Accessibility 权限。
7. Codex broker/socket 是否可读。
8. tmux 是否安装、有无 server。
9. 终端跳转辅助工具：osascript、wezterm、kitty/kitten。
10. 主要 App/Web surface 是否运行：Codex、Claude、ChatGPT、Chrome/Safari。
11. 自动审批当前是否启用。

当前已落地 CLI 诊断脚本、菜单复制入口和 Settings Diagnostics tab：

- `scripts/agent-island-diagnostics`
- 状态栏菜单：`Copy Diagnostics Report`
- Settings：`Diagnostics` tab 可运行和复制报告

### P3：快速推进

第一版 quick action 不直接批准：

- 复制待处理摘要。
- 打开对应会话/终端。
- 针对 request_user_input 展示问题和选项。
- 发送预设文本到 terminal，明确由用户触发。

第二版才做写回：

- Claude PermissionRequest allow/deny。
- Codex request_user_input 选项提交。
- 会话级 allow once / allow session。

## 自动审批信任边界

自动审批不是“减少点击”的功能，而是“明确什么时候会替你决定”的信任功能。

默认行为：

- 默认关闭。
- 不创建配置文件就不会自动批准。
- 所有 hook 仍写状态事件和风险标记。

只读候选：

- `Read`
- `Grep`
- `Glob`
- `LS`
- `TodoRead`

永不自动批准：

- `Write`
- `Edit`
- `MultiEdit`
- `NotebookEdit`
- `Bash`
- `Shell`
- 删除、移动、权限修改、sudo、kill、磁盘、launchctl、强推、reset hard、clean 等 shell 模式。

Shell 策略：

- 即使看起来是 `ls` / `git status` / `rg`，第一阶段也只标记为 `manual_safe_shell`，不自动放行。
- 只有未来加入显式“安全 Bash allowlist”并可视化展示后，才考虑 opt-in 自动放行。

配置位置：

```json
{
  "enabled": false,
  "allow_read_only": true
}
```

路径：`~/.agent-island/auto-approval.json`

当前实现：

- `agent-island-bridge.py` 会写入：
  - `tool_risk`
  - `tool_risk_reason`
  - `auto_approval_eligible`
- 只有用户显式启用时，Claude `PermissionRequest` 的只读工具才会自动 allow。
- Codex approval response schema 尚未完全验证，所以仍保持 status-only。

## 离岛与吉祥物

离岛模式不是彩蛋，而是多屏工作场景的替代展示面。

目标交互：

1. 长按刘海区域 0.35s。
2. 向下拖拽。
3. 角色脱离刘海，成为可拖动浮窗。
4. 点击浮窗显示当前会话状态气泡。
5. 右键菜单：回到刘海、退出应用、打开诊断。
6. 浮窗位置持久化。
7. 外接显示器时可停留在当前工作屏。

吉祥物是信息设计，不只是装饰：

- idle：低频轻动画。
- working：节奏型动效。
- warning / needs attention：更强颜色和动作。
- done：短暂完成动效，随后收敛。

每个 engine 可独立配置：

- Codex
- Claude
- Claude Science
- ChatGPT
- Web
- CLI

## 开源产品化计划

发布前要整理：

1. 统一工程命名：Scheme / build script / app bundle / docs 名称都用 `Agent Island`。
2. 增加 `LICENSE` 和第三方 NOTICE。
3. 标注代码来源：
   - Apache/MIT 参考可列入 NOTICE。
   - GPL / CC BY-NC 只做研究引用，不进入源码。
4. README 明确核心定位和边界。
5. 安装路径：
   - Release zip。
   - Homebrew cask。
   - 首次启动自动提示 hooks/权限。
6. 诊断导出：用户反馈 bug 时可以一键复制完整 report。
7. 安全说明：自动审批默认关闭，危险操作永不自动放行。
8. 隐私说明：事件默认写本机 `~/.agent-island`，不上传。

## 下一阶段路线

1. PendingRequest：结构化 permission / question / approval。
2. ChatDetailStore：hook-driven 聊天记录和工具调用详情。
3. ZombieDetector：pid/tmux/process liveness。
4. SmartSuppress：会话所在终端/窗口前台时不弹大提示。
5. 诊断面板第二版：结构化 severity、可修复项、可选 capability。
6. QuickReply：先复制/打开/发送预设文本，再做 allow/deny。
7. Off-Island floating pet。
8. Sound + mascot。
9. Open-source release hygiene：Git repo、release zip、sign/notarize、Homebrew cask。
