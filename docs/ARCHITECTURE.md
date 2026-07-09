# Architecture

Agent Island is a native Swift macOS app plus small local scripts.

## Layers

| Layer | Code | Responsibility |
| --- | --- | --- |
| App shell | `Sources/AgentIsland/main.swift` | menu-bar app, panel lifecycle, app/browser/process probes |
| UI | `Sources/AgentIsland/UI/` | expansion controller and settings window |
| Models | `Sources/AgentIsland/Models/` | jump targets and typed UI targets |
| State | `Sources/AgentIsland/State/` | hook event reducer and session rollups |
| Focus | `Sources/AgentIsland/Services/Focus/` | terminal/tmux/app focusing |
| Hook socket | `Sources/AgentIsland/Services/Hooks/` | local Unix socket and pending hook response lifecycle |
| Hooks | `scripts/agent-island-bridge.py`, `scripts/install-hooks` | Claude/Codex hook capture and install |
| Diagnostics | `scripts/agent-island-diagnostics` | local health and capability report |

## State Philosophy

- App/process presence only means online.
- Hook lifecycle and broker/thread details determine working, waiting, done, and
  needs-attention states.
- Approval and question states are first-class human handoff states, not generic
  errors.

## Safety Philosophy

Auto approval is opt-in and limited. Manual approval is explicit: the hook bridge
blocks only for a pending request, the island shows the tool/risk summary, and
the local socket returns allow or deny only after the user acts. Unsupported
question/approval schemas are captured but fall back to the native agent flow
instead of guessing a response.
