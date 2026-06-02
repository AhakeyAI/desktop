# Status

## 当前状态

- 已按平台策略建立统一 desktop baseline 目录结构。
- Windows 源码已保留在 `platforms/windows/`。
- macOS 客户端源码已迁入 `platforms/macos/client/`。
- 当前仓库现在同时承载 Windows + macOS 两个平台的桌面端源码入口。

## 当前未导入

- `wxcloudrun-flask-main/` 云端后端
- 安装包和打包目录
- 预编译 DLL、私钥、本地配置

## macOS 当前备注

- 本轮只做结构迁移、必要忽略和文档更新，不改业务逻辑。
- macOS 仍处于迁移后的早期整理阶段。
- 后续仍需单独处理 bundle id 清理、构建收敛和发布规范化。
