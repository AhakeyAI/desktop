# Repo Layout

## 顶层原则

- 顶层 `docs/` 只放仓库级共享文档。
- 代码按平台拆分，而不是按工具拆顶层。
- 当前只导入 Windows。
- 安装包不进仓库，发布走 GitHub Releases。

## 当前目录说明

- `docs/`
  - 仓库级说明、安装、发布与布局文档
- `platforms/windows/`
  - Windows 相关代码与说明
- `assets/`
  - 预留给仓库级共享资源
- `scripts/`
  - 预留给仓库级共享脚本
- `releases/`
  - 预留给发布说明，不保存二进制

## Windows 子目录说明

- `desktop-main/`
  - Windows 主桌面客户端源码
- `ble-bridge/`
  - BLE 与 TCP 之间的桥接程序源码
- `hook-installer/`
  - Claude / Cursor hook 安装与分发相关源码
- `speech/`
  - Windows 本地语音输入 / 转写相关源码
- `shared/`
  - 预留给 Windows 共享代码，当前仅 README 占位
- `scripts/`
  - Windows 专属构建 / 打包脚本，当前保留历史 Inno Setup 脚本
