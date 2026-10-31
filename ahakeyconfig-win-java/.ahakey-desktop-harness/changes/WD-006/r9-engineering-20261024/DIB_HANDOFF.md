# WD-006 R9：内置 WCH、驱动准备与烧录执行交接

2026-10-24；本聊天仅工程核实，生产实现由唯一 DIB 承担。本文是实现输入，不替代主 DLA 的正式 Contract/派工。没有运行 WCH、PnPUtil、安装器或设备命令，没有修改生产、STATE、Contract、官网、Firmware。

## 0. 最新要求优先，旧流程不再作为前置

已读取 `CP25_CP26_WINDOWS_INTAKE_20261024.json` 和根 `DECISIONS.md`。两者读取时仍含部分较早叙述，按本轮主 DLA 传达的 Owner 最新要求收敛：

- 用户不另装 WCH；应用自带工具、必要驱动，可在应用内请求 UAC 完成驱动准备。
- 选择 HEX → 关机按住语音键插 USB → 检测唯一下载设备 → 点击烧录；双区清除。**不强制普通 USB 预连接、备份、恢复或 onboarding。**
- 超时/失败统一“本次链路失败，点击退出重新链路”。后台有限时清理本次进程，清理完成后才能重开；不提供继续等待、断点重试或自动再刷。
- 成功必须工具写入/校验确认，并正常重连读到实际版本。未知 HEX 不要求匹配目录目标版本，不从文件名猜版本；读不到版本仍不能报成功。
- Windows 不提供 Consumer 编辑。已有 Consumer 只展示保留；明确保存 K1 才将**当前模式**设 ordinary 并保存明确动作。保存其它内容不得覆盖该 route；不能把旧 intake 的“选择 Consumer”文字落实为新入口。
- CP2.6 的单项 REGATE PASS 不等于 CP2.6+WS4 Restore 合并 Owner UAT 已完成；不得由此擅自替换内置固件。此限制不禁止 Owner 已允许的未知本地 HEX 流程。

## 1. 输入已复核，可直接用于配方

`INPUT_RECHECK.json` 对 R8 的 **16 项本地输入**重新检查存在性与 SHA256，全部一致。`BUNDLE_INPUTS.json` 给出 **13 个安装内文件落点**（CH375DLL 在 runtime 与完整驱动包中各一份）；`INPUT_TABLE.md` 给逐项 hash。这些是实际文件路径，不是待用户寻找的输入。

工具默认位置统一为 `<安装根>/app/tools/wchisp`，驱动为 `<安装根>/app/drivers/wch-ch375`。由 jpackage 安装身份解析根目录，不能依赖当前工作目录或硬编码 `C:/WCH.CN`；发布版缺失/损坏时报告准备失败，不悄悄使用用户其它版本 WCH。

|组成|确认的本地来源|关键事实|
|---|---|---|
|EXE、ISP DLL、CH343 DLL|C:/WCH.CN/App/WCHISPTool/WCHISPTool_CH57x-59x|版本分别 3.9.0.0 / 3.8.0.0 / 1.40，均 x86|
|必需 CH375DLL.DLL|C:/WCH.CN/App/WCHISPTool/WIN 1X/CH375DLL.dll|3.5、x86；不能用 DLL64 替换|
|芯片 DB|上述工具目录/ChipType/chiplist_CH57x_CH59x.wcfg|2515 字节，原样复制|
|净化配置|C:/Users/20825/Desktop/windows-eternal/ahakeyconfig-win-java/src/main/resources/wchisp/CONFIG_CH57X59X-sanitized.WCH|66841 字节，五路径槽全零，SHA256 f21f73360c7f650ab36cc4a0bbe2b88316c85bc1caf2e010139a47486abf5a8a|
|完整驱动|C:/WCH.CN/App/WCHISPTool/WIN 1X 下 7 文件|保留 INF/CAT、3 个 SYS、2 个 DLL，不改厂商文件|

比 R8 更深入的只读核验：四条非系统静态依赖边的导入符号全部能在实际 DLL 导出表中找到、架构匹配、相关导出非转发。EXE→CH375 2 项；EXE→ISP 10 项；ISP→CH375 8 项；ISP→CH343 3 项。**23 个直接导入符号均闭合**。这不等于加载成功、动态依赖穷尽或驱动已可用；其它静态导入为 Windows 组件，完整列表已保存。

实际打包入口是 `scripts/package-local-model.ps1`。需加入上述 staging 和发布资源身份，不能只改旧根 build-installer.ps1。当前 runtime profile 固定 5 项且使用原始机器 CONFIG hash，应改为发布的 6 个 runtime 文件与独立完整 driver 清单。元数据由构建根据实际字节生成，不把哈希交用户维护。

