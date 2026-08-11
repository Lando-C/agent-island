# Agent Island 迭代记录

> 这是按日期保留的工程历史记录，其中的文件位置、行号和产品状态可能已过时。
> 当前架构、安全边界和发布状态以根目录 README、`docs/ARCHITECTURE.md`、
> `SECURITY.md` 与 `docs/RELEASE.md` 为准。

## 2026-07-09 Iteration 1 - Session reducer / active tool state

目标：

- 先落实 Phase 1 的状态真实性，不做大 UI 重写。
- 修复 `PostToolUse` 被长期误判为 `工作中` 的问题。
- 为后续 approval proxy、小窗回复、Codex app-server 精准窗口跳转打状态层基础。

改动：

- 新增 [SessionStore.swift](Sources/AgentIsland/State/SessionStore.swift)。
- 新增 `SessionPhase` 和 `AgentSessionStore` reducer。
- `PreToolUse` 增加 active tool count。
- `PostToolUse` / `PostToolUseFailure` 消耗 active tool count。
- `PermissionRequest` / `Elicitation` / `PostToolUseFailure` 显示为 `需处理`，不再归类为普通异常。
- `Stop` / `SessionEnd` 显示为短期 `已完成`。
- 新增 `thinking` 状态，用于“工具已完成、可能等待模型下一步”的短暂状态，不计入 `工作中`。
- `done` 保留时间从 60 分钟收窄到 10 分钟。
- event reducer 入口增加重复 hook 去重，避免重复 `PreToolUse` 把 active tool count 抬高。
- working 状态优先展示最近 `PreToolUse`，避免出现“完成工具”却标 `工作中` 的文案矛盾。
- 新增 [validate-session-reducer](scripts/validate-session-reducer) 做回归验证。

验证：

- `swift build -c release` 通过。
- `scripts/validate-session-reducer` 通过以下对抗用例：
  - `PreToolUse -> PostToolUse` 不再是 `working`，而是 `thinking`。
  - 单独 `PreToolUse` 是 `working`。
  - 并行两个工具，完成一个后仍是 `working`。
  - `PermissionRequest` / `PostToolUseFailure` 是 `needs_attention`。
  - `Stop` 是 `done`。
  - 新工作开始会清掉旧 attention。
- 已重新打包并安装到 `/Applications/Agent Island.app`。
- 当前运行进程：`/Applications/Agent Island.app/Contents/MacOS/AgentIsland`。

遗留风险：

- active tool count 仍依赖 hook 成对出现；如果上游漏掉 `PostToolUse`，最多会在 30 分钟后过期。
- Codex App 多窗口精确跳转仍缺 thread/window 映射，需要接 app-server 协议。
- 小窗快速同意/回复尚未接管 hook response；当前 bridge 仍是 status-only。

下一步：

1. Iteration 2：重构 expansion/spotlight 交互，解决完成提示、hover、手动关闭之间的冲突。
2. Iteration 3：先修 app 点击跳转顺序，避免多窗口时提前随机激活。
3. Iteration 4：拆 `Models/` 并引入 `JumpTarget`，继续削薄 `main.swift`。

## 2026-07-09 Iteration 2 - Expansion / spotlight interaction controller

目标：

- 解决 hover 经过岛时可能重复展开/收起的问题。
- 让完成、等待推进、异常等自动提示可以明确关闭。
- 用户手动展开查看列表时，自动提示不能接管并把面板自动关掉。

改动：

- 新增 [IslandExpansionController.swift](Sources/AgentIsland/UI/IslandExpansionController.swift)。
- `IslandView` 不再直接维护 `autoExpandedUntil`、`suppressAutoSpotlightUntil`、hover work item 等分散状态。
- hover 展开、手动展开、自动 spotlight 分成不同 `ExpansionReason`。
- 自动 spotlight 到期时，如果鼠标仍在岛上，保持展开，等鼠标离开再收起。
- 用户点击关闭后：
  - 同一条 spotlight 两分钟内不再弹出。
  - 12 秒内抑制新的自动 spotlight，避免刚关闭又反弹。
  - 1.2 秒内抑制 hover 重新展开，避免关闭按钮附近触发回弹。
- `SpotlightSummary` 增加明确的关闭按钮。
- 顶部收起按钮在有 spotlight 时显示 `xmark`，语义变为“关闭本次提示”。
- 手动展开状态下收到 spotlight，只显示提示，不启动自动收起 timer。
- 新增 [validate-expansion-controller](scripts/validate-expansion-controller) 做交互状态机回归验证。

验证：

- `swift build -c release` 通过。
- `scripts/validate-session-reducer` 继续通过。
- `scripts/validate-expansion-controller` 通过以下对抗用例：
  - hover 尺寸变化造成的 exit/enter 抖动不会重复展开或意外收起。
  - 手动展开后，鼠标离开不会自动收起。
  - 用户关闭某条 spotlight 后，同一条提示不会马上反弹。
  - spotlight 到期时如果鼠标仍在岛上，会等 hover exit 后再收起。
  - 手动展开期间出现 spotlight，不会被自动 timer 关掉。

遗留风险：

- 这轮没有改点击跳转，所以 Codex/Claude 多窗口精确定位仍需后续 `JumpTarget`。
- 这轮没有接管 approval response，小窗同意/拒绝仍是下一步状态模型能力。

下一步：

1. Iteration 3：迁移 `JumpTarget` / Terminal / tmux / app-window focuser，修“点击随机跳一个窗口”。
2. Iteration 4：拆 `Models/`，让 `AgentSnapshot`、`AgentEvent`、`AgentPhase`、`JumpTarget` 从 [main.swift](Sources/AgentIsland/main.swift) 里移出。
3. Iteration 5：接入 pending request 数据模型，先做只读展示和快速跳转，不自动批准。

## 2026-07-09 Iteration 3 - App window focus order

目标：

- 修复点击 Codex/Claude App 行时，先激活宿主进程导致随机窗口被带到前台的问题。
- 为后续 `JumpTarget` 和 Codex app-server thread 路由铺路。

改动：

- `AgentLauncher.focus(_:)` 对 `.app` surface 改为先执行 `focusAppWindow(_:)`，标题匹配失败后才 fallback 到 `targetPID` 和 bundle 激活。
- `focusAppWindow(_:)` 的 AppleScript 改为先遍历更具体的 hint，再遍历窗口，避免短 session 前缀抢先匹配。
- `windowTitleHints(for:)` 保留顺序并按长度降序匹配，不再用 `Set` 打乱顺序。
- `windowTitleHints(for:)` 清理 UI 省略号 `…`，使缩略标题可以作为窗口标题前缀 hint。
- 过滤 `未命名对话` 和内部 task 文本，避免用无意义标题匹配窗口。

验证：

- `swift build -c release` 通过。
- 用 System Events 读取当前窗口标题，结果显示：
  - Codex 当前 3 个窗口标题均为 `Codex`。
  - Claude 有 `Claude` 和 `New session`。
  - ChatGPT 为 `ChatGPT`。
- 结论：这轮低风险修复可以防止“先随机激活”的路径，但 Codex App 精准跳到某个 thread 不能只靠窗口标题或 AX 文本，需要接 Codex app-server / URL route。

遗留风险：

