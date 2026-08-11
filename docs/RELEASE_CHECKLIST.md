# Agent Island Release Checklist

Updated: 2026-08-12

## Product and safety gates

- App runs from `/Applications/Agent Island.app` and uses packaged scripts.
- Settings, Diagnostics, redacted support bundle, and hook repair work.
- Hook installation preserves unrelated entries and fails closed on invalid
  configuration.
- Auto approval is disabled by default; sensitive/out-of-workspace/unknown and
  all mutating/shell operations require manual handling.
- Browser and broker transports pass their parser/socket trust-boundary tests.
- Optional tools are reported as capability gaps, not fatal product failures.
- MIT, Apache-2.0, and third-party notices are present in source and app bundle.

## Validation

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
git diff --check
```

CI must execute the Swift tests with `--require-xctest`, and both CI and CodeQL
must pass on the release commit. Re-run a full tracked-history secret scan before
tagging.

## Build and inspect

```bash
AGENT_ISLAND_VERSION=0.2.0 \
AGENT_ISLAND_BUILD_NUMBER=2 \
AGENT_ISLAND_UNIVERSAL=1 \
scripts/build-app
codesign --verify --deep --strict --verbose=2 "dist/Agent Island.app"
```

Confirm `Contents/Resources/Licenses/` contains the project MIT license,
Apache-2.0 text, and `THIRD_PARTY_NOTICES.md`.

## Preview release

A preview may be ad-hoc signed, but release notes and README must say that it is
not notarized. Trigger:

```bash
gh workflow run release.yml -f tag=v0.2.0 -f prerelease=true
```

Verify both release assets and install into a temporary destination:

```bash
AGENT_ISLAND_INSTALL_DIR="$HOME/Applications" \
  bash scripts/install --version v0.2.0 --no-hooks --no-open
```

## Stable release gates

Do not mark a release stable or publish the Homebrew tap until all are true:

1. Developer ID signature verifies.
2. Hardened runtime is enabled.
3. Apple notarization succeeds and the ticket is stapled.
4. Gatekeeper assessment passes on a downloaded artifact.
5. `SHA256SUMS` matches the release asset.
6. The one-command installer succeeds from a clean user account and restores a
   previous app after an injected installation failure.
7. The rendered Cask points to the verified notarized artifact and passes audit.

## Public release contents

- Source, docs, scripts, changelog, security/privacy policy, and license notices
- `Agent-Island-macOS.zip`
- `SHA256SUMS`
- generated release notes that distinguish shipped features from roadmap items

Never include `.build/`, `dist/`, local runtime data, transcripts, credentials,
support bundles, or downloaded competitor source snapshots.
