# Installation

本仓库是源码仓库，不直接提供安装包。

## 获取安装包

- Windows 与 macOS 安装包统一通过 GitHub Releases 分发。
- 仓库内不提交 `exe`、`msi`、`dmg` 等发布二进制。

## 当前源码构建入口

### Windows desktop-main

- 目录：`platforms/windows/desktop-main/vibe_code_config_tool/`
- 可判断的开发启动方式：
  - `pip install -r requirements.txt`
  - `python main.py`
- 可判断的打包入口：
  - `KeyboardConfig_onedir.spec`
  - `KeyboardConfig.spec`

### Windows ble-bridge

- 目录：`platforms/windows/ble-bridge/BLE_tcp_bridge_for_vibe_code/`
- 可判断的构建方式：
  - 使用 Visual Studio 打开 `BLE_tcp_driver.sln`
  - 或基于 `BLE_tcp_driver.csproj` 走 .NET Framework 4.7.2 构建

### Windows hook-installer

- 目录：`platforms/windows/hook-installer/vibe_code_hook/`
- 可判断的运行方式：
  - `python hook_install.py`
  - `python install_hook.py`
  - `python install_cursor_hook.py`
- 可判断的打包入口：
  - `hook_install.spec`

### Windows speech

- 目录：`platforms/windows/speech/Capswriter/`
- 可判断的开发启动方式：
  - `pip install -r requirements.txt`
  - `python start_server.py`
  - `python start_client.py`
- 可判断的打包入口：
  - `build.spec`

### macOS client

- 目录：`ahakeyconfig-mac/`
- 当前可判断的环境要求：
  - macOS 15.0+
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

## 历史打包脚本说明

- `platforms/windows/scripts/inno-setup/` 中保留了历史 Inno Setup 脚本和语言文件。
- 这些文件当前只作为迁移留档与后续整理输入，不应视为“拿来即可复用”的正式构建入口。
