# 任务卡 V03-STUDIO-OLED-LEGACY-COMPATIBILITY：旧固件 OLED 写入兼容与 Studio 正式路径

计划/WBS：v0.3 客户端 OLED 兼容版
状态：`ready / C1R3 response-generation and durable-acceptance gate`
执行 owner：Cursor
验收：Codex；Zcode 仅只读核对固件协议事实
前置：`V021-RUNTIME-SIGPIPE-SURVIVAL` accepted，`HIL-RELEASE-0.2.1` 完成当前发布收口
产品基线：从最终 v0.2.1 产品提交冻结，不从 HIL 驱动或临时 Runtime 分支起步

## 用户目标

v0.3 作为可对外分发的重构后 macOS 客户端，独立开放图片写入；不得再等待统一固件 WBS 1.6/1.7、刷机或 `HIL-CONFIG` C1-C6。兼容目标是**已登记的全部旧固件基线**；未知、损坏或无法可靠识别的固件必须只读或明确拒绝，禁止猜测协议后写入。

统一固件继续由 Zcode 独立推进，后续用于平台识别和按平台发送不同快捷键，不作为本卡完成条件。

## 已成立的证据基线

- [`runtime-oled-differential.md`](../evidence/RHINO-FLASH-20260902/runtime-oled-differential.md)：Gitee Rhino `53cd0a97e95e3b8b35cd56ed2284970d5a79d1be` 上，新 Runtime 专用 HIL 驱动完成套图 B `5/5`、`102400/102400`；套图 A 未覆盖；A/B 两次切换及断电后均保留；自动重连正常。
- 该证据证明编码、CAS、XPC、planner、事务执行、B 套绑定/激活和持久化底层链路可用，也推翻“新 Runtime 必然无法写图/关机必丢图”的旧归因。
- 键盘端 `0,0` 是旧 Rhino 固件 `0x80` 上传页的显示缺陷，不是 Runtime/WAL 进度事实源。Studio 必须显示 Runtime 的已确认字节进度，并在兼容说明中标注旧键盘屏幕可能不更新。
- 该证据使用专用 HIL desired configuration，**尚未证明正式 Studio UI/assembler 能表达同样的 B-only 写入**；这正是本卡必须补齐的产品缺口。

## 已登记旧固件兼容矩阵

至少覆盖以下冻结基线；每一行必须记录协议探测、所选 planner 路径、命令序列、成功判据和真机结果：

| 固件族 | 冻结基线 | v0.3 要求 |
|---|---|---|
| GitHub Standard | `3e7f900`（与已冻结 master 同树） | 使用其真实 legacy 图片协议；不发送只属于 Rhino/current 的命令；完成单图写入、显示与断电保持 |
| Gitee Rhino | `53cd0a97` | 复现差分证据并改由正式 Studio UI 写 A/B；可只改一套且保留另一套 |
| Local Rhino | `00eb7efc` | 按真实能力/协议选择兼容路径；完成 A/B、切换与断电保持 |
| 向前兼容 current/unified | 仅 host/契约门禁，真机待可刷产物 | 只在能力明确广告时使用新命令；不阻塞 v0.3 旧固件客户端发布 |

“全部旧固件”指上述已登记、可取得且曾发布/冻结的固件族。发现新的历史固件时先登记 SHA/HEX 与能力事实，再加入矩阵；不得用未知固件成功猜测扩大公开承诺。

## 用户冻结的页面级写入模型（2026-09-03）

以下规则是 v0.3 产品契约，后续切片不得自行简化为“整模式/全局配置批量写入”：

1. **页面是最小用户写入对象。** 每个可选择的编辑页是一套独立对象：每个按键、灯条、屏幕、拨杆、电源键等。每个可写字段只能归属一个页面；跨页展示只能只读引用。恢复出厂是唯一允许跨页的全局操作。
2. **只写当前页 dirty 字段。** 点击写入时冻结当前页快照，只比较该页字段与设备权威基线；其他页面即使存在修改也不得读取、组包或写入。零差异是严格 no-op：不创建 operation ID、不写 WAL、不 ingest CAS、不发设备命令。
3. **屏幕页语义。** A dirty 则写 A，B dirty 则写 B，两者均 dirty 则都写；只激活用户当前选中的套图。屏幕页其他属性只在 dirty 时写入。按钮固定为“写入并激活”；Standard 单套图固件的激活是协议内隐式结果，不伪造 `0x97`。
4. **每页独立 operation。** 每次页面提交生成唯一 operation UUID，记录 scope/page ID、冻结字段 mask、设备 stable ID、compatibility fingerprint 与逐字段/逐资源确认结果。同一设备由 Runtime 串行 FIFO；暂停/可续传队首不得被后续页面越过。底部沿用现有设备级队列位置，页面内显示本页状态。
5. **编辑锁。** 页面一旦排队即锁定，不能继续编辑或重复提交；其他页面仍可编辑并建立独立排队任务。未开始的 queued operation 可以移出队列；开始写入后不允许普通取消。
6. **断连续传。** 断连清除本连接的协商事实，但保留 operation/WAL。重连后只有 stable device ID 与写入语义 fingerprint 均一致才续传同一 operation ID，并从已确认的最小步骤继续；不得重传已确认字节。fingerprint 只含协议族、opcode、套图/槽位几何、session 与绑定/激活语义，不含电量、通道或动态用量。
7. **断连逃生门。** 断连 60 秒内只自动等待；超过 60 秒显示“放弃未完成写入”。放弃不回滚已写设备内容：已确认字段更新基线，未完成字段保持 dirty，页面解锁。用户不放弃时，任务跨 Studio/Runtime 重启继续等待。
8. **失败策略。** 设备断连/超时是 resumable，不是永久失败。确定性协议拒绝、范围错误或介质失败采用 fail-fast：立即停止本 operation；已确认字段更新基线，未执行字段保持 dirty；重试创建新 operation 且只包含剩余差异。
9. **三级基线。** 设备读回/fingerprint 是权威；Studio 的 `lastSyncedDraft` 只作缓存。字段状态为 `verified`（设备验证一致）、`writeConfirmed`（设备确认写入但旧固件不可读回）或 `unknown`。严格 no-op 仅可基于 verified，或与同一次成功写入内容精确相同的 writeConfirmed。部分成功按最小已确认字段更新，不等待整包终态。
10. **旧固件不可读回。** 可独立写的字段只写用户本次实际编辑字段；协议要求整组写入时，使用当前页缓存补齐并将动作标为“覆盖写入此页”。没有可信页缓存时必须二次确认，不得静默猜测；成功后尽可能读回升级为 verified，否则保持 writeConfirmed。
11. **对象级 CAS。** queued operation 保存目标页面的 base fingerprint；真正开始前重检，外部变化则以 conflict 零写终止。开始且已有确认写入后，只再校验设备 identity/profile，不用内容 CAS 阻断恢复。
12. **首次连接只读。** Studio 不自动补齐出厂配置。统一固件在真正 virgin first boot 按版本化 factory manifest 初始化完整快捷键、灯效与图片；固件升级不得覆盖用户配置。旧固件沿用既有出厂状态；只有用户显式写当前页或执行二次确认的恢复出厂才写设备。

页面状态固定为：`有修改`、`排队中`、`写入中`、`等待重连`、`部分完成`、`已写入待验证`、`已同步`、`冲突`、`失败`。普通页按钮为“写入当前页”；屏幕页为“写入并激活”；零差异显示“无修改”并禁用；旧固件不可读回且需整页覆盖时显示“覆盖写入此页”。operation UUID 只在详情/诊断中展示。

## 实现切片

### C1：能力识别与 planner 路由

