# Installation

本仓库是源码仓库，不直接提供安装包。

## 获取安装包

- Windows 安装包未来通过 GitHub Releases 分发。
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

## 当前未随仓库导入的内容

- `Capswriter` 的预编译 DLL
- 安装器装配目录
- 发布后的 `exe` / `msi`
- 云端后端服务
- macOS 源码

## 历史打包脚本说明

- `platforms/windows/scripts/inno-setup/` 中保留了历史 Inno Setup 脚本和语言文件。
- 这些文件当前只作为迁移留档与后续整理输入，不应视为“拿来即可复用”的正式构建入口。
