# Agent Island Codebase Integration Matrix

Date: 2026-07-09

This file tracks what we can actually reuse from the downloaded reference
projects, what must stay clean-room, and what should be implemented first.

## Product Position

Agent Island should not become another generic notch utility. The product is:

> AI Agent Operations Island: status truth, human handoff, approval, quick return
> to the exact conversation, and diagnostics that make local environment issues
> visible.

This means the product bar is not "shows a beautiful island". The bar is:

1. Online is not working.
2. Waiting for approval/input is not an error.
3. Finished must not stay expanded forever.
4. Clicking a row must return to the exact app window, browser tab, terminal tab,
   tmux pane, or thread where possible.
5. Optional local dependencies such as tmux, WezTerm, kitty, Warp, cmux, Kaku,
   and browser tabs must be diagnosed as capability coverage, not as a single
   generic failure.

## License Strategy

| Source | Local path | License state | Mainline strategy |
| --- | --- | --- | --- |
| Vibe Notch | `research/competitors/repos/new-20260709/vibe-notch` | Apache-2.0 in `LICENSE.md` | Can adapt/copy with NOTICE. Best direct source for hook socket, session state, chat history, sound, notch geometry. |
| AgentBro | `research/competitors/code-study/permissive/AgentBro` | Apache-2.0 | Can translate terminal routing and state boundaries. Keep NOTICE. |
| DevIsland | `research/competitors/code-study/permissive/DevIsland` | MIT | Can adapt approval/terminal ideas. Keep MIT notice. |
| pi-island | `research/competitors/code-study/permissive/pi-island` | MIT | Can adapt host placement and package layout. Keep MIT notice. |
| Ping Island | `research/competitors/code-study/permissive/PingIsland` | Local permissive study area; verify source notice before direct copy | Prefer architecture translation for Codex broker, tmux matching, notch geometry. |
| MioIsland | `research/competitors/repos/new-20260709/MioIsland` | No license file in local snapshot | Do not copy into open-source mainline until license is confirmed. Use behavior/spec reference only. |
| BoringNotch | `research/competitors/code-study/gpl-reference/BoringNotch` | GPL isolated reference | Clean-room only. Use for UX comparison, not copied source. |

## Source-Level Comparison

