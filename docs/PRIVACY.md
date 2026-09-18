# Privacy and Data Use

Last updated: 2026-09-19

PinChat is a local macOS companion for Codex. It does not operate its own AI
service or analytics backend, but prompts and selected attachments are still
processed through Codex and OpenAI under the user's existing account. This
document distinguishes local PinChat storage from Codex processing.

## Data flow

| Data | Purpose | Destination |
| --- | --- | --- |
| Prompt text and follow-up guidance | Start or steer a Codex task | Local Codex App Server, then the service used by Codex |
| Selected files, folders, and screenshots | Attachment context for the requested task | Local Codex App Server; subsequent access follows the active Codex permission mode |
| Codex thread identifiers and task states | Continue a task and render desktop progress | Read locally through Codex App Server and local task records |
| Codex permission selection | Match the host's current permission behavior | Read locally from `~/.codex/.codex-global-state.json` |
| Conversation display copy | Restore PinChat's current local UI | `~/Library/Application Support/PinChat/sessions.json` |
| Window preferences and completion receipts | Restore UI state and avoid repeated notices | macOS `UserDefaults` for PinChat |
| Dropped or captured image copies | Supply stable attachment files | `~/Library/Caches/PinChat/Attachments/` |
| Desktop pet sprite cache | Render the floating mascot | `~/Library/Caches/PinChat/Pets/` |

## Network behavior

PinChat itself currently makes one direct HTTP request only when no usable local
pet sprite is available: it downloads the legacy fallback sprite from
`persistent.oaistatic.com` and caches it locally.

AI requests are sent by the local Codex executable using the user's Codex or
ChatGPT account and are governed by the applicable OpenAI product settings and
policies. PinChat does not proxy those requests through a PinChat-operated
server.

PinChat currently includes no self-hosted analytics, advertising SDK, tracking
pixel, or automatic crash-reporting service.

## Credentials and account data

PinChat does not ask for or persist passwords, browser cookies, OAuth tokens, or
OpenAI API keys. Authentication and usage limits are managed by the local Codex
installation.

## Permissions

PinChat follows the permission selection stored by Codex Desktop. Depending on
that selection, a task may be read-only, workspace-scoped, approval-gated, or
configured for full access. Full access does not force a task to read files, but
it gives the task broad authority if it chooses to do so.

Full Disk Access is optional. PinChat can open the relevant System Settings page
but cannot grant the permission itself. Grant it only if your intended tasks
need access to protected locations.

## Removing local PinChat data

Quit PinChat before removing data. The relevant locations are:

- `~/Library/Application Support/PinChat/`
- `~/Library/Caches/PinChat/`
- PinChat preferences stored by macOS for bundle identifier `app.pinchat.macos`

Removing PinChat data does not delete the corresponding Codex account, Codex
desktop tasks, or server-side conversation records.

## Scope

This document describes the current source code. Future releases that add
telemetry, another backend, or new third-party integrations must update this
document before release.
