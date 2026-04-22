# Architecture

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

## 当前边界

- `wxcloudrun-flask-main/` 为云端后端，不在本仓库中。
- `shared/` 暂未抽出独立共享源码，第一轮只保留占位说明。
