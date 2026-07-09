# Privacy

Agent Island is local-first.

## Local Files

Agent Island writes local status and logs under:

```text
~/.agent-island/
```

Common files:

- `events.jsonl`
- `agent-island.log`
- `bridge.log`
- `auto-approval.json`

## Hook Configuration

Agent Island can update:

- `~/.claude/settings.json`
- `~/.codex/hooks.json`
- `~/.codex/config.toml`

Backups are created by the hook installer before modifying configs.

## Network

Agent Island does not upload events, prompts, transcripts, diagnostics, or local
state. GitHub release downloads and external package managers are outside the app
runtime.

## Permissions

Accessibility and Apple Events are used for local app/window/browser focusing
and conservative UI state detection. Without these permissions, Agent Island
continues to run with degraded focusing and app/web detection.

## Diagnostics

Diagnostics may contain local paths, running app names, hook state, and recent
event summaries. Review reports before sharing publicly.
