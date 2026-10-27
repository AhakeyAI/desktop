# WD-006 R10：原目录软件升级修正（2026-10-25）

本轮生效范围见 `R10_INSTALL_UPGRADE_SCOPE_20261025.md`、`R10_RECONCILE_REASON_20261025.md`。Owner已批准保留原安装目录、减少更新向导、事务失败恢复以及新1.0.11/1.0.12完整本地模型测试包。此段优先于历史安装体验条款；其余R9能力保持。当前实际旧1.0.11在D:\ahakey\，必须覆盖同版手装新起点。官网已由Owner测通，不修改官网。安装/设备真实UAT仍由Owner执行。

# WD-006 — main 模型版最小本地语音适配

## 本轮生效修订：完整更新与 CP2.5 / CP2.6（2026-10-24，R9）

Firmware 只读实现输入固定在 `r9-firmware-snapshot-20261024/MANIFEST.json` 指向的 CP2.6 candidate 精确 Git 字节；依据 `R9_FIRMWARE_REFERENCE_PIN_REASON_20261024.md`。不追随正在实现 WS4 的实时工作树。正式 gate 外部引用及每份协议/源码导出均受当前 approval_assets 校验，后续新固件仍需正式 intake/reconcile。

本段及 `R9_COMPLETE_DELIVERY_SCOPE_20261024.md`、`R9_RECONCILE_REASON_20261024.md` 优先于下文历史范围。Owner 已授权恢复完整实现、必要验证、独立审阅和完整本地模型安装包交付；正式 contract-reconcile 后执行。下文仅 F18 的暂停边界及旧 schema2/证书前置、强制备份恢复、外部 WCH 工具方案被本次明确决定取代，历史原件保留。

绑定 Journey J002/J005/J006/J007/J008/J009/J010；分类 architecture_change、protocol_change、scope_expansion、bug_fix；high_impact。独立设计审阅 `r9-review-20261024/R9_DESIGN_REVIEW.md/json` 为 PARTIAL_BLOCK：已有有效 K1 route 的适配、OTA、随包烧录及 CP2.5 回归可实施；B1 无 route 记录首次配置仍为必须闭合的 Firmware 依赖，不降低完整交付验收。Windows 不得靠四模式重写或旧协议降级绕过失败。详细限制及证据见修订原因。

两包计划为完整本地模型 1.0.11 升级起点及 1.0.12 目标，共用发行公钥与 UpgradeCode；软件两种形态仍共用一个最新版本号。最终交付真实 EXE 与云托管环境变量/完整 OTA 测试方案。实现阶段不自动安装、刷机或部署官网；真实硬件与安装测试保持待 Owner 执行。

## 本轮优先执行边界（2026-10-24，F18 文案）

Owner 明确批准的本轮新增实施仅为带本地语音模型版键码列表中 F18 后增加“（本地语音输入）”，轻量版原样；保留数值、排序、选择/解析/保存及语音行为。不增加向导或自动配置，不构建/安装/设备写入。仅 InspectorPane.java 可作本增量必要显示调整。Journey J007，增量为 UI 文案；累计历史审阅要求保留。依据 evidence/20261024-f18-label-owner-authorization.md 和本目录 F18_LABEL_REVISION_REASON_20261024.md。其余更新与烧录的后续设计/实施继续暂停；下文历史范围用于保留证据，不是本轮恢复工作的授权。

Owner 已批准已合入 main 的模型版方案，范围依据 evidence/20261023-wd006-main-model-owner-approval.md。Journey J007；architecture_change + scope_expansion，high_impact 独立审阅。

仅借鉴 main@a2dae1a 的 ahakeyconfig-win-model-java 语音配置、Sherpa 1.13.3、流式 Paraformer 初始化与识别，来源清单 SOURCE_MANIFEST.json。允许为当前服务接口、正确释放/失败传播、中文安装路径、JNI独立依赖和打包适配做必要修正。不得整包复制，不用 eternal 代码，不纳入模型版 UI、云服务、宏编辑、固件。

allowed_paths 以 change.json 精确列表为准。保留原 App/VoiceInputManager 生命周期接口、现有语音启动入口、F18系统路由、键盘注入时机；不改变 WD-005 OLED/灯光/协议/Hook/会话。现有语音入口与通知反馈沿用，失败要记录原因并显示未启用，JNI UnsatisfiedLinkError 必须捕获。

