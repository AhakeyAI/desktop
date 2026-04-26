# AhaKey Desktop

> 中文 | English

`AhakeyAI/desktop` is AhaKey’s official desktop baseline source repository.
`AhakeyAI/desktop` 是 AhaKey 官方桌面端 baseline 源码仓库。

## What this repository contains | 仓库包含什么

This repository currently includes source code for both desktop platforms, managed by platform-specific directories.
当前仓库包含 Windows 与 macOS 两个平台源码，并按平台目录拆分管理。

- `platforms/windows/` — Windows source code | Windows 相关代码
- `platforms/macos/client/` — macOS client source code | macOS 客户端源码

Windows and macOS use different tech stacks, system capabilities, and build pipelines, so they are intentionally separated.
Windows 与 macOS 的技术栈、系统能力和构建链路不同，因此目录上保持明确隔离。

## Repository scope | 仓库范围

This repository stores source code, project files, required assets, and documentation.
仓库只保存源码、工程文件、必要资源与说明文档。

Build artifacts are not committed (for example: `exe`, `msi`, `.app`, `.dmg`).
不提交构建产物（如 `exe`、`msi`、`.app`、`.dmg`）。

Installers are distributed via GitHub Releases.
安装包统一通过 GitHub Releases 分发。

## Current status | 当前状态

The macOS baseline source migration is complete, and the codebase is now in post-migration cleanup.
macOS baseline 级源码迁入已完成，当前处于迁移后的整理阶段。

At this stage, the focus is preserving source/project/build assets; no broad refactor of existing business logic or platform implementation is planned here.
当前阶段以保留源码、工程文件、必要资源和构建脚本为主，不在此范围内对现有业务逻辑与平台实现做大规模重构。

## Start here (new contributors) | 新同学建议先读

- `docs/repo-layout.md`
- `docs/installation.md`
- `docs/architecture.md`
- `docs/releases.md`
- `platforms/windows/README.md`
- `platforms/macos/README.md`