# WD-005 蓝牙单帧上传耗时观察

日期：2026-10-18。Owner 要求暂停修改、先测蓝牙；本轮只读调查并追加证据，不修改生产/驱动/固件代码、不构建、不启动或停止进程、不发送设备命令。

## 现场与结果

Owner 反馈蓝牙上传一张图片耗时很久、尚未完成。实际 Preview 日志为：
.ahakey-desktop-harness/previews/WD-005/preview-20261017T104547091113Z-0e6fcf/runtime-jar-classpath/logs/ahakey-studio.log。

读取时实际连接是 ble-tcp-reader / TCP BLE 桥接链路，设备 AhaKey 645E；不是将 USB 日志当蓝牙证据。

- 16:00:57.500：Begin 成功响应 AA BB 8A 00 CC DD。
- 16:04:16.759：累计 538 个 chunk 成功响应，约 90%，仍在继续传输，无该事务 FAIL 日志。
- 16:04:38.945：第 598 个 chunk 成功响应。
- 16:04:39.260：Commit 成功响应 AA BB 8C 00 CC DD。
- Begin 成功至 Commit 成功约 221.760 秒，即 3 分 41.76 秒。此区间不含导入、用户确认及 Begin 请求等待。

上传目标本地记录为 entry 5 / Mode 2 SINGLE 工作中，1 帧，28672 字节成品；上传中读取到 inFlight=true。不以旧 device 字段冒充新上传已经完成，最终提交结果以 0x8C ACK 为准。

## 代码与吞吐分析

冻结 Preview OledUploadService 每包最多 48 字节，发送后等待协议 ACK 才发下一包；一帧 28672 字节需要 ceil(28672/48)=598 包。观察到典型成功 ACK 间隔约 0.36-0.45 秒，整次有效载荷吞吐约 129 字节/秒。

同级只读 BLE_tcp_bridge/TcpServer.cs 的 WriteCommand 将完整命令按 20 字节拆分；Program.cs 使用 GattWriteOption.WriteWithResponse。满载 CP2 chunk 的协议帧 59 字节因而对应 3 次 GATT 写入，再加固件应用层 ACK。这能解释该链路存在明显的逐包往返成本，但尚未验证这个源码与 Owner 正在运行的 BLE_tcp_driver.exe 的构建身份，不将它写成二进制已证实根因。

期间 status-poller 与 Hook 状态查询仍有流量。未做受控对照，不能量化各项对耗时的贡献，不能将全部延迟归责 Windows、驱动或固件任一侧。

## 分类与后续

- BLE-PERF-01：蓝牙单张静态图片上传约 3 分 42 秒，性能/进度体验问题，OPEN。
- 本次事务结果：协议提交成功；并非前面 USB 上传超时故障的直接复现。
- 不等于 Owner 已确认物理屏幕内容、蓝牙全部功能或正式 UAT 通过。
- 后续优化需先量测驱动分片/GATT确认/固件ACK/连接参数成本，再决定最小改动；不能直接增大固件不支持的 chunk、并发流水发送、跳过 ACK、切回旧 raw-write 或自动重发来伪造提速。
- 若需修改同级 BLE_tcp_bridge 或固件，须另行协调范围，Windows DIB 不因性能反馈自动获准改这些目录。
- 建议下一轮进度体验显示真实已确认进度与耗时，避免正常缓慢传输看似卡住；新增 UI 细节仍需遵守现有交互约束。

继续尊重 Owner 最新“先等一下再改、先测蓝牙”的要求；此前修复范围准备未构成生产修改或新构建。