- 当前 Codex App 的 AX window title 不包含 thread 信息，AX static text 也没有暴露会话标题。
- 需要下一轮引入 `JumpTarget` 和 Codex app-server monitor，基于 thread id 路由，而不是继续猜窗口。

下一步：

1. Iteration 4：做 `JumpTarget` 模型，把 app/window/thread/terminal/tmux 的跳转目标从 `AgentSnapshot` 里拆出来。
2. Iteration 5：接 Codex app-server thread list/read，验证是否能通过官方 app-server 路由 thread。
3. Iteration 6：接 terminal/tmux focuser，修 CLI 会话精准回跳。

## 2026-07-09 Iteration 4 - Codex broker read-only thread identity

目标：

- 验证 Codex App / Claude Codex plugin 当前暴露的 app-server/broker 能否被 Agent Island 安全读取。
- 修复 Codex App 基础行只靠进程在线、旧 goal 和 hook 事件猜测状态的问题。
- 过滤 Codex Companion stop-gate 内部线程，避免它们的 `systemError` 污染用户可见的“异常/需处理”统计。

调研结论：

- Ping Island 的可复用方向不是 UI，而是 Codex app-server `thread/list` / `thread/read` 的线程同步模型。
- AgentBro 的价值是 app-server readiness/probe 思路，说明先做探针和降级比直接做控制链路更稳。
- 当前本机 Claude Codex plugin 已有 broker socket：`/var/folders/.../T/cxc-B83VuS/broker.sock`。
- broker `thread/list` 能返回真实 Codex thread id、preview、cwd、rollout path、source、statusType。
- 当前返回的 40 条里，38 条是 `Codex Companion Task` / stop-gate 内部线程；这些不应该显示为用户任务，更不应该显示为 Codex 异常。

工程反思：

- 不继续猜 `codex://` URL route。路径格式未确认，直接调用可能有副作用。
- 不再依赖 AX window title 精准识别 Codex thread；当前 Codex 多窗口标题都是 `Codex`，AX 文本也不暴露 thread。
- Codex App 基础状态优先相信 broker 线程摘要；broker 没有活动/待处理信号时才回退到旧 goal。
- `notLoaded` 表示 broker 可读但该 thread 未加载，不等价于“待推进”或“工作中”。
- app-server 读取必须缓存和降级；刷新循环不能因为 broker socket 短暂不可用而卡 UI。

改动：

- 新增 [codex-broker-probe](scripts/codex-broker-probe)，通过 Claude Codex plugin broker socket 只读调用 `thread/list`。
- `AgentMonitor` 新增 `CodexBrokerThread` / `CodexBrokerSummary`，每 6 秒缓存读取一次 broker 线程。
- `readConversationInfo` 合并 broker 线程的 `preview` 和 `cwd`，让 Codex event 行不再只有短 session id。
- `makeCodexApp` 接入 broker summary：
  - 过滤 Companion / stop-gate 内部线程。
  - `running` / `processing` 等才算工作中。
  - approval/input/error 类状态显示为需处理。
  - `notLoaded` 只表示线程可读，不计入工作/待推进。
- Codex App target PID 优先选 `/Applications/Codex.app/Contents/MacOS/Codex` 主进程，减少点击时先落到 app-server 子进程的概率。
- [build-app](scripts/build-app) 现在会把 `scripts/` 打包进 `Contents/Resources/scripts`。
- 新增 [validate-codex-broker-probe](scripts/validate-codex-broker-probe) 验证 broker 可读和内部线程过滤。

验证：

- `swift build -c release` 通过。
- `scripts/validate-session-reducer` 通过。
- `scripts/validate-expansion-controller` 通过。
- `scripts/validate-codex-broker-probe` 通过：`threads=40 visible=2 auxiliary=38`。
- `scripts/build-app` 通过，包内存在 `Contents/Resources/scripts/codex-broker-probe`。
- 包内 probe 直接运行通过。
- 已重新安装并从 `/Applications/Agent Island.app` 启动，当前 PID：`84798`。

遗留风险：

- 这轮仍是只读 thread list，还没有接 `thread/read` 的 turn/status 细节，因此“正在生成/等待批准”的粒度取决于 app-server 当前 `statusType`。
- Codex App 精准跳到某个 thread 还没完成；下一步应基于 broker thread id 调研官方 route 或 app-server navigation 方法。
- Claude App 多窗口仍主要靠 hook pid/process chain，仍需引入统一 `JumpTarget`。

下一步：

1. Iteration 5：读取 Codex `thread/read`，提取当前 turn、approval/input request、last assistant/user 摘要。
2. Iteration 6：设计 `JumpTarget`，把 `AgentSnapshot.targetPID` 升级为 app/thread/window/terminal/tmux 的结构化目标。
3. Iteration 7：小窗 quick action 只先支持“打开对应线程/窗口”和“复制待处理摘要”，批准/拒绝等写操作等状态链路稳定后再接。

## 2026-07-09 Iteration 5 - Codex thread/read compact turn details + thread URL jump

目标：

- 在 `thread/list` 之外读取 Codex `thread/read`，提取 last turn 摘要，改善“正在做什么 / 是否完成 / 是否待推进”的判断。
- 不把完整 turns 历史塞进 Swift；只传递压缩字段。
- 用已经验证的 Codex thread URL 修复具体 Codex App 会话点击跳转。

调研结论：

- `thread/read` 参数为：
  - `threadId`
  - `includeTurns: true`
- 返回结构顶层为 `{"thread": ...}`，thread 内包含：
  - `status.type`
  - `turns[]`
  - turn 的 `status` / `startedAt` / `completedAt`
  - item 类型如 `userMessage`、`agentMessage`、`fileChange`
- 实测当前 Codex thread：
  - `thread/list.status.type = notLoaded`
  - `thread/read.turns[-1].status = interrupted`
  - 结论：`notLoaded` 不能当工作/待推进；last turn status 才能补充“本轮是否完成/中断”。
- Ping Island 本地源码确认 Codex thread URL：
  - `codex://threads/{threadId}`
- 本机实测 `open codex://threads/019f1bc0-...` 返回 0，并切到 Codex 前台。

改动：

- [codex-broker-probe](scripts/codex-broker-probe) 新增：
  - `--read-visible-details`
  - `--read-limit`
  - 只对过滤后的可见线程调用 `thread/read`
  - 输出压缩字段：`turnCount`、`lastTurnStatus`、`lastUserText`、`lastAgentText`、`lastWorkLabel`、`activeItemCount`、`failedItemCount`
- [main.swift](Sources/AgentIsland/main.swift) 新增 Codex last-turn 字段解码。
- Codex broker phase 规则升级：
  - `activeItemCount > 0` → `工作中`
  - `failedItemCount > 0` → `需处理`
  - `waiting_for_input` / `waiting_for_approval` / `input_required` → `需处理`
  - `interrupted` / `cancelled` → `待推进`
  - `completed` 且 10 分钟内 → `已完成`
  - `notLoaded` 仍只表示可读，不单独计入工作/待推进
- `validate-codex-broker-probe` 升级：
  - broker 可读时验证可见线程有 compact `thread/read` 详情
  - 验证内部 Companion/stop-gate 线程没有被展开
  - broker 不在线时输出 `SKIP`，不让本地构建失败
- `AgentLauncher` 对具体 Codex App session 优先打开 `codex://threads/{sessionID}`，失败后才回退到窗口标题和 PID。

验证：

