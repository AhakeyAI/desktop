# Supported Platforms

## 当前仓库状态

仓库以多平台 monorepo 组织,每个客户端独立目录:

- **macOS** — `ahakeyconfig-mac/`(Swift · SwiftUI),主力开发,由仓库根 `Package.swift` 构建。
- **Windows** — `ahakeyconfig-win-java/`(Java · JavaFX · Maven)与 `ahakeyconfig-win-python/`(Python · PyInstaller,Capswriter 基线)两套客户端。
- **Linux** — `ahakeyconfig-ubuntu-java/`(Java · JavaFX · Maven),Ubuntu 桌面客户端。
- **键盘固件** — `CH582m_vibe_coding_BLE_keyboard-master/`(C,CH582M MCU)。
- **BLE ↔ TCP 桥接** — `BLE_tcp_bridge/`(C#),供非原生客户端通过本地 TCP 与设备交互。

## 当前非目标

- 云端后端部署仓库
- 安装包二进制归档(统一走 GitHub Releases)

## 平台说明

- 各平台代码按客户端独立目录管理,不混放;运行时、UI 模型与系统能力差异较大。
- macOS 为主力实现:原生 BLE 栈 + 常驻 `ahakeyconfig-agent`,并提供拨杆审批 AI hook。详见仓库根 `README.md` 与 `docs/architecture.md`。
