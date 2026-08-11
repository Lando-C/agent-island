## Summary

## User impact and safety boundary

## Validation

- [ ] `swift build`
- [ ] `scripts/test-swift`
- [ ] Python fixture/security tests pass
- [ ] shell, Python, JSON, and changed JavaScript syntax checks pass
- [ ] reducer, expansion, and Codex broker validators pass
- [ ] hook-installer and support-bundle validators pass
- [ ] packaged app contains license/notice resources when packaging changed

## Safety

- [ ] Does not make online equal working.
- [ ] Does not auto-approve dangerous, sensitive, out-of-workspace, or unknown tools.
- [ ] Preserves unrelated hook configuration and local user data.
- [ ] Documents user-visible behavior in English and Chinese where applicable.
- [ ] Adds or updates tests for trust-boundary changes.
