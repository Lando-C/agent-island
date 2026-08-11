# Contributing to Agent Island

Agent Island is pre-1.0. The most useful contributions are focused, testable
improvements to state accuracy, terminal/app focusing, diagnostics, privacy, and
safe human handoff.

## Development setup

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools (full Xcode is required to execute XCTest locally)
- Swift 5.9+
- Python 3 and Node.js

Run the same validation surfaces used by CI:

```bash
swift build
scripts/test-swift
python3 Tests/Python/test_claude_hook_fixture_replay.py
python3 Tests/Python/test_codex_broker_probe_security.py
scripts/validate-session-reducer
scripts/validate-expansion-controller
scripts/validate-codex-broker-probe
scripts/validate-install-hooks
scripts/validate-support-bundle
```

Also run syntax checks for changed Python, shell, JSON, and browser-extension
files. Package locally with `scripts/build-app`; confirm that the app bundle
contains the MIT license, Apache-2.0 text, and third-party notices.

## Contribution rules

- Keep behavior changes small and explain the user problem they solve.
- Do not make "online" mean "working".
- Do not show approval/input requests as generic errors.
- Do not broaden auto approval without explicit threat analysis and tests.
- Keep optional local tools such as tmux, WezTerm, kitty, Warp, cmux, and Kaku
  as optional capability checks.
- Preserve unrelated user changes and avoid committing generated builds,
  credentials, transcripts, or downloaded competitor source snapshots.
- Update English and Chinese user-facing docs together when behavior changes.

## Reference code policy

Reference projects are documented in `docs/CODEBASE_INTEGRATION_MATRIX.md`.

- MIT/Apache code may be adapted with attribution in
  `THIRD_PARTY_NOTICES.md` and the applicable license text.
- GPL and unknown-license projects are clean-room references only.
- Do not commit downloaded competitor source snapshots into this repository.

## Pull requests

Use a focused branch, complete the pull-request checklist, and identify privacy,
approval, socket, installer, or release implications. Maintainers may ask for a
smaller PR when security-sensitive and product changes are mixed.
