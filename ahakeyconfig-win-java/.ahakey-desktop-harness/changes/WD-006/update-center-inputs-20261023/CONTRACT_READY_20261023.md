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

