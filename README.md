# Agent Island

[简体中文](README.zh-CN.md)

Agent Island is a macOS Dynamic Island-style operations panel for AI agents.
It is built for people running Codex, Claude Code, Claude Desktop, Claude
Science, ChatGPT, terminal agents, and browser-based AI sessions at the same
time.

The goal is not to show that an app is online. The goal is to answer:

- Which agent is truly working?
- Which one has finished?
- Which one is waiting for human approval or input?
- Which one is stuck or failed?
- Can I jump back to the exact app window, browser tab, terminal tab, or tmux
  pane?

## Current Capabilities

- Notch-style floating panel with collapsed and expanded states.
- Separate surfaces for App, CLI, Runtime, and Web.
- Separate `available` (installed) from `online`, `idle`, and active work, so an
  installed CLI is not presented as a running session.
- Hook-driven session state for Claude Code and Codex CLI.
- Codex app thread probing and `codex://threads/{threadId}` jump targets.
- Claude Science app/runtime detection.
- ChatGPT App/Web conservative detection. Background browser tabs are not
  reported as "working" without reliable signals.
- Terminal and tmux jump targets through `JumpTarget.terminal` and
  `JumpTarget.tmux`.
- Exact cmux tab/terminal selection and multi-socket WezTerm pane discovery,
  with TTY/CWD and app-level fallbacks for the remaining terminals.
- Clickable rows for returning to related sessions where a target can be known.
- Scrollable expanded session list.
- Auto spotlight for working, waiting, done, and error transitions, with short
  duration and manual dismissal.
- `Escape` closes the expanded panel, and `Option-N` toggles the island.
- When the island is focused, `Command-Y` allows the first inline permission
  request and `Command-N` denies it.
- Screen-safe positioning using visible screen bounds, with user-adjustable
  idle/working widths.
- Settings window with Appearance, System, Safety, Diagnostics, and Roadmap
  tabs.
- Diagnostics report for app, hooks, event stream, permissions, Codex broker,
  hook socket, terminal helpers, app/web surfaces, and auto approval state.
- Hook installer for:
  - Claude Code: `~/.claude/settings.json`
  - Codex CLI: `~/.codex/hooks.json` and `~/.codex/config.toml`
- Pending request store and local hook socket for human handoff.
- Direct Claude Code write-back for `PermissionRequest`, `AskUserQuestion`, and
  `Elicitation`, including multi-question, multi-select, and free-text answers.
- Persistent Codex Desktop broker client for `requestUserInput`, command, file,
  and permission responses when a live `cxc-*/broker.sock` is available. If the
  broker is absent or the request has expired, Agent Island fails closed and
  leaves the native Codex prompt in control.
- On-demand local chat detail windows for Claude and Codex JSONL transcripts,
  including user/assistant messages and tool calls/results.
- Smart spotlight suppression when the corresponding App or terminal is
  already frontmost; status still updates and manual expansion still works.
- Off-island floating mode with 0.35-second long-press/downward-drag detach,
  persisted position, status-menu toggle, and right-click return to the notch.
- Stale session convergence: completed work expires after 10 minutes, idle
  capability rows after 1 hour, and inactive waiting/error events after 12
  hours. Process-aware zombie detection remains on the roadmap.
- Incremental Hook-log ingestion and throttled fallback probes keep status
  transitions responsive without continuously reparsing the full event and
  conversation history.
- Low-frequency activity motion preserves visible working feedback without
  permanent 60 fps redraws, and respects macOS Reduce Motion.
- In-island allow/deny for Claude Code `PermissionRequest` hooks.
- `request_user_input` / elicitation events are captured as structured pending
  requests. Verified Claude hook and Codex app-server schemas are written back
  directly; unsupported transports remain visible but fail closed.
- Optional auto approval for safe read-only Claude PermissionRequest tools.
  It is off by default. Dangerous operations are never auto-approved.

## Quick Install

Requirements: macOS 13 or later. Published release bundles are universal for
Apple Silicon and Intel Macs.

Run the installer in Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Lando-C/agent-island/main/scripts/install)"
```

The installer downloads the newest non-draft GitHub Release, verifies the
published SHA-256 checksum, installs the app at `/Applications/Agent Island.app`,
backs up and installs Claude Code/Codex CLI hooks, and opens the app. It does not
enable auto approval.

To inspect the installer before running it:

```bash
curl -fsSL https://raw.githubusercontent.com/Lando-C/agent-island/main/scripts/install \
  -o /tmp/agent-island-install
