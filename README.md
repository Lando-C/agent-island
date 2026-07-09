# Agent Island

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
- Hook-driven session state for Claude Code and Codex CLI.
- Codex app thread probing and `codex://threads/{threadId}` jump targets.
- Claude Science app/runtime detection.
- ChatGPT App/Web conservative detection. Background browser tabs are not
  reported as "working" without reliable signals.
- Terminal and tmux jump targets through `JumpTarget.terminal` and
  `JumpTarget.tmux`.
- Clickable rows for returning to related sessions where a target can be known.
- Scrollable expanded session list.
- Auto spotlight for working, waiting, done, and error transitions, with short
  duration and manual dismissal.
- Screen-safe positioning using visible screen bounds, with user-adjustable
  idle/working widths.
- Settings window with Appearance, System, Safety, Diagnostics, and Roadmap
  tabs.
- Diagnostics report for app, hooks, event stream, permissions, Codex broker,
  terminal helpers, app/web surfaces, and auto approval state.
- Hook installer for:
  - Claude Code: `~/.claude/settings.json`
  - Codex CLI: `~/.codex/hooks.json` and `~/.codex/config.toml`
- Optional auto approval for safe read-only Claude PermissionRequest tools.
  It is off by default. Dangerous operations are never auto-approved.

## Install From Source

```bash
git clone https://github.com/Lando-C/agent-island.git
cd agent-island
swift build
scripts/build-app
open "dist/Agent Island.app"
```

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
5. Click `Reinstall Hooks` to install Claude Code and Codex CLI hooks.
6. Run `Diagnostics` and check the report.

Missing optional tools such as tmux, WezTerm, kitty, Warp, cmux, or Kaku should
appear as capability warnings. They are not fatal unless you expect Agent Island
to jump into those tools.

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

## Product Direction

The product direction is documented in:

- [`docs/PRODUCT_BLUEPRINT.md`](docs/PRODUCT_BLUEPRINT.md)
- [`docs/CODEBASE_INTEGRATION_MATRIX.md`](docs/CODEBASE_INTEGRATION_MATRIX.md)
- [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md)
- [`research/feature-coverage-matrix.md`](research/feature-coverage-matrix.md)

Next priority is not a UI rewrite. The next product work should be:

1. Structured `PendingRequest` cards for approval and `request_user_input`.
2. More exact terminal focusing for Warp, Ghostty, WezTerm, kitty, cmux, and Kaku.
3. Hook-driven chat history and tool details.
4. Zombie detection and old-session pruning.
5. Smart suppression when the exact target session is already frontmost.
6. Release packaging, signing/notarization plan, and Homebrew cask.
7. Off-island floating mode, mascot, and sound once the status/jump core is
   reliable.

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
