# Security Policy

## Supported versions

PinChat is currently a development preview. Security fixes are applied to the
latest code on `main`; older local builds are not maintained as separate
supported release lines yet.

## Reporting a vulnerability

Please do not open a public Issue for a vulnerability that could expose user
data, credentials, local files, or command execution.

Use GitHub's private vulnerability reporting page instead:

<https://github.com/foolyuyu/PinChat/security/advisories/new>

Include the affected commit or version, macOS version, reproduction steps,
expected impact, and any suggested mitigation. Remove personal prompts, file
contents, access tokens, usernames, and local paths from screenshots or logs.

If private vulnerability reporting is unavailable, contact the maintainer
through the GitHub profile before sharing technical details publicly.

## Security boundaries

- PinChat launches a local Codex App Server and inherits the permission mode
  selected in Codex Desktop.
- A Codex `full access` configuration is intentionally powerful. PinChat does
  not reduce that authority and cannot bypass macOS privacy protections.
- Full Disk Access is optional and must be granted manually in System Settings.
- Files and screenshots selected as attachments can be read by the Codex task
  receiving them.
- PinChat does not store passwords, browser cookies, OAuth tokens, or API keys.
- The repository currently has no third-party Swift package dependencies.
- Local test builds are ad-hoc signed. Public distribution should use a
  Developer ID signature, notarization, published checksums, and reproducible
  release notes.

See [docs/PRIVACY.md](docs/PRIVACY.md) and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the complete data flow and
trust model.
