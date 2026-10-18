# WD-005 外部协作工单与回收要求

日期：2026-10-18。此页随Windows修订批准，登记外部依赖，不授予Windows DIB跨仓写权限，不冒充桥接/固件本地已登记任务。

## 共同事实

Owner已授权本轮汇总问题和BLE上传性能一起走Harness修复。Windows正式范围为PREVIEW_FIX_CONTRACT_R3_20261018.md。
调查：C:/Users/20825/Desktop/windows软件代码/desktop/ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261018-wd005-ble-chain-research-plan.md。
原始事件：同目录evidence/20261018-wd005-multi-slot4-and-primary-selection.md、20261018-wd005-default-upload-retry-owner-feedback.md、20261018-wd005-single-runtime-after-upload-timeout.md。

基线为Preview preview-20261017T104547091113Z-0e6fcf；一帧598包、221.760秒，平均ACK间隔370.248ms。驱动源码与现场EXE未完成构建对应，固件工作区与实际HEX须重新匹配；不能只按同名路径认定同一输入。

## BRIDGE-01：BLE桥接

接收：已有BLE桥接开发窗口；若尚无，由Owner另行指定，Windows DLA不自动创建/发送消息。
工作目录：C:/Users/20825/Desktop/windows软件代码/desktop/BLE_tcp_bridge。
邻近打包目录BLE_tcp_driver_package只用于只读身份核验，禁止覆盖现场运行EXE/config_server.json。

先读本工作区及父目录AGENTS/正式规则、现有变更状态；若没有Harness或独立起点/范围记录，先登记任务/边界和构建身份，不能声称Windows approval等于桥接preflight PASS。无需重新询问已确认产品行为。

建议精确范围：TcpServer.cs、Program.cs；只有连接参数生命周期确需接线才纳入Form1.cs；对应无硬件单元测试/诊断文件先在本地合同列明。不默认改csproj目标框架或发布版本。

1. 固定实际EXE身份和源码来源；补事务/帧队列、分片、GATT完成、通知、TCP返回时长和错误码，记录实际MTU和连接代次。
2. 保持现有TCP包类型与完整命令语义；命令帧分片有界、顺序、不可跨客户端交错，断连时取消旧连接队列。TCP回传亦需避免并发帧交错。
3. 根据已验证实际MTU-3/特征上限分片；MTU不足时保留20字节。不能依赖对端拒绝的long write，不能单方WriteWithoutResponse。
4. 正确区分AsyncStatus和GattCommunicationStatus；失败不能触发假成功。桥接不能伪造固件0x8B/0x8C成功ACK，也不能盲目重发导致非幂等问题。若现有TCP协议无法表达传输失败，提出最小版本化扩展交Windows DLA协调，不自行定格式。
5. 可评估Windows11吞吐参数，需API存在性/旧系统回退和生命周期恢复，不默认扩大.NET依赖。需要新增上传开始结束消息时暂停该部分等双方确认；不阻塞队列/诊断独立修复。
6. 现有发现/连接/状态缓存/托盘/退出行为不顺带重构；旧Data通道不得被CP2绕过使用。

只做源代码实现与离线隔离检查，禁止运行桥接连接设备、杀进程、安装、覆盖现场包、Git写入。若需构建诊断包，经本地审阅及明确构建步骤另行交接。
回执必须含实际变更范围、源码身份、GATT行为与协议是否改变、已执行/未执行检查、可复现构建依赖及给Windows需配合的事项。不能承诺未经设备测量的倍数。

## FW-01：固件资源上传与主槽屏幕

接收：已有固件负责人/Lead窗口，工作目录C:/Users/20825/Desktop/vibe-code。
由固件自身Harness确认当前WS3 CP2任务与变更归属，Windows仅提供Owner意图与证据，不覆盖固件起点、报告、Gate、HEX或seal。

建议重点范围：APP/sub_main/command_solve.c、APP/services/resource_upload_transaction.[ch]、APP/services/display_presentation.c；Flash helper、Profile/hiddev.c、hidkbd连接参数等仅经固件Lead登记后按必要最小范围改。

1. UP-01/02：检查Begin失败与Chunk ACK超时的真实原因；记录接收/执行/Flash/通知阶段，保留失败/未知结果，不凭性能问题就认定同一根因。
2. BLE-PERF-01：事务资源区域使用专用顺序写路径，在WRITING元数据落盘后每个覆盖扇区首次到达擦除一次，按页写，避免48字节小包反复4KB读改写。检查物理对齐/区域边界/容量、写入失败、断连/休眠、旧连接身份、CRC及恢复。不能对其他配置写入全局改行为，不取消必要Flash busy/错误检测，不在未写入时提前ACK。
3. 评估Flash同步阻塞对BLE调度/输入影响，必要时用任务状态机分段执行；不能通过大幅延长上位机超时掩盖所有问题。
4. RT-03：明确foreground主槽存在但valid=0时，不回退其他槽的WAITING/RUNNING/DONE；OLED回正常默认/生命周期展示，其余槽灯光照常。有效主槽继续按其状态显示全局MULTI资源。无foreground的legacy场景保留或明确兼容策略；不能擅自改变0x99字段/长度。Quiet/Sleep/安全显示始终优先。
5. 保持0x8A/8B/8C、48字节最大chunk、CRC/offset、19资源布局和8/12帧容量、0x90/98/99/9A及WS001-004既有协议。需要线协议变化立即回双方Lead，不先实施压缩、大包、批量ACK或CP1.5。
6. MTU/上传期间连接参数先记录实际值；不永久耗电模式、不影响键盘/其他蓝牙设备，不拿请求值冒充协商值。通知失败需有可核实处理，不能无界重试或跨连接发旧ACK。

允许所属Harness下的实现与无设备测试；不自动烧录/设备写入/Git写入，不在Windows授权中夹带固件发布。新HEX构建仍走固件本地批准/构建/Gate流程。
回执需含实际代码差异、协议不变声明或明确变更、测试覆盖/剩余风险；有正式产物时附本地可读取Gate/HEX/哈希/来源。Windows DLA自行回收事实，不能要求Owner搬运仓内已有字段。

## 整体闭环

Windows、BRIDGE-01、FW-01分别记录OPEN/已实现/已审阅/已打包/已实测，不互相冒充。先单端受控A/B，再两端或三端组合；同图、空白/覆盖、1/8/12帧、USB/BLE、断连恢复、输入响应和其他蓝牙外设共存。
没有可配对桥接/固件产物时，Windows可完成独立UI/会话身份修复，但BLE性能/RT-03不能关闭。Owner等待中资源测试仍为待测，formal fresh/candidate/UAT保持独立。
