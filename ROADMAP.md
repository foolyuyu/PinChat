# PinChat Roadmap

This roadmap describes direction, not promised dates. Priorities can change as
the Codex desktop protocol and user feedback evolve.

## Before the first public release

- [ ] Complete repeated real-world testing across supported macOS versions.
- [ ] Publish a short, privacy-safe product demo and screenshots.
- [ ] Create an Apple Developer ID signed and notarized distribution.
- [ ] Provide a simple DMG or ZIP download with checksums and release notes.
- [ ] Verify clean install, upgrade, uninstall, and first-run permission flows.
- [ ] Add English user-facing documentation for broader discoverability.
- [ ] Document known Codex version compatibility.

## Product reliability

- [ ] Improve recovery when Codex Desktop or App Server updates unexpectedly.
- [ ] Expand accessibility and VoiceOver verification.
- [ ] Add diagnostics that users can export after redacting personal data.
- [ ] Reduce visual differences across macOS appearance and display modes.
- [ ] Continue performance testing for task observation and sprite loading.

## Possible future work

- Optional integrations with other AI providers through user-supplied API keys.
- More configurable shortcuts and placement behavior.
- Localization beyond the current Chinese-first interface.
- Additional attachment and workflow affordances exposed by official Codex
  protocols.

## Explicit non-goals for now

- Replacing the Codex desktop application.
- Maintaining a separate cloud account, conversation service, or analytics
  backend.
- Shipping or redistributing proprietary OpenAI desktop assets in the repo.
- Simulating unsupported Codex controls through brittle accessibility clicks.

Feature ideas are welcome, but please describe the user problem before a
specific implementation.