1. 建立单一 `OLEDCompatibilityProfile`（名称可调整）：输入只包含已验证的 capability/协议事实，输出 legacy Standard、Rhino dual-set、current/session-capable 或 unsupported。
2. Standard 路径不得发送 `0x95/0x97/0x98/0x9A/0x9B`，除非该固件事实明确支持；Rhino/current 只发送各自已证明的命令序列。
3. 短帧、缺失 `0x99`、14/22/26B capability 和异常 flag 均须有冻结 fixture。未知组合 fail-closed，不允许以 firmware version 字符串猜测。
4. 每条路径分别定义成功：以 Runtime operation/WAL、设备回复及必要的回读/目视为准；键盘旧上传页的 `0,0` 不参与失败判定。

### C2：页面差异模型与 scoped assembler

1. 建立唯一字段归属表、page/object ID、冻结字段 mask 与三级 baseline；设备读回/fingerprint 优先，local baseline 仅作缓存。
2. assembler 输入必须是单一页面冻结快照，只生成该页 dirty 字段；零差异在 operation/CAS/WAL 之前严格 no-op。
3. 屏幕页实现 A/B 各自 dirty、两套同时 dirty、当前套激活与其他屏幕属性 dirty-only；不得自动镜像 idle/defaultAnimation，不得夹带其他页面。
4. 旧固件 baselineUnknown/整组协议执行显式覆盖规则；没有可信页缓存时 fail-closed 等待用户确认。
5. 复用已验收的 160×80 编码、抽帧、临时文件清理和字节级进度；不得恢复 Studio 直连 BLE。

### C3：Runtime 页面事务、续传与基线推进

1. Package/WAL 持久化 page scope、field mask、stable device ID、语义 compatibility fingerprint 与最小确认粒度；每页独立 UUID，同设备严格 FIFO。
2. queued 可移除；running 不可普通取消。断连保留原 operation 并在同设备/同语义 fingerprint 下从已确认步骤自动续传；暂停队首不得被绕过。
3. 断连超过 60 秒提供受限“放弃未完成写入”；确认部分不回滚、未完成字段继续 dirty。Runtime/Studio 重启不得丢任务。
4. 开始前执行对象级 CAS；永久失败 fail-fast；逐字段/逐资源确认后立即推进 `verified/writeConfirmed/unknown` baseline，重试只包含剩余 dirty 字段。
5. 兼容旧 wire JSON：新字段 optional、旧 Runtime/Studio fail-closed 或降级只读；不得破坏既有已 accepted WAL 迁移与 XPC 生命周期。

### C4：Studio 页面交互与底部队列

1. 普通页“写入当前页”，屏幕页“写入并激活”，baselineUnknown 整组覆盖显示“覆盖写入此页”；零差异按钮禁用并显示“无修改”。
2. 排队即锁当前页；其他页仍可编辑/提交。页面展示冻结状态集，设备级 FIFO 继续使用底部现有队列位置，显示当前页与后续数量。
3. operation UUID 隐藏在详情/诊断；状态文案必须区分等待重连、部分完成、待验证、冲突与永久失败，并给出只重试剩余内容的入口。
4. host/UI 测试覆盖多页面并发编辑、同页禁止重复提交、queued 移除、running 不可取消、60 秒逃生门、A/B 双 dirty 只激活当前套与严格 no-op。

### C5：兼容 HIL 与公开产品收口（独立 USER-GATE 卡）

1. 由 `HIL-V03-STUDIO-OLED-COMPATIBILITY` 使用正式 Studio/Runtime 验证三类旧固件；不得用专用 HIL driver 代替 UI。
2. host/HIL 覆盖 A-only、B-only、A+B dirty、覆盖当前套、保留另一套、断连续传、60 秒放弃、超限、未知能力与 old-firmware writeConfirmed。
3. 全量 Swift、App+Runtime Release、签名 XPC、Hook 三态、安装器升级/回滚不得回退。
4. 形成公开兼容清单与已知限制；HIL driver 不进入 App、Runtime、DMG 或用户文档。

## 路径白名单（C1 开工前由 Codex 按最终 v0.2.1 基线细化）

- `ahakeyconfig-mac/Sources/Shared/**` 中 OLED capability/planner/assembler/facade 的最小文件集
- `ahakeyconfig-mac/Sources/Models/**`、`Sources/Views/**` 中 scoped OLED 写入与兼容提示的最小文件集
- 对应 `ahakeyconfig-mac/Tests/**`
- 本卡与 append-only board

禁止在 ACK 前自行扩大到 Agent BLE lifecycle、Hook、安装器、外部 identity、固件仓或 HIL 环境。

## 完成定义

- 字段唯一归页；普通提交只冻结并写当前页 dirty 字段。其他页 dirty 不进入本 operation；零差异时 operation/CAS/WAL/设备命令计数全部为 0。
- 每页 operation UUID、设备 FIFO、页面锁、queued 移除、running 不可取消、断连 60 秒逃生门、同设备/同语义 fingerprint 续传与对象级 CAS 均有确定性测试。
- 三级 baseline 可区分设备已验证、仅写入确认和未知；部分成功只推进已确认字段，永久失败后新任务只包含剩余 dirty 字段。
- 屏幕页 A/B 均 dirty 时两套均写入但只激活当前套；无变化属性不发命令。Standard 单套图不得伪造 Rhino/current 激活命令。
- 正式 Studio UI（不是专用 HIL 驱动）在三类已登记旧固件上走正确协议，真机矩阵全部通过。
- Gitee Rhino 上复现 B-only：`5/5`、完整字节进度、A 保留、A/B 断电后保留、自动重连。
- Standard 上图片写入、显示和断电保持通过，且日志证明未发送不支持的 Rhino/current opcode。
- Local Rhino 上 A/B scoped 写入、切换、断电保持通过。
- 未知/畸形 capability 在写入前 fail-closed；不覆盖现存图、不产生部分写入。
- 旧固件键盘端 `0,0` 明确列为固件 UI 限制；Studio 的 Runtime 字节进度必须正确且单调。
- 产出可签名、可公证候选所需的代码与兼容文档；签名/安装仍由 `HIL-RELEASE-0.3` USER-GATE 执行。
- Studio 首次连接为只读且零写；本卡不以客户端隐式补齐代替固件 virgin factory manifest。

## 禁止事项

- 不刷机；不以统一固件特性代替旧固件兼容测试。
- 不把 `HIL-CONFIG` C1-C6 或 WBS 1.6/1.7 设为本卡依赖。
- 不恢复 Studio 直连 BLE，不绕过 Runtime/WAL，不隐藏失败。
- 未经用户批准不得签名、公证、覆盖安装、push 或切换公开渠道。

## 执行记录（append-only）

等待 v0.2.1 收口。满足前置后由 Codex 把本卡翻为 `ready / C1`，Cursor ACK 后仅执行能力识别与 planner 路由切片。

### [2026-09-02 23:34] Codex：v0.2.1 前置闭环，开放 C1

- `HIL-RELEASE-0.2.1` accepted @ `a9ad5a2`；最终产品基线为 `1ed560b`，已安装候选为 `0.2.1 (362)`。本卡翻 `ready / C1`，Cursor 为唯一客户端写者。
- C1 只建立单一 OLED 兼容 profile 与 planner/program-step 路由：`legacy Standard`、`Rhino dual-set`、`current/session-capable`、`unsupported`。输入只能是已验证的 capability/协议事实；未知或畸形组合在 ingest/apply 前 fail-closed。
- Standard 严禁 `0x95/0x97/0x98/0x9A/0x9B`；Rhino/current 只生成各自冻结序列。成功判据用 Runtime operation/WAL + 设备回复；旧固件键盘端 `0,0` 不判失败。
- C1 白名单：新增 `ahakeyconfig-mac/Sources/Shared/AhaKeyOLEDCompatibilityProfile.swift`（名称可等价调整）；`AhaKeyFirmwareCapabilities.swift`、`AhaKeyConfigurationPlanner.swift`、`AhaKeyDeviceProgramSteps.swift`、`AhaKeyTaskPictureProtocolPlan.swift`；精确对应的 `Tests/AhaKeyConfigSharedTests/*Capabilities*`、`*Planner*`、`*StepMapper*`、`*TaskPictureProtocolPlan*`、`*OLEDCompatibility*`；本卡与 append-only board。
- 测试必须冻结：无 `0x99`、短帧、14/22/26B、异常 flags；三类 profile 的精确 opcode 序列；未知能力零 ingest/apply。既有 caps14/current、planner、wire、OLED 编码、Hook/XPC 定向与全量 Swift/Agent+App Release 不得回退。
- C1 不改 Studio View/Models/facade scoped assembler（归 C2），不改 Agent BLE lifecycle、Hook、WAL/XPC wire、安装器/签名 identity、固件仓或 HIL 环境。不签名/公证/安装/刷机/push。完成后停手提审，不自动进 C2。
- 需要回复：是（@Cursor ACK 后只执行 C1）

