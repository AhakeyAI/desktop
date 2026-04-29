# Windows

安装与发布入口说明见：`docs/installation.md`。

## 这个目录是什么

Windows 平台源码的汇总入口。

## 当前包含什么

- `desktop-main/`：主桌面客户端源码
- `ble-bridge/`：BLE bridge 源码
- `hook-installer/`：Claude / Cursor hook 相关源码
- `speech/`：Windows 本地语音相关源码
- `shared/`：共享代码占位目录
- `scripts/`：Windows 历史构建 / 打包脚本

## 当前不包含什么

- macOS 源码
- 云端后端源码
- 安装包二进制
- 本地配置与私钥

## 如何构建

按子目录分别构建，不存在一个已经确认可直接复用的统一总构建入口。

### 模块 README 入口

- `desktop-main/README.md`
- `ble-bridge/README.md`
- `hook-installer/README.md`
- `speech/README.md`

## GitHub Releases 对应发布物

Windows 安装包和各组件发布产物未来统一通过 GitHub Releases 分发，不保存在本目录中。
