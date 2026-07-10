# Contributing to Agent Island

Thanks for helping improve Agent Island. This project is early, so the most
valuable contributions are small, testable improvements to state accuracy,
terminal/app focusing, diagnostics, and safe approval workflows.

## Development Setup

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools
- Swift 5.9+
- Python 3

Build and validate:

```bash
swift build
scripts/test-swift
python3 -m py_compile scripts/agent-island-bridge.py scripts/codex-broker-probe scripts/validate-codex-broker-probe
bash -n scripts/agent-island-diagnostics scripts/build-app scripts/install-hooks scripts/agent-island-event scripts/test-swift
scripts/validate-session-reducer
scripts/validate-expansion-controller
scripts/validate-codex-broker-probe
```

Package locally:

```bash
scripts/build-app
open "dist/Agent Island.app"
```

## Contribution Rules

- Keep behavior changes small and explain what user problem they solve.
- Do not make "online" mean "working".
- Do not show approval/input requests as generic errors.
- Do not add automatic approval for write, shell, destructive, or unknown tools.
- Keep optional local tools such as tmux, WezTerm, kitty, Warp, cmux, and Kaku as
  optional capability checks.
- Preserve unrelated user changes in the working tree.

## Reference Code Policy

Reference projects are documented in `docs/CODEBASE_INTEGRATION_MATRIX.md`.

- MIT/Apache code may be adapted with attribution in `THIRD_PARTY_NOTICES.md`.
- GPL and unknown-license projects are clean-room references only.
- Do not commit downloaded competitor source snapshots into this repository.

## Pull Request Checklist

- `swift build` passes.
- Production Swift tests pass through `scripts/test-swift`.
- Python and shell validation pass.
- Existing reducer/expansion tests pass.
- User-facing docs are updated when behavior changes.
- New approval or quick-action behavior states its safety boundary.