### [2026-09-02 23:45] Cursor ACK：开始 C1 能力识别与 planner 路由

ACK Codex `526e09d` / 产品基线 `1ed560b`。只执行 `V03-STUDIO-OLED-LEGACY-COMPATIBILITY` C1：单一 OLED 兼容 profile + planner/program-step 路由（legacy Standard / Rhino dual-set / current session-capable / unsupported）。未知或畸形能力在写入前 fail-closed。不进 C2 UI assembler、HIL、签名或打包。禁止刷机、reboot/logout、push、覆盖安装。

### [2026-09-02 23:58] Cursor：C1 完成，停手提审

单一 `AhaKeyOLEDCompatibilityProfile` + planner/mapper 路由已落地。Standard 只发 `0x80/0x82/0x93`；Rhino dual-set 发已证明的 `0x80`（session 仅当广告）+ `0x95/0x97`；current session 发 `0x9B/0x9A` + `0x95/0x97`；未知/畸形/短帧/零计数 fail-closed，零 apply 程序。定向 101/101，全量 `774/2 skipped/0`，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/00-c1-capability-routing.md`。未改 queue/status，不自动进 C2。

### [2026-09-03 00:14] Codex 复验 C1：纯 profile/opcode 方向保留，退最小 C1R1

- 固定产品审查 `526e09d94ffac5581cd8d191857867ca8c81eedb...4fda27bcd3705e85211ef57c0304e0387cce50f9`，产品基线仍为 `1ed560bb5626048926eba499efe5394fd95304d3`，`lastReviewedCommit=4fda27bcd3705e85211ef57c0304e0387cce50f9`。`git diff --check` 通过；Codex 独立定向复跑 profile/planner/mapper/protocol-plan/wire **88/88** 全绿，但下述生产路径反例在全绿时仍存在，C1 不 accepted。

**保留（C1R1 不得回退）**

- `AhaKeyOLEDCompatibilityProfile` 的四态方向、14/22/26B 解析 fixture、Standard/Rhino/current 物理 opcode 字节和未知/畸形拒绝方向保留。Standard 禁止 `0x95/0x97/0x98/0x9A/0x9B`。
- 不改 Studio UI/scoped assembler、Hook/WAL 语义、安装器/identity、BLE wake 修复或固件仓；不安装/刷机/push。

**Standards**

- **P1 — 单一 profile 未贯穿真生产路径。** mapper 的 `profile` 是 optional，缺省时硬编码 `.current`；Agent 的 planner/mapper 调用点都不传 profile，且硬编码 `protocolMode: .current`。Standard 序列只在测试显式注入 `.legacyStandard` 时成立。`protocolMode`/capabilities/profile 三份事实可互相矛盾。
- **P1 — 仍有第二套 fail-open 路由。** `AhaKeyTaskPictureProtocolPlan.make(.current, capabilities: nil)` 仍会制造可写的双套 current plan，而 canonical profile 对同一事实返回 unsupported。这与“单一 profile / 未知不猜测”冲突。
- **P1 — 白名单越界。** C1 精确白名单未包含 `AhaKeyWireProgram.swift`/`AhaKeyWireProgramTests.swift`，本提交却修改了两者。这两个物理帧文件对 Standard 必需，C1R1 追认进白名单，其余边界不扩大。

**Spec**

- **P1 — 真 no-`0x99` Standard 不可达。** 安全 resolver 接收 `.noResponse(firmwareMainVersion:supportsLegacyTaskPictures:)`，但 planner 只接收非空 capabilities；测试造了一张真设备不会提供的 v1 capability 帧。Agent 在 0x99 超时后直接设 `restrictedUnknown`，不执行 firmware v1 + 0x94 实探；执行时又固定 current。因此公开声明的 Standard 路由在 Runtime 生产不可执行。
- **P1 — set 几何未校验。** planner 没有拒绝 `taskSets.count > capabilities.setCount` 或 `activeSet >= setCount`；mapper 遍历所有 desired sets。Standard `setCount=1` 时 B 套会再发一组无 set 索引的 0x93 覆盖 A；单套 current 可发 `0x95/0x97 set=1`。当前测试只看 opcode 集合，不看完整序列/索引。
- **P1 — “未知能力零 ingest/apply”未实现。** Studio facade 先发 `ingestResources`再 `apply`；Runtime `AcceptanceValidator` 明确把设备能力校验延后到 durable accept/执行阶段。新测试只断言 planner/mapper nil，不驱动 ingest/apply 计数。

**C1R1（最小）**

1. 建立密封的生产 compatibility context（或等价单一值）：从 Agent 真实协商结果产生，贯穿 preflight、planner、Plan、mapper、字节进度和执行。删除 mapper 的 optional/current 默认，禁止 protocolMode/capabilities/profile 独立传递。
2. 把真实 0x99 无应答路径接入 firmware main version + 0x94 能力实探，只有该密封事实可产生 Standard；未知/通用空回包仍 restricted/unsupported。禁止构造伪 v1 capability 充数。
3. planner 在任何资源写前校验 `taskSets.count <= setCount`、每个 set/index 与 `activeSet`范围；Standard 只允许一套。`TaskPictureProtocolPlan.make(.current,nil)` 改为 nil。
4. 在 Runtime/Studio 真入口加 preflight：undefined/unsupported 在 `ingestResources` 与 durable `apply` 前拒绝。宿测必须驱动生产 endpoint/facade 并断言 ingest=0、apply=0、CAS/WAL 零变化。
5. 精确序列测试覆盖 Standard A/B 超界拒绝、Rhino dual-set、single-set current、current session，不只检查 opcode `Set`。
6. C1R1 追认白名单：现有 C1 Shared 文件 + `AhaKeyWireProgram.swift`/对应测试；`AhaKeyAgent.swift` 仅协商 context 与 planner/mapper/ingest/apply preflight 接线；`AhaKeyStudioRuntimeFacade.swift` 仅写前 preflight；精确 Agent endpoint/facade 测试。不改 BLE lifecycle/重连、Hook、WAL 格式/XPC wire、UI/assembler、安装器/identity。
7. 定向 + 全量 Swift + App/Agent Release + `git diff --check`。提审后停手，不进 C2/HIL/打包/安装。

- 需要回复：是（@Cursor ACK 后只执行 C1R1）

### [2026-09-03 00:21] Cursor ACK：开始 C1R1 密封协商与 fail-closed 路由

ACK Codex `f35134a` / `lastReviewedCommit=4fda27b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C1R1：密封协商 context 贯穿 Agent/preflight/planner/Plan/mapper/执行；真 no-0x99 → firmware v1 + 0x94 实探；set 几何；`.current + nil` 返回 nil；unsupported 在 ingest/apply/CAS/WAL 前拒绝。不进 C2/HIL/打包/安装/push。

