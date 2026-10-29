<div align="center">

# ⌨️ AhaKey Desktop

**The official cross-platform desktop suite for the AhaKey-X1 — the Vibecoding Keyboard.**

[**English**](README.md) &nbsp;·&nbsp; [**简体中文**](docs/zh/README.md)

[**Documentation**](#documentation) &nbsp;·&nbsp; [**SDK**](sdks/README.md) &nbsp;·&nbsp; [**⭐ Star History**](#star-history) &nbsp;·&nbsp; [**🤝 Contributing**](#contributing)

<br/>

<!-- Release & CI -->
<a href="https://github.com/AhakeyAI/desktop/releases"><img src="https://img.shields.io/github/v/release/AhakeyAI/desktop?include_prereleases&label=release&color=4F46E5" alt="Latest Release"></a>
<a href="https://github.com/AhakeyAI/desktop/actions"><img src="https://img.shields.io/github/actions/workflow/status/AhakeyAI/desktop/release.yml?label=build" alt="Build"></a>
<a href="https://github.com/AhakeyAI/desktop/commits/main"><img src="https://img.shields.io/github/last-commit/AhakeyAI/desktop?color=informational" alt="Last Commit"></a>
<a href="https://github.com/AhakeyAI/desktop/stargazers"><img src="https://img.shields.io/github/stars/AhakeyAI/desktop?style=flat&color=yellow" alt="Stars"></a>

<br/>

<!-- Platforms & Tech -->
<img src="https://img.shields.io/badge/macOS-12%2B-000000?logo=apple&logoColor=white" alt="macOS 12+">
<img src="https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white" alt="Windows 10/11">
<img src="https://img.shields.io/badge/Linux-Ubuntu-E95420?logo=ubuntu&logoColor=white" alt="Ubuntu">
<img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
<img src="https://img.shields.io/badge/Java-17%2B-007396?logo=openjdk&logoColor=white" alt="Java 17+">
<img src="https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white" alt="Python 3.10+">

</div>

### macOS WS1/WS2 adaptation checkpoint

The legacy macOS client includes capability-gated configuration readback, confirmed per-key/mode/standby/lever-binding writes, and explicit App voice takeover without Runtime. This is an integration checkpoint, not a complete new-firmware release: WS3 display resources, remaining UI/device regression and CLI lifecycle validation are pending. See the [handoff and validation record](docs/handoff/CONNECT_AND_TALK_HANDOFF.md).

The macOS firmware flasher waits up to 180 seconds for CH582 ISP. After a failed or cancelled attempt, **Retry Flashing** keeps the selected HEX and asks for confirmation again, then rechecks its hash and the target chip. See the [implementation and validation notes](docs/ahastudio/firmware-flash-wait-and-retry-2026-10-29.md) for the installed-version status.


## <div align="center">Overview</div>

AhaKey Desktop is the companion suite for the **AhaKey-X1 (Vibecoding Keyboard)**, with keyboard configuration, lever-gated AI approval, and an on-device voice agent on macOS.

<a id="documentation"></a>

## <div align="center">Documentation</div>

| Resource | What you'll find |
|---|---|
| [Project overview](docs/overview.md) | Features, clients, macOS highlights, build commands, and repository layout |
| [Installation](docs/installation.md) · [Downloads](https://github.com/AhakeyAI/desktop/releases) | Build instructions and published installers |
| [SDK overview](sdks/README.md) · [TypeScript guide](sdks/typescript/README.md) | Plugin development, API reference, and runnable examples |
| [Architecture](docs/architecture.md) · [BLE protocol](docs/ble-protocol.md) | System design and keyboard communication |
| [Contributing](CONTRIBUTING.md) | Bug reports, pull requests, and validation |

<a id="star-history"></a>

## <div align="center">⭐ Star History</div>

If AhaKey helps your workflow, give the project a [star on GitHub](https://github.com/AhakeyAI/desktop)! Follow our community's growth in the chart below.

<p align="center">
  <a href="https://github.com/AhakeyAI/desktop/stargazers"><img src="https://img.shields.io/github/stars/AhakeyAI/desktop?style=social" alt="GitHub stars for AhakeyAI/desktop"></a>
</p>

<p align="center">
  <a href="https://www.star-history.com/#AhakeyAI/desktop&amp;Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=AhakeyAI/desktop&amp;type=Date&amp;theme=dark">
      <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=AhakeyAI/desktop&amp;type=Date">
      <img width="700" src="https://api.star-history.com/svg?repos=AhakeyAI/desktop&amp;type=Date" alt="Star History chart for AhakeyAI/desktop">
    </picture>
  </a>
</p>

<a id="contributing"></a>

## <div align="center">🤝 Contributing</div>

Help improve AhaKey through bug reports, feature ideas, documentation, translations, or code. Read the [Contributing Guide](CONTRIBUTING.md) to get started, and share feedback through [GitHub Issues](https://github.com/AhakeyAI/desktop/issues). Thanks to everyone who has contributed! 🙏

<p align="center">
  <a href="https://github.com/AhakeyAI/desktop/graphs/contributors">
    <img src="https://contrib.rocks/image?repo=AhakeyAI/desktop" alt="AhaKey Desktop contributors">
  </a>
</p>