- `swift build -c release` 通过。
- `scripts/validate-session-reducer` 通过。
- `scripts/validate-expansion-controller` 通过。
- broker 可读时曾验证：`threads=40 visible=2 visible_with_details=2 auxiliary=38`。
- broker 不在线时验证脚本输出：`SKIP codex_broker_probe unavailable: no broker sockets found`。
- `open codex://threads/019f1bc0-289e-7910-b8f1-1bcdf4432c60` 返回 `EXIT:0`，前台应用变为 `Codex`。

工程反思：

- Claude plugin broker 是 opportunistic source，不应该被当作必有依赖。它不在线时 app 必须正常降级。
- `thread/read` 详情读取有成本，当前限制为最多 8 个可见线程；下一步如果要常驻实时监控，应改成持久连接或单独后台 actor。
- Codex thread URL 已经实测可用，可以先解决“点击随机窗口”的主要痛点；长期仍应把 `targetPID` 升级为结构化 `JumpTarget`。

遗留风险：

- `thread/read` 只通过 Claude Codex broker 可读；如果只运行 Codex Desktop 内置 app-server 而 broker 不在，仍只能依赖 hook/sqlite/rollout fallback。
- `interrupted` 的语义可能覆盖用户主动中断和当前会话被外部打断两种情况；目前保守显示为 `待推进`，不是异常。
- Claude App 多窗口精准跳转还没用 URL/thread route 解决。

下一步：

1. Iteration 6：正式引入 `JumpTarget`，让 Codex URL、ChatGPT tab、app PID、terminal/tmux 走统一跳转结构。
2. Iteration 7：读取 Codex rollout fallback 的 last turn summary，降低对 broker socket 的依赖。
3. Iteration 8：小窗 quick action 先做“复制待处理摘要 / 打开对应线程”，写入型 approval response 后置。

## 2026-07-09 Iteration 6 - Increment brainstorm + JumpTarget foundation

目标：

- 基于本地竞品代码和外部项目，重新梳理下一阶段增量。
- 引入 `JumpTarget` 基础模型，避免点击跳转继续只靠 `targetPID`。
- 先把已验证的 Codex thread URL 和 ChatGPT Web tab focus 接到统一结构上。

调研补充：

- 新增 [next-increments-brainstorm.md](research/next-increments-brainstorm.md)。
- GitHub API 校验的新增参考项目：
  - CodeIsland：2070 stars，MIT，多 agent + permission/question + jump + mobile companion。
  - Vibe Notch：2439 stars，Apache-2.0，Claude Code notifications/session manager。
  - Notchi：942 stars，GPL-3.0，Claude Code/Codex notch companion，含 compaction/usage/sound/mascot。
  - DynamicNotch：428 stars，GPL-3.0，notch 系统 surface。
  - NotchDrop：2070 stars，MIT，notch shelf/AirDrop，提示“待处理队列/shelf”可作为交互模式参考。

改动：

- 新增 [JumpTarget.swift](Sources/AgentIsland/Models/JumpTarget.swift)：
  - `url`
  - `process`
  - `app`
  - `chatGPTWeb`
- `AgentSnapshot` 增加 `jumpTarget`。
- `AgentLauncher.focus` 现在优先尝试 `jumpTarget`，失败才走旧 fallback。
- Codex App 具体 session snapshot 自动生成 `codex://threads/{sessionID}`。
- ChatGPT Web 基础行使用 `.chatGPTWeb`。

验证：

- `swift build -c release` 通过。
- `scripts/validate-session-reducer` 通过。
- `scripts/validate-expansion-controller` 通过。
- `scripts/validate-codex-broker-probe` 通过：`threads=40 visible=2 visible_with_details=2 auxiliary=38`。

工程反思：

- `JumpTarget` 要继续扩成真正的 route model，而不是只当 URL/PID 包装：
  - terminal/tmux pane
  - browser app/window/tab URL
  - IDE workspace URL
  - app bundle + thread id
- CodeIsland 的能力矩阵说明我们应该尽早显式建 `ProviderCapability`，不要把“能不能 approval / 能不能 jump / 能不能 reply”写死在 UI。

下一步：

1. 迁移 terminal/tmux focuser，补 `.terminal` / `.tmux` JumpTarget。
2. 做 Codex rollout fallback last-turn parser，broker 不在线也能读 Codex App 最近状态。
3. 把 `AgentLauncher` 从 `main.swift` 拆到 `Services/Focus/`。

## 2026-07-09 Iteration 7 - Terminal/tmux JumpTarget foundation

目标：

- 迁移 terminal/tmux focuser 思路，解决 CLI 会话点击只能按 PID 粗略聚焦、无法回到具体 tab/pane 的问题。
- 拉取并对比 Vibe Notch / MioIsland，补齐功能覆盖矩阵。
- 不把竞品大块源码直接混入 `Sources/AgentIsland`，先 clean-room 落一个可验证的最小跳转层。

调研结论：

- Vibe Notch 已浅克隆到 `research/competitors/repos/new-20260709/vibe-notch`，Apache-2.0，可参考 hook socket、approval、chat history、tmux target、terminal visibility。
- MioIsland Git 对象已在 `research/competitors/repos/new-20260709/MioIsland`，checkout 受网络/大目录影响未完整展开；已通过 README 和关键源码读取确认 TerminalJumper、CodexHookInstaller、HookDiagnostics、AskUserQuestion、QuickReply、ProcessLiveness 等方向。
- Ping / DevIsland / AgentBro 的一致结论是：终端会话身份应按 `tmux pane > tty > terminal app/window > cwd/title fallback` 递减，而不是只用在线状态或 PID。

改动：

- [JumpTarget.swift](Sources/AgentIsland/Models/JumpTarget.swift) 新增：
  - `TerminalJumpTarget`
  - `TmuxJumpTarget`
  - `.terminal(...)`
  - `.tmux(...)`
- 新增 [TerminalFocuser.swift](Sources/AgentIsland/Services/Focus/TerminalFocuser.swift)：
  - tmux：支持 `-S socket select-window/select-pane`，有 client 时尝试 `switch-client`。
  - iTerm2：AppleScript 按 tty/session/title 选择 session。
  - Terminal.app：AppleScript 按 tty/title 选择 tab。
  - WezTerm：先按 pane id，再按 CLI list 的 tty/cwd 查 pane。
  - kitty：先按 window id，再按 cwd 远程聚焦。
  - Ghostty：按 working directory/title AppleScript 尝试聚焦 terminal。
  - Warp / cmux / Kaku：先做 app activation fallback，后续继续深化。
- [agent-island-bridge.py](scripts/agent-island-bridge.py) 写入终端元数据：
  - `cwd`
  - `terminal_app`
  - `terminal_bundle_id`
  - `terminal_tty`
  - `terminal_window_id`
  - `terminal_tab_index`
  - `terminal_session_id`
  - `terminal_tmux_pane`
  - `terminal_tmux_socket`
  - `terminal_tmux_client`
- `AgentEvent` 解码新增上述字段。
- CLI event snapshot 的 `jumpTarget` 优先生成 `.tmux`，其次 `.terminal`，最后才 `.process(pid:)`。
- 新增 [feature-coverage-matrix.md](research/feature-coverage-matrix.md) 覆盖用户列出的功能，并标出当前完成/部分完成/未完成状态。

验证：

