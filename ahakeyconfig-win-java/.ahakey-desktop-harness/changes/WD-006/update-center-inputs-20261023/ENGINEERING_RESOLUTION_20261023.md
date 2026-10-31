# 更新中心工程核实与 CHANGE 收敛

2026-10-23；DLA 工程准备；仅追加 planned evidence。不是 approval、实现完成、线上发布或真机 PASS。原 CONTRACT_DRAFT.md / ENGINEERING_INPUTS.md 保留。

## 结论与可交付边界

可以实施完整更新中心客户端、离线推荐固件、已有官方工具适配、维护排他、可靠快照与恢复、安装协调，并交付本地模型 EXE。工程资料不足不等于不能实现；但不能把没有正式发布输入的 OTA、没有真实设备执行的烧录/清除、未做安装测试记为通过。

- Owner 已授权连续实现、必要机器检查、精确 Git 保存与阶段聊天；最终安装/烧录/真机由 Owner 操作。无需重复产品 Grill。
- 官网 stable 路由真实 GET 为 **404 / Cannot GET /stable.json**。客户端显示“更新信息尚未发布或暂不可用”，不说“已是最新版”，不把官网整体判断为故障。
- 当前 1.0.8 本地模型安装器 `Get-AuthenticodeSignature` 为 **NotSigned、SignerCertificate=null**。不编造发布者，不使用 Publisher 空值/contains，不用未签名内部包充当已可信 OTA 包。
- 已找到官方工具本机完整目录 `C:/WCH.CN/App/WCHISPTool/WCHISPTool_CH57x-59x`。采用自动发现/用户指定已安装工具目录；本批不随包分发许可未知工具、不自动下载工具/驱动。
- 内置推荐固定 CP2 memory-safety HEX `ffb9208f…5539`；保留 catalog `x1-c582-hw1-p1-1.0.0-r001`。它不是新语义版本，不能改称 1.1.1 或 CP2.5。
- 正常数字状态 1.0 新旧共用；暂没有可靠的已知旧版判别条目。因此已授权“旧版清空升级”分支实现但 **生产识别表为空，当前不可触发**。不能用超时/默认文案填上旧版身份。

## 1. 官网、版本与发布输入

### 实际仓与网络

本地网站 `C:/Users/20825/Desktop/ahakey-web`，Git HEAD `1f00390dc5e2117a7f8816080b2ce493822bf517`，origin `TheNorthStarYang/ahakey-web`。远程 contents 经连接器返回404，只说明该连接不可见；本地源码可读。

`package.json` 是 Node/Express，站点包版本1.0.0不是Windows客户端版本；`npm start`运行server.js；Docker为node:20-alpine、npm ci、端口3000。workflow会构建/push镜像，但实际更新云托管服务命令仍被注释，不能把workflow存在当作部署已完成。没有运行这些命令。

server.js：`/download/windows/latest`、`/installer`、`/stt`指向WINDOWS_DOWNLOAD_STT_URL；`/lite`指向WINDOWS_DOWNLOAD_LITE_URL。环境变量缺失均可退回同一个历史RAR地址。无stable.json路由、形态版本、SHA256、签名者或固件多版本契约。URL中的临时对象签名不是Windows Authenticode，不读取/公开服务器凭据。

网络证据在 HTTP_OBSERVATION_20261023.json：web工具失败、受限代理失败都没有来源HTTP状态；后续获准只读直连成功返回404，未关闭TLS验证。没有下载或执行包。

官方 `AhakeyAI/desktop` Releases连接器实际返回7项：最新v0.2.3（2026-10-16）只有macOS DMG；Windows历史资产包括v0.1.1 ZIP（87,141,532字节，GitHub报告SHA256 `6c25ca4ed846fb6115a69714d207518c0b5ba75f4803fe0ccefb99f0052f57a7`），v0.1.0的VibecodingKeyboard_Setup.exe（83,569,924字节，报告SHA256 `cb2b41276b5575cdfccd33170eb9b49bc34a91ace0f0384c5ddf71894272275a`）。没有下载；无法从这些标题证明与当前Java/本地模型形态和安装身份相同，不作为新版候选。完整摘要见GITHUB_RELEASE_OBSERVATION_20261023.json。

### 最小客户端契约（提案，不声称已上线）