厂商配置不能直接从本机原始 CONFIG 复制；不能把该配置、日志或历史 HEX 路径带进安装包。原始输入仅留 hash 供审计。许可仍是 authorization_not_verified；本轮无新许可证据，不改成“用户自己安装”。

## 2. 驱动准备：应用发起、一次 UAC、固定输入

驱动事实：INF DriverVer=08/21/2025,3.5.2025.08；CAT=CH375WDM.CAT。NTamd64 将 CH375W64.sys 绑定到 CH375_A64。INF 覆盖 4348:55E0 与 1A86:55E0。应用当前设备识别只包含 4348:55E0；后者的驱动覆盖不自动扩展为支持另一产品/VID 的批准。

R8 本机签名观测的驱动目录与厂商组件均 Valid，驱动 CAT 主体是 Microsoft Windows Hardware Compatibility Publisher。R9 hash 不变，但未重新宣称干净系统证书/驱动验证通过。无须安装自签证书来处理该原厂驱动；实际 Windows 安装验证仍必须通过。

建议执行契约（交 DIB 实现，本轮未执行）：

1. 验证安装内 runtime/driver 清单；检测下载设备的存在与驱动就绪分别表达。只有一个 boot 设备且其 driver/service/problem-code 状态可靠，才能进入 READY_TO_FLASH。设备在 PnP 列表出现不代表驱动可用。
2. 缺驱动时，在应用中发起受限 helper 的 `runas` UAC。helper 仅支持“准备本产品固定驱动”操作，参数不接受任意 exe/INF/命令字符串，不提升整个 Studio。
3. 提升后的 helper 自己重验受信发布清单和安装内固定驱动包，从系统目录解析原生 pnputil.exe，用独立参数数组调用：`pnputil.exe /add-driver <安装根>/app/drivers/wch-ch375/CH375WDM.INF /install`。不使用 PATH 上同名程序、用户提供的 INF、通配扫描、/reboot、/delete-driver、强制卸载、禁用签名或信任证书导入。不要从普通用户可替换的临时 request 中接受新的信任根；驱动输入应来自已验证的安装布局。
4. 收到拒绝 UAC、准备超时、失败或需重启，统一结束本次链路，原因记录到诊断；不进入烧录。驱动准备进程的生命周期单独记录，不把系统 PnP/安装服务放进烧录 Job 或全局杀进程名单。
5. exit=0 仍重新检查设备实际绑定；259 可能无匹配设备或已有更好驱动，不能直接当 ready；3010 是需重启，不能立即烧录；1641 表示已发起重启，本方案不传 /reboot，出现时应异常记录。其它码均按失败处理并保留日志。没有设备时 staging 成功只能叫“驱动已预置”，待插入 boot 再确认。
6. 记录 operationId、固定输入 hash、helper/PnPUtil PID 与启动时间、退出码、实际绑定 INF/服务/问题码；不捕获任意系统日志全文或用户凭据。

厂商 `DRVSETUP64.exe` 文件已定位，但静默参数没有可靠证据，**不作为本轮建议执行路线**。当前配方无需用户另装厂商应用。Windows UAC 可能出现，不等于安装独立 WCH 软件。

依据：[PnPUtil 语法](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax)、[PnPUtil 返回值](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-return-values)。这两项系统机制支持集成方案，不证明本包已经集成或某台机器通过。

## 3. 操作目录、设备绑定与运行顺序

推荐状态：SELECT_HEX → WAIT_BOOT → READY_TO_FLASH → FLASHING → VERIFYING → WAIT_NORMAL → COMPLETE；任何阶段失败/超时进入 FAILED，退出清理完成后回 SELECT_HEX。驱动准备是 WAIT_BOOT 内部准备步骤，不额外要求普通模式预连。

