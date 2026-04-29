[English](#english) | [简体中文](#简体中文)

---

# English

## macOS Platform

This directory contains macOS-related source code for the official AhaKey desktop baseline.

The goal of this platform directory is to keep macOS implementation clearly separated from Windows, since the two platforms use different runtime stacks, UI models, and system capabilities.

### Why macOS is separated

The macOS client is not just a small variant of the Windows client.

It may involve:

- Swift and Apple-native frameworks
- macOS-specific UI patterns
- Apple-specific system integration
- native transcription / system capability integration
- platform-specific workflow interaction design

Because of that, macOS source code is organized under `platforms/macos/` instead of being mixed directly with Windows code.

### What this directory is for

This directory is intended to contain:

- official macOS client source code
- macOS-specific platform logic
- build instructions
- platform documentation
- the imported client baseline under `platforms/macos/client/`

### Current status

macOS client source code has been imported into `platforms/macos/client/`.

The macOS baseline is still in an early post-migration state. Source, project files, required resources, and selected scripts are preserved as imported. Build/release normalization and later cleanup work are still pending.

### Notes

- Release binaries such as `.dmg` files are not stored in source directories
- Packaged macOS builds should be distributed through GitHub Releases
- Historical macOS repositories may be retained temporarily during migration
- macOS source is kept separate from Windows code and is not mixed into `platforms/windows/`

### Installation docs

- Repository-level installation overview: `docs/installation.md`
- macOS client build/package details: `platforms/macos/client/README.md`

---

# 简体中文

## macOS 平台目录

这个目录用于存放 AhaKey 官方桌面客户端基线中的 macOS 相关源码。

之所以单独拆出这个平台目录，是因为 macOS 和 Windows 在运行时栈、UI 模型以及系统能力上都有明显不同，需要分别组织。

### 为什么 macOS 要单独拆开

macOS 客户端并不是 Windows 客户端的一个小变体。

它可能涉及：

- Swift 和 Apple 原生框架
- macOS 特有的 UI 交互模式
- Apple 系统级集成
- 原生转录 / 系统能力接入
- 平台特有的 workflow 交互设计

所以 macOS 源码会放在 `platforms/macos/` 下，而不是和 Windows 混在一起。

### 这个目录会放什么

这个目录计划包含：

- 官方 macOS 客户端源码
- macOS 平台相关逻辑
- 构建说明
- 平台文档
- 已迁入的 `platforms/macos/client/` 客户端基线源码

### 当前状态

macOS 客户端源码已迁入 `platforms/macos/client/`。

当前状态仍属于迁移后的早期整理阶段。本轮以保留源码、工程文件、必要资源和选定脚本为主，后续再单独处理构建标准化、清理项和发布流程收敛。

### 说明

- `.dmg` 等发布二进制不会存放在源码目录中
- macOS 安装包应通过 GitHub Releases 分发
- 迁移过程中，历史 macOS 仓库可能会暂时保留
- macOS 源码不会混入 `platforms/windows/`

### 安装文档入口

- 仓库级安装总览：`docs/installation.md`
- macOS 客户端构建与打包细节：`platforms/macos/client/README.md`