稳定入口仍为 `https://ahakey.com/stable.json`；制定schema2而非静默误读参考schema1。字段：schema、channel=stable、generatedAt、windows（按lite/local-model区分，各自version、arch=x64、installerKind、url、size、sha256、productId、upgradeCode、signerPolicyId）、firmware.entries数组（releaseId、catalogKey、hardwareModel、protocolProfile、hexUrl、size、sha256、recommendedFor、capabilities、releaseOrder）。releaseOrder是正式目录排序，不解析r001为软件语义版本。一个releaseId只能绑定一个hash，同catalogKey多构建必须有不同releaseId与hash，不冒充可从设备远程分辨。

缺字段/不支持schema/不是HTTPS/重定向到未许可主机/下载长度超限/hash不符/形态缺项均明确失败。重定向白名单来自随应用封存的策略，不由远程manifest任意扩权。检查有超时与响应大小上限；启动一次只取信息，不自动下载、不循环弹窗。404/无网络不等于无更新；只有成功读取合法且匹配形态的目录才可比较版本。用户下载才取文件，取消删除本次临时分片，不续传。

未上线时用测试替身验证所有流程；生产显示真实不可用。未来网站实现/上传发布另属网站/发布责任，本任务不改网站。

## 2. 安装来源信任与包身份

实际内部安装器：`target/WD006-R4-LocalModel-1.0.8/installer-validated/AhaKeyStudio-1.0.8.exe`；SHA256 `11a4d91c5e6b2886b4b7366de93dee6756835651d08de8d1c10b898ee9645bdb`，签名检查NotSigned。后续1.0.9修复包必须重新记录，不能继承此hash或结果。构建脚本AppVersion=1.0.8、pom/JAR=1.0.0、旧build-installer=1.0.0互不相等，版本比较不能取JAR名或硬编码UI文案。

新包生成 `app-release.properties`，记录version、variant、arch、productId、upgradeCode、buildId/来源candidate；包装时填实值并校验，开发JAR标非安装形态。同应用两形态共享安装升级身份，不允许OTA顺手换形态。检查当前1.0.9最终MSI UpgradeCode再固定；不能凭空随机改UUID导致并存。新增包版本由主DLA依据最终已保存包递增。

OTA安装前要求：HTTPS官方目录+下载SHA256/长度+Windows签名状态Valid+受本地策略固定的签名证书SHA256/SPKI身份（不是subject contains）+匹配productId/upgradeCode/version/variant。签名策略未配置则显示“安装包可信发布配置尚未就绪”，阻止安装；不能从同一远程manifest接受新信任根。证书轮换走受信应用更新/已审核策略，不能自动学习首次见到的证书。当前无真实证书输入，策略可空且明确禁用生产安装；不生成假证书，不为测试放宽生产校验。

用户点“退出并安装”时再次在维护锁下排他检查资源上传/固件维护，固定operationId/hash/path后启动独立安装协调worker；worker握手成功才让应用退出，启动失败留原应用。路径参数逐项传递，不能把远端字符串拼接PowerShell命令。退出只走本应用原清理链，无全局kill。

安装器启动、进程退出、安装版本落盘、重启分别记状态；只有新进程读到匹配receipt的安装身份才确认成功。MSI的0/3010/1641应区分成功和需重启，不能对任意EXE套用；jpackage EXE需建立实际返回码/安装结果适配。失败或UAC取消保留日志及原配置，尽力重新打开已存在旧入口并显示失败，不自动再次安装。配置留在用户目录，不从更新包覆盖草稿、资源或绑定；重启不重放设备任务。真实覆盖安装/重启必须最后由Owner验收。

## 3. WCH 已有工具、配置与成功语义

本机工具：EXE 3.9.0.0，`CH343PT.DLL` 1.40，`WCH55xISPDLL.dll` 3.8.0.0，CONFIG_CH57X59X.WCH、ChipType/chiplist_CH57x_CH59x.wcfg、双语手册齐全。EXE SHA256 `7b5d84bfcc8786aabf74ba264de29c1e2eda7907fb8385426fda3270cd793f95`；各文件完整hash见SOURCE_HASHES。芯片库CH582：McuSer=6、McuType=130、MaxFlashSize=458752、MaxEepromSize=32768、USB支持。

官方手册2.2支持参数对：`-c <绝对INI> -o download|verify -f <绝对HEX>`。工作目录为工具目录，过程日志由本次operation独占。不执行`-u get`作为准入；参考工程已记录UID输出不可靠。准备阶段仅枚举设备，不启动CLI。首次实际写入仅发生在用户最终点击后；verify是非写入校验阶段，也只能由真实烧录流程调用，不在本轮执行。

