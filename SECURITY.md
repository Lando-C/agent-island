# Security Policy

Agent Island interacts with local AI-agent hooks, terminal metadata,
browser/app focus, local transcripts, and optional approval workflows. A flaw
can affect private files or approval decisions, so security reports are handled
privately.

## Supported versions

The project is pre-1.0. Test against the latest `main` branch or newest GitHub
preview release before reporting. Security fixes are not guaranteed to be
backported to earlier previews.

## Reporting a vulnerability

Do not open a public issue for vulnerabilities that could expose local files,
credentials, hook payloads, approval decisions, or command-execution behavior.

Use [GitHub private vulnerability reporting](https://github.com/Lando-C/agent-island/security/advisories/new).
If that form is unavailable, contact the repository owner privately through the
GitHub profile. Do not include real credentials or private transcripts in the
initial report.

Please include:

- macOS version
- Agent Island version or commit
- affected engine/surface: Codex, Claude, ChatGPT, terminal, browser, or hook
- minimal reproduction steps and expected/actual behavior
- a redacted support bundle only if it is safe to share

## Enforced safety boundaries

- Auto approval is off by default.
- Auto-approval candidates are limited to known read-only Claude tools whose
  targets resolve inside a non-root, non-home active workspace.
- Sensitive, out-of-workspace, shell, write, destructive, and unknown tools
  require manual handling.
- Unsupported or expired approval/input schemas fail closed and leave the
  provider's native prompt in control.
- The Browser Web Bridge is loopback-only, token-authenticated, request-bounded,
  and does not accept chunked/ambiguous HTTP framing.
- Codex broker discovery accepts only same-owner Unix sockets in same-owner,
  non-group/world-writable directories.
- Agent Island local state uses owner-only directories/files and rejects
  symbolic-link/non-regular sensitive targets.
- Support artifacts exclude event/transcript content and receive a second
  redaction pass.

## Release trust

Current releases are developer previews and are not Apple-notarized. A release
must not be described as stable until it is Developer ID signed, notarized,
stapled, and passes Gatekeeper assessment. Always verify the published
`SHA256SUMS`; signatures and checksums do not replace review of a preview build.