主线默认配置继续可不带模型运行；model-bundled 隔离包明确开启。模型、API/JNI允许从正式上游取得固定版本并记录SHA，不从eternal取文件。VAD保持关闭，标点非必需，流式中英文Paraformer；未取得真实匹配模型不得伪装成功。

机器检查：JDK17编译；加载缺失/空模型和JNI错误的反馈；生命周期停止/关闭；固定上游WAV真实离线识别及可观察输出；WD-005生产文件字节未变。允许离线合成音频/上游测试WAV，不自动开启用户麦克风或键盘注入。主程序启动若会启动Hook/BLE须先隔离，未经确认不启动旧运行实例。

交付：原WD-005归档不重开。本任务实现后先DLA实际diff及fresh独立审阅；新候选身份另存。EXE打包使用批次隔离输入输出，配置覆盖只在staging发生，禁止clean既有target、kill进程、自动安装/烧录/设备写入。WB-001是原WD-005批次草案，语音新代码不能冒充旧候选，后续新批次/Preview记录必须绑定新代码。

Owner UAT：安装/启动、启用本地语音、F18录音输出和WD-005界面实际体验尚待Owner；离线WAV检查不代替麦克风/硬件测试。恢复方式使用原WD-005归档包与原配置；不删除用户配置。


# Revision 2 生效附录：保真传输及新桥接二进制交付

前文为revision1语音范围；本附录明确扩展旧“不改变WD-005/协议/会话”约束：只允许下列USB/BLE内部服务生命周期配套变化，显示数据/固件协议仍不变。原语音及runtime修复仍须审阅和保留，不将继承代码自动视为PASS。新范围以本附录为准。

## 产品判断与范围

绑定 Journey J005（OLED 本地资源与上传应用），回归 J002（USB/BLE/Mode）与 J007（本地语音）。classification=bug_fix + scope_expansion，review_policy=high_impact。虽不改固件协议，本轮交付此前未出货的桥接写队列/连接代次实现，风险需要新的独立审阅。

已实际查看 StudioController.onConnected/onDisconnected、OledUploadService.uploadResource、BleManager.DisplayLease/queryStatus、KimiAhaKeyBridge、package-local-model.ps1。用户仍在既有 OLED 入口选图/GIF并上传应用；进度仍按固件 ACK 更新，只有提交 ACK_OK 后显示成功。无新增产品选择，无需再次询问画质/帧数/版本形式。

1. 保留 RGB565 160×80、每帧补齐 28672 字节、48 字节资源分包、0x8A/0x8B/0x8C、逐包固件 ACK、CRC、失败隔离/重连对账。不通过压缩本地 PNG/GIF 宣称传输量下降。
2. 对当前 ../BLE_tcp_bridge 的 BRIDGE-01 修复三文件及相关离线测试做本轮累计独立审阅，离线构建确切新二进制，随新 EXE 交付。既有源码使用 GattSession.MaxPduSize-3 且上限200、未知回退20，有界单写队列、真实GATT结果和代次隔离。旧现场 EXE仍为9B8F8C…6106E，不能复用它作为新驱动。桥接目录为本轮只读输入；若审阅发现必须改桥接生产源码，返回DLA收敛明确修订再实施，不能随手扩展。
3. 必要配套修复：USB 断开后关闭内部 Kimi 9000 服务，BLE连接前保证本应用不再监听同一端口；USB重连可重启服务，防止旧accept线程或迟到回调影响新会话。保留现有Kimi查询语义，不改变BLE TCP包类型/端口/固件协议。不杀外部进程、不改系统端口设置。
4. 既有WD-006语音与java.scripting/jdeps runtime修复是新包继承基线，明确来源与未正式验收限制，不重写语音。仅必要打包配方调整与隔离测试。
5. 本轮先交付可验证的MTU分片修复。ThroughputOptimized连接参数请求及轮询合并作为后续有证据的优化项，当前不引入新的上传状态跟踪或TCP扩展；不承诺固定倍数提速。

## 拟定 Windows 允许文件

