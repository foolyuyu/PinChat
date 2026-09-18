# GitHub Publishing Checklist

This checklist prepares PinChat for discovery without describing the current
development build as a stable public release.

## Repository metadata

Recommended GitHub description:

> Native macOS floating window, desktop pet and task monitor for Codex — quick chat, always-on-top answers, no API key.

Recommended Topics:

```text
macos
swift
swiftui
appkit
macos-app
codex
openai
chatgpt
ai-assistant
desktop-assistant
floating-window
menu-bar-app
productivity
open-source
```

Leave the website field empty until a maintained landing page or documentation
site exists. A stale or unfinished website reduces trust more than no website.

The current browser session was not signed in to GitHub, so these repository
settings were intentionally not changed automatically.

## Social preview

Upload [`docs/assets/social-preview.png`](assets/social-preview.png) in:

**Repository Settings → General → Social preview**

The preview deliberately uses an original companion character, contains no
official OpenAI logo, and labels the project as a community development preview.
The source image is 1774×887, matching GitHub's recommended 2:1 composition.

Image generation prompt:

```text
Use case: ads-marketing
Asset type: GitHub repository social preview, landscape 2:1 composition
Primary request: a polished, trustworthy product banner for an independent
open-source macOS utility named PinChat
Scene/backdrop: soft light macOS-inspired desktop atmosphere with layered
translucent frosted-glass panels
Subject: an original friendly blue pixel-art desktop companion beside a compact
floating chat bar and a minimal task-status card; do not copy an official mascot
Text: "PinChat", "Codex, always within reach.", and
"Community project • Development preview"
Constraints: no Apple, OpenAI, ChatGPT, or Codex logos; no official mascot
likeness; no watermark; no stable-release or download claims
```

The asset was generated using the built-in image generation tool and then copied
into this repository without further visual editing.

## Before asking for Stars

- [ ] Pin the first signed and notarized GitHub Release.
- [ ] Add a 20–40 second privacy-safe demo GIF or video near the README top.
- [ ] Publish SHA-256 checksums and concise release notes.
- [ ] Test installation on a Mac that has never run PinChat.
- [ ] Enable GitHub private vulnerability reporting.
- [ ] Verify the CI badge is green on `main`.
- [ ] Add at least one screenshot for light and dark appearance.
- [ ] Open a small set of clearly scoped `good first issue` tasks.
- [ ] State known limitations in every launch post.

## Suggested search phrases

Use these naturally in release notes and launch posts rather than repeating them
as keyword spam:

- Codex floating window for macOS
- Codex desktop pet and task monitor
- macOS AI always-on-top chat
- ChatGPT Codex quick launcher
- SwiftUI Codex companion
- Codex task completion notification

## Trust review for every release

Before publishing a release, compare the implementation with
[`PRIVACY.md`](PRIVACY.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), and the root
[`SECURITY.md`](../SECURITY.md). Update them whenever storage, network,
permissions, telemetry, authentication, or third-party services change.
