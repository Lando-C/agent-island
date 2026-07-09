## Summary

## Validation

- [ ] `swift build`
- [ ] `python3 -m py_compile scripts/agent-island-bridge.py scripts/codex-broker-probe scripts/validate-codex-broker-probe`
- [ ] `bash -n scripts/agent-island-diagnostics scripts/build-app scripts/install-hooks scripts/agent-island-event`
- [ ] `scripts/validate-session-reducer`
- [ ] `scripts/validate-expansion-controller`
- [ ] `scripts/validate-codex-broker-probe`

## Safety

- [ ] Does not make online equal working.
- [ ] Does not auto-approve dangerous tools.
- [ ] Documents user-visible behavior changes.