- src/main/java/com/example/ahakey/app/StudioController.java（USB/BLE服务生命周期）
- src/main/java/com/example/ahakey/service/KimiAhaKeyBridge.java（安全停止/重启与会话隔离）
- src/test/java/com/example/ahakey/transport/（隔离端口与生命周期回归）
- scripts/build-ble-driver.ps1（仅从固定桥接源码、既有SDK输入隔离构建，输入输出manifest）
- scripts/package-local-model.ps1（必要打包配方与新驱动完整依赖，不丢runtime修复）
- src/test/java/com/example/ahakey/packaging/PackagedStartupCheck.java（仅必要隔离启动核验适配）

桥接3文件的累计diff、csproj、离线测试、当前hash和构建依赖单独绑定为不可变组件输入，不能利用Windows allowed_paths虚构对父目录的权限。

## 验收与交付

- 新旧像素/帧数/上传协议常量与编码路径保持；Java编译、已有显示/传输相关离线回归和Kimi生命周期隔离测试。
- 桥接MTU 23/62/203/247/517、59字节命令分片、队列上限/FIFO、部分失败停止、断连代次/迟到通知隔离测试；证明是当前源码执行，静态检查与行为测试分开描述。
- 原DLA实际累计diff审阅及fresh独立审阅覆盖Java变化、打包配方和完整BRIDGE-01三文件累计变化；新包不复用旧fresh PASS。
- 完整本地模型EXE版本1.0.8或更高；新Java、新BLE驱动、模型/JNI/runtime逐项manifest。提取嵌入MSI并与实际payload核对；隔离真实打包GUI启动核验、原本地WAV检查。不启动用户设备连接、Hook安装或真实麦克风。
- Owner真机：同一图片和GIF比较耗时与画面/帧数/播放；USB→BLE→USB；上传中断后不假成功，重连同步后可重传；原Kimi/键盘AI及本地语音操作。记录新包hash、设备身份、实际日志，旧包271498ms成功仅作为基线。
- 恢复：保留旧1.0.7安装包与用户配置；不自动覆盖安装、杀进程、设备写入或刷机。


# Revision 3 生效附录：桥接依赖补丁

# WD-006 revision3：桥接准入阻断修复

继承20261023-wd007-owner-dispatch.md中的用户自动实施/审阅/完整EXE授权。此次是用户已授权更新BLE驱动的必要配套修复，无画质/帧数/协议/产品选择变化，不需要用户再次判断。

原DLA和独立桥接审阅均已确认：F1，新FindService要求BluetoothLEDevice.ConnectionStatus=Connected才调用uncached GetGattServicesAsync，但FromIdAsync不保证建立连接，导致首次/冷重连可被提前return。微软官方来源：https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.bluetoothledevice.fromidasync?view=winrt-22621 。

F2，OnBleNotify只在入口核对generation/discoveryId，随后等待TCP客户端写锁期间若连接代次变化，旧通知仍可发出；状态缓存更新亦需保持身份绑定。需要在真正消费/发送处保留并重新核对身份，避免旧ACK/状态污染重连。

R2禁止编辑桥接输入；此次正式返回CHANGE扩大到受管dependency patch和针对性回归。../BLE_tcp_bridge原文件保持只读、BRIDGE_INPUTS.json保留为不可变base。唯一DIB在Windows仓scripts/ble-driver-fixes.patch保存小范围修复，在隔离源码副本上应用并构建。打包输入身份必须含base文件hash、patch hash、应用后完整源码manifest、新EXE与依赖；不能把base hash冒充patched source。

允许必要冷发现身份/失败判定修正、通知出口与状态缓存身份绑定；保护物理写入的Connected检查、原GATT_WRITE/MTU/队列/ACK/CRC语义。不加TCP消息，不关闭协议确认，不改固件。针对真实逻辑复现冷连接发现启动、迟到通知在发送锁内被挡住、新代次正常通知、状态缓存不继承旧代次；静态接线检查不冒充完整WinRT硬件测试。

原revision2合同及批准已备份contract-revisions/20261023-r2-before-bridge-fix，原起点和旧失败保留。fresh审阅将覆盖base累积diff与本次patch的实际应用后源码。

新增允许路径：scripts/ble-driver-fixes.patch、scripts/test-ble-driver.ps1。scripts/build-ble-driver.ps1允许在新隔离目录应用已审阅补丁并编译，校验固定base来源和最终源码manifest。其他R2范围不变。


# Effective revision4 更新中心

