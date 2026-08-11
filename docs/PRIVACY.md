# Privacy

Agent Island is local-first. It has no telemetry service and does not upload
events, prompts, transcripts, hook payloads, diagnostics, or approval decisions.

## Local state

Agent Island writes its own runtime state under `~/.agent-island/`, including:

- `events.jsonl` and local app/bridge logs
- `transport-health.json` and bounded diagnostics history
- retention and optional auto-approval settings
- `web-bridge-token`
- the runtime-only `hook.sock` Unix socket

The directory is enforced as owner-only (`0700`). Agent Island-owned regular
files are written as owner-only (`0600`) with atomic replacement or no-follow
append operations. Sensitive reads/writes reject symbolic links, foreign-owner
targets, and non-regular files.

The Safety settings offer 7/30/90-day retention for Agent Island's event
projection and redacted diagnostics history. Conversation detail projection is
memory-only. Cleanup controls are scoped to Agent Island-owned files and memory;
they never delete Claude, Codex, or other provider-owned transcripts.

## Provider data

When a user opens a conversation detail window, Agent Island can read local
Claude/Codex transcript files incrementally. Those provider-owned files remain
in place and are not copied into support bundles. Local hook events can include
session identifiers, workspace/transcript paths, tool names, and compact tool
input summaries; treat `~/.agent-island` as private user data.

## Hook configuration

With user action, Agent Island can update:

- `~/.claude/settings.json`
- `~/.codex/hooks.json`
- `~/.codex/config.toml`

The installer validates supported JSON structures, preserves unrelated hooks,
creates owner-only `.agent-island.bak` files, and writes replacements atomically.

## Network and local transports

- App runtime has no telemetry or cloud API endpoint.
- The optional Browser Web Bridge listens only on `127.0.0.1:27583`, requires a
  random 256-bit bearer token, and accepts bounded requests. The extension reads
  a conversation title and known UI controls, but not prompt/reply bodies, tool
  input, query parameters, or cookies.
- Codex broker and approval communication use owner-controlled local Unix
  sockets.
- The installer and release workflow contact GitHub to download release assets;
  that is distribution activity, not app telemetry.

## Permissions

Accessibility and Apple Events are used for local app/window/browser focusing
and conservative UI state detection. Without these permissions, Agent Island
continues to run with degraded focusing and app/web detection.

## Diagnostics and support bundles

Raw diagnostics can contain local paths, running app names, hook state, and
recent event metadata. The redacted support bundle deliberately excludes event
logs, transcripts, hook payloads, commands, and project content. It applies an
additional redaction pass for credentials, tokens, email addresses, session
identifiers, user/project paths, and non-loopback IP addresses.

No automated redaction can guarantee that arbitrary text is harmless. Review
every support artifact before sharing it.
