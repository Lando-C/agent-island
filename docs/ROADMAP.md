# Roadmap

Status updated: 2026-07-28. This document describes the shipped product rather
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
- Browser Bridge v3 for ChatGPT, Claude, and Codex Web. It is explicitly a
  non-authoritative DOM signal and never scans conversation text for approvals.
- Regression coverage for session lifecycle, liveness, Hook approval, and Hook
  question-answer socket round trips.
- Redacted, schema-derived fixture replay for Codex `requestUserInput`, command
  approval, file approval, and permissions approval. Unknown methods, malformed
  required fields, invalid permission payloads, and mismatched decision types
  fail closed.
- Provider-version fixture replay for Claude Code `PermissionRequest`,
  `AskUserQuestion`, and `Elicitation`, covering both the production Python
  normalizer and Swift response encoder.
- Browser Bridge v3 selector-profile fixtures for ChatGPT, Claude, and Codex
  Web. Protocol, detector, or selector drift is reported as a degraded
  capability and cannot overwrite the latest trusted session event.

Still required:

- Capture redacted live Codex broker frames across supported provider versions
  and compare them with the schema-derived fixtures. The client must not broaden
  write-back from inferred or newly observed payloads without fixture review.
- Capture redacted live Claude hook stdin frames and browser selector evidence
  across provider versions. Current Claude fixtures are documentation-derived
  and version-pinned; Browser fixtures are synthetic selector contracts.
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
- Offline terminal capability fixtures for missing helpers, stale metadata,
  duplicate stable IDs, multiple windows, and ambiguous TTY/CWD matches. The
  shared contract classifies only fresh, unique identities as exact or context.
- WezTerm and kitty runtime helper metadata now passes through the shared
  capability contract before focus. Invalid JSON, non-zero helper exit, stale
  metadata, ambiguous matches, or activation failure cannot report an exact or
  context route.

Still required:

- Real-machine regression matrix for Ghostty, WezTerm, kitty, Warp, and Kaku.
- Verified Warp workspace/tab and Kaku pane targeting. Until a stable local API
  is available, they remain application-activation fallbacks.
- Connect Ghostty/cmux and future Warp/Kaku metadata adapters to the same shared
  capability contract where those terminals expose a stable local interface.

## P2: Explainability and Product Operations

Implemented:

- Diagnostics with transport state, protocol version, last success, endpoint,
  and failure reason.
- A bounded local diagnostics history (100 state transitions) with consecutive
  duplicate suppression, `0600` persistence, path/URL/credential redaction, and
  a recent-history view in Settings.
- One-click hook repair, permission settings routes, redacted support bundle,
  local privacy documentation, and a public issue template.
- Conversation details that default to human dialogue; tool payloads are a
  compact, opt-in work record and large transcript reads start at the recent tail.
- A guided first-run checklist that separates the no-permission local baseline
  from optional CLI Hooks, Accessibility, notifications, and Browser Bridge.
- Explicit 7/30/90-day retention for Agent Island event projections and
  diagnostics history, plus disabled/until-quit conversation memory policies
  and confirmed cleanup scoped away from provider transcripts.

Still required:

- Optional diagnostics history filters/export after the bounded replay view has
  been exercised on real degraded transports.
- Validate first-run wording and retention defaults on a clean-machine
  install/uninstall acceptance run.

## P3: Experience Layer

Implemented:

- Notch panel expansion/collapse, Escape and Option-N controls, width settings,
  completion spotlight throttling, and Reduce Motion aware activity feedback.
- Detachable floating companion with long-press/downward-drag, per-display
  restoration, status bubble, and right-click return to the notch.
- Optional local sound alerts for start, completion, and human attention.
- Deterministic geometry fixtures for representative 13/14/16-inch notch,
  non-notch, compact, negative-coordinate external, display-removal, and
  detached companion bounds.

Still required:

- Per-engine mascot selection and a compact companion visual system that is not
  merely a resized notch panel.
- Quiet hours, per-event sound selection, and notification throttling controls.
- Pixel-level screenshot tests for notch, non-notch, and external displays;
  the current geometry fixtures do not claim rendered-pixel coverage.

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