- `python3 -m py_compile scripts/agent-island-bridge.py scripts/codex-broker-probe scripts/validate-codex-broker-probe` 通过。
- `swift build` 通过。
- `scripts/validate-codex-broker-probe` 通过：`threads=40 visible=2 visible_with_details=2 auxiliary=38`。
- 模拟 hook：
  - 输入 `TERM_PROGRAM=iTerm.app TMUX=/tmp/tmux-501/default,123,0 TMUX_PANE=%8 TTY=/dev/ttys778 ITERM_SESSION_ID=w0t0p0:agent-island-test-2`
  - 写出的 event 包含 `terminal_app=iTerm2`、`terminal_bundle_id=com.googlecode.iterm2`、`terminal_tty=/dev/ttys778`、`terminal_tmux_pane=%8`、`terminal_tmux_socket=/tmp/tmux-501/default`。
- 修复了测试中发现的污染：`__CFBundleIdentifier=com.openai.codex` 不再被误当成终端 bundle。

遗留风险：

- 这轮没有做 Warp sqlite tab、cmux surface、Kaku CLI 的精确跳转。
- Hook 事件在 Codex App 环境里运行时 surface 仍可能被判断为 `app`；真实 CLI hook 的 terminal/tmux 字段已具备，但还需要在用户实际 CLI 会话中验证。
- `.tmux` 只在 hook 提供 `TMUX_PANE` 时精准；没有 hook 元数据的旧事件仍只能 fallback 到 PID。

下一步：

1. 深化 Ghostty / Warp / WezTerm / kitty / cmux / Kaku 的具体跳转。
2. 引入 `PendingRequest` 模型，把 allow/question/request_user_input 结构化显示。
3. 做诊断页第一版：Hook、Socket、Broker、tmux、Apple Events、Accessibility、terminal jump、ChatGPT browser、LaunchAtLogin。

## 2026-07-09 Iteration 8 - Diagnostics export + auto-approval trust boundary

目标：

- 把“环境依赖”从模糊故障变成可见诊断项。
- 沉淀产品蓝图，明确开源产品定位、竞品代码复用边界、自动审批信任边界、离岛/吉祥物/诊断路线。
- 先做默认关闭的自动审批策略层，只给事件打风险标记，不突然改变用户工作流。

改动：

- 新增 [PRODUCT_BLUEPRINT.md](docs/PRODUCT_BLUEPRINT.md)：
  - 产品定位：AI Agent Operations Island。
  - Vibe Notch / MioIsland / Ping / DevIsland / AgentBro 参考模块表。
  - 自动审批信任边界。
  - 诊断面板覆盖项。
  - 离岛模式和吉祥物的信息设计定位。
  - 开源发布 checklist。
- 新增 [agent-island-diagnostics](scripts/agent-island-diagnostics)，覆盖：
  - App 是否运行在 `/Applications`。
  - Hook bridge 是否存在且可执行。
  - Claude / Codex hooks 是否安装。
  - Codex hooks feature。
  - Events log / app log。
  - Accessibility / Apple Events。
  - Codex broker probe。
  - tmux 和终端跳转辅助工具。
  - Codex / Claude / ChatGPT / browser surface。
  - Auto approval 配置状态。
- 状态栏菜单新增：
  - `Copy Diagnostics Report`
  - `Open Accessibility Settings`
  - `Open Notification Settings`
  - `Open Login Items Settings`
- [agent-island-bridge.py](scripts/agent-island-bridge.py) 新增风险分类字段：
  - `tool_risk`
  - `tool_risk_reason`
  - `auto_approval_eligible`
- 自动审批默认关闭，配置路径为 `~/.agent-island/auto-approval.json`。
- 只读候选仅限 `Read` / `Grep` / `Glob` / `LS` / `TodoRead`。
- `Bash` / `Shell` 即使看起来只读，当前也只标 `manual_safe_shell`，不自动通过。
- `Write` / `Edit` / `MultiEdit` / destructive shell token 永不自动通过。
- [install-hooks](scripts/install-hooks) 帮助文本更新，明确默认 status-only。

工程反思：

- 自动审批必须先可解释，再可启用。直接把 allow/deny 接上会造成“它什么时候替我决定”的信任缺口。
- 诊断能力应该先从菜单复制报告落地，再升级成 App 内 Diagnostics tab；这样立刻能服务反馈和排障。
- `Codex` approval response schema 暂不接管，避免默认行为跨引擎不一致。

下一步：

1. 把 diagnostics report 做成设置页的 Diagnostics tab，并给 repairable item 接按钮。
2. 引入 `PendingRequest`，让 approval / request_user_input / AskUserQuestion 结构化显示。
3. 增加 `ZombieDetector`，让 pid/tmux pane 退出时会话自动 ended。

## 2026-07-09 Iteration 9 - Productization docs + Settings diagnostics + risk labels

目标：

- 回应“不是只给本机用，而是别人能从 GitHub 下载使用”的产品形态问题。
- 把 Vibe Notch、MioIsland、Ping、DevIsland、AgentBro 的代码级复用点拆成可执行矩阵。
- 把自动审批风险标记展示到 UI 文案里，让等待审批不是模糊的“异常”。

改动：

- 新增 [CODEBASE_INTEGRATION_MATRIX.md](docs/CODEBASE_INTEGRATION_MATRIX.md)：
  - 按 Hook transport、Hook installer、状态 reducer、审批语义、request_user_input、聊天详情、Codex app、终端跳转、智能抑制、notch geometry、诊断、声音、吉祥物、离岛、发布打包逐项对比。
  - 明确 Vibe Notch Apache-2.0 可优先迁移；MioIsland 本地快照未发现 LICENSE，暂不复制进开源主线；BoringNotch GPL 只做 clean-room 参考。
  - 明确诊断里的 tmux、WezTerm、kitty、Warp、cmux、Kaku 是可选能力缺口，不是统一失败。
- 新增 [RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md)，定义 GitHub release zip、checksum、README、third-party notices、隐私说明、签名/notarization/Homebrew 路线。
- 重写 [README.md](README.md)，改成外部用户视角：
  - 安装、首次启动、权限、hook、诊断、安全边界、隐私、产品路线。
- 更新 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，加入 Vibe Notch reference 和 research-only references。
- [AgentEvent](Sources/AgentIsland/main.swift) 解码新增：
  - `tool_risk`
  - `tool_risk_reason`
  - `auto_approval_eligible`
- 审批/等待处理行文案新增风险标签：
  - `safe_read` → `只读可自动`
  - `manual_safe_shell` → `Shell 需确认`
  - `dangerous_shell` / `dangerous_tool` → `危险需人工`
  - `manual_unknown` → `未分类需人工`
- 功能覆盖矩阵同步更新：
  - 宽度设置、开机自启、Settings diagnostics 已完成基础版。
  - 下一步诊断从纯文本升级为结构化可修复项。

工程反思：

- 本机没有某个 terminal helper 不等于产品失败。产品应该告诉用户“你的环境具备哪些跳转能力、缺哪些可选 helper、如何修复必需项”。
- 直接复制竞品源码不是目标，复制后仍要符合我们的产品状态机和许可证边界。能复制的优先从 Apache/MIT 迁移；未知/GPL 的项目只能做行为对照。
- 自动审批的 UI 必须解释边界，否则用户会产生“它是不是偷偷帮我点了”的不信任。