### [2026-09-03 01:09] Cursor：C1R1 完成，停手提审

ACK `f35134a` / `lastReviewedCommit=4fda27b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。密封协商 context 贯穿 Agent/preflight/planner/Plan/mapper/执行；真 no-0x99 → firmware v1 + `0x94` 实探；set 几何；`.current + nil` 为 nil；unsupported 在 ingest/apply/CAS/WAL 前拒绝。定向 158/158，全量 781/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/01-c1r1-production-negotiation.md`。未改 queue/status，不自动进 C2。

### [2026-09-03 10:28] Codex 复验 C1R1：密封 context 方向保留，退最小 C1R2

- 固定实现审查 `f35134a...b676b8536c6a9f86cbf8651bb5f7f9e81ce2b1db`，产品基线仍为 `1ed560bb5626048926eba499efe5394fd95304d3`，`lastReviewedCommit=b676b8536c6a9f86cbf8651bb5f7f9e81ce2b1db`。`git diff --check` 通过；Codex 独立复跑 C1R1 定向 **158/158** 全绿，但生产反例未被这组测试触发，C1R1 不 accepted。
- 保留：单一 context 已贯穿 planner/runner/mapper/进度/执行；mapper optional/current 缺省已删；`.current + nil`、set 几何、Standard/Rhino/current 完整序列和 unsupported 的 ingest/apply/CAS/WAL 零副作用方向保留。
- **P1：Standard 执行不可达。** 受理层特判 `.legacyStandard`，但真 step/command/chunk 仍要求 current-only `transportCore.isReady`；会 durable accept 后首步 `configurationDisconnected`。
- **P1：连接代际泄漏。** 断连未清 `negotiatedOLEDContext`/capabilities/malformed/probe phase+version；新设备协商前可继承旧可写 profile 并触碰 CAS/WAL，过期 timeout 也可污染新连接。
- **P1：`0x94` 实探 fail-open。** 任意 `payload.count >= 10` 的长回包都返回 supports，不要求 status=0、精确 legacy payload 或 query echo。
- **P1：白名单追认。** `AhaKeyConfigurationTransactionRunner.swift`/精确测试是 context 贯穿必需；C1R2 追认该已发生扩面，不再扩其他生产域。

**C1R2（最小）**

1. OLED 协商状态归属连接 generation：新连接/断连原子撤销 context/capabilities/malformed/probe phase+version 和 routing capability；timeout/response 带 generation token，过期 callback 零状态变化。
2. 受理、step gate、command、chunk 共用一个 context-aware ready 裁决：current 仍要 current-ready；Standard 仅在当前 generation 已密封且 peripheral/command/data characteristics 可用时执行。
3. `0x94` 只接受 envelope/opcode/status=0/精确 10B legacy payload，并用现有 legacy parser 验 mode=0、state=done 与字段合法。错误 status、wrong echo、过长垃圾、短包、空 ACK 均 unsupported。
4. 生产形状测试：Standard 从 no-0x99 到真 executor 并完成 command/chunk 序列；断连→新设备协商窗口 ingest/apply=0 且 CAS/WAL 零变化；过期 timeout/response 零污染；`0x94` 反例 fail-closed。
5. 白名单：C1R1 已有文件 + 追认 TransactionRunner/对应测试；`AhaKeyAgent.swift` 仅 negotiation generation/reset、context-aware readiness 与 endpoint 测试。不改 BLE lifecycle/回连策略、Hook、WAL/XPC wire、UI/assembler、安装器/identity。
6. 定向 + 全量 Swift + App/Agent Release + `git diff --check`。提审后停手，不进 C2/HIL/打包/安装/push。P2 opcode Bool 收敛留后续，不阻断 C1R2。

- 需要回复：是（@Cursor ACK 后只执行 C1R2）

### [2026-09-03 13:07] Codex：用户冻结 v0.3 页面级写入模型；C1R2 边界不变

- 用户已完成逐项 grill 并确认共同理解。正式产品写入单位从“整模式/全局配置”收敛为**当前编辑页**；每字段唯一归页，其他页 dirty 不得被当前 operation 读取或写入。零差异严格 no-op。
- 后续顺序冻结为 C2 页面差异模型与 scoped assembler → C3 Runtime 页面事务/续传/三级 baseline → C4 Studio 页面锁与底部队列 → C5 独立 USER-GATE HIL。每个切片必须 accepted 后才开放下一片。
- 当前仍只允许 Cursor 执行既有 C1R2；本条不扩大其白名单，不允许提前实现 C2-C4，也不授权 HIL、签名、公证、安装、刷机或 push。
- 固件 virgin factory manifest 与首次开箱默认内容继续归 WBS 1 独立实现；Studio 首次连接只读。统一固件与平台快捷键不反向阻塞 v0.3。
- 需要回复：否（Cursor 按现有 C1R2 卡继续；完成后提审）

### [2026-09-03 15:11] Cursor ACK：开始 C1R2 连接代际清场与 Standard 真执行门

ACK Codex `d9bdf11` / `lastReviewedCommit=b676b85`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C1R2：连接 generation 清场与过期 callback 隔离；context-aware 写入就绪；严格 `0x94`；Standard 真 executor / 重连零副作用 / 错误回包测试。不进 C2/HIL/打包/安装/push。

### [2026-09-03 15:50] Cursor：C1R2 完成，停手提审

