# WD-005 revision4 / round7 执行前静态 I/O 清单

日期2026-10-20，DIB。在本文件保存前没有执行本轮编译或测试。依据当前 effective approval、R6_ISOLATION_INTERFACE_PROPOSAL 与 Owner 窄授权；preflight已退出0/PASS。

## 输入与范围

修前 fingerprint 为 1fca9345199cd1166acd8b4df7125d3e17f1cad4032c7736dc1060361a2d3ccf，完整列表保存 evidence/20261020-wd005-r7/before.json。
生产唯一新增改动为 BleManager 的 protected isUsbDevicePresent 默认包装与两处调用替换；默认静态调用、控制流顺序、锁、连接代次、TTL、ACK不变。R4三项修复原样保留。

## 入口封闭

| 入口 | 静态检查结论 |
| --- | --- |
| BleManager 构造 | 原构造器只设置host/port/callback及字段，无线程/连接/枚举。所有displayconfig直接构造均改为final OfflineBleManager；它在返回前反射安装MemoryUsb，失败则构造抛出，不返回未隔离实例。 |
| USB发现 | tryConnectUsb/ensureUsbConnected均走实例入口。OfflineBleManager覆盖且不调用super，只返回内存usbPresent并计数。默认false；模拟存在为true，完全不查询物理USB。 |
| USB对象 | MemoryUsb为final测试类，覆盖open/isOpen/sendCommand/sendData/close，均不调用super。无原生句柄、reader线程或设备路径；数据和命令仅存内存并回调测试ACK。基类构造没有原生I/O。 |
| TCP连接 | 唯一new Socket/socket.connect位于生产connect线程；测试final子类覆盖public connect，在创建线程前抛AssertionError。测试无fromEnvironment或基类connect调用。 |
| BLE输出 | FakeSession只安装ByteArrayOutputStream或受控IOException OutputStream；不创建Socket，不安装真实inputStream/readerThread。生产writePacket及BLE封包保持执行。 |
| lease关闭/补发 | 不覆盖sendCommand/sendRuntimeState/flush/exchangeDisplay/reset。释放lease后发现入口仍分派到测试子类；USB替身/发现策略不随reset重建，生产reset清理语义保持。 |
| reconnect/disconnect | connect永远拒绝；私有tryConnectUsb仅由新增用例反射调用，发现与open均为内存替身。真实disconnect只关闭替身/内存流，socket和reader均null。 |
| 解析 | 原直接new BleManager解析用例统一OfflineBleManager。USB extractFrame仍反射真实纯解帧函数，不调用原生枚举/收发。 |
| 未知ACK | 删除A10中仅为固定TCP写入的displayReadUncertain=true。真实超时/恢复用例仍通过被测API建立隔离；新用例确认默认和reset后无伪造quarantine。 |

## 所有调用者

- DisplayConfigChecks：全部解析构造与FakeSession统一隔离；A10释放lease不再伪造readUncertain。
- DisplayConfigFxChecks：沿用共享FakeSession，覆盖真实服务和局部FX，不构造App/StudioController。
- DisplayConfigRaceChecks：共享夹具，用useUsb开启完整内存USB；反射读取基类字段适配测试子类。
- DisplayConfigRevision3Checks：BLE保持关闭USB与内存TCP；USB通过useUsb。无其他半实现USB替身。
- DisplayConfigRound5Checks：同一共享夹具，受控TCP IOException不被USB截走；反射字段明确取BleManager。
- DisplayConfigIsolationChecks：所有发送均来自共享夹具，模拟发现true/false、connect失败关闭、lease/reset/迟到ACK，以及匿名自身终态pending；不调用真实设备探测。
- DisplayConfigRevision3UiChecks、DisplayConfigEncodingProbe：无传输构造，局部UI/编码探针；本轮不启动真实应用或Hook。

已静态检查测试目录没有直接new BleManager、new UsbHidTransport、静态isPresent、Socket或fromEnvironment调用。connect唯一调用为阻断探针。测试线程仅为受控服务/FX/竞态，不启设备连接线程；原生USB的五个可达实例方法全部被替代。

此清单支持开始授权离线编译/隔离回归，不等于测试PASS、独立审阅或硬件验收。不会运行修前不安全夹具作红测试；历史443项不证明硬件隔离，也不推断历史发生过设备写入。本轮结果另记独立报告及日志。
