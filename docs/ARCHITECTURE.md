# Architecture and Trust Boundaries

PinChat is intentionally a companion layer rather than a second AI platform.

## Main components

```text
PinChat floating UI
    ├── Conversation App Server process ── prompts, streaming, approvals
    ├── Activity observer process ──────── read-only task summaries
    ├── Local UI store ─────────────────── session display copy and preferences
    └── Local caches ───────────────────── attachments and pet sprites

Codex Desktop / Codex CLI
    ├── authentication and usage limits
    ├── model, personality, reasoning, and permission settings
    ├── durable task history
    └── communication with the Codex service
```

## Conversation channel

PinChat launches the local `codex app-server` executable and communicates using
its structured protocol. This channel creates or resumes a real Codex thread,
streams the response, handles approval requests, and can steer or interrupt the
turn it owns.

When a user opens that task in Codex Desktop, PinChat unsubscribes and releases
its conversation process before opening `codex://threads/<thread-id>`. This
reduces ownership conflicts between two clients.

## Activity observation channel

A separate App Server process lists recent thread metadata. PinChat combines the
server's task state with local Codex task events to show compact progress. The
observer does not subscribe to, steer, interrupt, or modify Codex Desktop-owned
turns.

For that reason, a desktop-owned task's controls must return the user to its
owning Codex window instead of pretending that PinChat can safely control it.

## Permissions

Before a PinChat turn starts, the app reads Codex Desktop's current permission
selection and maps it to the corresponding App Server configuration. PinChat
does not maintain a second hidden permission mode. Approval prompts shown in
PinChat originate from the active Codex turn.

macOS privacy controls remain an outer boundary. Codex full access cannot grant
Screen Recording, Full Disk Access, camera, microphone, or other TCC permissions
that the user has not approved in System Settings.

## Asset boundary

Official desktop pet binary assets are not committed to this repository.
PinChat may read a compatible asset from an installed local ChatGPT app or use a
public OpenAI fallback resource at runtime. The MIT License applies to PinChat's
code and repository content, not to third-party trademarks or assets obtained
outside the repository.

## Current supply chain

The Swift package currently has no external package dependencies. Builds use
Apple frameworks, the locally installed Codex executable, and the source in this
repository. CI runs `swift test` on GitHub-hosted macOS runners.