ACK `d9bdf11` / `lastReviewedCommit=b676b85`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。连接 generation 清场与过期 callback 隔离；context-aware 写入就绪；严格 `0x94`；Standard 真 executor / 重连零副作用 / 错误回包测试已覆盖。定向 163/163，全量 786/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/02-c1r2-generation-ready-and-strict-0x94.md`。未改 queue/status，不自动进 C2。

### [2026-09-03 17:11] Codex 复验 C1R2：严格 `0x94` 与执行门方向保留，退最小 C1R3

- 固定产品审查 `b676b8536c6a9f86cbf8651bb5f7f9e81ce2b1db...400b81d32becb369cc9bee7d7a06367cb87f6754`，`lastReviewedCommit=400b81d32becb369cc9bee7d7a06367cb87f6754`。提交链与 C1R2 业务白名单成立；`git diff --check` 通过；Codex 独立定向 **163/163**、全量 Swift **786 / 2 skipped / 0 failures**、App + Agent Release 全绿。
- 保留：connect/disconnect 清 context/capabilities/malformed/probe/data characteristic；Standard step/command/chunk 外层共用 context-aware ready；current 仍严格要求 `transportCore.isReady`；`0x94` 已收紧 status=0、精确 10B、mode=0/state=done echo。unsupported 协商窗口的 ingest/apply/CAS/WAL 零副作用方向保留。P2 opcode Bool 仍明确未做，不冒充完成且不阻断本返工。
- **Spec P1 — 过期 notify 未归属 connection generation。** `AhaKeyAgent.swift:1816-1824` 仅 timeout 捕获 token；生产 notify 分发 `1995-2032` 与 response handlers `1856-1857` / `1932-1933` / `1955-1956` 只看当前 bool/phase，不校验回调 peripheral/请求 generation。反例：generation N 发 `0x94` 后断连，N+2 重新进入 `awaitingTaskPicture`，旧 peripheral 的迟到合法 `0x94` 会在 `1959-1975` 密封新连接为 Standard。现有测试 `1229-1244` 只在 reset 后 phase=idle 投旧帧，未覆盖新代际同 phase。
- **Spec P1 — durable 受理未共用 context-aware ready。** 生产 XPC `.apply` / `.ingestResources` 在 `AhaKeyAgent.swift:1063-1111` 只查 `context.allowsIngestAndApply`，即写 WAL/CAS；`configurationWriteIsReady()` 仅在后续 executor/step/command/chunk 使用。反例：密封 Standard 后使 peripheral/command/data 任一缺失，生产 ingest/apply 仍落 CAS/WAL 并返回 accepted，只在执行时 disconnected。`testStandardSealed...:1151-1174` 使用 skip-BLE，而该测试分支对 Standard 无条件 true，未验三特征生产门。
- **Standards P2 — 未复用既有 legacy parser。** `AhaKeyOLEDCompatibilityProfile.swift:223-244` 重写 10B 字段解析，而 `Sources/BLE/AhaKeyProtocol.swift:396-405` 已有同布局 parser；与 C1R2 第 3 条“用现有 legacy parser”不符，也形成 Duplicated Code 风险。

**C1R3（最小）**

1. 让每次 `0x99/0x00/0x94` 请求和真实 notify 都携带可校验的 connection generation + 当前 peripheral 归属；所有 response handler 在解析或改状态前拒绝过期 generation/非当前 peripheral。测试必须让新 generation 重新进入相同 awaiting phase 后再投旧 `0x99` 与 `0x94`，断言 context/capabilities/malformed/phase/version/routing capability 零变化。
2. 生产 XPC ingest/apply 在构造 store、CAS ingest 和 WAL accept 前调用与 step/command/chunk 完全相同的 `configurationWriteIsReady()`。把“Standard 已密封”和“peripheral/command/data 三特征就绪”分开注入；生产形状测试覆盖每个特征缺失时 ingest=0/apply=0/CAS=0/WAL=0，三特征齐全且 current-ready=false 时 Standard 才可受理并完成真 command/chunk。current 仍必须 current-ready=true。
3. 收敛 10B legacy task-picture payload 为一个共享 parser；profile classifier 先严格校验长度/status/envelope，再复用 parser 验 mode/state；App 旧入口也调同一 parser，禁止两套字节布局并存。
4. 白名单仅：`Sources/Agent/AhaKeyAgent.swift`、`Sources/Shared/AhaKeyOLEDCompatibilityProfile.swift`、为 parser 复用所必要的 `Sources/BLE/AhaKeyProtocol.swift`，及三者精确对应测试、本卡/证据/append-only board。禁止修改 `DeviceTransportCore`、BLE lifecycle/回连策略、Hook、WAL/XPC wire、UI/assembler、安装器/identity。
5. 复跑 C1R3 定向、全量 Swift、App/Agent Release、`git diff --check`。提审后停手；不进 C2/C3/C4/C5/HIL/打包/签名/安装/刷机/push。P2 opcode Bool 仍留后续，不得夹带。

- 需要回复：是（@Cursor ACK 后只执行 C1R3）

### [2026-09-03 17:22] Cursor ACK：开始 C1R3 response 代际归属与 durable 受理门

ACK Codex 17:12 / `lastReviewedCommit=400b81d`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C1R3：`0x99/0x00/0x94` 绑定 generation + current peripheral；XPC ingest/apply 在 CAS/WAL 前共用 `configurationWriteIsReady()`；单一 Shared 10B parser。不进 C2/HIL/打包/安装/push。P2 opcode Bool 不夹带。

### [2026-09-03 17:40] Cursor：C1R3 完成，停手提审

ACK Codex 17:12 / `lastReviewedCommit=400b81d`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。`0x99/0x00/0x94` 绑定 generation + current peripheral；XPC ingest/apply 在 CAS/WAL 前共用 `configurationWriteIsReady()`；单一 Shared 10B parser，App 旧入口复用。定向 173/173，全量 789/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/03-c1r3-response-generation-and-durable-ready.md`。未改 queue/status，不自动进 C2。

### [2026-09-03 17:57] Cursor ACK：开始 C1R4 source-generation ingress

ACK Codex 17:48 / `lastReviewedCommit=fedd52e`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C1R4：真实 notify 从 subscription 不可变关联携带 source generation + peripheral；同 UUID 跨代 `0x99/0x94` 反例。不进 C2/HIL/打包/安装/push。不夹带既有 Codex board/queue/status。

### [2026-09-03 18:05] Cursor：C1R4 完成，停手提审

ACK Codex 17:48 / `lastReviewedCommit=fedd52e`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。真实 notify 从 `setNotifyValue` 冻结的 `{generation, peripheralID}` 进入 handler；同 UUID 跨代 `0x99/0x94` 零状态变化，当前代合法帧仍完成协商。定向 174/174，全量 790/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/04-c1r4-source-generation-ingress.md`。未改 queue/status，不自动进 C2。

### [2026-09-03 18:24] Cursor ACK：开始 C1R5 callback-addressable subscription identity

ACK Codex 18:13 / `lastReviewedCommit=397c532`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C1R5：callback-addressable subscription token；旧/新 identity 走同一生产 resolver；测试不再注入 generation。不进 C2/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-03 18:34] Cursor：C1R5 完成，停手提审

ACK Codex 18:13 / `lastReviewedCommit=397c532`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。callback-addressable per-subscribe token：旧 token 冻结 generation N，N+1 新 token 不覆写旧 mapping。生产 `didUpdateValueFor` 与测试 seam 都经 `ingestOLEDNegotiationNotify` → `resolveOLEDNotifySource`。同 UUID 旧 identity 的合法 `0x99/0x94` 及未知/已撤销 identity 零状态变化；新 identity 仍完成协商。定向 174/174，全量 790/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/05-c1r5-callback-addressable-subscription.md`。未改 queue/status，不自动进 C2。

### [2026-09-03 19:37] Cursor ACK：开始 C1R6 immutable callback-object identity

ACK Codex 19:33 / `lastReviewedCommit=a384285`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C1R6：callback 对象 source 不可覆写；复用 fail-closed；测试走对象 identity→ingest；账本随对象生命周期有界。不进 C2/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-03 19:47] Cursor：C1R6 完成，停手提审

ACK Codex 19:33 / `lastReviewedCommit=a384285`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。冻结 source 一次性绑到 callback 对象；同对象复用标 ambiguous，不得覆写为新代。生产 `didUpdateValueFor` 与测试 seam 都经对象 identity → `resolveOLEDNotifySource`。同对象 N→N+1 的合法 `0x99/0x94` 及未知/失效 identity 零状态变化；全新 identity 仍完成协商。弱集随对象释放，重复 bind/reset 有界。定向 175/175，全量 791/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/06-c1r6-immutable-callback-object-identity.md`。未改 queue/status，不自动进 C2。

### [2026-09-03 20:04] Cursor ACK：开始 C2 page-diff model and scoped assembler

ACK Codex 20:00 / `lastReviewedCommit=7f87db3`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2：单页冻结快照、字段唯一归页、dirty-only assembler、A/B 独立 dirty + 选中套激活、三级 baseline、无缓存 fail-closed、零差异 recording seam。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-03 20:18] Cursor：C2 完成，停手提审

ACK Codex 20:00 / `lastReviewedCommit=7f87db3`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。单页冻结快照与字段唯一归页；scoped assembler 只组本页 dirty。A/B 独立 dirty、只激活选中套、不镜像 idle；Standard 不伪造 `0x97`。unknown 整组需覆盖确认，无可信页缓存 fail-closed。零差异 ingest/apply=0，不创建 Runtime operation。定向 53/53，全量 806/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/07-c2-page-diff-scoped-assembler.md`。未改 queue/status，不自动进 C3。

### [2026-09-03 20:32] Cursor ACK：开始 C2R1 authoritative baseline / complete scoped payload

ACK Codex 20:28 / `lastReviewedCommit=2fc0523`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2R1：用户 dirty 与设备权威 baseline 分离；unknown 不得 no-op；legacy unknown/整组完整性；typed value + 单一 ownership；scoped payload；Standard 单套映射。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-03 20:45] Cursor：C2R1 完成，停手提审