以下工程草案经本次DLA收敛采用，其原“未生效”标记仅属于封存来源；以本项contract-reconcile新批准为生效依据。原r3条款保留，更新阶段冻结继承语音/桥接行为，仅允许明确列出的集成改动。

# WD-006 Contract revision4：连续完整交付更新中心

Owner 已明确批准 BLE 修复后不等待真机验收，精确 Git 保存并继续此前对齐的固件 HEX 烧录和软件 OTA；依据 .ahakey-desktop-harness/evidence/20261023-continuous-ble-update-delivery-owner-authorization.md。

BLE 修复已完成实际差异审阅、142项行为检查、完整1.0.9 EXE及实际嵌入MSI 297文件核验、包内GUI和双WAV探针；恢复提交 a4c8b6ac715168a2876510fc81d501f432b6463b。EXE SHA256 82fc3c3fd64766646a1e4bc57bfcfb74219d4911e1fd2b33b7e680e8cbecab9e。Owner真机测试后置，不伪造PASS；原真实FAIL与r3记录已封存。

DLA已实际读取现有App启动关闭/托盘、TopBar两形态菜单、StudioController、BleManager写入和状态、USB及配置存储结构，并审阅工程收敛材料。单一更多→更新中心，默认软件更新、另一固件页签；完整产品取舍此前已决定，本次不重复提问。新增Journey J008/J009，关联J005/J006/J007。范围扩展与架构变化，high_impact，实施后新的独立实际审阅。

同一连续最终EXE采用WD-006 revision4，沿用原始start与guard-origin，不关闭假PASS、不切换main-anpx或伪造HEAD，不建立第二活跃实现。仅contract-reconcile更新有效批准。

正式工程边界见update-center-inputs-20261023/CONTRACT_READY_20261023.md及ENGINEERING_RESOLUTION_20261023.md。软件目录404、签名身份未配置需真实显示；不能以占位UI/禁用服务交付。备份/恢复、下载/校验/取消、安装协调、工具写入校验路径必须实际接入。禁止实际安装/设备写入/烧录/发布。WCH供应商工具不打包、不下载，自动发现或用户选择已安装的固定profile。

最终完整本地模型EXE版本1.0.10，UpgradeCode沿用{03E5A934-FFCA-3815-B455-7D49BF1CA1DC}；ProductCode由实际新MSI产生并绑定，不使用pom1.0.0替代安装版本。1.0.9签名状态NotSigned。软件OTA无可信正式发布输入时安全不可用，不编造线上可用与真实升级通过。

# 更新中心 CONTRACT_READY 工程草案（2026-10-23）
 
状态：工程准备完成；不是已生效Contract或实现授权。由主DLA 01a1684d-3953-79d0-9cc6-57f397a595f9在BLE修复EXE收据/精确Git保存后采用。优先纳入WD006 revision4；新建WD007仅作为满足真实暂停前提后的备选，不占用新编号。Owner产品选择继承原CONTRACT_DRAFT与两份grill记录；连续执行依据20261023-continuous-ble-update-delivery-owner-authorization.md。

## 1. 本轮结果与责任
 
交付同一AhaKeyStudio完整本地模型EXE，增加一个更多→更新中心入口，软件更新默认页签、键盘固件页签；保留WD001-005、WD006语音及BLE修复。架构扩展与范围扩展，high_impact，内部联调交付，不含网站发布或自动安装/烧录。
 
更新客户端、维护/备份/恢复和工具适配必须真实连通，不以独立未接入服务代替功能。线上没有可信目录/签名包时显示真实不可用，工具缺失时引导指定已安装目录；这些边界不阻止内部EXE构建。最终安装、实际烧录/清除、跨模式设备关联与恢复持久性由Owner真测，仍保持pending/owner_deferred。
 
## 2. 已冻结用户语义
 
