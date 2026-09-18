# Contributing to PinChat

Thanks for helping improve PinChat. The project is still a development preview,
so focused bug reports and small, reviewable changes are especially valuable.

## Before opening an Issue

1. Search existing Issues for the same behavior.
2. Reproduce on the latest `main` build when practical.
3. Remove prompts, account details, local paths, and file contents from logs or
   screenshots.
4. Use a security advisory instead of a public Issue for vulnerabilities.

## Local development

Requirements:

- macOS 14 or later
- Xcode with Swift 6 support
- ChatGPT Desktop or an available Codex CLI for integration testing

```sh
git clone git@github.com:foolyuyu/PinChat.git
cd PinChat
swift test
./scripts/build-app.sh
open Release/PinChat.app
```

Before submitting a pull request:

```sh
swift test
./scripts/verify-release.sh
git diff --check
```

## Pull request guidelines

- Keep one behavioral change per pull request where possible.
- Explain the user-visible problem and the resulting interaction.
- Add or update tests for state, placement, protocol, and policy changes.
- Include before/after screenshots or a short recording for visual changes.
- Preserve macOS accessibility labels, keyboard behavior, reduced-motion
  behavior, and full-screen Space support.
- Do not commit account data, task records, screenshots containing personal
  information, build outputs, or extracted official binary assets.
- Do not describe the project as an official OpenAI product.

Large product-direction changes should begin as a Feature Request or Discussion
before implementation.

## Licensing

By contributing, you agree that your contribution is licensed under the MIT
License in this repository. The license covers PinChat's source code; it does
not grant rights to OpenAI trademarks or assets that are not included here.
