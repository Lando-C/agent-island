# Roadmap

Status updated: 2026-07-14. This document describes the shipped product rather
than the original prototype plan. `README.md` is the public capability summary;
Diagnostics in the running app remains the source of truth for one Mac.

## P0: State and Trust

Implemented:

- Hook-driven Claude Code and Codex CLI status with a local Unix socket.
- Claude `PermissionRequest`, `AskUserQuestion`, and `Elicitation` write-back.
- Codex Desktop broker client for supported live request schemas, failing closed
  when no `cxc-*/broker.sock` is available.
- Session-first state reduction, duplicate suppression, old-session retention,
  PID/command-chain/TTY/tmux liveness, and source evidence labels.
- Incremental event-log and Claude/Codex transcript ingestion.
- Browser Bridge v2 for ChatGPT, Claude, and Codex Web. It is explicitly a
  non-authoritative DOM signal and never scans conversation text for approvals.
- Regression coverage for session lifecycle, liveness, Hook approval, and Hook
  question-answer socket round trips.

Still required:

- Capture redacted live Codex broker fixtures for every supported approval and
  input schema. The client must not broaden write-back from inferred payloads.
- Add provider-version fixture replay for Claude hooks and Browser Bridge DOM
  selectors, so a UI/provider update becomes a visible degraded capability.
- Add a safe app/web conversation adapter where a provider exposes a local event
  API. Do not use screen scraping as a source of truth.

## P1: Return to Work

Implemented:

- Exact Claude local-session focus when Accessibility is granted.
- `codex://threads/{threadId}` navigation for Codex Desktop.
- tmux pane, iTerm2/Terminal TTY, cmux, WezTerm, kitty, Ghostty, and application
  activation fallback routes with the actual route shown in Diagnostics.
- Conservative smart suppression when the matching app, browser page, terminal,
  or pane is already foregrounded.

Still required:

- Real-machine regression matrix for Ghostty, WezTerm, kitty, Warp, and Kaku.
- Verified Warp workspace/tab and Kaku pane targeting. Until a stable local API
  is available, they remain application-activation fallbacks.
- Per-terminal capability fixtures for helper absence, multiple windows, and
  stale terminal metadata.

## P2: Explainability and Product Operations

Implemented:

- Diagnostics with transport state, protocol version, last success, endpoint,
  and failure reason.
- One-click hook repair, permission settings routes, redacted support bundle,
  local privacy documentation, and a public issue template.
- Conversation details that default to human dialogue; tool payloads are a
  compact, opt-in work record and large transcript reads start at the recent tail.

Still required:

- A dedicated diagnostics history view with redacted event replay.
- A guided first-run checklist that can distinguish required permissions from
  optional terminal integrations.
- Explicit data-retention controls for local event and transcript projections.

## P3: Experience Layer

Implemented:

- Notch panel expansion/collapse, Escape and Option-N controls, width settings,
  completion spotlight throttling, and Reduce Motion aware activity feedback.
- Detachable floating companion with long-press/downward-drag, per-display
  restoration, status bubble, and right-click return to the notch.
- Optional local sound alerts for start, completion, and human attention.

Still required:

- Per-engine mascot selection and a compact companion visual system that is not
  merely a resized notch panel.
- Quiet hours, per-event sound selection, and notification throttling controls.
- Screenshot-driven layout tests for notch, non-notch, and external displays.

## Release Readiness

Implemented:

- Public repository, CI, build/release workflows, checksum installer, release
  documentation, license notices, privacy documentation, and a Cask template.

Still required before a stable public release:

- A real Developer ID Application identity in CI secrets.
- Apple notarization and stapling of the published archive.
- Publish the rendered Cask to `Lando-C/homebrew-tap` after the first notarized
  release; do not describe it as available beforehand.
- Public screenshots/demo and a clean-machine install/uninstall acceptance run.
