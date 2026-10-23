# R8 执行前静态隔离清单

2026-10-21，DIB；在本轮编译和回归执行之前保存。

- 正式preflight已PASS；revision5/round8，本轮合同允许离线编译和隔离测试，不允许打包或启动真实应用。
- 全部displayconfig测试的BleManager构造仍使用OfflineBleManager；唯一super构造不连接设备，返回前将usbTransport替换为完整MemoryUsb。
- OfflineBleManager阻断connect，USB发现返回受控内存事实，open/isOpen/close/sendCommand/sendData均为内存替身。没有覆写BleManager.sendCommand，没有Socket构造或真实USB发现调用。
- FakeSession输出为内存OutputStream；本轮将人工HEX确认替换为真实0x9F内存响应，保留两条实际发送分支。新增可选择未准入初始化，不伪造quarantine。
- 新增DisplayConfigCapabilityChecks只构造隔离服务、状态、JavaFX节点与生产静态UI装饰函数，不构造App/StudioController，不启动Hook/桥接。只读反射调用会话收包、reset与UI辅助函数。
- C01覆盖精确合法/空/旧显示/未来/控制字符/尾随垃圾/实际超时；C02覆盖USB及BLE旧代次收包与延迟FX票据；C03使用真实requireDisplayRecovery保持未知ACK保护；C04保留0x90；C05/C06检查分区操作禁用、标题原因可读与草稿；C07重跑既有隔离回归。
- 文件写入限临时测试目录、target编译产物及本轮evidence。新用例临时user.home在finally恢复，只清理其自身创建的临时目录。
- 原隔离/TTL/会话/租约测试未降低判定；旧507项不计为本轮执行。实际完整Inspector、输入设备交互、高DPI及USB/BLE真实设备均待Owner Preview。

此清单是执行前调用链审查，不是历史测试曾写设备的证据，也不是本轮回归PASS。后续日志如失败应原样保留。
