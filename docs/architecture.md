# Architecture

## 平台拆分原则

- `desktop` 作为统一官方 desktop baseline，按平台组织源码，而不是把不同技术栈混在同一目录。
- Windows 与 macOS 分别保留各自的运行时、UI 结构、系统集成方式和构建链路。
- 当前平台入口分别为 `platforms/windows/` 和 `platforms/macos/client/`。

## Windows 组件关系

- `desktop-main`
  - 用户侧主桌面程序
  - 负责设备配置、账号订阅交互、调用本地语音服务
- `ble-bridge`
  - 负责 BLE 与 TCP 之间的桥接
  - 供主客户端通过 TCP 与设备交互
- `hook-installer`
  - 负责 Claude / Cursor hooks 的安装、分发与状态桥接脚本
- `speech`
  - 负责本地语音输入、转写与相关客户端 / 服务端逻辑

## macOS 组件关系

- `client`
  - Swift / SwiftUI 原生 macOS 客户端
  - 负责设备配置、BLE 通信、OLED 资源、界面和本机脚本
- `client/Sources/Agent`
  - macOS 后台守护进程源码
  - 负责维持 BLE 连接与接收本地状态命令
- `client/Resources`
  - macOS 客户端运行所需资源文件
- `client/scripts`
  - macOS 构建、签名、DMG 打包相关脚本

## 当前边界

- `wxcloudrun-flask-main/` 为云端后端，不在本仓库中。
- `shared/` 暂未抽出独立共享源码，第一轮只保留占位说明。
- macOS 客户端源码已迁入 `platforms/macos/client/`，但未与 Windows 工程合并，也不共享目录结构。
