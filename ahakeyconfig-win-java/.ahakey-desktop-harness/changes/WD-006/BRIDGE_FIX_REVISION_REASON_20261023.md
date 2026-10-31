# WD-006 revision3：桥接准入阻断修复

继承20261023-wd007-owner-dispatch.md中的用户自动实施/审阅/完整EXE授权。此次是用户已授权更新BLE驱动的必要配套修复，无画质/帧数/协议/产品选择变化，不需要用户再次判断。

原DLA和独立桥接审阅均已确认：F1，新FindService要求BluetoothLEDevice.ConnectionStatus=Connected才调用uncached GetGattServicesAsync，但FromIdAsync不保证建立连接，导致首次/冷重连可被提前return。微软官方来源：https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.bluetoothledevice.fromidasync?view=winrt-22621 。

F2，OnBleNotify只在入口核对generation/discoveryId，随后等待TCP客户端写锁期间若连接代次变化，旧通知仍可发出；状态缓存更新亦需保持身份绑定。需要在真正消费/发送处保留并重新核对身份，避免旧ACK/状态污染重连。

R2禁止编辑桥接输入；此次正式返回CHANGE扩大到受管dependency patch和针对性回归。../BLE_tcp_bridge原文件保持只读、BRIDGE_INPUTS.json保留为不可变base。唯一DIB在Windows仓scripts/ble-driver-fixes.patch保存小范围修复，在隔离源码副本上应用并构建。打包输入身份必须含base文件hash、patch hash、应用后完整源码manifest、新EXE与依赖；不能把base hash冒充patched source。

允许必要冷发现身份/失败判定修正、通知出口与状态缓存身份绑定；保护物理写入的Connected检查、原GATT_WRITE/MTU/队列/ACK/CRC语义。不加TCP消息，不关闭协议确认，不改固件。针对真实逻辑复现冷连接发现启动、迟到通知在发送锁内被挡住、新代次正常通知、状态缓存不继承旧代次；静态接线检查不冒充完整WinRT硬件测试。

原revision2合同及批准已备份contract-revisions/20261023-r2-before-bridge-fix，原起点和旧失败保留。fresh审阅将覆盖base累积diff与本次patch的实际应用后源码。