## 2026-07-09 Iteration 10 - Quick actions + Escape close

目标：

- 不把“快速回复/推进”继续停留在文档里，先做不危险、可立即使用的基础动作。
- 避免复制摘要按钮误触发行点击跳转。
- 加上 Escape 关闭展开面板，降低完成/等待提示对工作的打扰。

改动：

- `AgentSnapshot` 新增 `hasQuickActions`，对 `需处理 / 待推进 / 已完成 / 异常` 显示快速动作。
- 新增 `AgentSnapshotSummary`，复制内容包含：
  - title
  - agent / surface / status
  - detail
  - session
  - last updated
  - jump target 描述
- `AgentRow` 从“外层整行 Button”改为：
  - 左侧主体按钮：打开对应会话。
  - 右侧独立按钮：复制推进摘要、打开对应会话。
  - 避免复制动作同时触发跳转。
- `SpotlightSummary` 增加同样的复制/打开按钮。
- `IslandView` 增加复制反馈，复制后图标短暂变成 checkmark。
- 新增 `AgentIslandControlKeys.collapseRequested`。
- `AppDelegate` 增加 local/global Escape key monitor；展开时按 Escape 会通过通知让 `IslandExpansionController.dismissByUser()` 关闭面板。

验证：

- `scripts/validate-session-reducer` 通过。
- `scripts/validate-expansion-controller` 通过。
- `scripts/validate-codex-broker-probe` 通过。
- `swift build` 通过。

遗留风险：

- 这轮仍然没有接管真实 allow/deny，也没有把 request_user_input 选项写回 agent；这是下一轮 `PendingRequestStore + HookSocketServer` 要做的事情。
- Global Escape 依赖 macOS 对辅助功能/输入事件的授权状态；本地 monitor 在面板获得键盘事件时可工作。

## 2026-07-09 Iteration 11 - Pending request fields in events and summaries

目标：

- 让“需要审批/推进”的行不只是显示工具名，还能看到关键输入，比如 Bash command、path、pattern。
- 为后续 `PendingRequestStore` 和 allow/deny socket 链路提前补齐 request id。

改动：

- [agent-island-bridge.py](scripts/agent-island-bridge.py) 新增：
  - `request_id(payload)`
  - `tool_input_value(payload)`
  - `tool_input_summary(payload)`
- 写入事件时新增字段：
  - `request_id`
  - `tool_input_summary`
- `AgentEvent` 解码新增：
  - `requestID`
  - `toolInputSummary`
- `AgentSnapshot` 新增同名摘要字段和风险字段，供 UI 和复制摘要使用。
- `eventActionText` 对 `PreToolUse` 和 approval/failure 类事件显示工具输入摘要。
  - 示例：`工具: Bash · command: git status --short`
  - 示例：`等待允许/处理: Bash · command: git status --short · Shell 需确认`
- `AgentSnapshotSummary` 复制摘要会包含 request id、tool input 和 risk reason。

验证：

- `python3 -m py_compile scripts/agent-island-bridge.py scripts/codex-broker-probe scripts/validate-codex-broker-probe` 通过。
- 模拟 Claude `PermissionRequest`：
  - 输入 `tool_use_id=tool-1`
  - 输入 `tool_input.command=git status --short`
  - 写出事件包含 `request_id=tool-1`、`tool_input_summary=command: git status --short`、`tool_risk=manual_safe_shell`
- 临时测试事件已从 `~/.agent-island/events.jsonl` 清理。
- `swift build` 通过。
- `scripts/validate-session-reducer` 通过。
- `scripts/validate-expansion-controller` 通过。
- `scripts/validate-codex-broker-probe` 通过。

## 2026-07-09 Iteration 12 - Option-N global toggle

目标：

- 落地用户要求的 `⌥N` 切换灵动岛。
- 和 Escape 一样通过 `IslandExpansionController` 状态机处理，不绕过现有 hover/spotlight 规则。

改动：

- `AgentIslandControlKeys` 新增 `toggleRequested`。
- `IslandView` 监听 toggle notification 并调用 `expansion.toggleFromHeader()`。
- `AppDelegate.setupKeyMonitors()` 增加 local/global `Option-N` 检测。
- 状态栏菜单新增 `Toggle Island`，快捷键显示为 `⌥N`。
- 如果面板已被 Hide Island 隐藏，`Option-N` 会先重新显示面板，再切换展开状态。

验证：

- `swift build` 通过。

## 2026-07-10 Iteration 13 - Expansion render-loop fix and current-product audit

触发场景：

- 通过 macOS Accessibility 执行收起态 header 的 Press action 后，Agent Island 持续占用约 100% CPU 并失去响应。
- 采样栈显示主线程先进入同步窗口 resize，随后长期停留在 SwiftUI AttributeGraph transaction flush。

根因与修复：

- `PendingRequestStore.request(for:)` 是 SwiftUI render path 上的查询，却调用 `prune()` 修改 `@Published requests`。
- 即使没有记录被删除，原先的 `removeAll` 也会发布变化，形成 render -> query -> publish -> render 循环。
- `request(for:)` 已改为纯读取；`prune()` 只有真正删除记录时才替换数组并发布。
- AppDelegate 的面板 frame 更新改为下一轮主线程执行、合并重复请求，并使用非阻塞 `NSAnimationContext` 动画，避免 Accessibility action 中的 AppKit 嵌套事件循环。

真实 UI 回归：

- Accessibility Press 可展开。
- 展开后的完整辅助功能树可在约 1 秒读取。
- ScrollView 和所有当前行可见。
- 再次 Press 可正常收起，进程不再持续 100% CPU。

验证：

- `swift build` 通过。
- `scripts/validate-session-reducer` 通过。
- `scripts/validate-expansion-controller` 通过。
- 重新构建并安装 `/Applications/Agent Island.app`。

审计结论：

- 当前产品属于 internal alpha，全部需求综合覆盖约 40%。
- 当前首要缺口仍是旧会话/僵尸状态、availability 与 activity 分层、多窗口会话身份、精准跳转和真实 Swift/UI 测试。
- 本机诊断为 `PASS=19 WARN=14 FAIL=0`；WARN 主要是可选终端能力和当前未运行的应用。

## 2026-07-10 Iteration 14 - State trust and production Swift tests

目标：

- 修复“已安装就显示在线”的状态语义错误。
- 让超过 12 小时没有活动的等待/异常事件退出面板，避免旧测试或死会话持续显示“需要处理”。
- 用真正执行生产 Swift reducer/store 的测试保护状态可信度和上一轮 render-loop 修复。

改动：

- `AgentPhase` 新增 `available`，中文显示为“已安装”。
- Codex CLI、Claude CLI、Claude Science Runtime 只有可执行文件但没有运行信号时使用 `available`，不再使用 `online`。
- 收起态活动摘要排除 `available`，已安装能力只在展开列表中作为低优先级信息展示。
- 新增共享 `SessionRetentionPolicy`：
  - working 30 分钟
  - thinking 90 秒
  - queued / done 10 分钟
  - idle / online / available 1 小时
  - needs attention / error 12 小时