- 软件只提供匹配当前安装形态的最新稳定版，不提供本地EXE/软件降级。启动只查信息；用户下载才取包，下载可取消且不隐藏后台；完成并校验后用户再确认退出安装。
- 明确区分无法获取、未发布匹配形态、已经最新版、有新版、下载中、校验失败、待确认、安装中、安装待确认、重启已确认；404不是已经最新版。
- 官方目录支持多固件；默认内置CP2修复HEX。无连接能选/浏览，不可烧录。已知不兼容拒绝；未知但合法本地HEX按高级风险确认。官方兼容降级明确风险确认。
- 按目标能力计算必要备份，未知本地HEX按全部约定范围备份。备份失败或必要回读失败阻止；未应用草稿不能冒充键盘配置。旧版例外仅在可靠识别旧版且协议确不支持时可用，当前生产识别表为空。
- CodeFlash与DataFlash同时清除，不擦外部OLED物理区，不重传OLED/蓝牙配对/睡眠/语音，不重放历史AI状态。PC配置、绑定、主槽位、资源保留。
- 真写入后不提供应用内取消；普通退出共用排他判断。工具download、verify、正常重连版本观察和恢复结果逐项独立，不说远程hash已确认。
- 重连后用户决定是否恢复可用配置；错设备、错目标、未知能力、读取失败均不盲恢复。恢复按项记录完成/跳过/失败。

## 3. 架构与数据边界
 
UpdateCenterDialog只呈现，不执行网络/进程/设备I/O。UpdateCenterService管理软件生命周期，FirmwareUpdateService管理维护生命周期，共用DeviceMaintenanceCoordinator以防安装退出与设备事务竞争。
 
Coordinator拥有唯一operationId、源连接身份/代次、目标hash、工具profile、备份hash与阶段token。预备阶段等待已有事务自然结束或拒绝；持久写入/上传的不确定结果必须先对账。维护期普通入口全部拒绝/暂停，不能靠禁用按钮。维护token仅允许当前阶段必要查询或恢复，不全局解锁。
 
BleManager保持既有事务锁顺序、DisplayLease、未知ACK隔离、TTL与连接代次。必须覆盖直接USB发送和TCP writePacket旁路、状态轮询和AI deferred；仅包sendCommand不合格。恢复后清除旧pending、重新识别能力，按最新事实恢复正常服务。
 
USB正常态/下载态/重连关联使用设备容器/端口等真实系统信息及唯一目标约束；没有关联证据不能假装serial/UID存在。多设备或换设备立即使备份及确认失效。BLE来源仍需要确认同一物理USB目标，不能将BLE地址当下载UID。
 
Backup保存：所有4Mode普通键(宏/描述)、全局侧拨、全局亮度、4×9灯效；PC草稿/绑定独立快照。目录下原子写入+读回hash验证，损坏/权限/磁盘满显式失败。恢复先生成不可变计划，用户确认后用原协议写入并读回，失败保留原备份和剩余计划，不自动重试。详细实际入口见ENGINEERING_RESOLUTION第5/6节。

## 4. 工程输入固定
 
固件candidate=70ca334f65d73b6a2f20a0598e55c6da59f26526；HEX=ffb9208f79084aa24a832ad2562a14dbbea5df4d114a135cb5b2eb98d4e05539；r001 ASCII catalog；正式schema6 gate PASS仅作为固件既有准入，不能代替本客户端真机验证。独立releaseId=cp2-memory-safety-20261018，不改变设备上报版本。
 
Intel HEX地址0..0x6FFFF，禁止Boot/DataFlash地址，校验完整记录、checksum、重叠、EOF与扩展地址溢出。内置/官方下载比较可信目录hash；本地未知文件保留高级分支但不自动推断模型。
 
WCH profile=wchisp-3.9.0.0-ch582-local；目录自动发现C:/WCH.CN/App/WCHISPTool/WCHISPTool_CH57x-59x并支持用户指定。固定EXE/DLL/芯片库hash；不从PATH执行同名未知工具。缺profile或混用文件拒绝。配置为UTF8文本INI、CH582 6/130、USB、[CH57x-58xUICfg]、IsEraseAllCFlash=1、IsClearDataFlash=1、DataFlashFileSel=0、仅UserFile1选中、IsAfterDownRest=0；其余硬件选项依据固定profile核对。
 
命令顺序为工具 -c <本次INI> -o download -f <冻结HEX>；成功退出后同文件-o verify。捕获独占stdout/stderr/console，严格完整终态与失败优先；退出0无终态拒绝，终态成功但退出冲突不无条件覆盖。超时不自动kill/重刷，保留维护直到进程已结束和状态处置明确。
 
