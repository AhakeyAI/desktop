[English](#english) | [简体中文](#简体中文)

---

# English

## AhaKey Desktop

Official baseline desktop client for AhaKey hardware.

This repository is the official starting point for the AhaKey desktop software experience.

Its purpose is to provide:

- a usable baseline client for AhaKey users
- a reference implementation for the public BLE protocol
- a starting point for community improvements and alternative clients

---

## Positioning

AhaKey Desktop is the **official baseline client**, not the only possible client.

We expect the ecosystem to grow through:

- official baseline software
- community-built native clients
- experimental tools
- workflow-specific integrations

The goal of this repository is to make AhaKey usable by default, while leaving room for the community to build more specialized clients.

---

## What this repository is for

This repository is intended to include:

- official baseline desktop application code
- device connection and management logic
- key configuration workflows
- protocol-backed desktop features
- documentation about client status and roadmap

---

## Relationship to the protocol repository

The public BLE contract is documented in the `protocol` repository.

This repository is the official baseline client built on top of that protocol layer.

If you want to understand device communication first, start with:

- `protocol/docs/overview.md`
- `protocol/docs/ble-services.md`
- `protocol/docs/commands.md`

---

## Current goals

Current repository goals include:

- basic usable device connection flow
- baseline configuration workflow
- protocol-aligned desktop behavior
- clear documentation for what is stable and what is still evolving

---

## What this repository is not

This repository is not intended to be:

- the only allowed client
- the only future UI
- a closed implementation
- a promise that every platform will have the same level of support immediately

We welcome the ecosystem to grow beyond this baseline.

---

## Repository structure

- `docs/status.md` — current implementation status
- `docs/roadmap.md` — short-term development direction
- `docs/supported-platforms.md` — support status by platform
- `docs/architecture.md` — high-level desktop architecture
- `app/` — application source area
- `assets/` — screenshots, icons, and visual assets

---

## Community

Questions, workflow ideas, bug reports, and client discussions are welcome in AhaKey Discussions.

If you want to build a different client, improve platform support, or propose a better workflow, we welcome that.

---

# 简体中文

## AhaKey Desktop

AhaKey 官方基础桌面客户端。

这个仓库是 AhaKey 桌面软件体验的官方起点。

它的目标是提供：

- 一个对 AhaKey 用户可用的基础客户端
- 一个基于公开 BLE 协议的参考实现
- 一个可以让社区继续改进和派生替代客户端的起点

---

## 仓库定位

AhaKey Desktop 是 **官方基础客户端**，但它不是唯一可能的客户端。

我们希望整个生态通过以下几部分一起生长：

- 官方基础软件
- 社区开发的原生客户端
- 实验性工具
- 面向特定工作流的集成

这个仓库的目标，是让 AhaKey 默认可用，同时给社区留下继续做更专业客户端的空间。

---

## 这个仓库会放什么

这个仓库计划包含：

- 官方基础桌面应用代码
- 设备连接与管理逻辑
- 按键配置流程
- 基于协议的桌面端功能
- 当前状态与路线图相关文档

---

## 和协议仓库的关系

公开 BLE 协议定义在 `protocol` 仓库中。

这个仓库则是建立在该协议层之上的官方基础客户端。

如果你想先理解设备通信方式，建议先看：

- `protocol/docs/overview.md`
- `protocol/docs/ble-services.md`
- `protocol/docs/commands.md`

---

## 当前目标

当前阶段，这个仓库的目标包括：

- 基础可用的设备连接流程
- 基础配置工作流
- 与协议对齐的桌面端行为
- 清楚说明哪些能力已经稳定，哪些还在演进

---

## 这个仓库不是什么

这个仓库并不是：

- 唯一允许存在的客户端
- 唯一未来 UI 方案
- 封闭实现
- 对所有平台立刻提供同等支持的承诺

我们欢迎生态在这个基础之上继续生长。

---

## 仓库结构

- `docs/status.md` — 当前实现状态
- `docs/roadmap.md` — 短期开发方向
- `docs/supported-platforms.md` — 各平台支持状态
- `docs/architecture.md` — 桌面端高层架构
- `app/` — 应用源码区域
- `assets/` — 截图、图标和视觉资源

---

## 社区参与

问题、workflow 想法、bug 反馈和客户端讨论，欢迎在 AhaKey Discussions 中进行。

如果你想做不同的客户端、改进平台支持，或者提出更好的工作流方案，我们都欢迎。
