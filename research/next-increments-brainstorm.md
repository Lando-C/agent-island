# Agent Island 下一阶段增量 Brainstorm

日期：2026-07-09

## 核心定位

不要做通用 BoringNotch/NotchNook，也不要只做 Claude/Codex mascot。Agent Island 应定位为：

> AI Agent Operations Island：准确知道哪些 agent 在工作、哪些已完成、哪些等人批准/回复、哪些卡住；点击能跳回具体线程/终端/浏览器标签；轻量场景能在岛上直接推进。

## 外部新增调研

| 项目 | 当前信号 | 许可证/风险 | 对我们的启发 |
| --- | --- | --- | --- |
| [CodeIsland](https://github.com/wxtsky/CodeIsland) | GitHub API：2070 stars、MIT、2026-07-09 更新；README 明确支持 Claude Code、Codex、Gemini CLI、Cursor、Copilot、Trae、Qoder、CodeBuddy、OpenCode、Kimi、Cline、Pi 等 13 类工具；有 permission management、question answering、one-click jump、smart suppress、iPhone/Watch Buddy | MIT，可参考架构；clone 网络慢，本轮只做网页/README/API 调研 | 它已经证明“多 agent + permission/question + terminal/IDE jump + mobile companion”是用户会买账的完整形态 |
| [Notchi](https://github.com/sk-ruban/notchi) | GitHub API：942 stars、GPL-3.0；描述为 `notch app for claude code & codex`；状态含 thinking/working/permission/compaction/errors/completions，支持多 session mascot、usage stats、sound、prompt sentiment | GPL-3.0，只做隔离参考 | mascot/情绪是可选皮肤，不是核心；usage/quota 和 compaction 状态值得加入 |
| [Vibe Notch](https://github.com/farouqaldori/vibe-notch) | GitHub API：2439 stars、Apache-2.0；描述为 Claude Code notifications/session manager | Apache-2.0，可参考；更偏 Claude Code | approval 直达和 chat history 是核心高频能力 |
| [DynamicNotch](https://github.com/jackson-storm/DynamicNotch) | GitHub API：428 stars、GPL-3.0；描述为把 MacBook notch 变成系统 surface | GPL-3.0，只 clean-room | 多屏、HUD 动效、系统事件可作为长期形态参考，不应现在分散 agent 主线 |
| [NotchDrop](https://github.com/Lakr233/NotchDrop) | GitHub API：2070 stars、MIT；把 notch 作为临时文件/AirDrop shelf | MIT，可参考交互但领域不同 | “临时搁置/稍后处理”的 shelf 概念可转化为待处理 agent 队列 |

## 增量优先级

### P0：状态真实性继续收紧

| 增量 | 目的 | 参考来源 | 实现方向 |
| --- | --- | --- | --- |
| Codex rollout fallback last-turn parser | broker 不在线时仍能读 Codex App 最新 turn | Ping `CodexRolloutParser`，我们当前 `thread/read` 实测结构 | 读 `~/.codex/sessions/...jsonl`，压缩 last turn status/items |
| Provider capability matrix | 不同 agent 支持哪些能力要明说 | CodeIsland supported tools 表 | `ProviderCapability(activity, approval, question, jump, quota, appServer)` |
| PendingRequest 模型 | allow/permission/question 是“需推进”，不是异常 | DevIsland Approval，Ping Intervention | 先只读展示，不写回 |
| Error vs Need Human vs Warning 分层 | tool failure 不是 always 异常 | AgentBro/Ping 状态模型 | 新增 warning/blockedByHuman/internalError 内部状态，再映射到 UI |

### P1：点击跳转统一

| 增量 | 目的 | 参考来源 | 当前进展 |
| --- | --- | --- | --- |
| `JumpTarget` | 替代单一 `targetPID` | 本地报告 + Ping `appLaunchURL` + AgentBro jump | 已新增基础模型 |
| Codex App thread URL | 具体 Codex 会话不随机跳窗口 | Ping `codex://threads/{id}`，本机 open 实测 | 已接入具体 session snapshot |
| Terminal/tmux focuser | CLI session 跳到具体 tab/pane | Ping `TerminalSessionFocuser`、DevIsland `TerminalFocuser`、AgentBro `jump.rs/tmux.rs` | 下一步迁移/重写 |
| Browser tab target | ChatGPT Web 跳到具体标签 | 我们现有 AppleScript tab focus | 已有 ChatGPTWeb target，后续扩展到 thread/tab id |
| IDE workspace target | Cursor/VSCode/Cline/Qoder | CodeIsland one-click jump | 后续用 `vscode://file` / `cursor://file` / workspace URL |

### P2：小窗快速推进

| 增量 | 目的 | 参考来源 | 风险控制 |
| --- | --- | --- | --- |
| 复制待处理摘要 | 不切窗口也能知道要点 | AgentBro completion/approval panel | 无写操作，先做 |
| 快速打开 + 聚焦输入 | 点击后跳到正确窗口并把用户带到输入位置 | DevIsland/Ping terminal focus | 只跳转，不注入文本 |
| AskUserQuestion 只读卡片 | 把问题/选项显示清楚 | DevIsland `SessionInterventionQuestion` | 先不提交答案 |
| Allow/Deny 手动按钮 | 在岛上处理权限 | CodeIsland/Notchi/Vibe Notch | 必须等 hook response path 稳定；默认禁用 |
| “本次会话允许” | 减少重复审批 | DevIsland/Ping scoped approval | 需要明示作用域和撤销入口 |

### P3：UI/动效/体验

| 增量 | 目的 | 参考来源 | 设计边界 |
| --- | --- | --- | --- |
| Completion queue | 多个完成事件依次展示，可关闭 | Ping completion notification，AgentBro completion panel | 不要长时间霸占屏幕 |
| Smart suppress | 用户已经看着对应终端/窗口时少打扰 | CodeIsland smart suppress | 需要精确 session focus，不只是 app frontmost |
| Usage/quota bar | 知道 Claude/Codex/ChatGPT 是否快到限制 | Notchi usage stats，TokenBar/ClaudeBar 类工具 | 只做可验证来源；未知就不显示 |
| Compaction 状态 | compaction 不等于异常 | Notchi 状态列表 | 加 `compacting` 内部状态，UI 显示“整理上下文” |
| 可选声音/触觉 | 等待批准/完成提醒 | CodeIsland/Notchi | 默认关闭或弱提醒 |
| mascot/情绪皮肤 | 情绪化反馈 | Notchi/CodeIsland | 后置；核心产品先保持工作台质感 |

### P4：开源/打包/安装

| 增量 | 目的 |
| --- | --- |
| Homebrew cask | 降低启动/安装复杂度 |
| Launch at login | 不需要每次手动 open |
| Hook installer UI | 不再让用户跑脚本 |
| Permission preflight | AX/Apple Events/Full Disk Access 状态可见 |
| License hygiene | GPL 项目只隔离参考，MIT/Apache 可保留 NOTICE |
| Crash-safe logs | 让用户能导出诊断包 |

## 下一步建议执行顺序

1. 完成 `JumpTarget` 第一阶段：Codex URL、ChatGPT Web、PID fallback 已接，下一步迁移 terminal/tmux。
2. 做 Codex rollout fallback parser，减少对 Claude Codex broker socket 的依赖。
3. 拆 `main.swift`：先把 `AgentLauncher` / `JumpTarget` / `CodexBroker` 移出去。
4. 设计 `PendingRequest` 只读模型，解决 allow/question 的 UI 表达。
5. 做 quick action 第一版：复制摘要、打开线程、关闭/稍后提醒；暂不做 allow/deny。