手册/参考物理步骤：关机断开USB，按最左语音键插入USB；下载/校验完成后拔USB、松键、正常接入开机。引导文本标明真实检测结果；实际按键流程待Owner真测。
 
软件schema2与信任策略见ENGINEERING_RESOLUTION第1/2节：仅官方HTTPS目录、限制重定向、精确形态/安装身份、长度/hash、Authenticode Valid及本地固定证书身份。当前证书策略未配置即禁止生产OTA安装，不允许contains/空publisher/自签假证书。未来正式签名输入补齐是发布输入，不需重新讨论已定UI产品流程，但策略变更必须审阅。
 
当前内部1.0.8未签名；1.0.9及最终新包每份重新记录真实身份。app-release.properties在打包时产生真实version/variant/x64/productId/upgradeCode/buildId，不能读取pom/JAR 1.0.0冒充安装器版本。先从已生成1.0.9 MSI提取实际UpgradeCode后沿用，最终版本主DLA递增。

## 5. 精确新增路径与职责
 
机器可读精确名单：CONTRACT_READY_20261023.json.allowed_paths_delta。所有路径相对Windows接收仓。下面Java路径均位于src/main/java/com/example/ahakey/，新增类为拟议唯一职责边界，不能任意扩目录授权。
 
| 路径 | 允许改动 |
|---|---|
| App.java | 仅启动信息检查、统一关闭准入、更新worker握手及重启receipt；保护语音初始化与原清理链 |
| view/TopBar.java | 两形态更多菜单更新中心入口；退出/重连/BLE驱动动作维护准入 |
| view/UpdateCenterDialog.java | 新增两页签、进度/取消/来源选择/风险/备份恢复确认；无直接外部I/O |
| app/StudioController.java | 服务组装、自动回读/轮询/保存/连接入口维护协调与UI绑定 |
| service/BleManager.java | 现有锁顺序下维护租约、阶段白名单、全部底层USB/BLE读写旁路准入与代次失效 |
| service/UsbHidTransport.java | 只读设备路径及容器/端口身份快照与候选计数；不改帧格式或传输优化 |
| service/DeviceSyncService.java | 复用普通键编码并提供恢复白名单命令；不让整份草稿灯效/亮度混入恢复 |
| service/DisplayConfigService.java | 维护暂停与全Mode可靠灯效读取/白名单恢复协作；原OLED事务保持 |
| service/AiRuntimeDisplayService.java | 暂停自动发送/回连/pending；不误记SENT；保留PC偏好与绑定 |
| model/DeviceStatus.java | 不可变身份观察快照；未知/失败/已知能力明确分层 |
| util/StudioStore.java | 严格快照读写异常可观察；旧loadOrDefault兼容 |
| util/AiRuntimeStore.java | 严格现存PC文件快照；不改草稿格式 |
| update/ReleaseManifest.java | schema2强类型、软件形态与固件目录记录，禁止schema1猜测 |
| update/ReleaseManifestClient.java | 固定HTTPS目录、超时/大小/重定向限制、明确404/网络状态 |
| update/VerifiedDownload.java | 用户触发、进度、取消、临时文件、长度/hash、冻结副本 |
| update/InstalledAppIdentity.java | 真实包元数据与已安装形态识别、版本比较 |
| update/InstallerTrustPolicy.java | Authenticode Valid及本地证书身份策略；缺策略fail closed |
| update/WindowsUpdateInstaller.java | 受控worker安装/receipt/重启；进程启动不假成功 |
| update/UpdateCenterService.java | 软件页状态机与两服务协调、一次启动检查 |
| firmware/FirmwareCatalog.java | 内置/官方/本地来源身份、能力表、未知与已知不兼容区分 |
| firmware/IntelHexValidator.java | 448KiB地址/格式/EOF/checksum/溢出/重叠检查 |
| firmware/DeviceMaintenanceCoordinator.java | 唯一operation/目标/阶段/连接身份、排他生命周期与受控权限 |
| firmware/DeviceBackup.java | 冻结设备事实和独立PC快照、完整性/来源/目标绑定 |
| firmware/DeviceBackupStore.java | 原子写/读回hash/损坏可观察、失败保留 |
| firmware/DeviceRestoreService.java | 按源/目标能力白名单恢复、每项ACK+读回、部分失败报告 |
| firmware/WchRuntimeLocator.java | 已安装目录自动发现/选择、工具profile全部hash校验、不下载分发 |
| firmware/WchFlashAdapter.java | 生成固定3.9 INI、download/verify及operation控制台结果解析 |
| firmware/FirmwareUpdateService.java | 准备/备份/确认/写入/校验/重连/可选恢复状态机 |
 
