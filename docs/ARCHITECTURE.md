# Architecture

Agent Island is a native Swift macOS app plus small local scripts.

## Layers

| Layer | Code | Responsibility |
| --- | --- | --- |
| App shell | `Sources/AgentIsland/main.swift` | menu-bar lifecycle, agent monitor, app/browser probes |
| Panel coordination | `Sources/AgentIsland/UI/PanelCoordinator.swift`, `PanelGeometryPolicy.swift` | notch/floating root view, deterministic multi-display geometry and screen restoration, window lifecycle |
| UI | `Sources/AgentIsland/UI/` | island rows, expansion controller, detached companion, settings, chat windows |
| Models | `Sources/AgentIsland/Models/` | jump targets, Codex broker thread model, transport health |
| State | `Sources/AgentIsland/State/` | hook event reducer, session rollups, display mode, island presentation model |
| Event normalization | `Sources/AgentIsland/Services/Events/AgentEventNormalizer.swift` | pure provider vocabulary mapping for family, surface, phase, and hook lifecycle names |
| Focus | `Sources/AgentIsland/Services/Focus/` | terminal/tmux/app focusing and PID/TTY/pane inspection |
| Focus capability contract | `Sources/AgentIsland/Services/Focus/TerminalFocusCapability.swift` | offline exact/context/fallback/unavailable classification for fresh, unambiguous terminal metadata |
| Conversations | `Sources/AgentIsland/Services/Chat/ConversationStore.swift` | incremental transcript tailing plus Hook/broker event merge |
| Codex transport | `Sources/AgentIsland/Services/Codex/CodexBrokerClient.swift`, `CodexBrokerEndpoint.swift` | one persistent initialized JSON-RPC connection for requests and threads, with one tested discovery/socket boundary |
| Hook socket | `Sources/AgentIsland/Services/Hooks/` | local Unix socket and pending hook response lifecycle |
| Hooks | `scripts/agent-island-bridge.py`, `scripts/install-hooks` | Claude/Codex hook capture and install |
| Diagnostics | `Sources/AgentIsland/Models/DiagnosticsHistory.swift`, `scripts/agent-island-diagnostics`, `scripts/agent-island-support-bundle` | bounded redacted transport history, health report, and privacy-safe support artifact |

The packaged `scripts/codex-broker-probe` intentionally keeps a small,
protocol-independent Python implementation of broker discovery. Diagnostics and
support collection must continue to work when the Swift app is not installed or
running. Both implementations honor the explicit socket override, scan the
temporary roots for `cxc-*/broker.sock`, prefer newer sockets, and fall through
failed candidates. The production app does not invoke the probe or maintain a
second broker connection. Within the app, all discovery and Unix-socket opening
goes through `CodexBrokerEndpoint`, while initialization, schema validation, and
unknown-request fail-closed behavior remain in `CodexBrokerClient` and
`CodexBrokerProtocol`.

Panel layout regression coverage uses deterministic geometry fixtures rather
than screenshot UI tests. The fixtures cover representative built-in and
external display frames, notch and non-notch placement, display removal and
restoration, and floating companion bounds without requiring a logged-in
WindowServer session. They validate geometry policy, not rendered pixels.

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
