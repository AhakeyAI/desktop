# Contributing to AhaKey Desktop

[English](CONTRIBUTING.md) · [简体中文](docs/zh/CONTRIBUTING.md)

Thank you for helping improve AhaKey Desktop! Bug reports, feature ideas, documentation, translations, and code contributions are all welcome.

## Report a bug or suggest a feature

- Search [existing issues](https://github.com/AhakeyAI/desktop/issues) before opening a new one.
- For bugs, include your operating system, app version, relevant keyboard firmware version, steps to reproduce, expected behavior, and actual behavior. Attach relevant logs or screenshots with credentials and personal information removed.
- For features, describe the workflow you want to improve. Discuss substantial changes in an issue before starting implementation.

## Submit a pull request

1. Fork [AhakeyAI/desktop](https://github.com/AhakeyAI/desktop), clone your fork, and create a branch for your change.
2. Read the [repository layout](docs/repo-layout.md), [architecture](docs/architecture.md), and [build instructions](docs/installation.md). For device changes, also read the [BLE protocol](docs/ble-protocol.md).
3. Keep changes focused and follow the surrounding code's conventions. Update relevant documentation; keep [README.md](README.md) and [docs/zh/README.md](docs/zh/README.md) in sync.
4. Run the relevant checks below. For hardware or UI changes, describe what you verified manually and identify anything you could not test.
5. Open a [pull request](https://github.com/AhakeyAI/desktop/pulls) against the official repository. Explain the problem, the change, related issues, and validation results. Include screenshots for visible UI changes.

Commit source and required assets only. Keep generated build output, installers, signing certificates, and credentials out of the repository.

## Validate your changes

Run commands from the directory shown, using the appropriate platform and toolchain. See the [CI workflow](.github/workflows/ci.yml) for the automated checks.

| Area | Working directory | Checks |
|---|---|---|
| macOS app / agent | Repository root | `swift build`; `swift test` for changes covered by the macOS test suite |
| TypeScript SDK | `sdks/typescript/` | `npm ci`, then `npm run typecheck` and `npm test` |
| Windows Java client | `ahakeyconfig-win-java/` | `mvn -q package` |
| Linux Java client | `ahakeyconfig-ubuntu-java/` | `mvn -q package` |
| Documentation | Changed files | Check links, Markdown rendering, and bilingual consistency |

For other components, follow the [build instructions](docs/installation.md) and describe your validation in the pull request. BLE and lever approval changes also need device testing, including behavior when the keyboard disconnects or its state cannot be read.
