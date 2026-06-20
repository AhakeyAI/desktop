# Status

## 当前状态

- 仓库已收敛为多平台 monorepo,各客户端独立目录(`ahakeyconfig-*`)。
- **macOS**(`ahakeyconfig-mac/`)为主力开发方向:BLE、voice agent、拨杆审批 AI hook、工作台 UI。
- **Windows** 提供 Java(`ahakeyconfig-win-java/`)与 Python(`ahakeyconfig-win-python/`,Capswriter 基线)两套客户端。
- **Linux** 客户端(`ahakeyconfig-ubuntu-java/`)已加入。
- 键盘固件(`CH582m_vibe_coding_BLE_keyboard-master/`)与 BLE ↔ TCP 桥接(`BLE_tcp_bridge/`)源码随仓库提供。

## 当前未导入

- 云端后端服务
- 安装包与打包产物(`.app` / `.dmg` / `.exe` / `.msi`)
- 预编译二进制、私钥、本地配置

## 备注

- 构建产物不应入库(含 `.class` / `.o`，以及 `*/target/` 等构建目录),安装包统一走 GitHub Releases。
- 各平台保持独立目录,不共享工程结构。
