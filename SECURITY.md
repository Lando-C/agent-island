# Security Policy

Agent Island interacts with local AI agent hooks, terminal metadata, browser/app
focus, and optional approval workflows. Treat security reports seriously.

## Supported Versions

The project is pre-1.0. Please test against the latest `main` branch or latest
GitHub release before reporting.

## Reporting a Vulnerability

Do not open a public issue for vulnerabilities that could expose local files,
credentials, hook payloads, approval decisions, or command execution behavior.

Use GitHub private vulnerability reporting if it is enabled. If not, contact the
maintainer privately through the repository owner profile.

Please include:

- macOS version
- Agent Island version or commit
- affected engine/surface: Codex, Claude, ChatGPT, terminal, browser, hook
- reproduction steps
- expected vs actual behavior
- diagnostics report if safe to share

## Safety Boundaries

- Auto approval is off by default.
- Dangerous tools and shell commands must never be auto-approved.
- Hook payloads and diagnostics are local by default.
- Optional helper tools are capability checks, not required dependencies.