- 新增 SwiftPM `AgentIslandTests` 和 `scripts/test-swift`，兼容只有 Command Line Tools 与完整 Xcode 的开发环境。
- CI、贡献指南和 PR checklist 已接入生产 Swift 测试。
- Hook 事件日志改为按 size/mtime 判定，并对普通追加只读取新增字节；截断、轮转或缺失时才重建缓存。
- 已解析事件和去重 key 增量维护，未变化时不再重复归一化 1200 条事件。
- Bridge 日志超过 2000 行时裁到 1500 行，留下追加缓冲区，避免每个 Hook 都重写整份 JSONL。
- process、Claude tasks、Codex goals、Claude Science、Codex broker、ChatGPT 和磁盘会话索引按变化频率分层节流。
- snapshot 只有语义字段变化时立即发布；纯时间戳变化最多 10 秒发布一次。
- 根视图和工作波形移除 `repeatForever` 60 fps 动画，改为低频状态动效并遵循 Reduce Motion。

生产回归覆盖：

- 等待审批在 12 小时内仍可见。
- 等待审批超过 12 小时后被清理。
- 同一会话的新工作事件会清除更早的需处理状态。
- `available` 与 `online` 语义、排序保持分离。
- `PendingRequestStore.request(for:)` 在 SwiftUI 渲染查询期间不会发布 `objectWillChange`。
- JSONL 多条完整记录和跨 chunk 半条记录均正确解码。
- snapshot 仅时间戳变化时判定为 display-equivalent，真实 detail/phase 变化仍会触发发布。

验证：

- `scripts/test-swift`：8 个测试、3 个 suite 全部通过。
- `swift build` 通过。
- Python 与 Shell 入口语法检查通过。
- `validate-session-reducer` 与 `validate-expansion-controller` 全部通过。
- `validate-codex-broker-probe` 因本机当前无 broker socket 正常跳过。
- 安装版真实 UI 展开/收起正常，Codex CLI 与 Claude Science Runtime 显示“已安装”而非“在线”。
- 持续 CPU 从最初 40–90% 降至活跃任务场景 45 秒平均约 8.5%；主线程采样 97% 以上时间休眠。
- 安装版诊断：`PASS=19 WARN=14 FAIL=0`。

工程反思：

- availability、liveness、activity 是三种不同事实，不能继续压成一个“在线”标签。
- 12 小时 TTL 能清理陈旧状态，但不能证明进程是否仍活着；下一轮仍要用 pid、terminal 和 tmux liveness 做主判据。
- 测试必须直接执行生产 reducer/store，Python 镜像验证只能作为协议补充，不能替代 Swift 回归。
- 常驻工具的动效应表达状态而不是占满刷新率；fallback 探针也必须按信号变化频率分层，而不是共用一个高频轮询周期。

## 2026-07-28 Iteration 15 - Codex broker protocol fixtures and fail-closed mapping

目标：

- 为 Codex app-server 当前支持的四类交互请求建立可回放、脱敏的协议 fixture。
- 让 socket 客户端只负责连接与请求生命周期，把请求/回复映射收敛到可独立验证的纯逻辑层。
- 核对 Diagnostics 中 transport route、protocol 和 endpoint 的展示。

协议依据：

- 使用本机 Codex CLI 的
  `codex app-server generate-json-schema --experimental` 生成当前协议 schema；
  fixture 记录生成版本 `codex-cli 0.145.0`。
- 覆盖 `item/tool/requestUserInput`、
  `item/commandExecution/requestApproval`、
  `item/fileChange/requestApproval` 和
  `item/permissions/requestApproval`。
- fixture 只包含通用的 redacted thread、turn、item、cwd 和命令示例，不包含真实会话内容、用户路径、凭证或 broker endpoint。

改动：

- 新增 `CodexBrokerProtocol`，集中处理四类 server request 到
  `HookSocketRequest` 的映射，以及用户决定到 JSON-RPC result 的映射。
- `CodexBrokerClient` 保留 socket、RPC id、pending lifecycle 和 transport
  health 职责，不再重复维护协议 payload 逻辑。
- 新增四个 JSON fixture 和 `CodexBrokerProtocolTests` 回放：
  - requestUserInput：多问题、选项、Other 和结构化 answers。
  - command approval：数字 RPC id、命令摘要和 accept。
  - file approval：reason/grantRoot 和 decline。
  - permissions approval：原始 permission profile 和 turn scope。
- 请求映射现在验证 schema 必需的 threadId、turnId、itemId、startedAtMs、
  cwd、questions 和 permissions；缺失或畸形时不创建可写回请求。
- permissions allow 在原始 permission profile 无法解析时返回 nil，不再生成
  空权限回复；command/file approval 收到错误 decision 类型时也不再隐式 decline。
- JSON-RPC id 和 startedAtMs 只接受协议允许的整数形态，不接受 Bool 或小数；
  command approval 若未提供本 UI 支持的 accept/decline 组合则不创建岛内请求。
- 如果本地状态异常导致无法生成 Codex result，PendingRequest 会回写为 failed，
  不再停留在“已允许/已回复”的假成功状态。
- 已知交互方法若字段或本地回复不受支持，会返回标准 JSON-RPC error 并结束请求，
  避免 broker 一直等待一个永远不会到达的 result。
- Settings Diagnostics 继续分别显示 Route/Protocol 和 Endpoint；endpoint 只在
  确实位于用户 home 下时缩写为 `~`，避免对中间字符串做错误替换。

验证：

- macOS 15.4 SDK 下 Debug build 通过。
- `scripts/test-swift` 完成主程序、12 个测试文件和 fixture resource bundle
  的编译与链接。
- macOS 15.4 SDK 下 Release build 通过。
- Python、Browser Bridge JavaScript/manifest、Shell、installer command
  surface 检查通过。
- Session reducer 和 expansion controller 回归通过。
- Codex broker probe 因当前没有 live broker socket 正常跳过。
- 当前机器只有 Command Line Tools，没有完整 `Xcode.app` / `xctest` runner；
  XCTest 的实际执行仍需由 GitHub Actions 的 macOS runner 完成。

遗留边界：

- 当前 fixture 来自官方生成 schema，并非真实用户会话抓包。后续仍需采集脱敏
  live broker 帧，用于发现 provider version 与生成 schema 之间的偏差。
- `acceptForSession`、execpolicy amendment、network policy amendment 和
  permission session scope 尚未开放给岛内 UI，不从本轮 fixture 推断支持。

## 2026-07-28 Iteration 16 - Provider compatibility and terminal capability contracts

目标：

- 把 Claude Hook 和 Browser Bridge 的 provider/version 变化变成可回放的
  兼容性测试，而不是依赖人工发现上游已经漂移。
- 当网页 selector、detector 或协议版本不匹配时，显式报告 degraded，并保留
  最后一条可信会话状态。
- 为终端 exact/context/fallback/unavailable 建立不依赖本机安装环境的保守
  判定契约，覆盖 helper 缺失、多窗口歧义和过期 metadata。

Claude fixture：

- 新增 Claude Code `2.1.191` 版本锚定的三类脱敏 fixture：
  `PermissionRequest`、`PreToolUse/AskUserQuestion` 和 `Elicitation`。
- Fixture 同时保留 documentation-derived provenance、脱敏说明、原始 Hook、
  bridge frame、归一化 socket request 和预期写回。
- Python 回放直接调用生产 `agent-island-bridge.py` 的 event/normalizer；
  Swift 回放直接调用生产 `PendingRequestStore` 和
  `HookSocketServer.responseData`。
