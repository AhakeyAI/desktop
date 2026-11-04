# WD-006 R9 独立高影响设计审阅

日期：2026-10-24（Asia/Shanghai）。角色：fresh DLA 独立设计审阅；接续主 DLA：01a1684d-3953-79d0-9cc6-57f397a595f9。

## 结论

**PARTIAL_BLOCK：整体方案可落实；发现一个局部、真实的 Firmware 协议闭合缺口 B1。** OTA、随包 WCH/驱动、烧录状态机、CP2.5 回归以及已有有效 route 的 CP2.6 适配可在主 DLA 正式 reconcile 后继续。不能把“无有效 route 时可直接单模式配置”或完整 CP2.6 交付标为已满足。没有需要 Owner 重新选择的产品方案。

本报告是设计审阅，不是实际累计 diff PASS、实现授权、Git candidate、EXE 可安装证明或 UAT。当前生产仍为先前实现；下面指出的既有代码缺口不能被误读为 R9 实现失败，必须在后续实现与实际审阅闭合。R8 仅为参考草稿，其 schema1、两个环境值及旧 bootstrap 版本建议均不再适用。

## B1：无持久 route 记录时，当前 0x9E 无法完成要求的单模式首次配置

严重程度：P1，局部设计/协议阻断；触发是整个 K1 store 没有有效记录，**不是**可正常读取的 ordinary 空动作。

证据来自正式 CP2.6 candidate `2f7c54a927410c59479307c1ebc2b0d20f236d97`，用只读 `git show` 交叉核对当前源文件：

- `APP/services/k1_restore_store.c:151-154` 的双槽无记录分支令 `s_usable=0`；`:209` 的 load 在不可用时返回 0，`:219` 的 read 同样失败。
- `APP/sub_main/command_solve.c:435` 的 read 将该结果映射成通用 FAIL；`:501` 的单模式 commit 必须先 load 全部 routes，失败即拒绝。capability 成功不代表 store 已存在；通用 FAIL 也不能区分无记录、损坏、restore pending 和其它失败。
- `APP/sub_main/main.c:951` 的启动投影不创建缺失记录。当前 APP 调用检索只发现 0x9E commit 调用 replace；没有可依据的自动创建分支。
- selector=0xFF 可以提供整个快照，但正式 registry 将它限定为明确全局初始化；当前 Owner 要求普通编辑只修改所选模式、无新增向导、Consumer 保留。Windows 不能用四个本地草稿偷偷初始化来绕过失败。

因此 R9 A 节“缺 route 可明确配置”若包含清空 DataFlash 后的无记录设备，与当前绑定协议不闭合。双区擦除后的首次配置正会触发该路径；这不影响烧录后只读实际版本即可成功的独立语义。

精确返回值：`command_solve.c:393-398` 定义统一 12 字节失败帧 `AA BB 9E 01 <request_version> <request_subcommand> <correlation:u32_le> CC DD`。合法 v1 read 无记录时为 `AA BB 9E 01 01 10 <nonce:4> CC DD`；即使 begin/chunk 已成功，单模式 commit 在 load 失败时为 `AA BB 9E 01 01 22 <token:4> CC DD`。第4字节 `01` 是 FAIL，不带 NO_RECORD 细分原因。这里是源码静态推导，不是本轮真实串口/USB捕获。能力响应可仍返回 flags=03、modeCount=04（`:425-429`），不能据此解锁无记录写入。

无需修改 Firmware 即可纳入本轮的安全边界：

|已观察事实|Windows 展示及动作|
|---|---|
|能力确认且有效 route 回读成功|按实际 ordinary/Consumer 展示；显式普通编辑可保存所选模式并读回|
|能力确认，但 0x10 返回匹配 FAIL|显示“K1 配置暂不可读取，无法确认当前设置”；禁止 K1 保存，保留草稿，不确定地标成“未配置”也不允许；可提供只读重试|
|读取超时/错 nonce/错 CRC/断连|显示读取失败或连接变化，禁写，迟到回调不解锁；不能降级旧写路径|
|只改 K2-K4/其它设置|不发 K1 旧写或 route 写，K1 未确认不应被全配置成功提示覆盖；其它项按各自许可与回读结果处理|
|发生未确认 commit|显示“保存未确认”，回读匹配才能确认成功；不得清 dirty 或自动重放 commit|
|全擦后正常 USB 重连且实际版本已读取，WCH download/verify均确认|可按既定语义显示烧录成功；K1 若读取失败独立显示不可配置，不把这两个结果混同|

