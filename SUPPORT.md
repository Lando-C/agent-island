# Support

Use GitHub Issues for bugs, feature requests, and diagnostics questions.

Before opening an issue:

1. Run Agent Island from `/Applications`.
2. Reinstall hooks from the app menu or Settings.
3. Open `Settings...` and run Diagnostics.
4. Check whether warnings are required failures or optional capability gaps.

Useful local commands:

```bash
"/Applications/Agent Island.app/Contents/Resources/scripts/agent-island-diagnostics"
swift build
scripts/validate-session-reducer
scripts/validate-expansion-controller
scripts/validate-install-hooks
scripts/validate-support-bundle
```

Do not paste private prompts, credentials, API keys, or sensitive command output
into public issues. Use the redacted support-bundle command from the README and
review the resulting archive before attaching it. Security issues belong in
GitHub private vulnerability reporting, not a public issue.
