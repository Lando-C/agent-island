# Agent Island Engineering Review - 2026-07-10

## Executive judgment

Agent Island now has a credible product core: session-first status, direct Claude
question/approval responses, conditional Codex Desktop responses, shared
incremental local chat details, precise jump targets, smart spotlight
suppression, diagnostics, and an installable macOS app. It is no longer only a
process-online indicator.

It is not yet a finished 1.0 control plane. The largest remaining risks are
transport coverage, source attribution, exact foreground matching across every
terminal, incremental chat storage, release trust, and the gap between the
floating-island MVP and the intended detached companion experience.

## Implementation truth table

| Area | Current implementation | Evidence | Remaining boundary | Judgment |
|---|---|---|---|---|
| Claude approval | Unix hook socket returns verified `PermissionRequest` output | Unit tests plus live allow/deny path | Other Claude hooks can coexist and produce follow-up events | Production-capable, fail-closed |
| Claude questions | `AskUserQuestion` preserves original questions and writes `answers`; Elicitation returns structured content | Live option and custom-text end-to-end tests | Future Claude schema changes need fixtures | Strong |
| Codex Desktop control | Persistent `cxc-*/broker.sock` JSON-RPC client retains server request IDs | Generated local app-server schema plus payload tests | No active broker was available for live E2E; Codex CLI stdio sessions are not intercepted | Conditional, accurately disclosed |
| Chat details | Shared incremental Claude/Codex JSONL tailer plus Hook and broker events | Transcript and parser tests | Unsupported app/web chats remain unavailable; recent-tail cap is shown to the user | Useful MVP |
| Smart suppression | App, ChatGPT active tab, TTY, cmux and tmux target checks | Classifier tests and live frontmost suppression logs | Warp/kitty/Kaku exact active-pane checks remain incomplete | Conservative after hardening |
| Terminal jump | iTerm2, Terminal, Ghostty, WezTerm, kitty, cmux and tmux fallbacks | Existing focus code plus live app/session checks | Some terminals expose weak automation APIs | Broad but not uniformly exact |
| Off-island mode | Long press/down drag, movable panel, saved position, context-menu return, compact status bubble | Live detach/restart/right-click/return tests | Still needs per-engine mascot assets and broader display layout regression | MVP, not final mascot system |
| Packaging | Public repository, release archive, checksum installer, app bundle | Anonymous installer and CI | No Developer ID notarization or Homebrew cask | Developer preview |

## What was weak and is now corrected

1. Question cards silently displayed only three questions and four options.
   They now render every structured question and use horizontal option scrolling.
2. Claude/Codex option questions lacked an Other path. Structured questions now
   expose custom text without copying data back to the source app.
3. ChatGPT Web suppression previously treated any foreground browser as the
   target. It now inspects the active tab title and URL and fails open when it
   cannot confirm ChatGPT.
4. Terminal suppression previously stopped at the app boundary. iTerm2,
   Terminal, WezTerm, cmux, and tmux now compare target-level identity where the
   local APIs make that possible.
5. Chat details silently retained only the last 600 parsed items and searched
   directories before consulting hook metadata. It now prefers the exact
   `transcript_path`, keeps the complete parsed history, and collapses
   near-simultaneous Codex duplicate events.
6. Repeated clicks or duplicate hook connections could deliver a decision twice
   or leak the older file descriptor. Decisions are now one-shot; duplicate
   connections replace and close the stale transport; pending sockets expire.

## Architecture review

### What is sound

- `PendingRequestStore` owns user decisions instead of embedding transport JSON
  in SwiftUI controls.
- Provider transports are separated: Claude hook socket and Codex broker client.
- Unsupported transports fail closed and preserve native agent UI.
- `JumpTarget` expresses app, URL, terminal, tmux, and Claude local-session
  identity explicitly.
- Chat parsing is isolated from the monitoring loop, so opening a transcript
  cannot stall routine status refreshes.
- Diagnostics, settings, hook installer, release scripts, and CI are part of the
  repository rather than local-only operational knowledge.

### What still needs restructuring

- `main.swift` still owns monitoring, event reduction, layout, rows, launchers,
  panel placement, and application lifecycle. This increases regression risk.
- `AgentSnapshot` mixes display projection with transport identity and counters.
  A durable session model should project into a smaller view model.