额外资源：
- messages_zh.properties、messages_en.properties、style.css：仅更新中心局部文案/样式；
- update/trust-policy.json：空可信身份表及明确不可安装状态；未来仅封存真实签名身份；
- update/app-release.properties：构建输入模板/真实安装形态元数据；
- update/windows-update-worker.ps1：仅获用户确认的安装/结果/重启协调；
- firmware/wch-capture-worker.ps1：本次进程归属与控制台捕获，不常驻、无全局kill；
- firmware/catalog.json、wch-runtime-profiles.json：固定固件/工具hash及能力，不猜版本；
- firmware/x1-c582-hw1-p1-r001-cp2-memory-safety-20261018.hex：只复制已hash核实的正式推荐HEX，不改Firmware源文件。
 
测试限定JSON逐文件名单内的UpdateCenterChecks、InstallerTrustChecks、FirmwareUpdateChecks、DeviceMaintenanceChecks、BackupRestoreChecks、WchAdapterChecks、UpdatePackageCheck。临时目录与替身I/O，禁止测试真实用户目录/设备/安装器/烧录器。
 
scripts/package-local-model.ps1仅增加上述资源、worker、固件及真实包元数据/升级身份验证，保留隔离输出和模型输入来源；scripts/verify-update-package.ps1只验证包内容/资源hash/升级身份与worker语法，不安装。
 
依赖决定：Java17 HttpClient、MessageDigest、现有Jackson/JNA/JavaFX足够；本增量不增加Maven依赖。pom.xml在r3累计allowed中保留但本阶段不因更新随意改依赖。若实现发现真实必需依赖，由DLA精确reconcile，不默许扩大。
 
**累计范围**：r4保留r3完整allowed列表以审阅历史累计diff；新增delta并集。继承SpeechService/ModelConfig/VoiceInputManager/LibraryLoader/语音测试/桥接patch等只为累计归属，本阶段冻结其行为；不能借累积allowed继续改语音或BLE策略。新增协议命令、改共享payload、CP2.5、网站或参考仓修改均不在范围。

## 6. Journey Registry拟新增
 
J008「软件更新与安装恢复」：触发更多→更新中心→软件更新/启动信息检查；Windows UpdateCenterService拥有状态，维护Coordinator拥有退出准入，安装worker拥有进程/receipt；无设备新协议。失败模式覆盖网络/404/schema/形态/hash/签名/UAC/安装失败/重启版本不符；回归两语音形态菜单、托盘、配置保留、活动设备写入排他。
 
J009「固件维护、配置快照与可选恢复」：触发键盘固件三来源选择；Windows拥有文件/备份/维护，官方工具拥有写入/校验，固件拥有真实配置与响应；沿用0x9F/0x87/0x97/0x88/0x8E/旧普通键写与保存，不改变协议。失败模式为错目标/换设备/未知旧版/不完整备份/工具不兼容/超时/未重连/恢复部分失败；回归USB/BLE身份、显示上传、Hook AI后台、所有写入入口与窗口关闭。
 
现有J005/J006/J007作为关联回归；实际登记ID前主DLA重新核对无冲突。本轮未登记。

## 7. 可判定验收
 
