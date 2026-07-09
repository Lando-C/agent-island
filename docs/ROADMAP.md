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

Remaining:

- Codex approval/question response schema validation before write-back.
- Direct inline answer write-back for `request_user_input` once response schemas
  are verified. Current question cards show/copy options but do not claim to
  submit them.
- Old idle/waiting session pruning.
- Zombie detection for pid, process tree, terminal, and tmux pane liveness.

## P1: Return to Work

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