- Conversation history is shared through `ConversationStore`; next, provider
  adapters should populate it from safe app/web event APIs instead of more file
  scanning.
- Foreground detection is distributed between monitor probes, launcher code, and
  smart suppression. These should share one target-inspection service.
- Codex broker discovery and one-shot broker probing duplicate connection and
  thread parsing concerns.

Recommended target boundaries:

```text
Models/Session, PendingRequest, Conversation, JumpTarget
Events/ProviderEvent -> EventNormalizer -> SessionReducer
Transports/ClaudeHookTransport, CodexBrokerTransport
State/SessionStore, PendingRequestStore, ConversationStore
Focus/TargetInspector, TargetFocuser
Presentation/IslandViewModel, PanelCoordinator, FloatingCompanionCoordinator
```

## Product and UX review

- The primary product value is interruption management, not decorative notch UI.
- Waiting for approval/input must dominate working and completion states.
- Completion should be visible, dismissible, and deduplicated, but never hold the
  desktop open indefinitely.
- A detached companion should use a distinct compact information hierarchy. A
  640-pixel floating copy of the notch is not the final interaction.
- Mascots and sound should encode idle/working/attention/completion consistently;
  they should not introduce a second state system.
- Settings should expose behavior and diagnostics, not implementation roadmap
  prose in the long term.

## Security and privacy review

- The hook socket is local and mode `0600`; auto approval remains disabled by
  default.
- Dangerous operations remain outside automatic approval.
- Secret question fields use `SecureField` and are not written to Agent Island
  logs.
- Chat transcripts remain local, but opening details necessarily reads local
  agent history. The README must continue to state this clearly.
- A future TCP/remote bridge must add authenticated envelopes, replay protection,
  version negotiation, and explicit host trust. The current Unix-socket trust
  model must not be copied directly to a network listener.

## External reference check

Repository metadata was checked on 2026-07-10:

| Project | Stars | License | Best reference area | Copy policy |
|---|---:|---|---|---|
| [vibe-notch](https://github.com/farouqaldori/vibe-notch) | 2,439 | Apache-2.0 | Product surface, history/tool views, sound/companion interaction | Adapt with attribution |
| [Ping Island](https://github.com/erha19/ping-island) | 956 | Apache-2.0 | Session reducer, Codex app-server, transcript ingestion, energy policy | Adapt with NOTICE compliance |
| [MioIsland](https://github.com/MioMioOS/MioIsland) | 512 | CC BY-NC 4.0 | AskUserQuestion UX, detached companion, diagnostics concepts | Reference only for an open commercial-friendly mainline |
| [DevIsland](https://github.com/nangchang/DevIsland) | 4 | MIT | Approval proxy boundaries, Other answers, provider adapters, exact terminal focus | Direct adaptation allowed with attribution |

Star count is discovery evidence, not a quality score. License compatibility and
tested behavior remain the deciding factors.

## Next execution sequence

### P0 - Reliability and observability

1. Capture redacted live Codex broker schema fixtures and replay them against
   the persistent RPC client.
2. Add Browser Bridge selector fixtures and provider-version degradation
   reporting.
3. Expand terminal focus regression coverage on real Ghostty/WezTerm/kitty/Warp
   installations.
4. Add a safe provider adapter for app/web conversation summaries.

Acceptance: no false inline-success state, no stale pending request after a dead
transport, deterministic replay tests for every supported response schema, and
explicit degradation rather than a guessed status for unsupported providers.

### P1 - Detached companion and notification quality

1. Create a compact floating companion view rather than resizing the notch view.
2. Add idle/working/attention/completion animation states driven by the same
   session reducer.
3. Add a click popover for the top session and a keyboard-accessible return path.
4. Add opt-in event sounds with per-event throttling and quiet hours.

Acceptance: no overlap on 13-inch, 14-inch, 16-inch, non-notch, and external
displays; position survives display removal; reduced-motion mode remains usable.

### P2 - Distribution

1. Developer ID signing and notarization.
2. Homebrew cask and update channel.
3. Migration-safe hook installer with versioned backups and rollback diagnostics.
4. Public support bundle that excludes conversation contents by default.

Acceptance: a new user installs, grants only required permissions, sees a healthy
diagnostic page, and can fully uninstall without editing config files manually.
