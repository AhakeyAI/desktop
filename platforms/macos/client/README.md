# AhaKeyConfig — AhaKey-X1 原生 macOS 配置工具

## 项目简介

这是一个用 Swift + SwiftUI 写的 macOS 原生应用，直接通过 CoreBluetooth 连接 AhaKey-X1（Vibecoding Keyboard），**不需要 TCP 桥接层**。

原厂工具的架构是 Python (PySide6) → .NET TCP Bridge → Swift BLE Helper，三层转接。这个项目把整个链路压缩成一个 Swift 应用，直连 BLE。

### 功能

- BLE 自动扫描/连接/重连 AhaKey-X1 设备
- 设备状态查询（电量、固件版本、工作模式、灯光、拨杆）
- 4 键 × 3 模式的键位映射（快捷键 + OLED 描述文字）
- IDE 状态同步 → LED 变色（Claude Code hooks 集成）
- OLED 图片/GIF 管理界面（协议已实现，上传功能 TODO）
- 后台守护进程维持 BLE 连接（LaunchAgent）

### 协议实现完整度

BLE 协议已从原厂工具反编译完整还原，包括：
- 帧格式（AA BB ... CC DD）
- 全部 DeviceCmd（0x00-0x90）
- 按键配置（快捷键/宏/描述 三种子类型）
- 大数据写入流程（OLED 图片）
- IDE 状态同步（0x90）

详见 `docs/ble-protocol.md`。

---

## 构建说明

### 环境要求

- macOS 15.0+
- Xcode 15+（或等效 Swift toolchain）
- Swift 5.9+
- Apple Silicon（arm64）

### 编译

```bash
# 仅编译
swift build -c release --arch arm64 --product AhaKeyConfig

# 编译 + 打包 .app bundle（含图标生成、代码签名）
bash scripts/build.sh

# 编译 + 安装到 /Applications
INSTALL_TO_APPLICATIONS=1 bash scripts/build.sh

# 编译 + 安装 + 启动
INSTALL_TO_APPLICATIONS=1 LAUNCH_AFTER_INSTALL=1 bash scripts/build.sh
```

也可以用 Makefile：

```bash
make build    # 等同 bash scripts/build.sh
make install  # 等同 INSTALL_TO_APPLICATIONS=1 LAUNCH_AFTER_INSTALL=1 bash scripts/build.sh
```

### 代码签名

`scripts/build.sh` 会自动查找本机的 Developer ID Application 或 Apple Development 证书。如需指定：

```bash
SIGNING_IDENTITY="你的签名身份" bash scripts/build.sh
```

**重要**：当前 bundle ID 是 `lab.jawa.ahakeyconfig`，你们需要改成自己的（搜索替换即可，出现在 `Package.swift` 的 product name 不需要改，主要改 `scripts/build.sh` 里的 `APP_IDENTIFIER` 和源码里的 Logger subsystem）。

### 蓝牙权限

App 需要 Bluetooth entitlement 才能使用 CoreBluetooth：

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

`scripts/build.sh` 会自动生成 entitlements 文件并签名。如果用 Xcode 打开项目，需要在 Signing & Capabilities 里手动添加 Bluetooth。

---

## 项目结构

```
ahakeyconfig/
├── Package.swift                          # SPM 包定义，两个 target
├── Makefile                               # 快捷构建命令
├── scripts/
│   ├── build.sh                           # 完整构建脚本（编译+打包+签名+安装）
│   ├── ahakey-state.sh                    # Claude hooks 用的 LED 状态同步脚本
│   └── generate_icons.swift               # 程序化生成 app icon
├── Sources/
│   ├── AhaKeyConfigApp.swift              # App 入口，单实例控制
│   ├── BLE/
│   │   ├── AhaKeyProtocol.swift           # ★ 协议编解码（帧格式、命令、HID 键码表）
│   │   └── AhaKeyBLEManager.swift         # ★ CoreBluetooth 通信管理器
│   ├── Views/
│   │   ├── ContentView.swift              # Tab 容器
│   │   ├── DeviceInfoView.swift           # 设备信息 + LED 测试 + BLE 日志
│   │   ├── KeyMappingView.swift           # 键位映射配置 + 预设方案
│   │   └── OLEDManagerView.swift          # OLED 图片/GIF 管理
│   ├── Utilities/
│   │   └── AgentManager.swift             # LaunchAgent 守护进程管理 + Claude hooks 安装
│   └── Agent/
│       ├── AhaKeyAgent.swift              # 轻量 BLE 守护进程（Unix socket 接收状态命令）
│       └── main.swift                     # Agent 入口
├── docs/
│   └── ble-protocol.md                    # ★ 完整 BLE 协议文档
└── .gitignore
```

### 重点文件

| 文件 | 说明 |
|------|------|
| `Sources/BLE/AhaKeyProtocol.swift` | 你们的协议完整实现——帧编解码、所有 DeviceCmd、HID 键码表、响应解析 |
| `Sources/BLE/AhaKeyBLEManager.swift` | 直接 CoreBluetooth 通信，自动扫描/连接/重连，写入队列防过载 |
| `docs/ble-protocol.md` | 协议完整文档（从原厂工具反编译 + 抓包验证） |
| `Sources/Agent/AhaKeyAgent.swift` | 后台守护进程，通过 Unix socket 接收 LED 状态命令 |
| `Sources/Utilities/AgentManager.swift` | Claude Code hooks 自动安装/卸载（追加模式，不覆盖已有 hooks） |

---

## 架构说明

### 与原厂工具的对比

```
原厂:  Python (PySide6) ←TCP→ .NET (BleTcpBridge) ←stdin/stdout→ Swift (ble_helper)
本项目: Swift (SwiftUI + CoreBluetooth) ──BLE──> 键盘
```

省掉了 TCP 桥接层，连接更稳定，延迟更低，部署更简单（单个 .app）。

### 双进程架构

1. **AhaKeyConfig**（主进程）：SwiftUI GUI，键位配置、设备管理、OLED 管理
2. **ahakeyconfig-agent**（守护进程）：无 UI，LaunchAgent 管理，维持 BLE 连接 + 接收 Unix socket 命令

守护进程的存在是为了在 GUI 关闭后仍能接收 Claude Code hooks 的 LED 状态推送。

### LED 状态同步流程

```
Claude Code hook → ahakey-state.sh → Unix socket → ahakeyconfig-agent → BLE 0x90 → 键盘 LED
```

---

## 已知限制 / TODO

1. **OLED 图片上传**：协议已文档化（见 `ble-protocol.md` 第 8 节），UI 已有，但分包上传逻辑未实现
2. **宏录入 UI**：协议支持宏（sub_type 0x74），但 UI 只做了快捷键映射
3. **多模式切换**：代码支持 3 种工作模式（mode 0/1/2），但 UI 目前只操作 mode 0
4. **拨杆联动**：原厂的拨杆→自动授权功能未移植（需要在 PermissionRequest hook 中查询 SwitchState）

---

## 许可说明

本项目无偿共享，欢迎自由使用、修改、集成到你们的官方工具中。无需署名，无附加条件。

协议文档 (`docs/ble-protocol.md`) 基于原厂工具反编译整理，版权归原始作者所有。

如有问题欢迎随时沟通。