| ID | 离线机器验证 | 最终真实验收 |
|---|---|---|
| U01 | 更多仅一个入口，两页签默认软件；model on/off及中文/英文 | 真实EXE界面、DPI/托盘 |
| U02 | 启动不下载；下载大小/未知总长/取消/关闭，无隐藏任务 | 实网发布输入后下载体验 |
| U03 | 404、错schema、错形态/产品、损坏、重定向、缺/错签名均安全失败 | 真签名包来源与更新 |
| U04 | 维护与安装并发、worker握手、UAC取消、退出/重启receipt模拟 | 覆盖安装、失败恢复、重启实际版本 |
| U05 | 包含完整模型/runtime/资源/升级身份，PC数据路径不覆盖 | 安装前后草稿、资源、绑定保留 |
| F01 | 三来源/无连接/本地高级确认/合法降级/目标改变失效 | 实际固件选择与引导 |
| F02 | 全4Mode/全灯效快照，草稿与回读分离，能力裁剪 | 键盘实际配置一致 |
| F03 | 缺失/损坏/满盘/回读异常拒绝，旧数字1.0不触发例外 | 实际备份保存与恢复可用 |
| F04 | 冻结HEX/profile/hash/INI双区清除参数；download/verify顺序 | 真双区清除、写入/校验效果 |
| F05 | 全底层旁路排他、锁顺序、代次/设备替换、旧pending不回放 | USB/BLE切换与独占 |
| F06 | 准备取消；写入不可取消；超时不杀/重试；无终态不成功 | 实际WCH控制台/UAC/进程归属 |
| F07 | write/verify/reconnect/catalog分层，错版本不恢复 | 实际重连r001观察，不宣称远程hash |
| F08 | 恢复按项ACK+回读/部分失败，白名单不含OLED等 | 恢复配置与重启持久性 |
| R01 | 原显示/输入/语音/Hook/传输适用回归，不改金样凑PASS | Owner后置BLE和整体验收 |
 
实现前I/O边界自检；实现后DLA累计actual diff与新的high-impact独立审阅；Git candidate/产物/固件身份每轮真实绑定。测试fixture只能标模拟，不放入生产目录当官网成功响应。可发布签名包、真实安装、刷机测试缺失不转为PASS；客户端在缺依赖状态可构建/可试用。

## 8. 接续、封存与授权
 
主DLA先冻结r3及BLE修复EXE、保存精确候选；沿用原始start/guard-origin，使用contract-reconcile进入r4，不close假PASS、不新建第二active，不为suspend修改main-anpx/伪HEAD。suspend需HEAD满足committed_inputs，另分支候选不能代替；详见ENGINEERING_RESOLUTION第7节。
 
新Contract approval_assets建议包括本草案、工程结论、SOURCE_HASHES、HTTP/GitHub观测与正式本任务原因记录；主DLA把需要冻结的附件复制入本任务证据再绑定，保留原草案。local.json.source_root不改；windows-eternal参考只以精确绝对路径/hash证据使用。
 
主DLA可在当前持续授权内完成工程范围收敛与helper批准；不再让Owner重复已定产品选择。只有真正超出本次边界的变化回CHANGE。DIB仅在新effective approval和合法preflight后实施，本文件本身不能开工。独立审阅由主DLA按Owner授权新建，DIB不自审。



## R5 生效补充：R6-F1 界面动作能力对应（2026-10-24）

依据 Owner 连续交付授权（20261023-continuous-ble-update-delivery-owner-authorization.md），将 R6 独立审阅发现 R6-F1 的必要界面修正纳入精确文件范围。此次不要求新的产品选择：按钮只应在实际支持对应操作时可用。

R6-F1：可信非 r001 固件的 lights 能力只允许读取/保存灯光；共用 writeReady 错误开启 0x89 预览和多任务模式。底层拒绝正确，不能扩大协议授权来修复界面。

新增精确路径：
- src/main/java/com/example/ahakey/view/InspectorPane.java：仅分开灯光保存/读取与预览、运行模式的可用条件和必要原因提示。
- src/main/java/com/example/ahakey/model/DisplayConfigState.java：仅加入上述动作可用状态，供实际服务和界面绑定。

已有 DisplayConfigService、Controller、资源文案及已批准测试文件只作本缺陷必要配套；不增加协议命令、不扩大非 r001 的 OLED/运行态权限、不改维护锁或底层能力语义。DIB 可选择最小实现，不要求两个新增路径都必须改。

回归须实例化实际 InspectorPane/DisplayConfigService，可信非 r001 精确 catalog、内存传输；灯光保存/读取可用，预览和多任务禁用并有可理解原因，不发送被禁用动作帧；r001 原功能保持；覆盖 lights 子集与未知 catalog。

R4 原件已封存 contract-revisions/20261024-r4-before-ui-capability-fix/ARCHIVE.json。保留原 start/guard-origin、所有历史批准和失败。当前 R6 不记 PASS；本次由正式 contract-reconcile 生成 R5/build_round 7 后 DIB preflight 实现，提交新 pack 再双重审阅。真实安装/设备/烧录仍 Owner 后置。
