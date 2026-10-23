# WD-005 BLE 上传链路调研与优化建议

日期：2026-10-18。角色：Windows DLA。性质：只读调查后的方案，不是实现批准、根因实测闭环、构建或验收。

Owner 最新要求：调研瓶颈，区分上位机、桥接、固件责任，暂不改代码。本轮仅追加本记录；没有修改生产/测试/固件/桥接代码或 Harness 路由，没有构建、运行应用、安装 Hook、发送设备命令、烧录或 Git 写入。

## 1. 输入身份和证据边界

- Windows 实际测试输入：Preview `preview-20261017T104547091113Z-0e6fcf` 的冻结源码、runtime-jar-classpath 日志。
- 日志：`.ahakey-desktop-harness/previews/WD-005/preview-20261017T104547091113Z-0e6fcf/runtime-jar-classpath/logs/ahakey-studio.log`。
- 桥接只读源码：`C:/Users/20825/Desktop/windows软件代码/desktop/BLE_tcp_bridge`。
- 本地驱动文件：`../BLE_tcp_driver_package/BLE_tcp_driver.exe`，52736 字节，文件/产品版本均为 1.0.0.0，SHA256 `9B8F8C9D18AE7EE93B71ED7C867E1CE1E60040EBC6832498F5F2D00DCBD6106E`。
- 该哈希仅标识读到的文件，不能证明现场进程加载此文件，更不能证明其与桥接源码同一次构建。后续需绑定实际驱动路径和构建来源。
- 固件源码只读来源：`C:/Users/20825/Desktop/vibe-code`。已有 Owner 配对 HEX 确认不等于当前工作区所有代码均在设备内；下述固件结论是源码结论，细分耗时尚无现场探针。
- 全局 STATE 仍为 WD-005 IMPLEMENT/PREVIEW_FIX/next_actor DIB。本轮按 Owner 最新要求只调查，没有恢复被暂停的代码修改，也不改变路由。

## 2. 已经量化的事实

本次 BLE 上传 Begin 成功至 Commit 成功：16:00:57.500 至 16:04:39.260，共 221.760 秒。收到 598 个成功的 0x8B ACK，最后 0x8C 成功。没有把此前 USB 超时混入这笔事务。

- 单帧固定 28672 字节；160 x 80 x RGB565 为 25600 字节，其余 3072 字节是帧槽填充。
- 每包最多 48 字节有效数据，需要 ceil(28672/48)=598 包；满载命令总长 59 字节。
- 597 个相邻 chunk ACK 间隔：平均 370.248ms，中位数 360ms，P95 407ms，最小 271ms，最大 585ms。
- 从 Begin/chunk ACK 日志到下一次 chunk 发送日志，共 598 对：总计 207ms，平均 0.346ms，最大 2ms。日志时间不是底层发包探针，但不支持“Java 每包主动等待几百毫秒”的判断。
- 有效吞吐约 129 字节/秒。若相同吞吐持续，多帧时长大致随帧数增加，8 帧约半小时；这是外推，不是 GIF 实测。

## 3. 调用链和瓶颈候选

### Windows Java

冻结 `service/OledUploadService.java:27`：Begin -> 逐个 chunk 等应用 ACK -> Commit。`BleManager.exchangeDisplay` 持有上传租约，等待回复，不存在已观察到的每包固定 360ms sleep；TCP 客户端设置了 TcpNoDelay。

stop-and-wait 是当前协议安全边界，不应直接删除。ACK 仅有 opcode/status，没有事务号或 offset；并发发送多个 chunk 后无法可靠区分迟到 ACK，也不能假定重传幂等。

日志中存在 status-poller / Hook 查询。TCP type 3/4 查询桥接状态或缓存，不等于每次都走 BLE；type 2 的 5 字节设备查询才占用实际命令通路。其增量影响尚未量化，不能称为主要根因。

### BLE 桥接

