# Agent Island Release Checklist

Date: 2026-07-09

This checklist is for turning the local app into a GitHub-downloadable product.

## Pre-Release Product Gates

- The app runs from `/Applications/Agent Island.app`.
- Packaged scripts are used at runtime instead of the developer checkout path.
- `Settings...` opens and contains Appearance, System, Safety, Diagnostics, and Roadmap tabs.
- `Run Diagnostics` works inside the app and `Copy Diagnostics Report` works from the menu.
- Hook installer can install Claude Code and Codex CLI hooks without deleting unrelated hooks.
- Auto approval is disabled by default.
- Dangerous tools are never auto-approved.
- Missing optional tools such as tmux, WezTerm, kitty, Warp, cmux, and Kaku are reported as optional capability gaps, not fatal product failures.

## Build

```bash
cd agent-island
AGENT_ISLAND_VERSION=0.1.0 \
AGENT_ISLAND_BUILD_NUMBER=1 \
AGENT_ISLAND_UNIVERSAL=1 \
scripts/build-app
```

The app bundle is generated at:

```text
dist/Agent Island.app
```

## Local Install Smoke Test

```bash
osascript -e 'tell application "Agent Island" to quit' >/dev/null 2>&1 || true
pkill -f '/Applications/Agent Island.app/Contents/MacOS/AgentIsland' 2>/dev/null || true
rm -rf '/Applications/Agent Island.app'
ditto 'dist/Agent Island.app' '/Applications/Agent Island.app'
'/Applications/Agent Island.app/Contents/Resources/scripts/install-hooks' --all
open '/Applications/Agent Island.app'
```

Then verify:

```bash
'/Applications/Agent Island.app/Contents/Resources/scripts/agent-island-diagnostics'
```

## GitHub Release Shape

- Commit source, docs, scripts, and research reports.
- Do not commit `dist/`, `.build/`, or downloaded competitor source snapshots.
- `Agent-Island-macOS.zip`: zipped `.app` bundle.
- `SHA256SUMS`: checksum file.
- `README.md`: first-run guide, permissions, hooks, safety boundaries.
- `THIRD_PARTY_NOTICES.md`: MIT/Apache attributions and clean-room notes.
- `docs/PRODUCT_BLUEPRINT.md`: product direction.
- `docs/CODEBASE_INTEGRATION_MATRIX.md`: reference-source integration plan.
- `docs/RELEASE_CHECKLIST.md`: this release process.

The `.github/workflows/release.yml` workflow validates the tag, runs production
tests and reducer checks, builds a universal app, publishes both assets, and
creates or updates the GitHub Release. Trigger it with:

```bash
gh workflow run release.yml -f tag=v0.1.0 -f prerelease=true
```

After publication, verify the public one-command installer in a temporary app
destination before announcing the release:

```bash
AGENT_ISLAND_INSTALL_DIR="$HOME/Applications" \
  bash scripts/install --version v0.1.0 --no-hooks --no-open
```

The installer must verify `SHA256SUMS`, reject missing assets or mismatches,
and restore an existing app if replacement fails.

## Notarization Roadmap

Initial GitHub builds can be unsigned for internal testing, but public releases
should move to:

1. Developer ID signing.
2. Hardened runtime.
3. Apple notarization.
4. Stapled ticket.
5. DMG or signed zip.
6. Homebrew cask.

## Privacy Statement Needed Before Public Release

- Events are written locally under `~/.agent-island`.
- Hook configs live in `~/.claude/settings.json` and `~/.codex/hooks.json`.
- No telemetry or network upload is performed by Agent Island.
- Browser/app detection uses local macOS Automation and Accessibility signals.
- Auto approval is opt-in and limited to safe read-only Claude PermissionRequest tools.