**版本差异已定位**：随附手册旧示例 `[CH57x-59xUICfg]` / `IsClearCodeFlash`；本机EXE UTF16字节实际含 `[CH57x-58xUICfg]`对应名称、`IsEraseAllCFlash`、`IsClearDataFlash`，未检出旧两字段。实际适配profile固定该EXE/DLL/芯片库hash，生成UTF8文本INI：MCUName=CH582、bMCULine=6、bMCUType=130、bDnInterType=0、IsEraseAllCFlash=1、IsClearDataFlash=1、DataFlashFileSel=0、仅UserFile1选中、其余文件未选中、IsAfterDownRest=0。沿用已核实CH582配置选项，不随意修改读保护/复位/看门狗引脚。二进制CONFIG不在原目录patch；profile的字符串证据不是擦除已验证。

同一冻结HEX先download，明确成功且owned process退出后再verify；两阶段分别保留完整终态和进程结果。官方文档错误码0成功、1参数、2配置、3初始化、5无设备、6芯片不符、13下载失败、14校验失败、100未知。官方手册成功截图及本机EXE包含 `Status=Finished / Code=0 / Message=Succeed`；参考9月真实测试摘要指出控制台有终态而stdout/stderr为空，不能只读管道。需要operation专属控制台捕获，严格解析完整结构化终态，失败优先，尾部残留/其他进程输出不得采信。退出0但无终态不是成功；可信终态与非0退出冲突记录“结果不一致待确认”，不静默报成功，除非后续固定工具真实证据证明特定非0码可接受。旧参考解析器允许任意非0码被成功文本覆盖，不能无条件沿用。

写入开始后UI不能取消，超时不要自动杀烧录进程或重试；保留维护锁与“结果未知/仍可能执行”状态，直到确认owned process结束。异常退出不把锁简单释放为可写。不得无条件taskkill/WMI杀所有同名工具。

再分发：参考 `wchisp-runtime.json` 明记authorization not verified；release-permissions-checklist仍列WCH商业再分发待确认。本机目录无单独license/readme授权，官方网页返回JS壳，搜索未取得可引用再分发许可。不能据免费可下载推出可再分发。最小方案：定位上述已安装工具，缺失时显示官方获取链接与目录选择；不捆绑。其他机器未具备工具时烧录不可开始，但不阻塞客户端构建。保留工具配置到本次工作目录/自己的日志目录，不改用户原配置。

## 4. 固件身份、来源与物理流程

Firmware根 `C:/Users/20825/Desktop/vibe-code` 只读。固定candidate `70ca334f65d73b6a2f20a0598e55c6da59f26526`；HEX `.ahakey-harness/evidence/builds/ws3-cp2-memory-safety-20261018/HID_Keyboard_582m_vibe_coding.hex`；SHA256 `ffb9208f79084aa24a832ad2562a14dbbea5df4d114a135cb5b2eb98d4e05539`；schema6正式gate `.ahakey-harness/evidence/checkpoints/X1-AI-WORKFLOW-PRESENTATION/CP2/20261018T175441/gate-receipt.json`，hash `bf6efc5ac8380b6420c4ded17492b4bc798cad46072699c38ede41945fb5dbaa`，result PASS。design-review hash `2d480cbccfddaeb21c8312b9bb3bec43799d51f29d81f986628814dd3727e7c9`。本次只重新核对字节和现有gate，没有执行Firmware脚本或采纳CP2.5。

candidate中command_solve.c已通过git show只读核实：0x9F是ASCII catalog，0x00数字字段仍1/0。r001被多次修复构建复用；展示“所选HEX写入/校验完成；重连观察版本r001”准确，不宣称远程hash一致。未知本地HEX结构合法不证明型号正确；能确定不兼容的拒绝，不能确定的按既定高级风险确认。地址上限来自candidate链接脚本与官方chip数据库：0..0x6FFFF（448KiB）；禁止写DataFlash/Boot区。校验checksum、EOF、长度、扩展地址溢出、重叠、非法记录、零数据；文件在最终确认时重新hash并固定只读副本，防止选择后变化。

