# Release And Distribution

Stable releases require a Developer ID Application certificate, hardened runtime,
Apple notarization, stapling, and Gatekeeper assessment. Preview releases may be
ad-hoc signed, but they must be marked as previews and must not be published to a
Homebrew Cask tap.

The currently published release line is a developer preview. The checked-in Cask
is a template only; no README or release note may imply that the tap exists until
the stable gates below have passed.

## Local stable release

```bash
export AGENT_ISLAND_VERSION=0.2.0
export AGENT_ISLAND_BUILD_NUMBER=42
export AGENT_ISLAND_UNIVERSAL=1
export AGENT_ISLAND_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)'
scripts/build-app

export AGENT_ISLAND_NOTARY_KEYCHAIN_PROFILE=agent-island-notary
scripts/notarize-app
shasum -a 256 dist/Agent-Island-macOS.zip
scripts/update-homebrew-cask 0.2.0 "<zip-sha256>"
```

`scripts/notarize-app` accepts an App Store Connect API key instead of a keychain
profile through `AGENT_ISLAND_NOTARY_KEY_FILE`,
`AGENT_ISLAND_NOTARY_KEY_ID`, and `AGENT_ISLAND_NOTARY_ISSUER_ID`.

## Support bundle

```bash
scripts/agent-island-support-bundle --output ~/Desktop
```

The support bundle deliberately excludes event logs, transcript files, Hook
payloads, commands, session IDs, and project paths. It contains only redacted
diagnostics, macOS metadata, signing/Gatekeeper state, and transport-health data.
Run `scripts/validate-support-bundle` before every public release.

## Homebrew

The checked-in [Casks/agent-island.rb](../Casks/agent-island.rb) is a release
template. After a notarized GitHub release exists, publish the rendered cask to a
dedicated tap such as `Lando-C/homebrew-tap`, then users can install it with:

```bash
brew install --cask Lando-C/tap/agent-island
```

Do not publish that command in installation guidance until the tap and notarized
artifact have been verified from a clean machine.