1. 选择本地 HEX；验证 Intel HEX 长度/校验和/记录/地址边界/非重叠/EOF，复制到唯一操作目录冻结为 firmware.hex，记录 hash。未知指“版本/目录身份未知”，不等于允许不合法或越出 CH582 CodeFlash 的文件。沿用现有 448KiB CodeFlash 检查，不在此输入增加 DataFlash 数据文件写入。
2. 已存在普通连接可在维护开始时释放，但不得以其存在或读取成功为前提。维护排他只阻止其它配置/资源事务介入；创建操作身份应允许从唯一 boot 设备取得 port/location/instanceId，不依赖旧 source firmware 或备份 hash。
3. 用户按说明进入 boot。枚举唯一受支持 boot 设备，核验驱动就绪；保存本次 boot 身份/物理端口，按钮点击前重新枚举。多设备或换设备不得启动。现有普通 USB→boot 端口比较前置需重写为 boot 首次绑定；不能用 BLE 地址当 USB 身份。
4. 将校验过的 6 文件 runtime 复制到本次操作目录的 runtime 子目录，保持 ChipType 相对路径；复制后重新核对 hash。WCH 运行目录使用该副本，避免把工具写配置/日志的行为落到 Program Files；原始安装副本保持不变。进程启动前再核验 HEX、输入文件和操作 ID。不同会话不得共用 worker 输出/运行目录。
5. 生成本次 operation.ini。保留厂商 CH582 profile 的其它既有已审参数；强制 `[Public] MCUName=CH582, bMCULine=6, bMCUType=130, DataFlashFileSel=0, IsUserFile1Sel=1, IsUserFile2..5Sel=0`；只将冻结 HEX 设为 swzUserFile1。
6. `[CH57x-58xUICfg] bDnInterType=0, IsEraseAllCFlash=1, IsClearDataFlash=1, IsAfterDownRest=0`。采用实际工具使用的段名与字段，不换回旧手册的 CH57x-59xUICfg/IsClearCodeFlash。Code/DataFlash 清除是本轮明确动作，不恢复用户配置。其余保护位不得因重建模板悄悄改变；实际双区擦除仍需设备实测。
7. 在本次受控进程组内执行固定 EXE，传独立参数 `-c <operation.ini> -o download -f <firmware.hex>`；成功后同样执行 `-o verify`。保留独占隐藏控制台捕获，以及 stdout/stderr。路径使用参数数组/Windows 正确 quoting，不拼接用户 shell 命令。
8. 工具退出和明确成功终结记录必须一致；无输出、输出矛盾、非零 exit、超时、worker 死亡不能判成功。终结解析要使用完整记录及已验证输出格式，不能仅看文件名/进度100%或搜索 Succeed 子串；模拟输入可覆盖带引号 JSON 与厂商文本形式，但真实支持格式需来自捕获证据。
9. 写入与 verify 均确认后，只提示拔 USB、松键、正常接入开机。与本次 boot 物理端口关联唯一正常设备，建立新连接代次并实际读取版本，不使用旧缓存。onboarding 未完成不应挡版本查询。
10. 读到版本后显示“烧录成功，当前版本 XXX”。未知 HEX 不强制目标版本匹配；已知目录可另做其已有身份校验，但不把未知 HEX 强行塞入目录或猜目标。若换端口无法可靠关联，统一本次失败退出，而不是把同 VID/PID 任一设备当原目标。

## 4. 有界超时和仅本次进程清理

当前 Java 在 120 秒 timeout 后调用无参数 `worker.waitFor()`，worker 自身循环等待 WCH；当前失败状态依赖未退出进程永久保持锁。**这些路径与最新决定冲突，不能继续复用。**

建议由父端 supervisor 管理本次独立 Windows Job Object：

- 建立独占 Job，设置 JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE；Job 句柄只由 supervisor 持有，不设 breakaway，也不放 Studio 主进程或别的会话进入此 Job。
- 以 CREATE_SUSPENDED 创建本次 worker，赋入 Job 成功后才 ResumeThread；赋入失败则结束该尚未运行的 owned child，报告未启动。避免“启动后才纳管”遗漏快速派生子进程。worker 通过 CreateProcess 创建的 WCH 子进程默认继承 Job；不用 WMI/外部调度器绕过。
- 当前 worker 的隐藏控制台捕获可保留；其后代属于本次 Job。记录进程句柄、PID、创建时间与 operationId；PID 文件仅用于诊断，不能成为杀进程授权依据。
- 每阶段固定 deadline（可沿用 download/verify 各 120 秒；检测、UAC/helper、重连与清理也须有明确上限，DIB 在配置/测试中固定数值）。到期原子置本次 FAILED，停止追加工作，所有迟到 ACK/结果按 operationId+generation 丢弃。
- supervisor 对本次 Job 调 TerminateJobObject，有限时等待进程句柄和 Job 活跃进程数归零；停止 reader/定时器、关闭自身句柄，保存结果，再释放维护会话。建议清理预算 5 秒作为工程初值，不能用无参数 waitFor/join 或无限轮询。
- 正常退出也确认该 Job 无残留子进程；用户点击“退出”幂等地执行同一清理路径，不启动第二次清理/重刷。不得 `taskkill /IM ...`、遍历并杀所有同名工具，或杀用户已独立打开的 WCH。
- 系统错误导致有限时内无法确认归零时，必须返回终态诊断（含 Win32 错误及 owned handles/PID 证据），允许关闭失败页，但不得假装已清理并重开烧录；明确要求重启应用/处理系统异常后重新开始。此异常不得退化为无限等待或后台自动再刷。OS 无法及时结束进程的情况不能在产品代码里假保证。

