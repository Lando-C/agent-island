# Changelog

All notable changes are recorded here. Agent Island follows semantic versioning
for public releases while pre-1.0 interfaces remain subject to change.

## Unreleased

### Security

- Enforce owner-only local state directories/files with no-follow sensitive
  reads/appends and secure atomic replacement.
- Bound and strictly parse Browser Web Bridge HTTP requests, reject ambiguous
  framing, generate pairing tokens with system randomness, and compare bearer
  values without data-dependent byte comparison.
- Accept Codex broker endpoints only from same-owner Unix sockets in private
  same-owner directories.
- Restrict optional read-only auto approval to non-sensitive targets inside the
  active workspace, including protection against relative-path escapes.
- Fail closed on invalid hook configuration instead of replacing it, preserve
  unrelated hooks, and make installer replacement rollback-safe.
- Add second-pass support-bundle redaction and remove hostnames, event content,
  transcripts, commands, and project paths from support artifacts.
- Sanitize untrusted metadata before AppleScript interpolation.

### Added

- CodeQL workflow and immutable GitHub Action references.
- Offline security fixtures for the broker, hook installer, support bundle,
  Browser Web Bridge parser/token, and AppleScript escaping.
- Packaged MIT, Apache-2.0, and third-party notice resources.

## 0.1.0 - 2026-07-09

- First public developer preview for macOS.