less /tmp/agent-island-install
bash /tmp/agent-island-install
```

Options:

```bash
bash /tmp/agent-island-install --version v0.1.0
bash /tmp/agent-island-install --no-hooks
bash /tmp/agent-island-install --no-open
```

Re-run the same command to update. The previous app is restored automatically
if installation fails.

## Manual Release Install

1. Open [GitHub Releases](https://github.com/Lando-C/agent-island/releases).
2. Download both `Agent-Island-macOS.zip` and `SHA256SUMS`.
3. Verify the archive in Terminal:

   ```bash
   shasum -a 256 -c SHA256SUMS
   ```

4. Unzip the archive and move `Agent Island.app` to `/Applications`.
5. This developer preview is not Apple-notarized yet. On first launch,
   Control-click the app, choose **Open**, then confirm **Open**.
6. In Agent Island, open **Settings > Diagnostics**, then install hooks and
   grant only the permissions needed by the surfaces you use.

## Install From Source

```bash
git clone https://github.com/Lando-C/agent-island.git
cd agent-island
swift build
scripts/test-swift
scripts/build-app
open "dist/Agent Island.app"
```

`scripts/build-app` applies a stable local designated requirement so rebuilding
does not create a new Accessibility identity on every run. Release builds should
set `AGENT_ISLAND_SIGNING_IDENTITY` to a Developer ID Application identity.

For local daily use, install the built app into `/Applications`:

```bash
rm -rf "/Applications/Agent Island.app"
ditto "dist/Agent Island.app" "/Applications/Agent Island.app"
open "/Applications/Agent Island.app"
```

Then open the status menu and use:

- `Settings...`
- `Reinstall Claude/Codex Hooks`
- `Copy Diagnostics Report`

## First Run

1. Move `Agent Island.app` to `/Applications`.
2. Open the app.
3. Open `Settings...`.
4. Grant Accessibility/Automation permissions if you want app/browser focusing
   and UI-based detection.
5. If you used the manual ZIP/source path, click `Reinstall Hooks` to install
   Claude Code and Codex CLI hooks. The one-command installer already does this.
6. Run `Diagnostics` and check the report.

Missing optional tools such as tmux, WezTerm, kitty, Warp, cmux, or Kaku should
appear as capability warnings. They are not fatal unless you expect Agent Island
to jump into those tools.

Claude App session jumps use Claude's local `cliSessionId -> localSessionId`
metadata and raise the window containing the exact local session URL. macOS
Accessibility permission is required for this exact selection. Without it,
Agent Island activates Claude but deliberately does not choose a random session;
use `Open Accessibility Settings` from the status menu to grant permission. An
authorization prompt is shown at most once per app launch.

## Hook Model

Agent Island uses status hooks first and process/app detection as fallback.
Without hooks, it can often tell whether an app is online, but it should not
pretend that online means working.

Install hooks manually:

```bash
scripts/install-hooks --all
```

The packaged app runs the bundled copy:

```text
/Applications/Agent Island.app/Contents/Resources/scripts/install-hooks
```

Events are written locally:

```text
~/.agent-island/events.jsonl
~/.agent-island/agent-island.log
```

Human approval requests use a local Unix socket:

```text
~/.agent-island/hook.sock
```

The hook bridge connects to that socket for pending requests. Claude Code
`PermissionRequest` can be allowed or denied directly in the island, while
`AskUserQuestion` and `Elicitation` can return structured answers. If the app is
not running or the socket is unavailable, the bridge falls back to the native
agent flow instead of silently approving anything.

## Safety Model

Auto approval is a trust feature, not a shortcut.

Default:

- Off.
- No network upload.
- No hidden approvals.

Can be auto-approved only when explicitly enabled:

- `Read`
- `Grep`
- `Glob`
- `LS`
- `TodoRead`

Never auto-approved:

- `Write`
- `Edit`
- `MultiEdit`
- `NotebookEdit`
- `Bash`
- `Shell`
- `rm`
- `sudo`
- `git push --force`
- `git reset --hard`
- `git clean`
- permission changes
- disk/system/launchctl operations

Config path:

```text
~/.agent-island/auto-approval.json
```

## Diagnostics

From the app menu or Settings window, copy/run the diagnostics report. It checks:

- App bundle location and packaged scripts.
- Claude/Codex hook installation.
- Hook socket availability.
- Event stream freshness.
- Accessibility and Apple Events.
- Codex broker/socket visibility.
- tmux availability and server state.
- terminal helper tools such as `wezterm`, `kitty`, `kitten`, and `osascript`.
- running app surfaces such as Codex, Claude, ChatGPT, Chrome, and Safari.
- auto approval state.

Command-line diagnostics:

```bash
"/Applications/Agent Island.app/Contents/Resources/scripts/agent-island-diagnostics"
```

## Uninstall

Remove Agent Island's hook entries before deleting the app. Other hooks are
preserved and the configuration files are backed up first.

```bash
"/Applications/Agent Island.app/Contents/Resources/scripts/install-hooks" --uninstall
rm -rf "/Applications/Agent Island.app"
```

Optional local runtime data removal:

```bash
rm -rf "$HOME/.agent-island"
```

## Product Direction

The product direction is documented in:

- [`docs/PRODUCT_BLUEPRINT.md`](docs/PRODUCT_BLUEPRINT.md)
- [`docs/CODEBASE_INTEGRATION_MATRIX.md`](docs/CODEBASE_INTEGRATION_MATRIX.md)
- [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md)
- [`docs/ENGINEERING_REVIEW_2026-07-10.md`](docs/ENGINEERING_REVIEW_2026-07-10.md)
- [`research/feature-coverage-matrix.md`](research/feature-coverage-matrix.md)

Next priority is not a UI rewrite. The next product work should be:

1. Connect Codex CLI interactive requests that do not expose a desktop broker,
   while preserving the fail-closed native prompt fallback.
2. More exact existing-window focusing for Warp, kitty, and Kaku.
3. Incremental hook-driven chat history so details do not need on-demand JSONL
   parsing.
4. Process-aware zombie detection and transcript fallback beyond the existing
   time-based stale-session pruning.
5. Release signing/notarization and Homebrew cask.
6. Replace the floating capsule MVP with configurable animated mascots and add
   opt-in event sounds.

## Reference Projects

Agent Island studies and selectively adapts ideas from:

- [DevIsland](https://github.com/nangchang/DevIsland)
- [agentbro](https://github.com/shirenchuang/agentbro)
- [pi-island](https://github.com/phun333/pi-island)
- [vibe-notch](https://github.com/farouqaldori/vibe-notch)
- [MioIsland](https://github.com/MioMioOS/MioIsland)
- BoringNotch and other notch utilities as clean-room UX references only.

License notes are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Privacy

Agent Island stores local status data under `~/.agent-island`. It does not upload
events, conversations, hook payloads, or diagnostics.