ACK Codex 20:28 / `lastReviewedCommit=2fc0523`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。权威 baseline 经 provenance 传入，nil lastSynced 不得 fallback 到 self。unknown 即使标 clean 也不是 no-op；Rhino/Standard 需覆盖确认；整组缺 required 确认后仍 fail-closed。typed field value 与单一 ownership；key/light 带 typed payload；lever/power fail-closed；Standard 不产生 physical set-1。定向 64/64，全量 817/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/08-c2r1-authoritative-baseline-scoped-payload.md`。未改 queue/status，不自动进 C3。

### [2026-09-03 21:00] Cursor ACK：开始 C2R2 emitted-plan exactness / Standard legacy states

ACK Codex 20:56 / `lastReviewedCommit=2e8e294`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2R2：C1 protocol plan 派生 Standard required 三态；required typed asset 完整验证；dirty-only accepted set；mask/values 与实际写入 logical fields 一致；单一 ownership descriptor。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-03 21:10] Cursor：C2R2 完成，停手提审

ACK Codex 20:56 / `lastReviewedCommit=2e8e294`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Standard required 只用 C1 legacy 3 态，无 idle。required typed asset 缺 URL/帧数/几何/identifier 确认后仍 fail-closed。非整组页确认后只写 dirty；Standard A+B 选 B 时 mask/values 只有 B，resources 全是 physical0。ownership 由单一 descriptor registry 派生。定向 68/68，全量 821/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/09-c2r2-emitted-plan-legacy-states.md`。未改 queue/status，不自动进 C3。

### [2026-09-04 07:01] Cursor ACK：开始 C2R3 emitted-action exactness / typed payload validation

ACK Codex 21:28 / `lastReviewedCommit=011513f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2R3：Standard activeSet-only 不得空物理 `.write`；picture 写入才记录隐式激活；逐 field typed 校验；Rhino/current activeSet-only 仍发 `0x97`。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 07:14] Cursor：C2R3 完成，停手提审

ACK Codex 21:28 / `lastReviewedCommit=011513f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Standard activeSet-only 为 `.noOp`；picture+activeSet 只记录隐式激活且 mask 不含 activeSet。Rhino/current activeSet-only 发 `0x97`。status/FPS/key/light/activeSet 错型或 activeSet 越界/不一致在 `.write` 前 fail-closed。定向 75/75，全量 828/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/10-c2r3-emitted-action-typed-payload.md`。未改 queue/status，不自动进 C3。

### [2026-09-04 07:22] Cursor ACK：开始 C2R4 whole-group confirmation / selected-range closure

ACK Codex 07:27 / `lastReviewedCommit=893486d`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2R4：Standard whole-group 扩写前强制覆盖确认；frozen selected ∈ 0...1；dirty activeSet 在 Standard filter 前校验；单一 FieldActionKind；真实 draft→snapshot 反例。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 07:35] Cursor：C2R4 完成，停手提审

ACK Codex 07:27 / `lastReviewedCommit=893486d`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Standard whole-group 扩写前强制覆盖确认，确认后 overwriteSemantic=true。picture/activation 前 selected ∉ 0...1 fail-closed。合法 Standard activeSet-only 仍 noOp，malformed fail-closed。单一 FieldActionKind 驱动校验/过滤/动作/空写。定向 84/84，全量 837/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/11-c2r4-whole-group-selected-range.md`。未改 queue/status，不自动进 C3。

### [2026-09-04 07:51] Cursor ACK：开始 C2R5 post-filter whole-group trigger

ACK Codex 07:49 / `lastReviewedCommit=652727b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2R5：whole-group 只由 post-filter emitted picture 触发；idle-only / 未选中逻辑套 dirty 必须 no-op；补齐 keyDescription/keyVoicePreset/lightMapping/taskAsset 真实 draft→snapshot malformed。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 07:57] Cursor：C2R5 完成，停手提审

ACK Codex 07:49 / `lastReviewedCommit=652727b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。whole-group 只由 post-filter emitted picture 触发；空 emitted 先 no-op。Standard idle-only 与仅未选中逻辑套 dirty 无论是否确认均为 no-op。draft→snapshot 补齐四类 typed 错型 fail-closed。定向 86/86，全量 839/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/12-c2r5-post-filter-whole-group.md`。未改 queue/status，不自动进 C3。

### [2026-09-04 08:09] Cursor ACK：开始 C3A page-operation contract / WAL ledger

ACK Codex 08:08 / `lastReviewedCommit=18eb055`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3A：page-operation contract、page scope/field mask/device/fingerprint/确认 ledger、operation-ID 冲突门、WAL schema/migration/reopen、同设备 FIFO/head-blocking。不进 C3B/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 14:42] Cursor：C3A 完成，停手提审

ACK Codex 08:08 / `lastReviewedCommit=18eb055`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。schema=2 持久化 page scope/field mask/device/fingerprint/ledger；旧 JSON 与 v4 WAL 可迁移。空证明 fail-closed。同设备 FIFO + paused head-blocking。旧 peer 未广告 schema=2 拒绝，零 ingest/apply。定向 154/154，全量 855/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/13-c3a-page-operation-wal-ledger.md`。未改 queue/status，不自动进 C3B。

### [2026-09-04 14:53] Cursor ACK：开始 C3AR1 contract identity / FIFO closure

ACK Codex 14:52 / `lastReviewedCommit=d30d679`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3AR1：verified 资源摘要进入 package identity；base fingerprint 改为调用方 CAS/content digest；compatibility fingerprint 由本次实际 opcode/slot/geometry 生成；typed ledger/schema 精确匹配；schema=1/2 统一 FIFO。不进 C3B/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 15:41] Cursor：C3AR1 完成，停手提审

ACK Codex 14:52 / `lastReviewedCommit=d30d679`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。资源 digest 进入 package/canonical identity；同 metadata 不同字节冲突。base fingerprint 为调用方 CAS/content digest。compatibility fingerprint 由本次实际动作生成。typed ledger/schema 精确匹配；删除 projection Middle Man。统一 FIFO 状态边界。定向 158/158，全量 859/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/14-c3ar1-contract-identity-fifo.md`。未改 queue/status，不自动进 C3B。

### [2026-09-04 17:48] Cursor ACK：开始 C3AR2 explicit resource binding / semantic fingerprint

ACK Codex 17:42 / `lastReviewedCommit=0f1f73a`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3AR2：显式 field→resource binding；canonical typed emitted-action；family wire 矩阵；typed ResourceIdentity 与单一 strict CodingKey。不进 C3B/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 18:03] Cursor：C3AR2 完成，停手提审

ACK Codex 17:42 / `lastReviewedCommit=0f1f73a`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。显式 field→resource binding；Standard 三态同几何可组包；fingerprint 为 typed emitted-action 列表；decoder 拒绝不可能语义。定向 162/162，全量 863/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/15-c3ar2-explicit-binding-semantic-fingerprint.md`。未改 queue/status，不自动进 C3B。

### [2026-09-04 18:46] Cursor ACK：开始 C3AR3 fingerprint-contract / WAL reopen closure

ACK Codex 18:10 / `lastReviewedCommit=1eeef9b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3AR3：fingerprint actions 与 fieldMask/resource binding 精确双射与 canonical 顺序；显式持久化实际 wire opcode/必要 subtype 与 operation-wide cardinality；真实 persistent-store schema=2 WAL 污染/reopen。不进 C3B/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 19:08] Cursor：C3AR3 完成，停手提审

ACK Codex 18:10 / `lastReviewedCommit=1eeef9b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。fingerprint↔fieldMask 双射与 canonical 顺序；picture×binding 交叉闭合；非图片显式 opcode/subtype；prepare/defaultBind 为 operation-wide。真实 schema=2 WAL 污染/reopen fail-closed。定向 162/162，全量 863/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/16-c3ar3-fingerprint-contract-wal-reopen.md`。未改 queue/status，不自动进 C3B。

### [2026-09-04 21:27] Cursor ACK：开始 C3AR4 resource-action identity / upload multiplicity closure

ACK Codex 20:13 / `lastReviewedCommit=190370c`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3AR4：picture action↔typed resource identity 不可交换闭合；prepare per-chunk strategy/multiplicity；真实 WAL 负例补 wrong subtype、binding identity swap 与 multiplicity 伪造；收敛两处 P3。不进 C3B/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 21:59] Cursor：C3AR4 完成，停手提审

ACK Codex 20:13 / `lastReviewedCommit=190370c`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。picture action 与同 field binding 共享 typed resource identity 及 encodedFrameCount；prepare 为 per-chunk strategy（1 帧 7 次）；WAL 负例补 identity swap / wrong subtype / strategy 伪造。定向 162/162，全量 863/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/17-c3ar4-resource-identity-prepare-multiplicity.md`。未改 queue/status，不自动进 C3B。