硬件引导来自参考hardware-flash-test-checklist及现有UI：关机、断开USB，按住最左侧语音输入键插入USB；检测WCH下载设备VID_4348&PID_55E0后才继续。写入/校验完成，拔掉USB、松键、正常重新接入开机。本次没有物理验证此按键链；不把芯片PB22抽象名当普通用户步骤。正常USB参考vid_413c/pid_2107/mi_01。必须唯一设备与同一维护会话：源连接代次、USB路径/容器或端口身份、选择HEX hash、工具profile、用户确认一起冻结；进入下载模式可能路径变化，需可验证的端口/容器关联。无稳定关联或多设备有歧义时要求用户只保留目标设备并重新准备，不能取列表第一个。BLE地址不是USB下载UID，也不能伪装跨模式唯一身份。

旧版例外：在没有可靠旧版catalog/硬件身份映射前生产表为空；已确认新版任一必需回读失败都阻止。不允许r001/数字1.0/0x9F超时被误分类为旧版。未来补充可靠旧版身份属于精确元数据审阅，不改Firmware。

## 5. 备份/恢复白名单与实际入口

| 对象 | 可靠读取 | 恢复与确认 |
|---|---|---|
| 4 Mode × KEY1..4普通键、宏、描述 | BleManager.readOrdinaryKeyConfig → 0x87，解析后冻结原始语义/字节 | 复用现有0x73/0x74/0x75编码，saveConfig持久化后逐键0x87比对；不把writeSequentially发完视为成功 |
| 全局侧拨上下位置 | readSideSwitchConfig → 0x97，保留binding/action完整值 | writeSideSwitchConfig已有ACK/回读验证，不能把每Mode草稿拼成全局侧拨 |
| 全局亮度 | DisplayLease下displayRead(kind=0) → 0x88 | 0x8E saveDisplayBrightness + ACK，建议再读比对 |
| 4 Mode × 9 SINGLE AI灯效 | displayRead(kind=1,mode,ai) → 0x88 | 逐项0x8E保存+ACK/读回，报告部分成功，不发整包草稿 |
| PC偏好/绑定/主槽位 | StudioStore/AiRuntimeStore现存文件严格快照；存储接口区分缺失与损坏 | 保留PC记录，目标不支持停用不删除；不恢复历史运行态 |

StudioStore与AiRuntimeStore会默认回退/吞保存错误，不能用这些成功返回作为备份依据。新增严格接口或独立BackupStore读取真实文件并写临时文件、原子命名、读回hash，异常向上返回。保存设备回读与PC草稿为不同字段；未应用草稿永不替代设备事实。冻结对象不引用可变JavaFX模型；枚举全部4Mode而非当前页。

不备份恢复设备OLED/GIF、蓝牙配对、睡眠/语音等未列项目；保留现有PC资源文件，安装不清空目录，烧录不自动重传OLED。备份文件绑定格式、operationId、连接代次/设备身份、源catalog、目标hash、能力决定、读取结果、内容hash；失败仍保留。恢复只允许本次明确确认的集合，错目标/错设备/未知能力拒绝；每项成功/跳过/失败分开。

## 6. 排他不能只锁UI

统一MaintenanceCoordinator，由BleManager底层入口执行准入；业务owner token不可由普通调用者伪造。事务租约与现有commandTransactionLock→commandLock顺序一致，不能等待锁时持有JavaFX/UI锁。进入前等已有事务安全结束或拒绝；未知ACK隔离未清不能进入。维护期间普通读写/模式/睡眠/AI/OLED/自动重连不能插入，维护内部只开放阶段白名单读/恢复写。

必须覆盖sendCommand、sendCommandExpecting、writeData、writeLargeData、openDisplayLease/readDisplayConfig/exchangeDisplay、queryStatus、queryStatusAndWait、setWorkModeAndVerify、setSleepWaitTimeMinutesAndVerify、sendRuntimeState/deferredRuntimeState、setRuntimeDisplayMode、sendMultiRuntimeSnapshot、直接usbTransport.sendCommand分支、writePacket里的QUERY/WRITE分支。维护不能通过USB/BLE自动降级切到另一设备。

StudioController的自动回读、statusPoller、保存、侧拨、模式和手动重连均接入；DisplayConfigService已有上传/预览事务必须先结束；AiRuntimeDisplayService.onDeviceReady、Hook事件和pending snapshot暂停，不把暂停包装成SENT。维护释放丢弃旧pending与旧代次回调，重新识别后按最新事实恢复；PC绑定留存。