- `TcpServer.cs:176` 将 WriteCommand 固定按 20 字节切片；59 字节命令产生 20+20+19 三次 GATT 写入。
- `Program.cs:280` 使用 WriteWithResponse；调用者不 await 每片完成，没有明确的跨客户端有界帧发送队列。系统内部可能排队，不能据此宣称无线同时并发。
- `AsyncStatus.Completed` 分支取 GattCommunicationStatus 后无论成功与否均触发 WriteDataSuccess；Error/Canceled 没有相应失败回传。属于可靠性问题，不是本次耗时占比已证实的原因。
- `TcpServer.cs:267` 写回 TCP；源码未看到桥接端 NoDelay 和统一的 per-client 写串行化。这是可检查的次要项，不把其当成 360ms 的既定解释。
- 工程目标为 .NET Framework 4.7.2；不能未经适配直接引入 Windows 11 新 API 并破坏旧系统。

### 固件

- `command_solve.c:58` 的资源写入调用 `W25QXX_Write`。
- `w25qxx.c:269` 每次先读整个 4096 字节扇区；只要目标小段存在非 0xFF 字节，就擦除该扇区，修改小段，然后重写整个扇区。其余旧内容被保留，所以下一小段仍可能再次触发同一扇区擦写。
- `resource_upload_begin` 只先持久化 WRITING 元数据，没有为整个上传区预擦除。因此覆盖已有资源时，48 字节小包与通用读改写组合会产生明显写放大；空白扇区仍有逐包整扇区读取成本。
- 598 个 chunk 覆盖 7 个扇区，不意味着目前只擦 7 次；实际次数取决于已有字节。不能从代码估计值冒称现场擦除次数或耗时。
- 命令由 `MCT_COMMAND_TODO` 事件触发执行，未见这一路固定 360ms 定时调度。Flash busy wait 同步占用执行时间，需测对 BLE 调度及键盘输入的影响。
- `hidkbd.h:55` 请求 interval 24..40 (30..50ms)、slave latency 4。这不是实际协商结果，也不能把 latency 4 等同于每次必等 5 个 interval。
- `gattprofile.c:103` 命令特征仅声明 GATT_PROP_WRITE。当前不能把桥接单方面改成 WriteWithoutResponse。
- 命令特征声明最大 200 字节；写回调拒绝非零 offset，不能依赖 Windows 自动 GATT long write 替代已验证的普通分片。
- 固件命令组帧缓冲为 256 字节；资源 chunk 最大 48 字节是显式校验。提高 MTU 不会自动提高资源 chunk 上限。
- 通知发送失败会返回，当前代码未提供这一路明确的 ACK 排队重试。优化吞吐时需避免把缓冲耗尽变成 ACK 丢失；本次成功日志不证明发生过此问题。

## 4. 推荐实施顺序与责任

### 第一阶段：三端可关联计时，先保留协议

经范围批准后，由各端分别增加最小诊断；不要先改传输行为再猜改善来源。

- Windows：记录事务/entry/offset、本地单调时钟的发包到 ACK 耗时、字节进度；统计真正下发设备的非上传命令数。
- 桥接：记录实际 exe 身份、连接代次、协商 MTU、每片入队/开始/GATT 完成、结果码、固件通知接收和 TCP 回传；不将 GATT 完成当作资源提交成功。
- 固件：诊断计数或可控摘要记录组帧到执行、Flash 读取/擦除/编程耗时和次数、ACK 提交结果，以及实际 interval/latency。考虑固件空间预算，禁止在每字节高频打印造成新的瓶颈。
- 三端时钟不直接相减；分别测本地阶段时长，以连接代次、事务和 offset 关联。
- 对照同一图片的空白目标/覆盖已有目标、USB/BLE、固定版本各重复多次。若覆盖明显更慢且 Flash 耗时高，确认写放大贡献；若空白也慢且 GATT 时间占优，优先桥接/连接参数。

### 第二阶段：不改变 0x8A/0x8B/0x8C 语义的最小优化

**固件负责：事务专用 Flash 顺序写入。** WRITING 元数据成功持久化后，仅对该资源有效范围按扇区首次到达时擦除一次，再按页边界编程。不要每 48 字节走通用整扇区读改写，也不要直接全局修改通用 W25QXX_Write 影响按键等存储。检查扇区边界、连接失效、写入失败、超时与 INVALID 恢复；ACK 时机不得早于对应数据安全写入。按需擦除优于把大量 GIF 擦除集中在 Begin，避免新增长阻塞；如仍长阻塞需拆分状态机。保持 CRC、精确 offset、WRITING/VALID/INVALID、断连隔离和原资源区域界限。