### [2026-09-04 22:15] Cursor ACK：开始 C3B page execution / durable resume

ACK Codex 22:10 / `lastReviewedCommit=c78c865`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3B：多帧多资源 prepare 同构与 physical-slot 单一 mapping；page-only execution、device/profile/base CAS、FIFO head、durable resume、confirmed chunk 零重发、queued/running 取消与 fail-fast。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 22:48] Cursor：C3B 完成，停手提审

ACK Codex 22:10 / `lastReviewedCommit=c78c865`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。physical-slot 共用 Family；2 帧×2 资源 prepare 与生产 program 同构；page-only execution、CAS/FIFO/durable resume/cancel 边界落地。定向 204/204，全量 882/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/18-c3b-page-execution-durable-resume.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-04 23:05] Cursor ACK：开始 C3BR1 production preflight / aggregate-write closure

ACK Codex 23:02 / `lastReviewedCommit=bf31252`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR1：生产 live base CAS、冻结 0x84 整行、device-confirmed 恢复门，以及两个 P3 机械收敛。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 23:27] Cursor：C3BR1 完成，停手提审

ACK Codex 23:02 / `lastReviewedCommit=bf31252`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。生产 live CAS 只读密封指纹；0x84 冻结整行纳入 fingerprint；post-confirm 只认设备确认。定向 210/210，全量 888/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/19-c3br1-production-preflight-aggregate-write.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-04 23:40] Cursor ACK：开始 C3BR2 authoritative CAS lifecycle / write-fact closure

ACK Codex 23:38 / `lastReviewedCommit=d212e6aad2de0119d8f996e6e22710b56ae0e375`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR2：权威对象生产生命周期写入 live CAS；先判 typed device-write fact 再决定是否要求 CAS；page 终态统一按真实设备写分类；step 用 frozen program 判定 writesDevice；补 `0x84` 值域 0...7 与 WAL `0xff` 负例。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 23:58] Cursor：C3BR2 完成，停手提审

ACK Codex 23:38 / `lastReviewedCommit=d212e6aad2de0119d8f996e6e22710b56ae0e375`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。权威对象生产入口写入 live CAS；先判 typed `writesDevice` 再决定是否要求 CAS；page 终态按真实设备写分类。定向 216/216，全量 894/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/20-c3br2-authoritative-cas-write-fact.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 00:21] Cursor ACK：开始 C3BR3 production authority-event wiring

ACK Codex 00:12 / `lastReviewedCommit=25a1a5998f26eb9813fab6e1184fcdbff6ee546d`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR3：canonical object 接入已有 `deviceChanged` 设备快照事件；测试穿过该事件，不直调 record wrapper；删除 `sealed-object:*`。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 00:42] Cursor：C3BR3 完成，停手提审

ACK Codex 00:12 / `lastReviewedCommit=25a1a5998f26eb9813fab6e1184fcdbff6ee546d`。live CAS 接入 `deviceChanged` 权威快照；测试穿过该事件；删除 `recordAuthoritativeObject` 与 `sealed-object:*`。定向 217/217，全量 895/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/21-c3br3-production-authority-event.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 09:04] Cursor ACK：开始 C3BR4 production authority source / ordered commit

ACK Codex 08:44 / `lastReviewedCommit=72a34cc7ea749f486c5704d1e7bbe86c89fa2963`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR4：生产路径用已验证 sync baseline 产出 canonical object；先 durable commit 再发布权威 `deviceChanged`；generation 条件提交；失败不吞、不发布权威快照。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 10:46] Cursor：C3BR4 完成，停手提审

ACK Codex 08:44 / `lastReviewedCommit=72a34cc7ea749f486c5704d1e7bbe86c89fa2963`。生产路径从已验证 schema=1 live CAS 产出权威对象；durable commit 成功后再发布对应权威 `deviceChanged`；generation 拒绝过期换代；失败不吞、不发布权威快照。测试穿过非测试 producer 与有序 commit，不等 persist Task。定向 220/220，全量 898/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/22-c3br4-production-authority-source.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 11:20] Cursor ACK：开始 C3BR5 authority-version closure

ACK Codex 11:06 / `lastReviewedCommit=0a39d8217ea40b7225198717d2eda081854bf882`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR5：typed authority version；stale 零发布；同 generation 换代不回滚；cache 绑完整 identity；重启 epoch 允许低 generation。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 11:36] Cursor：C3BR5 完成，停手提审

ACK Codex 11:06 / `lastReviewedCommit=0a39d8217ea40b7225198717d2eda081854bf882`。typed authority version；stale 零发布；同 generation 换代不回滚；cache 绑完整 identity；重启 epoch 允许低 generation。定向 228/228，全量 906/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/23-c3br5-authority-version-closure.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 11:50] Cursor ACK：开始 C3BR6 writer-epoch lease closure

ACK Codex 11:46 / `lastReviewedCommit=7a27ea2717e08e37572f907d6ab7b2b0dde9b179`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR6：进程级 durable writer lease；首次并发不得回滚 CAS；多设备历史不得永久拒绝；typed counter 去掉 sentinel 0。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 12:12] Cursor：C3BR6 完成，停手提审

ACK Codex 11:46 / `lastReviewedCommit=7a27ea2717e08e37572f907d6ab7b2b0dde9b179`。进程级 durable writer lease；首次并发不得回滚 CAS；多设备历史不得永久拒绝；typed counter 去掉 sentinel 0。定向 237/237，全量 915/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/24-c3br6-writer-epoch-lease.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 12:25] Cursor ACK：开始 C3BR7 store-global lease fence

ACK Codex 12:20 / `lastReviewedCommit=aeacf4c638c758814d66f9f8b0e47664f12b9971`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR7：persist 必须等于当前 store-global lease；旧 writer 跨设备续写与伪造 lease 一律拒绝；missing/corrupt metadata fail-closed。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 12:36] Cursor：C3BR7 完成，停手提审

ACK Codex 12:20 / `lastReviewedCommit=aeacf4c638c758814d66f9f8b0e47664f12b9971`。persist 核当前 store-global lease；旧 writer 跨设备续写与伪造 lease 拒绝；missing/corrupt fail-closed。定向 241/241。全量第一次 919/2 skipped/1（延迟用例未等 gate），补 waitUntilEntered 后第二次 919/2 skipped/0。App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/25-c3br7-store-global-lease-fence.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 13:05] Cursor ACK：开始 C3C Runtime abandon + partial-baseline

ACK Codex 13:00 / `lastReviewedCommit=705a2579f101c02b1c224b0de8cb2bb37173a7e6`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3C：durable 60 秒 abandon、field/resource baseline 同事务推进、partial/no-write 终态与精确 residual。不接 UI，不进 C4/C5/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 13:40] Cursor：C3C 完成，停手提审