- 未知 Claude 交互仍映射为 `status_only`；fixture 不冒充真实 stdin 抓包，
  后续仍需用脱敏 live frame 对比版本偏差。

Browser Bridge v3：

- 事件新增 `detector_version`、provider-specific `selector_profile` 和
  `selector_state`。
- ChatGPT、Claude、Codex Web 只有在主页面和 composer anchor 组均存在时，
  才能把 stop/approval control 的有无解释为会话状态。
- 协议、detector、profile 或 selector 漂移统一写入 Transport Diagnostics
  的 degraded 状态；degraded frame 不写 `events.jsonl`，不会把未知状态
  转成假的 idle、working 或 needs-attention。
- v1/v2 仍可解码以给出升级诊断，但因没有 selector provenance，不再覆盖
  可信 session truth。
- 新增三类正常 provider fixture 和一类 selector-drift fixture；扩展版本
  升至 `0.3.0`。

终端能力契约：

- 新增 `TerminalFocusCapabilityResolver`，只在 helper 可用、metadata 新鲜且
  stable ID 唯一时返回 `exact`。
- 唯一 TTY/CWD 只返回 `context`；helper 缺失、metadata 过期、重复 ID 和
  多窗口 TTY/CWD 歧义均降为 `fallback`，连应用级 fallback 都不存在时为
  `unavailable`。
- 当前契约和 fixture 是 terminal adapter 的离线验收边界；后续仍需把各终端
  的实时 metadata adapter 接到这一共享判定，并完成真机矩阵。

验证：

- Claude Python fixture replay：2 个测试全部通过。
- macOS 15.4 SDK 下 Debug 主程序、全部 Swift 测试 target 和 Release 构建
  通过。
- Browser Bridge JavaScript、manifest/fixture JSON、Python 和 Shell 语法
  检查通过。
- Session reducer、expansion controller 回归通过；Codex broker probe 因
  当前没有 live broker socket 正常跳过。
- 本机仍只有 Command Line Tools；XCTest runner 缺少完整 Xcode PlatformPath，
  真实 XCTest 执行继续由 GitHub Actions macOS runner 强制完成。

遗留边界：

- Claude fixture 是官方 Hooks Reference 派生并按本机 provider 版本锚定，
  Browser fixture 是合成的 selector contract；两者都仍需要真实脱敏样本。
- Browser selector 只能作为非权威网页信号，不能扫描对话文字或替代 Hook/
  broker 审批协议。
- Terminal capability resolver 尚未替代各 terminal focuser 的运行时探针；
  真机 exact/context/fallback 矩阵仍是下一轮工作。

## 2026-07-28 Iteration 17 - Runtime focus contracts and redacted diagnostics history

目标：

- 把 Iteration 16 的 terminal capability policy 接入真实 helper metadata，
  避免测试模型与生产 route 分离。
- 建立有界、可查看、默认脱敏的传输诊断历史，帮助复现短暂 degraded/failure。
- 收敛 Swift App 内重复的 Codex broker socket 发现和连接边界。

终端运行时接线：

- WezTerm `cli list --format json` 和 kitty `@ ls` 的真实输出先解析为统一
  `TerminalFocusCandidate`，再交给 `TerminalFocusCapabilityResolver`。
- 只有 helper 退出成功、JSON 有效、metadata 新鲜且 stable ID/TTY/CWD
  唯一匹配时，才会执行目标激活并报告 `exact` 或 `context`。
- helper 缺失、非零退出、无效 JSON、重复 stable ID、多窗口上下文歧义、
  未匹配、pane/window 激活失败或 App 激活失败均保守降为
  `fallback/unavailable`。
- Diagnostics route 同时记录精度和降级原因；新增 WezTerm/kitty helper
  shape、路径规范化和歧义回退测试。

脱敏 Diagnostics history：

- 新增 `DiagnosticsHistoryStore`，本地最多保留 100 条 transport 状态变化，
  连续同态记录自动去重。
- 只保存 transport id/name、state、protocol/route、脱敏 endpoint、错误摘要
  和时间；不保存对话、命令、原始 event/payload 或凭证。
- URL user/password/query/fragment、Bearer、API key/token/secret、UUID、home/
  temp/TTY/任意绝对路径均在持久化前处理；文件权限固定为 `0600`。
- Settings Diagnostics 展示最近 12 条，明确说明数据边界。
- 测试覆盖上限、去重、顺序、重载、权限和秘密不落盘。

Codex broker 边界：

- 新增 `CodexBrokerEndpoint`，统一 Swift App 内显式 override、临时目录扫描、
  mtime 排序、路径去重、顺序连接和首个成功停止。
- `CodexBrokerClient` 删除重复 discovery/connect 实现，协议初始化、请求解析
  和未知 schema fail-closed 语义保持不变。
- Python `codex-broker-probe` 继续作为 App 未运行时的独立诊断入口；架构文档
  明确两端遵守同一发现顺序，但生产 App 不调用脚本或建立第二条连接。

验证：

- macOS 15.4 SDK 下生产 App 和全部 XCTest target 编译、链接通过。
- Diagnostics、Codex endpoint 和 terminal helper 新测试均进入生产测试目标。
- 本机 Command Line Tools 仍缺少 XCTest PlatformPath；实际 XCTest 由
  GitHub Actions macOS runner 强制执行。

遗留边界：

- WezTerm/kitty 仍需真实多窗口和 helper 缺失场景的机器矩阵。
- Ghostty、cmux、Warp 和 Kaku 尚未统一接入 capability resolver；没有稳定
  local API 的终端继续只报告 fallback。
- Diagnostics history 暂不包含搜索、筛选或导出；先验证 100 条有界数据对
  排障是否足够，再决定是否扩大产品面。

## 2026-07-28 Iteration 18 - Onboarding, retention, event extraction, and geometry fixtures

目标：

- 将首次运行的必需项与可选集成说清楚，避免用户误以为所有系统权限都是
  Agent Island 启动前提。
- 为 Agent Island 自有事件、诊断和内存对话投影提供明确保留策略，同时绝不
  删除 Provider 原始 transcript。
- 继续削薄 `main.swift`，并把多屏/刘海/浮动窗口几何变成可离线回放的策略。

首次运行与数据保留：

- 首次启动自动打开 Settings 的“开始使用”页；基础本地岛面不要求 macOS
  系统权限，CLI Hooks、Accessibility、通知和 Browser Bridge 按工作流选用。
- 引导完成状态仅保存在本机 UserDefaults，不会改变系统权限或静默安装集成。
- 新增事件与诊断 7/30/90 天保留选项；默认 30 天。
- 对话详情只允许“不保留内存投影”或“保留到退出 App”，不创建第二份
  transcript。
- 清理事件、诊断和内存对话投影均需明确二次确认；清理器只处理
  `~/.agent-island` 自有投影或进程内缓存。
- Hook 和手动 event 脚本读取同一 retention 配置；按小时或达到 1 MB 时执行
  修剪，避免每个 Hook 都重写完整 JSONL。修剪状态 marker 和设置文件均为
  `0600`。

架构拆分：

- 新增纯 `AgentEventNormalizer`，从 `AgentMonitor` 移出 family、surface、
  phase 和 Hook lifecycle vocabulary 映射。
- 7 个生产调用点使用统一静态契约；新增 provider alias、CLI 保守 fallback、
  lifecycle override 和 phase alias 测试。