退出入口：TopBar.exitApplication、App主窗口close、托盘Exit、App.stop/shutdownApplication统一判断；主窗隐藏也不能把下载悄悄变后台，活动下载需可见窗口或明确取消。维护写入/verify未收口时普通退出拒绝。系统强杀无法阻止，不声称绝对安全。

## 7. 合法接续：优先 WD-006 revision4

本轮观察WD006 revision3 ACTIVE/PREVIEW_FIX；当前HEAD main-anpx/8c654c99a582d897d50698148e6c83cbe51c5d59；另有授权win-zxy-harness候选分支。新编号WD007目录尚无，但不能因此new第二active。

主DLA发现并已由本轮源码复核：suspend没有--commit参数，guardrails.run在suspend前强制committed_inputs(HEAD)。只保存win-zxy-harness不能满足main-anpx HEAD；不能为腾槽改其他分支、伪造HEAD或夹带foreign。已有TRANSPORT_REVISION_REASON记录合法revision2先例，故主DLA可采用同一连续完整EXE任务的revision4：

1. 等唯一BLE DIB完成修复提交、DLA实际review和1.0.9隔离包；不并行修改共享生产代码。
2. 主DLA逐字保存r3 CONTRACT/change/REFERENCES/approval/submit/review/preview/构建与FAIL记录，记录实际1.0.9产物hash与Git保存点，owner_deferred指向真实授权；不把R4真实FAIL改PASS。
3. 在planned CONTRACT_READY和精确allowed delta上收敛，Journey J008/J009登记；累计allowed_paths保留r3范围但新阶段不得重写语音/桥接。
4. 主DLA按helper既有模式更新有效Contract/必要change元数据/approval_assets并保存旧字节；调用 `python .agents/skills/ahakey-desktop-harness/scripts/desktop.py contract-reconcile --id WD-006 --owner-record .ahakey-desktop-harness/evidence/20261023-continuous-ble-update-delivery-owner-authorization.md --reason-record <主DLA新增真实revision原因记录> --role DLA`。没有理由使用--repair-origin；不重置start/guard-origin。
5. DIB `preflight --id WD-006 --role DIB` 后实施。新actual diff、高影响fresh review、候选/包/固件身份重新绑定；旧机器结果只在字节与范围适用时作历史证据，不冒充新结果。formal UAT保留pending/owner_deferred，最终Owner真测再收口。

若主DLA最终仍选择独立任务：只有真正满足HEAD保存条件且能合法suspend时才 `suspend --id WD-006 --note <已保存暂停证据> --role DLA`，随后new、Journey、change-meta、baseline-start、approve；paused存在时approve需要--isolation-record。本轮未执行任何上述状态命令。

参考根windows-eternal不同于local.json.source_root，不静默重绑。既有Firmware协议REFERENCES保持；新参考资料可作为本任务approval_assets中的工程证据/精确绝对路径hash附件，不伪称pin-ref --workspace source已经绑定该不同根。

## 8. 独立审阅与剩余验证

architecture_change + scope_expansion + high_impact。正式DIB开工前主DLA完成状态/锁/备份/安装边界设计收敛；实现后新独立审阅聊天检查累计实际diff、实际调用链、全部I/O入口、不能用设计审查代actual diff。重点：锁反转、连接代次、错设备、未知ACK、覆盖草稿、失效批准、假成功、任意进程/路径执行、签名策略和未签内部包隔离。

机器检查：只用临时目录/假HTTP/假进程/假传输，覆盖schema/形态/取消/hash/签名错误、HEX边界、WCH参数与终态、断连/换设备、备份不完整/损坏、恢复部分失败、全部底层绕行、关闭入口；适用既有传输/语音/显示回归。安装包提取核对runtime/模型/推荐HEX/版本/worker实际入包；PowerShell语法和假worker进程测试可做，无安装/烧录。

真实外部待验：签名发布输入与网站schema2、真实安装覆盖/取消/失败重启、WCH download+verify和双区清除、物理进入/退出与设备关联、恢复持久性；不能将这些标为本轮已测。完成客户端和EXE不自动意味这些已完成。

主要在线来源：[官方发布列表](https://github.com/AhakeyAI/desktop/releases)、[WCH工具页](https://www.wch.cn/downloads/WCHISPTool_Setup_exe.html)、[微软签名检查](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature)、[Windows Installer返回码](https://learn.microsoft.com/en-us/windows/win32/msi/error-codes)。本地手册章节与文件hash见SOURCE_HASHES。
