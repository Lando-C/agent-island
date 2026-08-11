# Public Release Security Audit — 2026-08-12

This is a maintainer-performed pre-release audit, not an independent penetration
test. It records the checks used to prepare Agent Island for a broader public
developer preview.

## Scope

- tracked Git history and the intended public working tree
- Swift app, local Unix sockets, Browser Web Bridge, and AppleScript focusing
- Python hook/event bridges and local retention
- installer, hook configuration mutation, release workflow, and support bundle
- dependency/action provenance and third-party license notices

Ignored build output, runtime state, and downloaded competitor snapshots are not
part of the public source or release artifact.

## Secret and provenance review

- Gitleaks 8.30.1 was checksum-verified against its official release metadata.
- The tracked Git history produced zero Gitleaks findings.
- A snapshot containing every tracked file plus intended new public files
  produced zero Gitleaks findings.
- A token-like value was found only in an ignored third-party research snapshot;
  it was never tracked or packaged. The ignored snapshots are removed after the
  audit.
- GitHub Actions are referenced by immutable commit SHA with version comments.
- The Apache-2.0 text matches the Apache Software Foundation canonical text; the
  applicable Ping Island NOTICE is retained, and the non-bundled font notice is
  explicitly excluded as non-pertaining.

## Trust-boundary changes

- Local Agent Island directories/files are constrained to `0700`/`0600`.
  Sensitive reads/appends reject symbolic links, foreign owners, and non-regular
  files; replacements use owner-only same-directory temporary files.
- Codex broker discovery accepts only same-owner Unix sockets under same-owner,
  non-group/world-writable directories.
- Hook peers must deliver bounded JSON promptly; malformed/oversized payloads
  fail closed without descriptor double-close behavior.
- Browser HTTP parsing bounds headers/body, requires one valid content length,
  rejects duplicate authorization, chunked/ambiguous framing, and trailing
  pipelined bytes, and uses a system-random 256-bit token.
- AppleScript literals remove control/line-separator characters before escaping.
- Optional read-only auto approval is confined to the active non-root/non-home
  workspace and rejects sensitive, missing, escaping, and unknown targets.
- Hook configuration updates validate supported JSON first, preserve unrelated
  entries, create owner-only backups, and replace files atomically.
- Support bundles exclude events/transcripts/commands and apply a second pass for
  credentials, IDs, user/project paths, email addresses, and non-loopback IPs.

## Validation performed

- Swift debug and release builds pass; warnings-as-errors passes.
- Swift XCTest and Swift Testing targets compile locally. Full XCTest execution
  is required in GitHub CI because the audit Mac has Command Line Tools rather
  than the full Xcode test runner.
- Eight Python security/fixture tests pass.
- Browser JavaScript and manifest syntax checks pass.
- Shell syntax plus reducer, expansion, broker, hook-installer, and support-bundle
  validators pass. The live broker integration validator safely skips when no
  Codex broker is running; offline real-socket tests still execute.
- The release app verifies under its ad-hoc designated requirement, has bundle ID
  `local.agent-island`, contains exactly the required runtime scripts, and
  packages the MIT, Apache-2.0, and third-party notice files.

## Remaining limitations

- Public bundles remain developer previews until Developer ID signing,
  notarization, stapling, and clean-machine Gatekeeper verification are complete.
- Browser provider selectors can drift; version/profile mismatches are reported
  as degraded and do not overwrite the last trusted state.
- Same-user local processes remain inside the operating-system user trust
  boundary. Agent Island reduces confused-deputy and accidental-target risks but
  is not a sandbox for mutually hostile processes running as the same macOS user.
- No automated secret scanner or redactor guarantees absence of all sensitive
  data. Maintainer review remains required before every release.
