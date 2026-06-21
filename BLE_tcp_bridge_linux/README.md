# BLE TCP Bridge for Linux (GUI 版)

使用 BlueZ D-Bus API 连接 BLE 设备，提供 TCP 接口给上位机通信。
对标 Windows 版 BLE_tcp_bridge 的功能和界面。

## 功能特性

- **GUI 界面**: PyQt5 桌面应用，类似 Win 版布局（适配 Ubuntu 20.04）
- **自动扫描**: 启动后自动扫描周围 BLE 设备
- **自动连接**: 发现已保存的 AhaKey 设备后自动连接
- **设备选择**: 下拉列表选择设备，无需手动输入 MAC
- **系统托盘**: 关闭窗口最小化到托盘，后台持续运行
- **TCP 桥接**: 提供 127.0.0.1:9000 接口给 Java 应用连接
- **DEB 包**: 支持打包成 deb 包，一键安装

## 构建 deb 包

```bash
# 进入目录
cd BLE_tcp_bridge_linux

# 构建 deb 包
make

# 安装 deb 包
sudo dpkg -i ahakey-ble-bridge_1.0.0_all.deb

# 修复依赖（如果需要）
sudo apt-get install -f
```

## 安装后使用

1. 在应用程序菜单中找到 **AhaKey BLE Bridge**
2. 点击图标启动程序
3. 程序会自动扫描并连接 AhaKey 设备

## 卸载

```bash
sudo dpkg -r ahakey-ble-bridge
```

## 开发运行

```bash
# 正常启动
python3 bridge_gui.py

# 最小化启动
python3 bridge_gui.py --minimized

# 调试日志
python3 bridge_gui.py --debug
```

## 界面说明

| 组件 | 说明 |
|------|------|
| 设备下拉框 | 显示扫描到的 BLE 设备 |
| 连接按钮 | 手动连接选中的设备 |
| 当前连接设备 | 显示已连接的 AhaKey 设备名 |
| TCP服务 | 显示本机IP、端口和客户端数 |
| 下次最小化启动 | 设置后下次启动自动最小化到托盘 |
| 退出程序 | 完全退出 |
| 日志区 | 显示蓝牙扫描、连接、TCP 通信日志 |

## 首次使用

1. 确保蓝牙适配器已启用：
   ```bash
   sudo systemctl start bluetooth
   ```

2. 启动程序后会自动扫描设备

3. 连接成功后启动 Java 应用：
   ```bash
   java -jar ahakey-studio.jar
   ```

## TCP 协议

与 Windows 版 BLE_tcp_bridge 兼容，包格式：
```
[Type:1字节][Length:2字节小端][Data:N字节]
```

### 客户端 → 服务器

| 类型 | 值 | 说明 |
|------|-----|------|
| WriteData | 0x01 | 写数据到 BLE |
| WriteCommand | 0x02 | 写命令到 BLE |
| QueryBleStatus | 0x03 | 查询 BLE 连接状态 |
| QueryDeviceInfo | 0x04 | 查询设备状态信息 |

### 服务器 → 客户端

| 类型 | 值 | 说明 |
|------|-----|------|
| BleNotify | 0x81 | BLE 通知数据 |
| BleStatusResp | 0x82 | BLE 连接状态响应 |
| DeviceInfoResp | 0x83 | 设备状态信息响应 |

## 配置文件

配置保存在 `~/.config/ahakey/ble_bridge.json`：
```json
{
  "ble_name": "AhaKey XXXX",
  "ble_mac": "DC:04:5A:XX:XX:XX",
  "server_port": 9000,
  "start_minimized": false
}
```

## 文件结构

```
BLE_tcp_bridge_linux/
├── bridge_gui.py          # GUI 主程序
├── ble_bridge.py          # 命令行版本
├── requirements.txt       # Python 依赖
├── Makefile               # 构建脚本
├── README.md              # 说明文档
└── deb_package/           # deb 包结构
    ├── DEBIAN/
    │   ├── control        # 包控制信息
    │   ├── postinst       # 安装后脚本
    │   └── prerm          # 卸载前脚本
    ├── usr/
    │   ├── bin/
    │   │   └── ahakey-ble-bridge  # 启动脚本
    │   ├── share/
    │   │   ├── applications/
    │   │   │   └── ahakey-ble-bridge.desktop  # 桌面入口
    │   │   └── pixmaps/
    │   │       └── ahakey-ble-bridge.svg      # 图标
    └── opt/
        └── ahakey/
            └── ble-bridge/
                └── bridge_gui.py              # 程序文件
```
