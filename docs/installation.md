# Installation

本仓库是源码仓库，不直接提供安装包。

## 获取安装包

- Windows 与 macOS 安装包统一通过 GitHub Releases 分发。
- 仓库内不提交 `exe`、`msi`、`dmg` 等发布二进制。

## 当前源码构建入口

### Windows — Java 客户端

- 目录：`ahakeyconfig-win-java/`
- 技术栈：Java · JavaFX（Maven），入口 `com.example.ahakey.Main`
- 构建：`mvn -q package`
- 打包入口（PowerShell）：`build-exe.ps1` / `build-installer.ps1`

### Windows — Python 客户端（Capswriter 基线）

- 目录：`ahakeyconfig-win-python/`
- 开发启动：
  - `pip install -r requirements.txt`
  - `python main.py`
- 打包入口（PyInstaller）：`KeyboardConfig.spec` / `KeyboardConfig_onedir.spec` / `KeyboardConfig-onefile.spec`
- IDE hook 安装相关在 `hook/`（`hook_install*.spec`）

### Linux — Java 客户端

- 目录：`ahakeyconfig-ubuntu-java/`
- 技术栈：Java · JavaFX（Maven），入口 `com.example.ahakey.Main`
- 构建：`mvn -q package`

### BLE ↔ TCP 桥接

- 目录：`BLE_tcp_bridge/`
- 技术栈：C#（.NET），供非原生客户端通过本地 TCP 与设备交互

### macOS client

- 目录：`ahakeyconfig-mac/`
- 当前可判断的环境要求：
  - macOS 12.0+
  - Xcode 15+ 或等效 Swift toolchain
  - Swift 5.9+
  - Apple Silicon（arm64）
- 当前开发 / 构建入口：
  - 从仓库根目录：`swift build -c release --arch arm64 --product AhaKeyConfig`
  - 或进入 macOS 工程目录：`cd ahakeyconfig-mac && swift build -c release --arch arm64 --product AhaKeyConfig`
  - 完整 `.app` bundle：`cd ahakeyconfig-mac && zsh scripts/build.sh`
- 当前正式打包入口：
  - `cd ahakeyconfig-mac && zsh scripts/package_dmg.sh`
  - `cd ahakeyconfig-mac && zsh scripts/pack-release.sh`
- 说明：
  - `.dmg` 等产物不进入仓库
  - `AhaKeyKeyboardCanvasView` 等模拟键盘/建模 UI 位于 `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
  - 根目录 `Package.swift` 已指向同一套 macOS 源码，避免从仓库根目录构建时遗漏 Studio UI

## 当前未随仓库导入的内容

- `Capswriter` 的预编译 DLL
- 安装器装配目录
- 发布后的 `exe` / `msi`
- 云端后端服务
- 发布后的 `.app` / `.dmg`
- 本地签名证书、私钥、描述文件和其他敏感材料

## Windows 打包脚本

- Windows 安装包脚本在 `ahakeyconfig-win-java/`：`build-exe.ps1`、`build-exe.bat`、`build-installer.ps1`。
- 构建产物不入库，正式安装包统一通过 GitHub Releases 分发。
