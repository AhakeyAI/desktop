# AhaKey Desktop Harness v0.1-alpha1

面向当前 **Java 17 + JavaFX AhaKey Studio** 的轻量开发 Harness。目标不是重写旧代码，而是把未来的 UI / 用户动线 / Firmware 联调 / 协议变更变成可追踪、可审查、可回归的受控修改。

## 核心原则

1. **Preserve-First**：当前 Java 架构默认保留，除非真实需求或重复缺陷证明必须改变。
2. **User-Journey-First**：任何 UI 新增前，必须先确认用户为什么来到这里、看到什么、下一步做什么。
3. **Contract-Before-Code**：涉及设备的功能，必须先确定 Desktop/Firmware responsibility 与协议合同。
4. **No UI Piling**：禁止默认在现有 ScrollPane / 弹窗底部“再加一块”。必须先做 UI Placement Decision。
5. **Protocol Is Shared Contract**：Desktop 不得自行发明 command；Firmware 也不能把 UI policy 塞进协议。
6. **Minimal Change**：Builder 在既有架构上做最小改动；未来 Rust 不得成为当前 Java 重写理由。

## 两个长期角色

- **DLA / Desktop Lead**：产品、UX、信息架构、协议、责任边界、Review。默认不改生产 Java。
- **DIB / Desktop Builder**：按已接受 Contract 实现、测试、联调。不得自行改变 UI placement、协议或产品语义。
- **Owner**：用户动线、产品语义、真机体验、最终 UAT。

## 流程

### Phase 0 — BASELINE_ADOPT（一次）
读取现有代码与 `baseline/`，确认当前事实，建立 Canonical Truth。禁止重构。

### Phase 1 — CONTRACT
对每个新需求/固件交接：

`INTAKE → USER JOURNEY → UI PLACEMENT → RESPONSIBILITY → PROTOCOL → OWNER GRILL → FRESH REVIEW`

输出一个 Change Contract；没有 Contract 不进入实现。

### Phase 2 — BUILD_VERIFY

`IMPLEMENT → MACHINE TEST → DEVICE INTEGRATION → OWNER UAT → DEFECT LOOP`

实现缺陷留在 Phase 2 解决；只有产品语义 / UI 信息架构 / 协议 / Responsibility 改变才退回 Phase 1。

## 当前 baseline

本包已带入 Codex 对当前仓库的 8 份 Code Archaeology 结果。安装后仍要求 DLA 对照真实仓库复核；baseline 不是新的“理想架构”。

## 安装

```powershell
python .\install_desktop_harness_v01.py `
  --repo "C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java" `
  --commit
```

安装后先运行：

```powershell
python .agents\skills\ahakey-desktop-harness\scripts\desktop_status.py
```

然后在 Codex App 新开一个对话，使用 `docs/architecture/DESKTOP_HARNESS_FIRST_RUN_PROMPT.md` 里的短 Prompt 启动 Phase 0。