上述禁写保护可以完成并验证，但不等于“无记录可配置”已交付；该完整可用承诺保持 **BLOCKED**。

**最小落实：** 主 DLA 在 reconcile 中保留该需求，单列 Firmware-side dependency。Windows 先实现精确 capability/read/write、支持有效记录的单模式编辑；read FAIL 显示不可确认/不可编辑，保留草稿，禁止退回旧 K1 写入及 0xFF 偷渡。由 Firmware 正式证据闭合“可辨识的无记录状态 + 明确单模式首次配置 + 其余模式保留/初始化规则”，或提供已批准且确实可到达的等价初始化路径；Windows 再按新证据适配。不得由本审阅或 DIB 修改 Firmware、发明状态码、要求用户完成 onboarding、删掉验收要求或将此分支假通过。只读重新发现后续合并候选即可，不让 Owner 搬路径/帧。

闭合测试：全擦无记录、已有 ordinary 空动作、已有混合 Consumer/ordinary、损坏记录、restore pending 分别覆盖；只有有依据的状态可写；成功修改当前模式且其它模式字节保持，重启回读一致。此依赖不能仅靠 mock 成功闭合。

## 可直接落地的实现约束（不是新增产品选择）

### K1 与 CP2.5

1. 绑定正式 reviewed_allocations 0x9E v1 和 candidate 实现：102 字节单记录、408 字节全快照、完整帧≤62、读片≤42、写片≤47。ordinary data 包含动作类型与长度；实际 store 接受 0x73/0x74，100 字节 data 上限包含该 envelope，原始动作最大 98 字节。不足以表达的动作必须明确拒绝，不能截断或复用旧 100 字节假设。
2. 读取整条 route 时匹配 nonce/mode/offset/total/CRC；多片 CRC 必须一致，最后校验整体 CRC。失败保留未知，不能成为普通空键。Consumer 展示实际 usage，无 Consumer 设置入口；显式普通动作编辑才将当前模式改为 ordinary。
3. `StudioState` 当前分开记录 dirtyParts 与 dirtyModes，这两集合不能推断准确的 `(mode,K1)` 修改集合。例如 A 模式改 K1、B 模式改 K2，不能因此重写 B 模式 K1。增加最小的按模式 K1 dirty/snapshot 跟踪，提交时冻结连接代次、mode、动作及描述；迟到回调不得覆盖切换后的 UI 或清除较新编辑。
4. 接通 `StudioController` 实际 connect/edit/save/verify 路径及 `DeviceSyncService.commandsForModes`，支持 route 时跳过未编辑 K1 的旧普通写入；旧 0x87 回读不能覆盖 Consumer 真相。保存后用 0x9E 回读匹配才确认；commit ACK 丢失先回读、不盲重放。读写串行且遵守维护锁/资源上传互斥；中断不可直接创建新的并行事务。
5. 严格 nonce/version/subcommand/flags/modeCount 与精确长度；generic ACK 不当支持。仅有据旧固件走旧路径，超时/未知/新能力错误不能降级成旧路径写 K1。0x96 不改 route，K2-K4 与侧拨语义保持。
6. CP2.5 gate 为机器 PASS；Owner 接受及三个定量债务沿 intake 保留。覆盖 USB/BLE 双向切换、配置连接与 HID readiness 区分、资源串行上传/背压/超时、断线重开，不做额外 BLE 架构重写。

### 软件 OTA