**桥接负责：有界顺序传输和按实际 MTU 分片。** 每个连接只有一条受控发送队列，同一完整命令的分片不能被其他 TCP 客户端插入；await 每次写结果并处理错误/断连。分片上限取实际 MTU-3、特征限制和已验证接收上限的最小值。若 MTU>=62，59 字节 CP2 命令可用一次普通写；若仍是 23，则回退 20 字节，不能硬发 59 或指望 long write。队列是正确性修复，不承诺它单独提速。

**桥接与固件配合：仅上传期间使用吞吐连接参数，结束/失败/断开后恢复。** Windows 11 可评估 ThroughputOptimized；Windows 10 保留兼容路径。固件配合 MTU/连接参数支持，读取实际协商结果。不要永久提高耗电或挤占其他蓝牙设备。判断是否需要新的桥接上传生命周期消息，若需要则作为显式协议范围协调。

**Windows 负责：上传调度和可观察进度。** 保留设备状态变化、断连侦测与租约隔离；暂停/合并非必要设备查询，不关闭所有状态感知。显示已确认进度、耗时、近期吞吐估计；区分传输结束和 Commit 成功。保留未知 ACK 隔离与最新 CP1 事实补发，不以盲目重试掩盖故障。无需因 MTU 优化改 48 字节资源协议。

### 第三阶段：只有仍不达标才改协议

- 较大 chunk、窗口/批量 ACK：固件先定义能力协商、事务 ID、序号/offset、去重、重传和断连恢复，再由 Windows/桥接适配。保留旧固件及 USB 64 字节报告兼容，不强行共用更大的 USB 包。
- 无响应写不能单端启用，需要特征属性、接收流控、缓冲和应用层确认配套。
- 压缩可评估流式 RLE 等，但必须版本化压缩类型、压缩/解压后长度、边界和 CRC；必须考虑 RAM/Flash 空间。对噪声图压缩可能无收益或变大，需原始格式回退。
- 直接压小 PNG/GIF 文件不会变小当前固定 RGB565 上传流。去掉 3072 字节填充也最多减少约 10.7%，还需要更改接收长度/补齐约定，不能解决分钟级根因。
- 不绕过 CP2 事务切回旧 0x84/0x85 或 raw 0x7341 写入路径。

## 5. 验收与不变项

先分端 A/B，再合并；禁止三端同时大改后仅凭一次上传成功归因。

- 性能：同图、同硬件、同连接条件，空白/覆盖分别统计总耗时、P50/P95、有效 B/s、GATT 次数、擦除次数；再测 8 帧默认资源与 12 帧状态资源。当前不能承诺具体倍数。
- 正确性：CRC/长度/offset、重复点击、过程中断连/重连、ACK 丢失与迟到、失败无假成功；屏幕最终资源由 Owner 实际确认。
- 兼容：USB、原 BLE 普通配置、模式/版本/睡眠读取、按键/拨杆/Voice、SINGLE/MULTI 最新事实补发、输入响应，以及其他蓝牙外设共存。
- 不变：资源布局、提交持久化语义、设备身份门禁、WS001-004 已接受行为，不拿性能优化扩大到 CP1.5。
- Windows 调度/UI 可归类原问题修复；桥接新增范围、固件改动与任何协议扩展均需分别明确责任/范围，不能借 WD-005 的 Java allowed_paths 自动获得跨仓实现权限。

## 6. 官方资料

- Microsoft GattSession.MaxPduSize：实际 MTU 是只读属性，可监听变化；OS 自动分片描述仍受对端 GATT/ATT 支持约束。https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.genericattributeprofile.gattsession.maxpdusize
- Microsoft RequestPreferredConnectionParameters：Windows 11 build 22000 起提供，吞吐模式会影响可并发的其他蓝牙连接，使用结束应恢复。https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.bluetoothledevice.requestpreferredconnectionparameters

结论：确定慢在大量串行小包的下游往返，不是 Java 已观察到的主动等待；桥接固定 20 字节切片和固件小包通用 Flash 读改写均有明确优化依据，但现场各自贡献未分解。推荐先诊断并改善这两处，保留现有 CP2 协议；协议批量化和压缩留作有数据支撑的后续选择。
