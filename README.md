# AhaKey Desktop

`AhakeyAI/desktop` 是 AhaKey 官方 desktop baseline 源码仓库。

当前仓库已纳入 Windows 与 macOS 两个桌面平台的源码，并按平台拆分管理：

- Windows 相关代码位于 `platforms/windows/`
- macOS 客户端源码位于 `platforms/macos/client/`

Windows 与 macOS 使用不同技术栈、系统能力和构建链路，不在同一目录混放。仓库只保存源码、工程文件、必要资源和说明文档，不提交 `exe`、`msi`、`.app`、`.dmg` 等构建产物；安装包统一通过 GitHub Releases 分发。

当前 macOS 部分已完成 baseline 级源码迁入，但仍处于迁移后的整理阶段。现阶段以保留源码、工程文件、必要资源和构建脚本为主，不对现有业务逻辑和平台实现做重构。

建议先阅读：

- `docs/repo-layout.md`
- `docs/installation.md`
- `docs/architecture.md`
- `docs/releases.md`
- `platforms/windows/README.md`
- `platforms/macos/README.md`