- `main.swift` 本轮减少约 70 行；监控器仍然偏大，后续继续按
  EventNormalizer/ProviderProbe/Presentation projection 边界拆分。

布局回归：

- 新增 `PanelGeometryPolicy` 和 `PanelScreenSelectionPolicy`，实际接入
  `PanelCoordinator`、`IslandPanelSizing`、`NotchPlacement` 和 detached
  companion。
- Geometry fixtures 覆盖代表性的 13/14/16 英寸刘海、无刘海、紧凑屏、
  负坐标外接屏、显示器移除/恢复以及 companion 默认位置和 bounds clamp。
- 这些是无 WindowServer 依赖的确定性几何测试，不冒充 rendered pixel
  screenshot tests；像素级回归仍保留为后续工作。

验证：

- macOS 15.4 SDK 下 production App、全部 Swift/XCTest target 和 Release
  构建通过。
- Python retention/Claude fixture replay、Browser Bridge、Shell、installer、
  reducer 和 expansion controller 验证通过。
- 本机 Command Line Tools 缺少 XCTest PlatformPath；真实 XCTest 继续由
  GitHub Actions macOS runner 执行。

遗留边界：

- 首次运行文案和默认 30 天保留策略仍需 clean-machine 用户验收。
- Geometry fixtures 不覆盖 SwiftUI/AppKit 渲染像素、动态字体或真实 menu bar
  safe area。
- `main.swift` 仍包含 AgentMonitor、大量探针和主视图；本轮只完成一块低风险
  事件归一化拆分。

## 2026-07-28 Iteration 19 - Sound policy, compact companion, and core model extraction

目标：

- 补齐 quiet hours、按事件声音和节流，避免多会话同时变化造成通知噪声。
- 让 detached companion 拥有独立的信息层级，而不是缩小版 notch panel。
- 将稳定核心模型从 `main.swift` 迁到明确的 Models 边界。

声音策略：

- 新增纯 `SoundNotificationPolicy`；总开关继续默认关闭。
- 开始、完成、需处理/异常分别启停，开始默认关闭，完成和需处理默认开启。
- 每类事件可独立选择 Submarine、Glass、Basso、Ping 或 Pop，旧版默认声音
  映射保持不变。
- 支持跨午夜 quiet hours，默认配置为 22:00–08:00 但不自动启用；开始与
  结束相同表示全天静默。
- 所有会话共享 1/3/5/10 秒最小间隔，同一 session/state signal 30 秒内不
  重复播放；历史 key 有界清理。
- UserDefaults 兼容旧版仅有 master switch 的数据，并为新增字段使用保守默认。

Compact companion：

- 新增 `CompanionVisualPolicy`，为 Codex、Claude、Claude Science、ChatGPT
  提供独立内置 glyph/palette，并为所有 phase 提供 tone、motion 和摘要。
- 浮窗改为 provider identity、semantic state、session card 三层紧凑结构，
  继续只读取 `IslandViewModel.primarySnapshot`，没有第二套状态机。
- working/thinking 才允许低频 breathe；Reduce Motion 下不执行 ambient
  animation。
- 新增可见返回刘海按钮和 `⌥⌘N`，保留右键返回、Escape 收起、跳转和详情。
- 尺寸更新为 196×68 / 310×178，继续使用统一 geometry clamp。

核心模型抽离：

- 新增 Foundation-only 的 `Models/AgentModels.swift` 和 `AgentText.swift`，
  迁出 AgentFamily、AgentSurface、
  AgentPhase、AgentSnapshot、AgentEvent、JSONL decoder、ConversationInfo、
  AgentEventRollup、文本归一化和 control notifications；颜色扩展留在 UI 层。
- 类型定义保持唯一，现有 reducer、retention、event decoder 测试继续直接
  覆盖迁移后的生产类型。
- `main.swift` 从 4957 行降到 4588 行；相比 Iteration 17 前的 5054 行已
  减少 466 行。

验证：

- macOS 15.4 SDK 下 production App、全部 XCTest 测试 target 编译和
  Release 构建通过。
- 新增 sound policy/settings migration 和 companion visual policy 测试。
- Python、Browser Bridge、Shell、installer、session reducer、expansion
  controller 验证通过。
- 本机仅有 Command Line Tools；真实 XCTest 继续由 GitHub Actions macOS
  runner 执行。

遗留边界：

- 当前 companion 使用无版权风险的内置 SF Symbols；用户可选的 mascot
  主题/资产仍未实现。
- 声音提醒是本地系统声音，不等同于 macOS Notification Center 推送。
- `main.swift` 仍拥有 AgentMonitor、AgentLauncher、主 Island SwiftUI 和
  AppDelegate，后续继续按 provider probes 与 presentation 边界拆分。

## 2026-07-28 Iteration 20 - Companion themes, diagnostics export, and focus boundary

目标：

- 将 compact companion 从单一内置视觉推进到可配置但仍以状态为先的主题。
- 为已验证的脱敏诊断历史增加筛选和安全导出。
- 把跳转路由从 app shell 迁到 Focus 服务边界。

伴侣主题：

- 新增 Foundation-only `CompanionThemePreferences`，支持 system、friendly、
  technical 三套内置主题、全局默认和每个 AgentFamily 独立覆盖。
- UserDefaults 支持 canonical round-trip、损坏/未来值安全回退，以及早期
  prototype 的 classic/mascot/developer 等单值别名兼容。
- Settings 外观页可选择默认主题或让 Codex、Claude、Claude Science、
  ChatGPT 分别继承/覆盖；变更会即时刷新 detached companion。
- 主题只使用 SF Symbols 和原生形状，不引入来源或许可不明的外部素材；状态
  tone、session hierarchy、Reduce Motion 和可访问性行为保持一致。

诊断历史：

- 新增纯 `DiagnosticsHistoryPolicy`，支持 transport、state 和多词 AND 文本
  筛选并保持 newest-first 顺序。
- Settings 可复制筛选后的稳定文本，或通过 Save Panel 导出带 schema/privacy
  标记的 JSON；导出文件权限设为 `0600`。
- 筛选索引和导出记录都会再次经过现有 identifier/name/protocol/endpoint/
  failure 脱敏边界，防止手工构造或旧文件中的 raw 值外泄。

Focus 边界：

- 将 371 行 `AgentLauncher` 原样迁到
  `Services/Focus/AgentLauncher.swift`，保留 URL、process、terminal/tmux、
  Claude App、browser 和 app activation fallback 行为。
- `main.swift` 从 4588 行降到 4217 行；类型定义保持唯一。

验证：

- macOS 15.4 SDK 下 Debug App、XCTest 测试 target 和 Release App 编译通过。
- 新增主题解析/迁移、主题视觉差异、诊断组合筛选和二次脱敏导出测试。
- Python、Browser Bridge、Shell、installer、session reducer、expansion
  controller 和 Codex broker probe 验证通过。
- 完整 XCTest 执行继续交给 GitHub Actions macOS runner。

遗留边界：

- 原创 mascot 图片资产仍需要独立设计、许可和可访问性审查；当前内置主题
  已满足无外部素材的用户可选视觉方向。
- 像素级 notch/non-notch/external display 截图仍需要有 WindowServer 的
  UI 测试环境。
- 真实终端矩阵、clean-machine 安装验收、Developer ID 和 notarization
  仍属于外部环境/凭证工作。
