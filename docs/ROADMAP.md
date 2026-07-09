# Roadmap

Agent Island is pre-1.0. This roadmap separates implemented behavior from planned
work.

## P0: State and Trust

- Structured `PendingRequestStore`.
- In-app allow/deny for Claude PermissionRequest.
- Codex approval/question response schema validation before write-back.
- `request_user_input` question cards with option selection.
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
