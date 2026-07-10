# Roadmap

Agent Island is pre-1.0. This roadmap separates implemented behavior from planned
work.

## P0: State and Trust

Done:

- Structured `PendingRequestStore`.
- Local `HookSocketServer` at `~/.agent-island/hook.sock`.
- In-app allow/deny for Claude `PermissionRequest`.
- `request_user_input` / elicitation events captured as structured pending
  requests.
- Pending request cards for unmatched socket requests, so handoff events do not
  disappear when no session row can be matched.
- Focused-island `Command-Y` / `Command-N` shortcuts for the first inline
  approval request.
- Installed capability is represented as `available`, separately from online,
  idle, and active work.
- Time-based stale-session convergence: done 10 minutes, idle/available 1 hour,
  waiting/error 12 hours.
- Production Swift regression tests for session retention and render-safe
  pending-request lookup.
- Incremental JSONL event ingestion, bounded log-pruning headroom, semantic
  snapshot publication, and low-frequency activity motion.
- Process-aware active-session expiry with a 30-second race grace, process-tree
  family validation, Claude `--resume <session>` identity checks, and PID reuse
  rejection.
- No-op lifecycle suppression: `SessionStart -> SessionEnd` without prompt,
  tool, or approval evidence cannot create a fake completed task or replace the
  real session PID. New prompt/tool/approval evidence also clears an older
  terminal state so an active next turn cannot remain labeled completed.
- Claude App `cliSessionId -> localSessionId` metadata indexing with duplicate
  import rejection and exact Accessibility focus when permission is granted.
- Exact iTerm2/Terminal `windowID + tabIndex` focus before TTY/title fallback.

Remaining:

- Codex approval/question response schema validation before write-back.
- Direct inline answer write-back for `request_user_input` once response schemas
  are verified. Current question cards show/copy options but do not claim to
  submit them.
- Terminal and tmux pane liveness when no owning agent PID is available.
- Transcript-aware fallback beyond the current metadata/title extraction.

## P1: Return to Work

- Claude exact focus diagnostics and clearer in-row permission repair affordance
  when Accessibility is not granted. The status menu already opens the relevant
  System Settings pane.
- Warp workspace/tab lookup.
- cmux panel focusing.
- Kaku focusing.
- More exact Ghostty/WezTerm/kitty targeting.
- Smart suppression when the exact related session is already frontmost.

## P2: Explainability

- Structured diagnostics UI with required vs optional capabilities.
- One-click repair for hook, accessibility, notifications, and login item issues.
- Diagnostics export bundle with redaction guidance.

## P3: Experience Layer

- Off-island floating mode.
- Per-engine mascot selection.
- idle / working / warning animation states.
- Sound prompts for start, done, approval, and error events.

## Release Readiness

- Developer ID signing.
- Apple notarization.
- Signed zip or DMG.
- Homebrew cask.
- Public screenshots and demo video.
