# mac_bridge Build

该目录是当前 macOS 发布使用的 BLE-TCP 桥接实现。

技术路线：

- `.NET 8` TCP 服务
- `Swift CoreBluetooth helper`
- 最终输出 `BLETcpBridge.app`

## 构建依赖

- `dotnet` SDK 8
- `swiftc`（Xcode Command Line Tools）

## 直接构建

```bash
cd mac_bridge
chmod +x build_app.sh
./build_app.sh
```

输出：

- `mac_bridge/dist/BLETcpBridge.app`

## 运行说明

双击 `BLETcpBridge.app` 后会拉起一个 Terminal 窗口显示运行日志。

桥接器二进制和 BLE helper 都在应用包内：

- `Contents/Resources/bridge/BleTcpBridge`
- `Contents/Resources/bridge/ble_helper`
