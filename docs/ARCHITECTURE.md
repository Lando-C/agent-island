# Architecture

Agent Island is a native Swift macOS app plus small local scripts.

## Layers

| Layer | Code | Responsibility |
| --- | --- | --- |
| App shell | `Sources/AgentIsland/main.swift` | menu-bar lifecycle, agent monitor, app/browser probes |
| Panel coordination | `Sources/AgentIsland/UI/PanelCoordinator.swift` | notch/floating root view, multi-display geometry, window lifecycle |
| UI | `Sources/AgentIsland/UI/` | island rows, expansion controller, detached companion, settings, chat windows |
| Models | `Sources/AgentIsland/Models/` | jump targets, Codex broker thread model, transport health |
| State | `Sources/AgentIsland/State/` | hook event reducer, session rollups, display mode, island presentation model |
| Focus | `Sources/AgentIsland/Services/Focus/` | terminal/tmux/app focusing and PID/TTY/pane inspection |
| Conversations | `Sources/AgentIsland/Services/Chat/ConversationStore.swift` | incremental transcript tailing plus Hook/broker event merge |
| Codex transport | `Sources/AgentIsland/Services/Codex/CodexBrokerClient.swift` | one persistent initialized JSON-RPC connection for requests and threads |
| Hook socket | `Sources/AgentIsland/Services/Hooks/` | local Unix socket and pending hook response lifecycle |
| Hooks | `scripts/agent-island-bridge.py`, `scripts/install-hooks` | Claude/Codex hook capture and install |
| Diagnostics | `scripts/agent-island-diagnostics`, `scripts/agent-island-support-bundle` | health report and privacy-safe support artifact |

## State Philosophy

- App/process presence only means online.
- Hook lifecycle and broker/thread details determine working, waiting, done, and
  needs-attention states.
- Approval and question states are first-class human handoff states, not generic
  errors.
- Pending requests that cannot be attached to a current session snapshot are
  still rendered as standalone island cards.
- A session is not retained only because its terminal shell or tmux pane still
  exists: liveness combines command-chain, PID, exact TTY, and exact pane data.
- Transport health is written once to `~/.agent-island/transport-health.json`
  and consumed by the panel, settings diagnostics, CLI report, and support bundle.

## Safety Philosophy

Auto approval is opt-in and limited. Manual approval is explicit: the hook bridge
blocks only for a pending request, the island shows the tool/risk summary, and
the local socket returns allow or deny only after the user acts. Unsupported
question/approval schemas are captured but fall back to the native agent flow
instead of guessing a response. Question cards may expose choices for copying,
but they are not marked as answered until a verified write-back path exists.
