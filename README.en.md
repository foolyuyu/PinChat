# PinChat — a floating macOS companion for Codex

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![CI](https://github.com/foolyuyu/PinChat/actions/workflows/ci.yml/badge.svg)](https://github.com/foolyuyu/PinChat/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Status](https://img.shields.io/badge/status-development_preview-7C3AED)

[简体中文](README.md) · [English](README.en.md)

PinChat is a native macOS floating window, quick-chat bar, desktop pet, and task
monitor for **Codex Desktop / ChatGPT for macOS**. It lets you ask a quick
question, read a short answer, and notice when a Codex task finishes without
repeatedly switching applications.

PinChat is not another AI service. It communicates with the local Codex App
Server, uses the user's existing Free, Plus, Pro, or workspace account, and does
not require an OpenAI API key. Model, reasoning, personality, authentication,
and permission choices remain managed by the local Codex installation.

![PinChat floating macOS companion for Codex](docs/assets/social-preview.png)

> **Development preview:** interfaces and local data formats may still change.
> Current local builds are ad-hoc signed; a Developer ID signed and notarized
> public download is planned before the first stable release.

## Highlights

- A compact global composer opened with `⌥⇧Space` or the floating desktop pet.
- A persistent always-on-top answer window for short conversations.
- Live summaries for recent Codex and PinChat tasks.
- Native file, folder, image, and screenshot attachments.
- Standard macOS editing shortcuts, drag and drop, full-screen Spaces, light and
  dark appearance, and reduced-motion support.
- Real Codex threads that can be handed back to Codex Desktop.
- No separate PinChat account, API key, analytics backend, or cloud history.

The Chinese [README](README.md) currently contains the complete feature list,
protocol notes, and version-by-version implementation history.

## Build from source

Requirements: macOS 14 or later, Xcode with Swift 6, and either ChatGPT Desktop
or an available Codex CLI.

```sh
git clone git@github.com:foolyuyu/PinChat.git
cd PinChat
swift test
./scripts/build-app.sh
open Release/PinChat.app
```

The default output is `Release/PinChat.app`. It is intended for local testing.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow.

## What is next

Before the first public release, the project is prioritizing:

- broader real-world compatibility testing across macOS and Codex versions;
- Developer ID signing, notarization, and a safer installation experience;
- a privacy-safe demo, light/dark screenshots, and a proper GitHub Release;
- accessibility, failure recovery, diagnostics, and visual consistency;
- future shortcuts, localization, and integrations guided by user feedback.

These are directions rather than promised dates. See the complete
[ROADMAP.md](ROADMAP.md) for candidates and explicit non-goals.

## Trust and project status

- [Privacy and data use](docs/PRIVACY.md)
- [Security policy](SECURITY.md)
- [Architecture and trust boundaries](docs/ARCHITECTURE.md)
- [Roadmap](ROADMAP.md)
- [Contributing](CONTRIBUTING.md)
- [GitHub publishing checklist](docs/PUBLISHING.md)

PinChat does not store passwords, browser cookies, OAuth tokens, or API keys. It
stores a local UI copy of conversations, preferences, attachment cache files,
and pet sprite cache files. Prompts and selected attachments are processed by
Codex under the user's existing account and permission settings.

## License and trademark notice

PinChat source code is available under the [MIT License](LICENSE). This license
does not grant rights to OpenAI trademarks, the Codex or ChatGPT brands, or
third-party assets obtained outside this repository.

PinChat is an independent community project. It is not affiliated with,
sponsored by, or endorsed by OpenAI. Codex, ChatGPT, and OpenAI are trademarks
of their respective owners.
