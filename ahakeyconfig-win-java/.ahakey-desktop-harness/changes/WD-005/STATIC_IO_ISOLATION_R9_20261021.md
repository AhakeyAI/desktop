# WD-005 revision5 / round9 执行前静态隔离核查

2026-10-21，DIB；在本轮编译及回归之前记录。preflight 已通过。

## 真实 I/O 入口

- BleManager 的 Socket 创建仍在 connect；测试所有 FakeSession 使用 OfflineBleManager，connect 覆写在创建线程/Socket 前抛出 AssertionError。
- USB 发现两处均经 isUsbDevicePresent；OfflineBleManager 覆写只读取内存 usbPresent，不调用 UsbHidTransport.isPresent。
- OfflineBleManager 构造完成前将 usbTransport 替换为 MemoryUsb。其 open/isOpen/close/sendCommand/sendData 全部为内存实现，不调用父类硬件逻辑。
- FakeSession 的 BLE outputStream 为 ByteArrayOutputStream，回包由内存 responder 注入。USB 默认关闭，useUsb 显式启用内存 USB，因此不以 always-open USB 代替 BLE 覆盖。
- 核查 displayconfig 全部 FakeSession 使用点及直接构造：未增加真实 BleManager/Socket/USB 实例执行入口；保留原 sendCommand、lease、reset、补发、TTL、代次及未知 ACK 路径。

## 本轮新增测试

- 反射调用 InspectorPane 实际 runtimeSlotSupport 工厂；同一实际工厂由任务槽内容构造调用。只构造该 Label 与隔离分区，不构造 App 或 StudioController。
- 中英文切换位于临时 user.home 内；不读取或写入真实用户偏好。
- withIsolatedHome 将 Platform.startup 纳入 try/finally；受控注入启动 IOException、初始化 Error、body/退出失败，验证原异常、恢复和清理。
- 清理只遍历 Files.createTempDirectory 所生成目录；不跟随符号链接。保留临时 .openjfx 已加载缓存；不访问真实 user.home 缓存。独立模拟缓存哨兵也只在新临时目录内。
- 无新增网络、设备、Hook 或真实应用初始化。此静态结论不是历史设备写入判断，不是完整应用或真机 PASS。

## 执行范围

授权离线 test-compile（不 clean/package）及八个 displayconfig 隔离检查入口。新原始日志写入 evidence/20261021-wd005-r9；执行结果另记，不以本静态核查代替运行证据。