1. schema3 固定为 `schema/channel/version/windows.lite.url/windows.local-model.url`；来源仅三个白名单环境变量。两个形态共享 version，客户端选择已安装形态；缺形态/404/无效内容/网络失败不显示“已是最新”，不串包。schema2 若保留必须进入相同新签名验真链；schema3 不再强制 firmware.entries，不能猜远端固件身份来补空字段。
2. 采用固定公钥 RSA3072/SHA256withRSA 尾部封装；签名覆盖确定编码的原始 payload（用途/格式、EXE prefix 长度与摘要、产品、三段版本、形态、架构、UpgradeCode、实际 ProductCode）。私钥不进仓/日志/安装包，只保存于非仓专用受限目录，两个包公钥相同。没有 Owner 证书不是阻断。
3. DIB 必须先给出一个可审阅的字节格式与 Java/.NET 互操作向量：固定 magic/version、384 字节 RSA 签名、整数宽度和字节序、UTF-8/字段边界、EOF footer、envelope 上限及无溢出的 `prefix+envelope+footer=total`。拒绝重复/歧义字段、截断、尾随字节、未知算法与远端公钥。验原始 payload 字节，不解析后重序列化验签。此为工程实现细化，不需要 Owner 再选密码算法。
4. schema3 没有可信 size/hash，下载按本地硬上限流式写入并限制响应时间/体积；下载后依据签名中长度与摘要验全部 prefix，独立计算完整封装文件 hash/size 冻结给 worker。缓存和请求文件 hash 不能成为信任根。响应无 Content-Length 也要限量，取消/失败不进入 READY。
5. worker 内固定同一公钥，自行验签与实际 MSI 身份，持拒绝写删的文件锁直到安装器结束；不能使用 request 中的任意证书/public key/policy 覆盖。保留 ready→exit-permit→父 PID+启动时间退出→UAC→安装退出码/receipt→新版本真实身份核对。验签失败原应用继续运行，UAC取消/失败不得报已升级。
6. 允许工程证据确认的精确云存储主机与受限 HTTPS 跳转；不能泛放全部 `*.tcb.qcloud.la`。每跳验证、限制次数、拒绝 HTTP/用户信息/不受限目标，日志剔除 query。官网本轮仅准备，不部署；线上未就绪仅阻塞在线端到端验收，不阻塞离线实现。
7. 1.0.11 手装起点→1.0.12 OTA 目标可采用；两包同为完整模型版、同 UpgradeCode 与公钥，实际 app-release/MSI/签名版本分别一致。旧 1.0.10 空信任不承诺直接 OTA。MSI payload 追加前后相同仍须提取证明，覆盖安装和完整尾部 EXE 实际运行由授权 UAT 验证。未签名目录不能证明绝对最新性/防冻结，不作额外产品承诺。

### 随包工具与 HEX 烧录

1. 采用 r9-engineering 的 6 runtime 文件、7 driver 文件配方及 R8 STATIC_INPUTS；实际入口 `scripts/package-local-model.ps1` 必须带齐 x86 CH375DLL、芯片表和净化配置。使用安装内受验证输入，不扫描用户 WCH；构建时生成受信清单，提权 helper 不能接受可改请求指定新的信任根或任意 INF/命令。
2. 操作目录冻结合法 HEX/hash；每次复制 runtime 并复核，WCH 可写日志配置落本次目录。双区清除使用实际已查字段 `IsEraseAllCFlash=1/IsClearDataFlash=1`；其它保护位保持。未知 HEX 指版本未知，不是允许非法 Intel HEX/越界镜像。
3. boot 检测独立于普通 USB、BLE、旧 firmware/catalog/backup。枚举存在与驱动就绪分开；支持硬件 ID 以正式已确认集合为准，不因 INF 支持更多 VID 就扩产品支持。多台仅要求保留一台；点击写入前重新核对本次目标。驱动准备 UAC 拒绝/失败/需重启均不进入烧录。
4. 保留 download 与 verify 两阶段和明确终态解析；exit0/100%/含 Succeed 子串都不足。检测/准备不能自动写，点击仅启动一次；正常重连绑定同一物理目标及新代次，读真实版本，不能用旧缓存。未知 HEX 只称实际版本，onboarding 不作门槛，无强制备份/恢复分支。
5. 当前 `WchFlashAdapter:86` 的超时后无参数 waitFor 与 `FirmwareUpdateService` 的无限 UNCERTAIN 锁必须替换，不能只改提示。r9-engineering 的 owned Job/supervisor 方案可实施；进程纳管失败不得继续启动，含子孙进程、管道线程和迟到结果都须有界收尾。失败/超时不再恢复成功。退出只清理本次 owned processes，确认归零后才可重开；系统异常无法确认时返回诊断并阻止第二次烧录，不无限等待、不全局杀同名进程。
6. 厂商许可仍记录 authorization_not_verified；本报告无新增许可判断。不能据未知虚构允许或禁止。静态依赖闭合不等于干净系统驱动可用；开发机已装 WCH 不可替代该验收。