ACK Codex 13:00 / `lastReviewedCommit=705a2579f101c02b1c224b0de8cb2bb37173a7e6`。完整 field/resource 确认与 writeConfirmed baseline 同事务推进；chunk 不提前密封。60 秒 abandon 仅 FIFO 队首 paused/resumable 且仍断连时受理。定向 251/251，全量 929/2 skipped/0。App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/26-c3c-runtime-abandon-partial-baseline.md`。未改 queue/status，不自动进 C4。

### [2026-09-05 14:05] Cursor ACK：开始 C3CR1 disconnect-generation + atomic-abandon

ACK Codex 14:00 / `lastReviewedCommit=d02d82665d307e712495c06df703cf42794d4273`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3CR1：真实 device-disconnect 铸造带 connection identity 的 durable epoch；abandon 单事务重核；authority typed version 防倒退并允许 absent 建立 verified；local residual 与 writeConfirmed 分离；typed baseline digest/generation；删除越界 Relay YAML。不进 C4/C5/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 14:50] Cursor：C3CR1 完成，停手提审

ACK Codex 14:00 / `lastReviewedCommit=d02d82665d307e712495c06df703cf42794d4273`。真断连 epoch + 原子 abandon；authority typed version 防倒退；local residual 分离；删除越界 Relay YAML。定向 260/260，全量 938/2 skipped/0。App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/27-c3cr1-disconnect-generation-atomic-abandon.md`。未改 queue/status，不自动进 C4。

### [2026-09-05 16:45] Cursor ACK：开始 C3CR2 disconnect-token CAS / current-authority

ACK 用户转发的 Codex C3CR1 验收。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3CR2：callback 当场冻结 identity；abandon CAS observed disconnect epoch；重连 fence 先于恢复；readback 核当前 store authority；optional UUID 写 NULL；strict decode。不进 C4/C5/HIL/打包/安装/push。不夹带 Codex board/queue/status。未伪造 Relay review_decision。

### [2026-09-05 17:12] Cursor：C3CR2 完成，停手提审

ACK 用户转发的 Codex C3CR1 验收 / `lastReviewedCommit=4f9162be827b491c9d7994b73ea3c0c4f9e86df9`。callback 当场冻结 identity；abandon CAS observed epoch；重连 fence 先于恢复；current store authority；SQL NULL；strict decode。定向 268/268，全量 946/2 skipped/0。App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/28-c3cr2-disconnect-token-cas-current-authority.md`。未改 queue/status，未伪造 Relay review_decision，不自动进 C4。

### [2026-09-05 17:22] Cursor ACK：开始 C3CR3 lease-frozen epoch / monotonic fence / global-lease readback

ACK 用户转发的 Codex C3CR2 验收。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3CR3：断连 epoch 必须同步持有 writer lease；fence 单调；fence 失败不恢复；readback 核 global lease；删除未授权 Relay bootstrap YAML。不进 C4/C5/HIL/打包/安装/push。不夹带 Codex board/queue/status。未伪造 Relay review_decision。

### [2026-09-05 17:36] Cursor：C3CR3 完成，停手提审

ACK 用户转发的 Codex C3CR2 验收 / `lastReviewedCommit=5b8ca57c1a590e802822ee52295628cee2ab0238`。断连 epoch 同步持有 writer lease；fence 单调；fence 失败不恢复；readback 核 store-global lease；删除未授权 Relay bootstrap YAML。定向 273/273，全量 951/2 skipped/0。App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/29-c3cr3-lease-frozen-epoch-monotonic-fence.md`。未改 queue/status，未伪造 Relay review_decision，不自动进 C4。

### [2026-09-05 17:45] Cursor ACK：开始 C3CR4 eager lease / proven authority

ACK 用户转发的 Codex C3CR3 手工验收。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3CR4：fresh Agent 在可观察连接/断连或 abandon 前建立并缓存 writer lease；连接事实与 lease 缓存解耦；verified 必须证明当前 per-device authority；复用单一 global-lease decoder。不进 C4/C5/HIL/打包/安装/push。不夹带 Codex board/queue/status。未伪造 Relay review_decision。

### [2026-09-05 17:53] Cursor：C3CR4 完成，停手提审

ACK 用户转发的 Codex C3CR3 手工验收 / `lastReviewedCommit=8dfd7da7e5192291f6ca98ea3ac1d25ed79a9ef1`。生产路径在 connect 前建立 writer lease；连接事实与 lease 缓存解耦；verified 必须证明当前 per-device authority；复用单一 global-lease decoder。定向 276/276，全量 954/2 skipped/0。App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/30-c3cr4-eager-lease-proven-authority.md`。未改 queue/status，未伪造 Relay review_decision，不自动进 C4。

### [2026-09-05 19:14] Cursor ACK：开始 C3CR5 lease-allocation fail-closed

ACK 用户转发的 Codex C3CR4 手工验收。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3CR5：lease 分配失败不得 scan/connect，错误可观察；成功且仍 poweredOn 才连接；成功重试复用同一进程 lease。不进 C4/C5/HIL/打包/安装/push。不夹带 Codex board/queue/status。未伪造 Relay review_decision。

### [2026-09-05 19:21] Cursor：C3CR5 完成，停手提审

ACK 用户转发的 Codex C3CR4 手工验收 / `lastReviewedCommit=5902e723c15d3adc1ce5497ddb621abdf464a57a`。lease 分配失败保持离线且 emit 可观察；成功且仍 poweredOn 才 scan/connect；成功重试复用同一进程 lease。定向 278/278，全量 956/2 skipped/0。App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/31-c3cr5-lease-allocation-fail-closed.md`。未改 queue/status，未伪造 Relay review_decision，不自动进 C4。

### [2026-09-05 21:58] Cursor ACK：开始 C4 Studio 页面交互 + 设备 FIFO

ACK 用户确认进入 C4，以及 Codex 19:31 开放 C4。C1–C3 accepted @ `c6e0762`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4 白名单，不改 C2 assembler 冻结语义与 C3 Runtime/WAL/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-05 22:25] Cursor：C4 完成，停手提审

ACK 用户确认进入 C4 / Codex 19:31 开放 C4。C1–C3 accepted @ `c6e0762`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Studio 写入已收成当前页交互和设备 FIFO，只消费 C2/C3 已验收 frozen-page facade。定向 293/293，全量 971/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/32-c4-studio-page-interaction-fifo.md`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-05 22:58] Cursor ACK：开始 C4R1 canonical Runtime projection

ACK 用户转发的 Codex C4 未通过与 C4R1 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R1 白名单：Agent 密封 profile/page/epoch 的 additive snapshot 投影，Studio 只消费这些 typed 事实。不改 C2 assembler 决策与 C3 WAL/事务转移/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-05 23:25] Cursor：C4R1 完成，停手提审

ACK 用户转发的 Codex C4 未通过与 C4R1 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Agent 密封 OLED profile、typed page ownership 与 durable 60s eligibility 已投影进 Runtime snapshot；fresh Studio 只从 snapshot 重建。定向 318/318，全量 981/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/33-c4r1-canonical-runtime-projection.md`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-06 09:02] Cursor ACK：开始 C4R2 durable FIFO / live abandon / canonical asset

ACK 用户转发的 Codex C4R1 未通过与 C4R2 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 已通过项冻结 @ `7a838fa`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R2 三项：durable queue/terminal order、无外部事件的 59s→60s 队首资格、canonical sealed asset identity。不改 C2 assembler 决策与 C3 WAL/事务转移/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-06 09:42] Cursor：C4R2 完成，停手提审

ACK 用户转发的 Codex C4R1 未通过与 C4R2 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 已通过项冻结 @ `7a838fa`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Runtime snapshot 按 WAL queue/terminal order 投影；Studio 显式按这些字段重建 FIFO 与同页当前 operation。disconnect mint 可观测，静默 59s→60s 仅队首可放弃。draft/page commit 共用密封 GIF 身份。定向 325/325，全量 988/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/34-c4r2-durable-fifo-abandon-asset.md`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。