| Product area | Our current code | Reference files | What the reference does better | Import plan |
| --- | --- | --- | --- | --- |
| Hook transport | `scripts/agent-island-bridge.py`, JSONL event file | Vibe/Mio `Services/Hooks/HookSocketServer.swift`; DevIsland `Bridge/HookSocketServer.swift`; AgentBro `src-tauri/src/hooks/server.rs` | Keeps a live socket so approval decisions can be answered in-app instead of one-way status logging. Caches pending permission by session/tool id. | P1: add `PendingRequestStore`; keep JSONL as fallback, add local socket for allow/deny and question response. |
| Hook installer | `scripts/install-hooks` | Vibe `HookInstaller.swift`; Mio `HookInstaller.swift`, `CodexHookInstaller.swift`, `HookHealthCheck.swift` | Installer can detect stale script paths, preserve other hooks, enable Codex hook feature, uninstall cleanly, and report health. | P0/P1: translate health checks into Settings Diagnostics. Later replace shell installer with Swift installer service. |
| Status reducer | `Sources/AgentIsland/State/SessionStore.swift` | Vibe `Services/State/SessionStore.swift`, `ToolEventProcessor.swift`; AgentBro `hooks/session_store.rs`, `tool_processor.rs` | Tracks active tools by id, pending permissions, subagent tools, tool completion, interrupts, history sync, and zombie process checks. | P0: keep our smaller reducer but add pending request model, old-session pruning, and process liveness. |
| Approval semantics | Risk classifier in `agent-island-bridge.py`; UI label added in this iteration | DevIsland `ApprovalPolicyEngine.swift`; Vibe `ToolApprovalHandler.swift`; AgentBro pending permission structs | Separates "needs approval" from failure, supports policy evaluation, pending permission cache, and explicit user response. | P0/P1: model `PermissionRequest` separately from error; auto-approve only safe read tools, never dangerous shell/write operations. |
| request_user_input | Not implemented | AgentBro `PendingQuestion`, `QuestionOption`; Mio AskUserQuestion/QuestionResponder references | Provides choices, remembers question identity, and can submit answer back to running agent. | P1: render question card; first version opens/jumps/copies answer, second version writes back via socket/terminal. |
| Chat details | Compact title/preview from broker and events | Vibe `ChatHistoryManager.swift`, `ConversationParser.swift`, `ChatView.swift`, `ToolResultViews.swift`; AgentBro `TaskInfo`, `ToolResult` | Full message list, tool call rows, structured tool results, subagent filtering. | P1: create `ChatDetailStore` driven by hook events first; add transcript parser as fallback. |
| Codex app state | `scripts/codex-broker-probe`, `codex://threads/{id}` | Ping Codex app-server monitor; AgentBro `agents/codex_app_server.rs` | Reads visible threads, filters internal/auxiliary threads, extracts thread metadata and details. | P0: keep probe; improve multi-window/thread identity and route jump to exact visible thread where Codex URL supports it. |
| CLI terminal jump | `Sources/AgentIsland/Services/Focus/TerminalFocuser.swift`; `JumpTarget.terminal/.tmux` | Ping `TerminalSessionFocuser.swift`; DevIsland `TerminalFocuser.swift`; AgentBro `terminal/jump.rs`, `terminal/tmux.rs`; Mio `CmuxTreeParser.swift` | More exact order: tmux pane, tty, iTerm session id, Ghostty terminal id/cwd, WezTerm pane id/socket, kitty remote control, Warp sqlite, cmux panel. | P0/P1: expand support terminal by terminal. Treat missing helpers as optional capability warnings. |
| Smart suppress | Not implemented | Vibe `TerminalVisibilityDetector.swift`; DevIsland `isSessionFrontmost` | Suppresses big interruptions if the exact related terminal/session is already frontmost. | P1: add `isSessionFrontmost(target:)`; only suppress when target identity matches, not when any terminal is open. |
| Notch geometry | `IslandPanelSizing`, `visibleFrame` clamp; Settings width sliders | Vibe `NotchGeometry.swift`; Ping `NotchGeometry.swift`; BoringNotch `NotchSpaceManager.swift`; pi-island native host | More complete hardware notch geometry, screen selection, outside-click detection, multi-screen behavior. | P0/P1: keep current safety clamp; add screen selector and per-screen saved width/position. |
| Hover/auto collapse | `IslandExpansionController.swift` | Vibe `NotchActivityCoordinator.swift`; BoringNotch mouse tracker clean-room reference | Avoid duplicate hover expansion, coordinate auto spotlight and manual expansion, support Escape. | P0: our duplicate-hover bug is fixed; next add Escape and close controls for spotlight queue. |
| Diagnostics | `scripts/agent-island-diagnostics`; Settings Diagnostics tab | Mio `HookHealthCheck.swift`; AgentBro `hooks/diagnostics.rs`; Vibe installer checks | More structured severity, stale path detection, managed hook manifest, ring-buffer diagnostics. | P0/P1: diagnostics should report capability matrix: required fail vs optional missing vs not running. |
| Sound | Not implemented | Vibe `SoundSelector.swift`; Mio `SoundManager.swift` | Event-based sound selection, user toggles, synthesized tones/custom files. | P2: default off; start/done/approval/error sounds separately configurable. |
| Mascot/theme | Not implemented | Mio `NotchCustomization.swift`, `ThemeRegistry.swift`; BoringNotch visual polish clean-room reference | Per-state visual identity and persistent customization. | P3 after status/jump/approval stabilizes. |
| Off-island mode | Not implemented | BoringNotch drag/pan clean-room reference; Mio customization model | Makes multi-screen work practical when the notch is not in the user's current visual area. | P3: long press 0.35s + downward drag, free floating window, right-click return. |
| Release packaging | `scripts/build-app` | pi-island package scripts; Vibe `scripts/create-release.sh`; BoringNotch DMG config clean-room reference | Release artifacts, zip/dmg, signing/notarization, postinstall, release notes. | P0 for GitHub: zip app, README first-run guide, diagnostics, release checklist. P2: sign/notarize/Homebrew cask. |

## Required vs Optional Diagnostics

This distinction matters for users who download from GitHub.

| Diagnostic item | Severity if missing | Reason |
| --- | --- | --- |
| App binary / packaged scripts | FAIL | The app cannot operate or repair itself. |
| Hook bridge executable | FAIL | Agent lifecycle cannot be captured. |
| Hook config parse failure | FAIL | Existing user config may be broken or hook install failed. |
| Hook not installed | WARN with one-click fix | App can still run, but precise states will be degraded. |
| Accessibility / Apple Events denied | WARN with settings button | App can still show hooks, but focusing/browser detection is degraded. |
| tmux not installed/server absent | WARN optional capability | Many users do not use tmux. Not a product failure. |
| WezTerm/kitty helpers missing | WARN optional capability | Only affects users who use those terminals. |
| Warp/cmux/Kaku not running | INFO/WARN optional capability | Support should be capability-based. |
| Codex broker unavailable | WARN | Codex app introspection degrades, but hooks and app open still work. |
| Auto approval disabled | PASS | Secure default. |

## Next Implementation Order

1. `PendingRequestStore`: permission/question cards with risk labels.
2. `TerminalFocuser` expansion: Warp sqlite, cmux, Kaku, more exact Ghostty/WezTerm/kitty.
3. `ChatDetailStore`: hook-driven conversation and tool details.
4. Structured diagnostics model in Swift, backed by `agent-island-diagnostics`.
5. Zombie detector and 12-hour stale idle/waiting pruning.
6. Smart suppress by exact jump target, not generic terminal visibility.
7. Release zip, signing plan, README, third-party notices, privacy doc.
8. Off-island mode, mascot, sound, and theme work after P0/P1 stability.