## 必须保留的交付与测试门

|范围|实现后必须获得的证据|本轮审阅状态|
|---|---|---|
|K1|精确帧/CRC/异常 ACK；混合 Consumer 保留；跨模式 dirty 及迟到回调；实际 UI save/回读；断线与 commit 不确定；B1 闭合|待实现/验证，B1 局部阻断|
|CP2.5|USB/BLE 切换、readiness、资源上传和恢复，既有定量债务不改 PASS|待实际回归|
|OTA离线|Java/.NET 交叉验签、错误公钥/版本/形态/MSI/损坏/截断/尾部；取消/上限/重定向；worker锁与握手/receipt|待实现/验证|
|完整包|两个真实模型 EXE；包内模型/JNI/BLE/WCH/driver/信任与版本身份；追加前后 MSI 摘要相同；隔离 GUI 冒烟|待实际构建，JAR 不替代|
|烧录离线|纯替身覆盖 boot 无旧连接、驱动异常、多设备、未知HEX、新代次版本、超时/退出/迟到成功；无设备测试进程树清理且无关同名程序不受影响|待验证，不启动真实 WCH download 冒烟|
|真实系统|手装覆盖、OTA安装/取消/配置保留、重启后身份；干净 Win10/11 自带驱动准备与检测；双区清除/verify/重连/超时重来|Owner待测，不由代码审阅代签|
|CP2.6正式配对|Firmware 正式允许交测的 CP2.6+WS4 Restore 合并 HEX、gate、candidate、实际 hash|外部交测前置，独立 CP2.6 REGATE PASS 不替代|

主 DLA 仍须完成实际增量及累计 diff 审阅、高影响实际实现审阅、精确 Git candidate、隔离构建与 Artifact/Firmware identity、完整测试包。不得复用本设计报告给新代码/EXE 记 review PASS。CP2.5 默认候选需重新准入；不能将独立 CP2.6 HEX 放入内置默认并称完整已验收。

最终交付步骤应直接提供两个 EXE 的绝对路径/版本/形态/SHA256；上传 1.0.12 完整签后包，准备并部署 schema3 官网接口的前提与准确三个环境变量。先将共享版本设 1.0.11 验证起点无更新，再同步切到 1.0.12 与目标 URL（两形态各自匹配，缺形态不造 URL），验证发现→下载→验签→退出安装→启动 1.0.12→再次检查→原配置保持；并列取消/损坏/网络/UAC失败预期。未部署期间这些步骤为计划，不标线上通过。HEX 测试另列完整既定动线与实际配对限制。

## 最小 reconcile 建议与权限

- 保留 R9 产品决定和本轮完整两包目标，正式 reconcile 引用本报告；修正 intake 中旧的“OTA 到 1.0.11”说明冲突，以新授权的 1.0.11→1.0.12 为准（保留原件历史）。DECISIONS 中旧 onboarding“讨论中”不覆盖最新明确决定。
- 把 B1 写入明确依赖/验收缺口；Windows 范围内可以先做安全禁写与其它实现，禁止把范围缩减当完成。Firmware 根只读，不自动发其它聊天消息。
- 主 DLA 交 DIB 的精确范围应包含 per-mode dirty/UI/protocol/parser、worker/公钥/封装脚本、包配方/驱动 helper/进程监督和有意义的行为测试；不要仅添加协议服务而漏实际入口。
- 本轮只保存本目录独立证据；未改 STATE/Contract/approval/生产/Firmware/eternal，未构建、测试运行、密钥生成、联网凭据访问、安装、烧录、杀进程或 Git 写。

证据字节身份、正式 gate/HEX 的本轮只读复核见 `R9_DESIGN_REVIEW.json`。当前源码的局部读取用于判断可行性与接入风险，未宣称完成全量代码审阅。