强制停止烧录进程不保证芯片完成写入，因此超时始终失败，下一次从选 HEX/物理 boot 开始。退出逻辑不会因迟到的成功输出改报成功。

系统依据：[Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)、[TerminateJobObject](https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-terminatejobobject)。这里只交实现方案，没有创建或终止任何进程。

## 5. 本机无设备验证与干净机限制

### 本轮已实际完成

- 16 项文件重新 hash 一致；13 落点清单与绝对来源已生成。
- x86 架构一致，23 项直接厂商导入符号与实际 DLL 导出匹配；R8 净化配置和文件身份保持。
- 静态查看现有 runtime/worker/USB/service/实际打包入口，定位外部工具默认、备份强制、无限 wait、旧正常态身份等冲突。
- 读取 CP2.5/CP2.6 intake 与决策，保留最新 Consumer 约束和 Firmware 交测限制。

### DIB 可在本机完成的非设备冒烟（尚未执行）

1. 配方 stage 到隔离目录，检查 13 文件和 generated metadata；删除/改坏 CH375DLL、配置、chip DB、driver CAT 的任一副本必须准备失败。安装源目录只读、路径含空格/中文仍可定位；runtime 副本不污染安装目录。
2. 无硬件的纯测试替身验证状态机：无普通 USB/备份仍可选 HEX→WAIT_BOOT；boot 缺驱动、多设备、UAC拒绝、259/3010、无版本、迟到成功、未知HEX读到任意有效版本等分支。替身 PASS 不冒充真机。
3. 用无设备行为的测试程序模拟 worker→child→grandchild：挂起、管道阻塞、父进程先退、生成晚到记录；验证 Job 超时清理、UI 响应、退出幂等、无无限等待。额外启动不属于 Job 的同名测试程序证明它不受影响。不要拿真实 WCH `-o download` 作“空载冒烟”，即使以为没有连接设备。
4. 不安装驱动即可测试 helper 参数拒绝、固定 exe/INF 路径与输入 hash、输出解析；真正 UAC 接受及驱动 staging 会改系统，不属于只读冒烟，另由正式授权测试执行。
5. 当前开发机已有 WCH/驱动，直接 DLL LoadLibrary、运行工具或“能检测设备”都不能证明独立闭包。非设备 fixture 可证进程托管；它不证明厂商 DLL 实际加载或 kernel driver 工作。

### 干净 Win10/11 必须另验（PENDING）

无 WCH 安装、无 CH375 driver store/系统 DLL 的 Win10/Win11 x64；记录系统版本、Secure Boot/内存完整性设置；普通用户安装 AhaKey后由应用 UAC 准备；断网验证自带依赖；检测实际 driver binding/problem-code，再完成双区擦除、verify、正常重连读版本。随后覆盖超时/拔线失败退出重来、未知有效 HEX、不经过 onboarding 的版本查询，以及升级后驱动/工具可用。不得在当前开发机卸载共享驱动伪造干净基线。

本轮没有厂商兼容性失败证据，也没有真实通过证据。没有驱动安装不意味着只能退回外部工具安装模式。许可事实、干净系统结果、固件真机结果分别记录，不混成一个 PASS。

## 6. DIB 修改点速查（不是本聊天改动）

|现有位置|要落实的边界|
|---|---|
|WchRuntimeLocator + runtime profiles|安装内 6 文件、driver 清单、封闭 hash 校验，去掉外部默认与固定5项|
|scripts/package-local-model.ps1|实际 EXE 配方带齐 runtime/driver，不拿开发机 DLL 偶然可用当包完整|
|WchFlashAdapter + wch-capture-worker.ps1|操作副本、精确输出、Job托管、有界超时和清理|
|FirmwareUpdateService + maintenance接口/UI|boot 起步、无需备份恢复、统一失败退出、版本读取成功、无onboarding门槛|
|UsbHidTransport.maintenanceDevices|设备存在/驱动就绪区分，boot首绑定与正常重连关联；枚举超时也清理 owned 辅助进程|
|K1相关保存入口（主线独立实现）|当前模式显式K1保存才ordinary+action，其它保存不覆盖Consumer；旧能力路径严格探测|

最终必须由主 DLA 按真实累计 diff/候选/实际安装包审阅。这个目录不授予生产写权限，不替任何构建或 UAT Gate。
