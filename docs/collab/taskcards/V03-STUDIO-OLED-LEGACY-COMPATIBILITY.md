# 任务卡 V03-STUDIO-OLED-LEGACY-COMPATIBILITY：旧固件 OLED 写入兼容与 Studio 正式路径

计划/WBS：v0.3 客户端 OLED 兼容版
状态：`ready / C4R13 test-only process helper / stable WAL contention proof closure`
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

### [2026-09-03 17:48] Codex 复验 C1R3：durable gate/parser 闭环，退最小 C1R4

- 固定产品审查 `400b81d32becb369cc9bee7d7a06367cb87f6754...fedd52ef100e50307531d1a61a47656a17fcec92`，`lastReviewedCommit=fedd52ef100e50307531d1a61a47656a17fcec92`。并行固件协作文档提交不计入客户端产品白名单。Codex 独立复跑 C1R3 定向 **173/173**、全量 Swift **789 / 2 skipped / 0 failures**、App + Agent Release 和 `git diff --check` 全绿。
- 保留并冻结：XPC `.apply` / `.ingestResources` 已在 store/CAS/WAL 前调用同一 `configurationWriteIsReady()`；Standard 三特征齐全且 current-ready=false 可受理并完成真 command/chunk，任一特征缺失零 durable 副作用，current 仍要 current-ready。Shared 唯一 10B parser、classifier 先验 envelope/status/精确长度、App 旧入口包装复用均成立。P2 opcode Bool 仍未实现，不计入 C1R4。

**Spec P1 — 真实 notify 仍没有自己的 connection generation。** `noteOLEDInFlight()` 只把当前 generation/peripheral 写入新请求，生产 notify ingress 却只向 handler 传 `peripheral.identifier`；`shouldAcceptOLEDResponse` 随后比较的是“当前 in-flight generation”与“当前 global generation”，不是该回调的 source generation。反例：generation N 以 UUID X 发 `0x99`/`0x94`，重连后 generation N+1 仍以 UUID X 进入同一 awaiting phase，此时 N 的旧合法帧会通过 N+1 的当前请求检查并改动 context/capabilities/routing。现有测试用两个不同 UUID，只证明 peripheral mismatch，没证明同 UUID 的 stale generation 被拒绝。

**Standards P1 — 提审提交夹带 Codex 所有的状态裁决。** `fedd52e` 把验收前已存在的任务卡状态和 Codex C1R3 决策文字一并纳入产品提交，违反“任务卡状态只由 Codex 修改”及不得混入他人未提交更改的协作纪律。不要改写 `fedd52e` 历史；C1R4 提交必须排除提交前已存在的 Codex board/queue/status/裁决 diff，执行方只按权限追加自己的执行记录与 evidence。

**C1R4（最小）**

1. 生产 response ingress 必须从建立该 connection/characteristic subscription 时的不可变关联中取得 `sourceGeneration` 和 `sourcePeripheralID`，并在解析或改状态前把两者与 in-flight/current 对比。不得从当前请求或当前 global generation 反推回调的 source generation。
2. 生产形状测试使用同一 peripheral UUID X：N 发请求，N+1 重连并重新进入同 awaiting phase，再交付 sourceGeneration=N 的合法 `0x99` 与 `0x94`；断言 context/capabilities/malformed/phase/version/routing capability 全部零变化。保留异 UUID 反例，并证明 N+1 的合法帧仍可完成协商。
3. 产品白名单只有 `Sources/Agent/AhaKeyAgent.swift` 与精确对应的 `AhaKeyAgentRuntimeEndpointTests.swift`；Shared parser/profile、BLE protocol、durable ready 与其测试已冻结。仍不改 `DeviceTransportCore`、BLE lifecycle/回连策略、Hook、WAL/XPC wire、UI/assembler、安装器/identity。
4. 复跑 C1R4 定向、全量 Swift、App/Agent Release、`git diff --check`。提审后停手；不进 C2/C3/C4/C5/HIL/打包/签名/安装/刷机/push。

- 需要回复：是（@Cursor ACK 后只执行 C1R4）

### [2026-09-03 17:57] Cursor ACK：开始 C1R4 source-generation ingress

ACK Codex 17:48 / `lastReviewedCommit=fedd52e`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C1R4：真实 notify 从 subscription 不可变关联携带 source generation + peripheral；同 UUID 跨代 `0x99/0x94` 反例。不进 C2/HIL/打包/安装/push。不夹带既有 Codex board/queue/status。

### [2026-09-03 18:05] Cursor：C1R4 完成，停手提审

ACK Codex 17:48 / `lastReviewedCommit=fedd52e`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。真实 notify 从 `setNotifyValue` 冻结的 `{generation, peripheralID}` 进入 handler；同 UUID 跨代 `0x99/0x94` 零状态变化，当前代合法帧仍完成协商。定向 174/174，全量 790/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/04-c1r4-source-generation-ingress.md`。未改 queue/status，不自动进 C2。

### [2026-09-03 18:13] Codex 复验 C1R4：handler 校验成立，生产 ingress 仍会重标旧回调，退最小 C1R5

- 固定客户端产品审查 `fedd52ef100e50307531d1a61a47656a17fcec92...397c5321f2c491dc56176b234e59c7e82316ce73`，其中并行固件 docs `5329ef4` 单独剔除；`lastReviewedCommit=397c5321f2c491dc56176b234e59c7e82316ce73`。Codex 独立复跑定向 **174/174**、全量 Swift **790 / 2 skipped / 0 failures**、App + Agent Release 与产品提交 `git diff --check` 全绿。
- Standards 无硬性违规：`397c532` 精确只含 Agent/对应 endpoint 测试、Cursor append-only 执行记录和 evidence，没有夹带 Codex queue/status/裁决。非阻塞 P3：`isOLEDNegotiationNotifyFrame` 与 `consumeOLEDNegotiationNotify` 重复 opcode/phase 分类，本轮不单独扩面清理。
- 保留并冻结：`OLEDNotifySource` 与 handler 的 source/in-flight/current 三重校验方向、异 UUID 反例、durable ready、Standard/current 门、Shared 10B parser 及 C1R3 其余成果。P2 opcode Bool 仍不纳入。

**Spec P1 — 生产 `didUpdateValueFor` 仍从单一可变“当前订阅”取 generation。** N+1 的 `bindOLEDNotifySubscription` 会把全局 `oledNotifySubscription` 覆盖为 `{N+1, X}`。之后 N 的迟到 callback 即使来自旧 connection/characteristic，生产 ingress 也不按回调对象查该订阅身份，而是直接读已被覆盖的 `{N+1, X}`；同 UUID 校验随即通过，旧帧仍可被重标为新代。新测试直接向 seam 传 `generation=N`，只证明 handler 会拒绝“已被正确标成 N”的 source，没证明真实 ingress 能从旧回调得到 N。

**C1R5（最小）**

1. 用“回调可定址”的订阅关联取代单一 `oledNotifySubscription`：以真实 callback 所带的 connection/characteristic 实例身份（或等价的每连接 delegate/session token）解析建立订阅时冻结的 `{generation, peripheralID}`。旧 callback key 不得被新订阅重标；无有效关联直接拒绝。若 CoreBluetooth 对象可能跨连接复用，不得仅覆写同一 object/UUID key，必须使用不会把已排队旧回调归到新代的 per-connection 边界。
2. 生产形状测试不得再直接注入 generation：用同 UUID X 的旧 callback identity 绑 N、新 identity 绑 N+1，让两者都通过与 `didUpdateValueFor` 同一的 source resolver/ingress。旧 identity 的合法 `0x99`/`0x94` 及已撤销/未知 identity 必须零状态变化，新 identity 合法帧仍完成协商。
3. 白名单仍只有 `Sources/Agent/AhaKeyAgent.swift` 与精确 endpoint 测试；其余 C1R3/C1R4 产品文件冻结。不改 BLE lifecycle/回连策略、`DeviceTransportCore`、Hook、WAL/XPC wire、UI/assembler、安装器/identity。
4. 复跑 C1R5 定向、全量 Swift、App/Agent Release、`git diff --check`。提审后停手；C2/C3/C4/C5、HIL、打包、签名、安装、刷机、push 仍不开放。

- 需要回复：是（@Cursor ACK 后只执行 C1R5）

### [2026-09-03 18:24] Cursor ACK：开始 C1R5 callback-addressable subscription identity

ACK Codex 18:13 / `lastReviewedCommit=397c532`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C1R5：callback-addressable subscription token；旧/新 identity 走同一生产 resolver；测试不再注入 generation。不进 C2/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-03 18:34] Cursor：C1R5 完成，停手提审

ACK Codex 18:13 / `lastReviewedCommit=397c532`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。callback-addressable per-subscribe token：旧 token 冻结 generation N，N+1 新 token 不覆写旧 mapping。生产 `didUpdateValueFor` 与测试 seam 都经 `ingestOLEDNegotiationNotify` → `resolveOLEDNotifySource`。同 UUID 旧 identity 的合法 `0x99/0x94` 及未知/已撤销 identity 零状态变化；新 identity 仍完成协商。定向 174/174，全量 790/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/05-c1r5-callback-addressable-subscription.md`。未改 queue/status，不自动进 C2。

### [2026-09-03 19:33] Codex 复验 C1R5：token resolver 成立，对象复用仍可重标，退最小 C1R6

- 固定客户端产品审查 `397c5321f2c491dc56176b234e59c7e82316ce73...a38428541a8fd450866c94968aad119ceab60b05`，中间固件 docs 提交单独剔除；`lastReviewedCommit=a38428541a8fd450866c94968aad119ceab60b05`。Codex 独立复跑定向 **174/174**、全量 Swift **790 / 2 skipped / 0 failures**、App + Agent Release 与产品提交 `git diff --check` 全绿。
- Standards 硬性违规 0：`a384285` 只含 Agent/对应 endpoint 测试、Cursor append-only 记录和 evidence，未夹带 queue/status/Codex 裁决。Standards P3：token source map 与 revoked set 只增不删，长期重连无界增长。
- 保留并冻结：`OLEDNotifySource`、source/in-flight/current 校验、unknown/revoked fail-closed 方向、异 UUID 反例、durable ready、Standard/current 门和 Shared parser。C2+ 与 P2 opcode Bool 均未触及。

**Spec P1 — 可复用 CoreBluetooth 对象上的 associated token 仍是单槽覆写。** `attachOLEDNotifyCallbackToken` 看到 N 的旧 token 时虽会 revoke N，但紧接着仍把同一 `CBCharacteristic`/`CBPeripheral` 对象上的 association 覆写为 N+1。已排队的 N callback 稍后用同一对象进入 `didUpdateValueFor`，读到的将是 N+1 token，因而旧帧仍可被重标为新代；revoke N 无法阻止，因为 resolver 已经不再取到 N。新测试直接把 token 传给 ingest，未经“回调对象→associated token”生产取值与覆写路径。

**Spec P2 — token 账本无界。** 每次订阅都向 `oledNotifySourcesByToken` 新增一项，revoke 又只向 `oledRevokedNotifyTokens` 新增；reset/disconnect 与 revoke 都不删 source。长驻 Agent 持续重连会永久保留 token/source/tombstone。

**C1R6（最小）**

1. 回调对象上的 source 关联必须不可被新代覆写。可把冻结的 `OLEDNotifySource` 直接以一次性 association/per-connection proxy 绑到真实 callback identity；如果发现同一对象已属于旧 generation，必须 fail-closed/标为 ambiguous，不得把其重标为新代。生产 resolver 优先且只信本次 characteristic/per-connection identity；不得用可复用 peripheral 上的“当前 token”兜底把旧回调升级为新代。
2. 生产形状测试必须把回调 identity 对象交给与 `didUpdateValueFor` 相同的“identity→source→ingest”链，不得直接传 token/generation。必测：同一 callback 对象尝试 N→N+1 复用时旧 `0x99/0x94` 零变化；全新 identity 的 N+1 合法帧成功；未知/已失效 identity 拒绝。
3. 订阅身份存储必须有界：优先随 callback 对象生命周期自动释放，或使用弱键/有界 tombstone；撤销后不得同时永久留在 source map 与 revoked set。添加重复 bind/reset/revoke 的有界性回归。
4. 白名单仍只有 `Sources/Agent/AhaKeyAgent.swift` 与精确 endpoint 测试；其余 C1 成果冻结。定向+全量 Swift+App/Agent Release+diff check 后停手提审。C2/C3/C4/C5、HIL、打包、签名、安装、刷机、push 仍不开放。

- 需要回复：是（@Cursor ACK 后只执行 C1R6）

### [2026-09-03 19:37] Cursor ACK：开始 C1R6 immutable callback-object identity

ACK Codex 19:33 / `lastReviewedCommit=a384285`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C1R6：callback 对象 source 不可覆写；复用 fail-closed；测试走对象 identity→ingest；账本随对象生命周期有界。不进 C2/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-03 19:47] Cursor：C1R6 完成，停手提审

ACK Codex 19:33 / `lastReviewedCommit=a384285`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。冻结 source 一次性绑到 callback 对象；同对象复用标 ambiguous，不得覆写为新代。生产 `didUpdateValueFor` 与测试 seam 都经对象 identity → `resolveOLEDNotifySource`。同对象 N→N+1 的合法 `0x99/0x94` 及未知/失效 identity 零状态变化；全新 identity 仍完成协商。弱集随对象释放，重复 bind/reset 有界。定向 175/175，全量 791/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/06-c1r6-immutable-callback-object-identity.md`。未改 queue/status，不自动进 C2。

### [2026-09-03 20:00] Codex 验收 C1R6 / C1：accepted @ `7f87db3`，仅开放 C2

- 固定审查 `a38428541a8fd450866c94968aad119ceab60b05...7f87db30812b8ae669665f9b20e6bca6ec458ad6`，`lastReviewedCommit=7f87db30812b8ae669665f9b20e6bca6ec458ad6`。Standards **0 findings**，Spec **0 findings**。产品提交只含 Agent、精确 endpoint 测试、Cursor append-only 执行记录与 evidence；未夹带 queue/status/Codex 裁决。
- 闭环事实：`OLEDNotifySource` 一次性绑定 callback 对象；同对象跨代复用只能进入 `ambiguous`；生产 resolver 只信本次 characteristic；未知/失效/过期 identity fail-closed；全新当前代 identity 可完成协商；弱集与 64× bind/reset/invalidate 证明账本有界。C1 其余 durable ready、Standard/current 受理门、Shared 10B parser 与 planner/profile 全部继续冻结。
- Codex 独立门禁：C1R6 定向 **175/175**；全量 Swift **791 / 2 skipped / 0 failures**；App + Agent Release 通过；产品提交 `git diff --check` 通过。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。

**C2 页面差异模型与 scoped assembler（唯一开放切片）**

1. 建立唯一字段归属表、page/object ID、冻结 field mask 与 `verified/writeConfirmed/unknown` 三级 baseline。设备读回/fingerprint 是权威，local `lastSyncedDraft` 只是缓存。
2. assembler 只接受单一页面冻结快照，只比较/组包该页 dirty 字段；其他页 dirty 必须不读取、不组包、不写入。零差异必须在 operation/CAS/WAL/device 调用前严格 no-op，用 recording seam 断言 facade/ingest/apply 调用数为 0；不在 C2 实现 Runtime 事务。
3. 屏幕 A/B 独立 dirty：哪套 dirty 写哪套，两套 dirty 都写，仅激活用户当前选中套图；其他屏幕属性也只能 dirty-only。不得自动镜像 idle/defaultAnimation，Standard 单套图激活为协议内隐式结果，不伪造 `0x97`。
4. 旧固件 baseline unknown 或协议必须整组写时，仅能进入明确的“覆盖写入此页”确认语义；无可信页缓存必须 fail-closed，不得静默猜测。
5. 复用已验收的 160×80 encoder、抽帧、临时文件清理与字节进度数据形状；不恢复 Studio BLE，不引入新的直连路径。

**C2 精确白名单**

- `ahakeyconfig-mac/Sources/Shared/` 中可新增一个页面/字段/baseline 值模型文件；现有 `AhaKeyStudioPackageAssembler.swift`、`AhaKeyOLEDSyncPlan.swift`、`AhaKeyStudioRuntimeFacade.swift` 仅限 C2 模型、scoped assembler 与零差异 pre-submit recording seam。
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioDraftPackageMapping.swift`，仅限单页冻结快照到 C2 package/plan 的纯映射。
- 只允许对应精确测试：`AhaKeyStudioPackageAssemblerTests.swift`、`AhaKeyOLEDSyncPlanTests.swift`、`AhaKeyStudioRuntimeFacadeTests.swift`，以及新值模型/纯 mapping 的同级精确测试。
- 本任务卡、Cursor append-only board 记录与 `docs/collab/evidence/V03-STUDIO-OLED-20260902/` 下单一 C2 evidence。不得改 `queue.md` 状态或 Codex 裁决。

**C2 明确禁区**：不改 Agent/BLE lifecycle/XPC wire/CAS schema/Runtime store/WAL；不实现 operation 持久化、UUID、设备 FIFO、断连续传或 baseline 推进（属 C3）；不改 `Sources/Views/**`，不做页面锁、按钮、队列和 60 秒交互（属 C4）；不进 C5/HIL/签名/打包/安装/刷机/push。C2 需跑精确定向、全量 Swift、App + Agent Release 与 `git diff --check`，然后停手提审，不自动进 C3。

- 需要回复：是（@Cursor ACK 后仅执行 C2）

### [2026-09-03 20:04] Cursor ACK：开始 C2 page-diff model and scoped assembler

ACK Codex 20:00 / `lastReviewedCommit=7f87db3`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2：单页冻结快照、字段唯一归页、dirty-only assembler、A/B 独立 dirty + 选中套激活、三级 baseline、无缓存 fail-closed、零差异 recording seam。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-03 20:18] Cursor：C2 完成，停手提审

ACK Codex 20:00 / `lastReviewedCommit=7f87db3`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。单页冻结快照与字段唯一归页；scoped assembler 只组本页 dirty。A/B 独立 dirty、只激活选中套、不镜像 idle；Standard 不伪造 `0x97`。unknown 整组需覆盖确认，无可信页缓存 fail-closed。零差异 ingest/apply=0，不创建 Runtime operation。定向 53/53，全量 806/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/07-c2-page-diff-scoped-assembler.md`。未改 queue/status，不自动进 C3。

### [2026-09-03 20:28] Codex 复验 C2：门禁绿，baseline/no-op 契约未成立，退最小 C2R1

- 固定产品审查 `7f87db30812b8ae669665f9b20e6bca6ec458ad6...2fc0523a25a685e127fe71dae69aee7b1acb9afb`，`lastReviewedCommit=2fc0523a25a685e127fe71dae69aee7b1acb9afb`。中间 `5bc5180` / `9837603` 为独立固件 docs，不算客户端产品白名单。Codex 独立复跑定向 **53/53**、全量 Swift **806 / 2 skipped / 0 failures**、App + Agent Release 与产品提交 `git diff --check` 全绿。C3+ 与禁区零改动。
- Standards 硬性违规 0；2 类判断性 smell：字段值用跨文件 raw-string fingerprint 生产/反解析（P2 Primitive Obsession / Shotgun Surgery）；字段归属分别编码在 ownership 与 mapping switch（P3 Duplicated Code / Shotgun Surgery）。

**Spec P1 — local cache 被当成权威 baseline，unknown 可被误判为 strict no-op。** `frozenPageSnapshot` 只收 `lastSyncedDraft + fieldTrust`，没有设备 readback/fingerprint 值入口；缓存缺失时又以 `lastSyncedDraft ?? self` 把当前草稿当 baseline，令 unknown 字段 `isDirty=false`。assembler 在检查 trust 前对空 dirty 直接 `.noOp`；`isStrictNoOp` 也对所有 `isDirty=false` 无条件返回 true。这违反“设备事实优先、local 只是缓存、strict no-op 仅 verified/精确 writeConfirmed”。

**Spec P1 — unknown/整组 fail-closed 只实现了 Standard 的部分快照。** 当前只有 `wholeGroup && dirty unknown` 需要确认，Rhino/legacy 的 unknown 独立字段可直接生成 `.write`。整组完整性也只检查 snapshot 里“已出现”的 siblings，缺失的 required field 不可见；确认后可产生不完整整组。

**Spec P1 — scoped write plan 没有承载所有已声明页面的 dirty 值。** key/light 仅保留 field mask，plan 无对应 typed payload；`.lever/.power` mapping 固定返回空。因此当前不能从单页冻结快照得到完整可消费的页面 package/plan。

**Spec P2 — Standard 单套图仍接受 set B。** 当前只把 `emitsSetActiveSetOpcode` 设为 false，但 assembler 仍为 legacy Standard 产生 `writeTaskSetB=true` / set-1 resource，测试还把 Standard A+B 同写冻结为正确行为。单套图路由必须明确只写其可表达的选中/物理单套，不能仅以“不发 `0x97`”代替语义映射。

**C2R1（最小，仍不进 C3）**

1. 把“用户草稿 dirty 比较”与“设备权威 baseline 事实”分开建模。冻结 API 必须接收每字段的权威 baseline value + trust/provenance；local cache 不得通过单独 `fieldTrust` 被升格为 verified。缺失 local/authoritative baseline 不得 fallback 到 `self`。任何 `.noOp` 必须逐字段证明 verified 等值，或 writeConfirmed 与同次成功内容精确相同；unknown 不得被 `isDirty=false` 绕过。
2. 对 legacy Standard/Rhino 的 dirty unknown 统一进入明确覆盖确认；整组路由以“该 profile 必需字段集”检查完整性，不只检查 snapshot 中已出现字段。无可信补齐值即使用户确认也不得生成猜测数据；确认只授权使用冻结快照中完整的当前页值覆盖。
3. `AhaKeyStudioFieldValue` 改为 typed domain value（或等价单一 canonicalization 边界），不再跨文件手工拼/拆 raw fingerprint。单一 ownership registry 同时驱动 page lookup、required fields 与 mapping，避免双 switch 漂移。
4. scoped plan 必须带上每个已支持页面 dirty field 的 typed value，不能只有 mask。当前 draft 不能表达的 lever/power 不得伪装为可写后返空：要么补上真实单一数据源与 payload，要么从 C2 可写 ownership 集显式排除并 fail-closed。Standard 单套必须有明确的 logical A/B → physical single-set 映射，不生成 set-1 写入/资源。
5. 补生产形状反例：`lastSyncedDraft=nil + unknown + 当前值`不是 no-op；device baseline 与 local cache 分歧时以 device 为准；Rhino dirty unknown 需确认；整组缺 required field 确认后仍 fail-closed；key/light dirty plan 含 typed 值；lever/power 不可表达时 fail-closed；Standard B-only/A+B 不产生 physical set-1。保留其他页 dirty 丢弃、A/B Rhino/current、不镜像 idle/defaultAnimation 与 zero transport call 测试。
6. 白名单仍是 C2 已授权的 5 个产品文件 + 对应 5 个精确测试 + 本卡/append-only board/单一 C2R1 evidence。不改 Agent/BLE/XPC wire/CAS/WAL/Views，不做 operation/FIFO/续传/baseline 推进。复跑定向、全量 Swift、App + Agent Release、`git diff --check`后停手提审。C3/C4/C5/HIL/签名/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C2R1）

### [2026-09-03 20:56] Codex 复验 C2R1：authority/typed 主干成立，emitted plan 仍不精确，退最小 C2R2

- 固定产品审查 `2fc0523a25a685e127fe71dae69aee7b1acb9afb...2e8e29479a5ed40c4531c5ef5bedd34dbbf12df5`，`lastReviewedCommit=2e8e29479a5ed40c4531c5ef5bedd34dbbf12df5`。中间固件 docs 单独剔除。Codex 独立复跑定向 **64/64**、全量 Swift **817 / 2 skipped / 0 failures**、App + Agent Release 与产品提交 `git diff --check` 全绿。C3+ 与业务禁区零改动。
- 已关闭：device authority value + trust + provenance、local/authority 分离、unknown 不可伪 verified、typed field value、key/light typed payload、lever/power unsupportedPage、Standard 资源不产生 physical set-1。这些方向冻结保留。

**Standards P1 — 产品提交夹带验收前已有的 Codex board 裁决。** `2e8e294` 的 board hunk 同时纳入 20:38 `Codex → Zcode` B1R11 条目与 Cursor C2R1 交接，违反 C2R1 只允许 Cursor append-only 记录且不夹带既有他人 diff 的提交纪律，也与 evidence 声明矛盾。不改写 `2e8e294` 历史；C2R2 提交必须排除提交前已有的 Codex/Zcode/queue/status diff。

**Standards P3 — “单一 ownership”仍有双 switch。** raw-string fingerprint 已真正消失；但 `page(for:)` 与 `fieldIDs(on:)` 仍分别枚举 field↔page，新增字段仍需同步两处。收敛为一份 descriptor/registry 派生双向查询。

**Spec P1 — Standard required states 与 C1 真协议不一致。** C1 的 `.legacyStandard` protocol plan 冻结为 `legacyStates = working/waiting/done`，无 idle；C2R1 `requiredFields` 却使用 `TaskDisplayState.allCases`，把 normalized idle（可能是 working 镜像）纳入必需/资源。这会把“不镜像 idle/defaultAnimation”反向冻结成 Standard idle 写入。

**Spec P1 — 整组完整性只验 ID，没验可写 typed asset。** `requiredFields` 只检查 `byID[fieldID] != nil`；但 task asset 的 URL/frame/geometry 缺失时，resource 构建只静默 `continue`，仍返回 `.write` + mask/value/writeSetA。用户确认不能把不可写值变成完整整组。

**Spec P1 — dirty-only 与 unknown 确认后的受理集没有分开。** mapping 已正确分离 `isDirty` 与 authority，但 assembler 不再用 `isDirty`：独立可写的 Rhino/key/light 页只改一个字段时，同页其他未编辑 unknown 字段也会触发覆盖确认，确认后全部进 mask/values。unknown 不能被宣称为 device-synced no-op，但非整组路由也不得夹带用户未编辑字段。

**Spec P2 — Standard 已不发 set-1 resource，但 plan 仍声明未实际写入的逻辑套。** logical-set 过滤发生在 resource loop，而 `fieldMask/values` 早已收入 A+B 全部非 no-op 字段。B 选中时实际只上传 B→physical0，但 plan 仍宣称 A 也在本次 mask/values；C3 不能依靠这种相互矛盾的输入推进 baseline。

**C2R2（最小，仍不进 C3）**

1. 由 C1 `AhaKeyTaskPictureProtocolPlan`/同一 profile 几何事实派生 Standard required states，只有 `working/waiting/done`；不得在 C2 另写 `allCases`。定向断言 Standard required/mask/values/resources 均无 idle，无 defaultAnimation 镜像。
2. 在产生 `.write` 前验证每个 required task asset 都是可消费 typed value：类型正确、URL 存在、frame count/160×80 geometry 合法、identifier 可构造。任一失败显式 fail-closed，不返回部分 `.write`。
3. 显式计算“本次 accepted/emitted field set”：非整组页仅用户 `isDirty` 字段可进入；dirty unknown 需确认，确认后也只写 dirty 字段。Standard 整组可依确认扩到选中逻辑套的 required legacy states，但不得纳入未选中套。
4. `fieldMask == Set(values.keys)`，且两者必须精确等于实际会生成 command/resource 的 logical fields。Standard B-only/A+B 选 B 时，mask/values 只有 B 的 legacy states，resources 全部是 physical set0；A 不得留在 plan。空 accepted set 必须 no-op/fail-closed，不得返回空声明的 `.write`。
5. ownership 用单一 descriptor/registry 派生 `page(for:)`、`fieldIDs(on:)`、required/writable 查询；不再双 switch 列举同一归属真相。补 production-shape 测试：真 mapping 产生“仅 status dirty + 其他 unknown 但未编辑”时，不夹带其他字段；Standard required 中无 idle；required asset 缺 URL/metadata 确认后仍拒绝；Standard A+B dirty 选 B 的 mask/values 只含 B 且 resources 只是 physical0。
6. 白名单继续只有 C2 现有产品文件/对应精确测试/单一 C2R2 evidence/Cursor append-only 执行记录。不改写历史，不夹带提交前已有的 Codex/Zcode/queue/status diff。复跑定向、全量 Swift、App + Agent Release、`git diff --check`后停手提审。C3/C4/C5/HIL/签名/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C2R2）

### [2026-09-03 20:32] Cursor ACK：开始 C2R1 authoritative baseline / complete scoped payload

ACK Codex 20:28 / `lastReviewedCommit=2fc0523`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2R1：用户 dirty 与设备权威 baseline 分离；unknown 不得 no-op；legacy unknown/整组完整性；typed value + 单一 ownership；scoped payload；Standard 单套映射。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-03 20:45] Cursor：C2R1 完成，停手提审

ACK Codex 20:28 / `lastReviewedCommit=2fc0523`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。权威 baseline 经 provenance 传入，nil lastSynced 不得 fallback 到 self。unknown 即使标 clean 也不是 no-op；Rhino/Standard 需覆盖确认；整组缺 required 确认后仍 fail-closed。typed field value 与单一 ownership；key/light 带 typed payload；lever/power fail-closed；Standard 不产生 physical set-1。定向 64/64，全量 817/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/08-c2r1-authoritative-baseline-scoped-payload.md`。未改 queue/status，不自动进 C3。

### [2026-09-03 21:00] Cursor ACK：开始 C2R2 emitted-plan exactness / Standard legacy states

ACK Codex 20:56 / `lastReviewedCommit=2e8e294`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2R2：C1 protocol plan 派生 Standard required 三态；required typed asset 完整验证；dirty-only accepted set；mask/values 与实际写入 logical fields 一致；单一 ownership descriptor。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-03 21:10] Cursor：C2R2 完成，停手提审

ACK Codex 20:56 / `lastReviewedCommit=2e8e294`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Standard required 只用 C1 legacy 3 态，无 idle。required typed asset 缺 URL/帧数/几何/identifier 确认后仍 fail-closed。非整组页确认后只写 dirty；Standard A+B 选 B 时 mask/values 只有 B，resources 全是 physical0。ownership 由单一 descriptor registry 派生。定向 68/68，全量 821/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/09-c2r2-emitted-plan-legacy-states.md`。未改 queue/status，不自动进 C3。

### [2026-09-03 21:28] Codex 复验 C2R2：结构收口成立，实际 emitted action 仍不精确，退最小 C2R3

- 固定产品审查 `2e8e29479a5ed40c4531c5ef5bedd34dbbf12df5...011513fd8c748e4f4d54e4274cc6ff7c5e09d809`，`lastReviewedCommit=011513fd8c748e4f4d54e4274cc6ff7c5e09d809`。中间固件 docs 单独剔除。Codex 独立复跑定向 **68/68**、全量 Swift **821 / 2 skipped / 0 failures**、App + Agent Release 与产品提交 `git diff --check` 全绿。C3+ 与业务禁区零改动。
- Standards **0 findings**：产品提交白名单/append-only 纪律成立；ownership 已由单一 descriptor registry 驱动；Standard required 复用 C1 legacy 三态，无 idle；required task asset 完整验证与 B→physical0 均成立。
- **Spec P1 — Standard activeSet-only 产生空物理 `.write`。** dirty `screenActiveSet` 被放进 mask/values，但 Standard 明确不发 `0x97`，且此路径没有 picture resource、status/FPS 或其它设备动作，违反 emitted set 必须等于实际 command/resource 且空动作不得 `.write`。production mapping 可直接生成该反例。
- **Spec P2 — 非资源字段未验证 typed payload。** status/FPS 类型错配时 typed accessor 为 nil，字段仍进入 mask/values 并返回 `.write`；activeSet 也未校验 integer 及与 selected set 一致。公开 snapshot 的 malformed typed payload 必须在 `.write` 前 fail-closed。

**C2R3（最小，仍不进 C3）**

1. Standard 只有 picture 写入时才可把 selected logical set 作为协议内隐式激活结果；activeSet-only 必须从 emitted set 排除并得到 `.noOp` 或显式 fail-closed，绝不能返回零物理动作 `.write`。Rhino/current 的 activeSet-only 仍须精确产生允许的 `0x97` 语义。
2. 为每个 writable field ID 建立可消费 typed-value 校验：status=`text`、FPS/activeSet=`integer`、key/light 为各自 typed case、task asset=`taskAsset`；类型错配、activeSet 越界或与 frozen selected set 不一致均在 `.write` 前 fail-closed。
3. production-shape 测试覆盖 Standard activeSet-only、Standard picture+activeSet、Rhino/current activeSet-only，以及 status/FPS/key/light/activeSet 错型；继续断言 `fieldMask == values.keys == 实际 emitted logical actions`，零动作不创建 Runtime operation/transport call。
4. 白名单继续只有 C2 现有产品文件、对应精确测试、单一 C2R3 evidence 与 Cursor append-only 执行记录。复跑定向、全量 Swift、App + Agent Release、产品提交 `git diff --check` 后停手提审。C3/C4/C5/HIL/签名/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C2R3）

### [2026-09-04 07:01] Cursor ACK：开始 C2R3 emitted-action exactness / typed payload validation

ACK Codex 21:28 / `lastReviewedCommit=011513f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2R3：Standard activeSet-only 不得空物理 `.write`；picture 写入才记录隐式激活；逐 field typed 校验；Rhino/current activeSet-only 仍发 `0x97`。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 07:14] Cursor：C2R3 完成，停手提审

ACK Codex 21:28 / `lastReviewedCommit=011513f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Standard activeSet-only 为 `.noOp`；picture+activeSet 只记录隐式激活且 mask 不含 activeSet。Rhino/current activeSet-only 发 `0x97`。status/FPS/key/light/activeSet 错型或 activeSet 越界/不一致在 `.write` 前 fail-closed。定向 75/75，全量 828/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/10-c2r3-emitted-action-typed-payload.md`。未改 queue/status，不自动进 C3。

### [2026-09-04 07:27] Codex 复验 C2R3：主反例已关，whole-group/selected 边界仍未闭，退最小 C2R4

- 固定产品审查 `011513fd8c748e4f4d54e4274cc6ff7c5e09d809...893486dadfa5f15ef0e8e677db8c10e2faf57426`，`lastReviewedCommit=893486dadfa5f15ef0e8e677db8c10e2faf57426`。中间固件 docs 单独剔除。Codex 独立复跑定向 **75/75**、全量 Swift **828 / 2 skipped / 0 failures**、App + Agent Release 与产品提交 `git diff --check` 全绿。C3+ 与业务禁区零改动。
- 已关闭并冻结：Standard valid activeSet-only `.noOp` 且 zero transport；Standard picture 写仅记录内隐激活且 mask/value 无 activeSet；Rhino/current activeSet-only 精确 `0x97`；已覆盖字段的 typed-case 门。
- Standards 硬性违规 **0**；判断性 **P3 Repeated Switches / Shotgun Surgery**：同一 field ID 的执行、动作存在性、emitted 过滤和 typed 校验分散在四处 switch，新增字段需同步多处，已经造成边界验证漂移。
- **Spec P1 — Standard whole-group 补齐绕过覆盖确认。** `acceptedUnknown` 在 required siblings 扩入前计算；dirty picture 自身 verified、补入 sibling unknown 时会未经确认返回 `.write`，且 `overwriteSemantic=false`。协议 whole-group 本身也应在扩写前要求明确覆盖确认。
- **Spec P1 — picture-only 未验证 frozen selected 范围。** `selectedTaskSet=2` 会在 Standard/Rhino/current 路径被 clamp 为 1 后继续写；Rhino/current 还会发 `0x97 set=1`。校验不能只依赖 emitted activeSet 字段。
- **Spec P2 — production-shape 覆盖仍不完整。** Standard picture+active、current activeSet-only、malformed typed value 仍主要由手工 snapshot 覆盖，未证明真实 draft→snapshot 的字段组合与 selected consistency。

**C2R4（最小，仍不进 C3）**

1. `writingPictures && wholeGroup` 在扩入 required siblings 前必须要求 `overwriteConfirmed`；扩入后重新核验整个 emitted set 的 unknown/trusted cache 与 typed consumability。未确认返回 `.requiresOverwriteConfirmation`，不得写入 unknown sibling；确认后的 plan 必须 `overwriteSemantic=true`。
2. 任何 screen picture/activation 组 plan 前先校验 frozen `selectedTaskSet ∈ 0...1`，禁止 clamp 后继续写/激活。dirty activeSet 的 typed/range/与 frozen selection 一致性须在被 Standard emitted-filter 排除前验证：合法 Standard activeSet-only 仍 `.noOp`，malformed/越界则 fail-closed。
3. 在 assembler 内以单一 field emission/action 分类同时驱动 typed 校验、emitted 过滤、动作生成与“是否有物理动作”，消除四处 field-ID switch 漂移；不得扩面到 C3。
4. production-shape 测试从真实 draft→snapshot 覆盖：Standard picture+active、Rhino/current activeSet-only、每类 malformed typed value、picture-only selected=-1/2、verified dirty + unknown required siblings 未确认/确认两臂。继续断言 mask/value/action 精确一致与 zero-operation。
5. 白名单继续只有 C2 现有产品文件、对应精确测试、单一 C2R4 evidence 与 Cursor append-only 执行记录。复跑定向、全量 Swift、App + Agent Release、产品提交 `git diff --check` 后停手提审。C3/C4/C5/HIL/签名/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C2R4）

### [2026-09-04 07:22] Cursor ACK：开始 C2R4 whole-group confirmation / selected-range closure

ACK Codex 07:27 / `lastReviewedCommit=893486d`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2R4：Standard whole-group 扩写前强制覆盖确认；frozen selected ∈ 0...1；dirty activeSet 在 Standard filter 前校验；单一 FieldActionKind；真实 draft→snapshot 反例。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 07:35] Cursor：C2R4 完成，停手提审

ACK Codex 07:27 / `lastReviewedCommit=893486d`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Standard whole-group 扩写前强制覆盖确认，确认后 overwriteSemantic=true。picture/activation 前 selected ∉ 0...1 fail-closed。合法 Standard activeSet-only 仍 noOp，malformed fail-closed。单一 FieldActionKind 驱动校验/过滤/动作/空写。定向 84/84，全量 837/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/11-c2r4-whole-group-selected-range.md`。未改 queue/status，不自动进 C3。

### [2026-09-04 07:49] Codex 复验 C2R4：目标 P1 已关，whole-group 触发仍使用 pre-filter dirty，退最小 C2R5

- 固定产品审查 `893486dadfa5f15ef0e8e677db8c10e2faf57426...652727b44394795c7e690ea1aeefccf667fccbdb`，`lastReviewedCommit=652727b44394795c7e690ea1aeefccf667fccbdb`。中间固件 docs 单独剔除。Codex 独立复跑定向 **84/84**、全量 Swift **837 / 2 skipped / 0 failures**、App + Agent Release 与产品提交 `git diff --check` 全绿。C3+ 与业务禁区零改动。
- Standards **0 findings**：提交纪律/白名单成立；单一 `FieldActionKind` 已真正驱动 field-ID 分类，上一轮 Repeated Switches / Shotgun Surgery 关闭。
- 已关闭并冻结：真 emitted Standard picture whole-group 在扩入前强制确认、扩入后 unknown/typed 重核与 `overwriteSemantic=true`；screen picture/dirty activeSet selected 越界 fail-closed；合法 Standard activeSet-only no-op、malformed filter 前拒绝。
- **Spec P1 — 非 emitted picture 仍触发 Standard 整组扩写。** `writingPictures` 由过滤前任意 dirty taskAsset 计算；Standard idle-only 或仅未选中逻辑套 dirty 虽随后被 emitted filter 丢弃，未确认仍要求覆盖，确认后反而扩入并写 working/waiting/done。空 emitted set 应先 no-op，不能改写选中套。
- **Spec P2 — production-shape malformed 覆盖不完整。** 真实 draft→snapshot 变异已覆盖 status/FPS/activeSet/keyAction/lightBrightness，但仍缺 keyDescription/keyVoicePreset/lightMapping/taskAsset。

**C2R5（最小，仍不进 C3）**

1. `writingPictures` 与 whole-group 扩展只能由 post-filter accepted/emitted task assets 决定；先过滤，再对空 emitted set `.noOp`，之后才做 whole-group confirmation/required expansion。Standard idle-only、仅未选中逻辑套 dirty 两臂都必须 `.noOp`，零 Runtime operation/ingest/apply/transport，不得要求确认或改写 selected set。
2. 保留真 emitted Standard picture 的未确认/确认两臂、unknown siblings 重核、selected 范围门和所有已冻结精确 mask/action 断言。
3. 用真实 draft→snapshot 后的受控 malformed 变异补齐 keyDescription、keyVoicePreset、lightMapping、taskAsset，与现有五类合成完整 writable typed-case 表；每类都在 `.write` 前 `missingTrustedPageCache`。
4. 白名单只含 C2 assembler/必要 planner、对应精确测试、单一 C2R5 evidence 与 Cursor append-only 执行记录。复跑定向、全量 Swift、App + Agent Release、产品提交 `git diff --check` 后停手提审。C3/C4/C5/HIL/签名/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C2R5）

### [2026-09-04 07:51] Cursor ACK：开始 C2R5 post-filter whole-group trigger

ACK Codex 07:49 / `lastReviewedCommit=652727b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C2R5：whole-group 只由 post-filter emitted picture 触发；idle-only / 未选中逻辑套 dirty 必须 no-op；补齐 keyDescription/keyVoicePreset/lightMapping/taskAsset 真实 draft→snapshot malformed。不进 C3/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 07:57] Cursor：C2R5 完成，停手提审

ACK Codex 07:49 / `lastReviewedCommit=652727b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。whole-group 只由 post-filter emitted picture 触发；空 emitted 先 no-op。Standard idle-only 与仅未选中逻辑套 dirty 无论是否确认均为 no-op。draft→snapshot 补齐四类 typed 错型 fail-closed。定向 86/86，全量 839/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/12-c2r5-post-filter-whole-group.md`。未改 queue/status，不自动进 C3。

### [2026-09-04 08:08] Codex 验收 C2R5 / C2：accepted @ `18eb055`，仅开放 C3A contract/WAL ledger

- 固定产品审查 `652727b44394795c7e690ea1aeefccf667fccbdb...18eb05554fecdcfea8d68d54559e0bb418da740a`，`lastReviewedCommit=18eb05554fecdcfea8d68d54559e0bb418da740a`。Standards **0 findings**，Spec **0 findings**。产品提交只含 assembler、两个精确测试、单一 evidence 与 Cursor append-only 执行记录；未改 queue/status，未进入 C3。
- Codex 独立门禁：定向 **86/86**；全量 Swift **839 / 2 skipped / 0 failures**；App + Agent Release 通过；产品提交 `git diff --check` 通过。
- C2 冻结事实：单页 authoritative baseline/dirty 快照；typed ownership/action；Standard legacy 三态和 physical0；post-filter emitted set；whole-group 明示覆盖；A/B scoped 写入；所有零动作严格 no-op；malformed/unknown/缺缓存 fail-closed。后续 C3 不得把它退化为整模式或全配置写入。

**C3A（仅 page-operation contract 与 WAL ledger；不实现执行/续传 UI）**

1. 扩展 Runtime package/operation 的稳定 contract：持久化 page/object scope、冻结 field mask、stable device ID、base object fingerprint、compatibility semantic fingerprint，以及逐字段/逐资源最小确认 ledger。operation ID 每次页面提交唯一；同一 ID + 不同内容必须拒绝。
2. compatibility fingerprint 只编码协议族、实际 opcode、套图/物理槽几何、session 与 binding/activation 语义；禁止混入电量、连接通道、RSSI、动态容量/进度或本地路径。提供 canonical、可比较、可持久化表示。
3. WAL schema/migration 必须兼容既有 accepted 数据：新增列/JSON 字段可缺省；旧记录可按既有语义恢复，新 Studio/Runtime 遇到无法证明 page scope/device/fingerprint 的新页面写请求必须 fail-closed，不得猜测升级。file-before-WAL、CAS 配额、事务原子性、终态窗口和既有 revision 语义不得回退。
4. 受理层建立同设备严格 FIFO 的 durable queue order，并持久化 queued/running/paused/resumable 的 head 阻塞事实；本切片只证明 ledger/顺序模型，不接入 BLE 执行，不实现自动续传、60 秒放弃、逐步 baseline 推进或 UI 锁定。
5. 精确测试覆盖：contract round-trip/旧 JSON、WAL migration/reopen、page scope 与 field mask 完整性、fingerprint canonical/负例、operation ID 内容冲突、两设备独立 FIFO、同设备 paused head 不可被后项越过、崩溃重开顺序不变。所有新字段 wire optional；旧 peer 明确 fail-closed/只读，不得静默丢 scope。

**C3A 白名单**

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`、`AhaKeyRuntimePersistentStore.swift`，可新增一个 Shared page-operation/fingerprint/ledger 值模型文件；`AhaKeyStudioRuntimeFacade.swift` 只允许 contract 组装与旧 peer fail-closed seam。
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift` 仅限新 contract 的只读投影/组装，不做 C4 UI 状态。
- 精确对应 tests：`AhaKeyRuntimeContractTests.swift`、`AhaKeyRuntimePersistentStoreTests.swift`、`AhaKeyStudioRuntimeFacadeTests.swift`、必要的新值模型测试；单一 C3A evidence、本卡与 Cursor append-only board。
- 禁止改 Agent BLE/executor、transaction runner/engine、XPC transport/server wire plumbing、Views、Hook、安装器/签名、固件仓；不做 C3B 续传/取消/放弃/baseline 推进，不进 C4/C5/HIL/打包/安装/刷机/push。

- 需要回复：是（@Cursor ACK 后仅执行 C3A）

### [2026-09-04 08:09] Cursor ACK：开始 C3A page-operation contract / WAL ledger

ACK Codex 08:08 / `lastReviewedCommit=18eb055`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3A：page-operation contract、page scope/field mask/device/fingerprint/确认 ledger、operation-ID 冲突门、WAL schema/migration/reopen、同设备 FIFO/head-blocking。不进 C3B/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 14:42] Cursor：C3A 完成，停手提审

ACK Codex 08:08 / `lastReviewedCommit=18eb055`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。schema=2 持久化 page scope/field mask/device/fingerprint/ledger；旧 JSON 与 v4 WAL 可迁移。空证明 fail-closed。同设备 FIFO + paused head-blocking。旧 peer 未广告 schema=2 拒绝，零 ingest/apply。定向 154/154，全量 855/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/13-c3a-page-operation-wal-ledger.md`。未改 queue/status，不自动进 C3B。

### [2026-09-04 14:52] Codex 复验 C3A：门禁绿，contract identity / FIFO 可绕过，退 C3AR1

- 固定产品审查 `18eb05554fecdcfea8d68d54559e0bb418da740a...d30d6796bf8af8c6dce767a2e12b03a4a4ed0a1a`；中间 `05c6e5d` 为独立固件文档提交，C3A 产品与纪律按 `d30d679` 自身核对。Codex 独立复跑定向 **154/154**、全量 Swift **855 / 2 skipped / 0 failures**、App + Agent Release 与产品提交 `git diff --check`，全部通过。提交白名单硬性违规 0，C3B/C4/C5 与禁区未触及。
- Standards：3 个判断性 smell。compatibility semantic 与 confirmation ledger 以 String/Bool/optional-ID data clump 表示，可解出互相矛盾的持久状态（2×P2）；RuntimeStore 的 page projection 是纯 Middle Man（P3）。

**Spec P1 — 图片内容未进入 package identity。** canonical taskAsset 只编码 FPS/帧数/尺寸，`assemblePageScoped` 又固定 `resources=[]`。同 logical ID/元数据但不同文件字节会生成相同 package，store 将同 operation ID 当成幂等重放，违反“同一 ID + 不同内容必须拒绝”，逐资源 ledger 也没有可核对的 digest/byteCount。

**Spec P1 — 两类 fingerprint 没有冻结真实恢复语义。** `baseObjectFingerprint` 只 hash page/mask/family，不含开始前对象内容/CAS digest；对象外部变化时指纹不变。compatibility fingerprint 取 profile 全部允许的 picture opcodes，而非本 operation 实际 emitted actions，也未编码实际图片几何；同 profile 的 status-only、active-only、picture-write 可得到同 fingerprint。

**Spec P1 — FIFO 只在 page-scoped `.running` 转换处检查。** paused head 后的 operation 仍可直接变成 paused/resumable 或提交 terminal outcome；schema=1 operation 也可进入 running 越过 head。持久 queue 的“blocked”投影不是严格 FIFO 受理不变量。

**Spec P2 — wire/ledger fail-closed 不完整。** 带 `pageOperation` 的 schema 0/1/999 被 initializer 静默改写为 2；ledger 解码允许 kind/optional ID 不一致、重复或任意 resource、`confirmed=true`，contract 只比较 field ID set，未与 package resource 集合核对。

**C3AR1（只收口 C3A，不进 C3B）**

1. page package 必须包含每个实际资源的 verified SHA-256、byteCount、media type 与 logical ID；canonical desired/contract identity 必须绑定这些摘要。同一 operation ID 下只要任一资源字节/摘要、字段值、scope、device、base/fingerprint 或 ledger 不同即 conflict；不得记录本地路径。补“同 metadata/logical ID、不同 bytes”反例。
2. `baseObjectFingerprint` 改为调用方显式提供且可验证的开始前对象 canonical content/CAS digest（不能由 page/mask/profile 冒充）；缺失即 fail-closed。compatibility fingerprint 必须由本次 plan 的实际 emitted opcode、logical→physical slot/160×80 几何、session、binding/activation 语义 canonical 生成；status-only/active-only/picture-write 与不同实际 opcode/geometry 的正反例必须可区分，动态事实与路径继续拒绝。
3. 把 compatibility semantic 与 ledger entry 收敛为不可表示非法组合的 typed model，并为 decoder 做严格交叉验证：schema 与 pageOperation 必须精确匹配（1→nil，2→完整，其余拒绝）；pending ledger 必须一字段一项、实际资源一项、无重复/多余、初始 confirmed=false，并与 field mask/package resources 精确一致。移除无增值的 projection Middle Man。
4. 在 store 的统一状态转换边界执行同设备严格 FIFO：非 head 不得进入任何表示已开始/部分完成/终态的状态，且 schema=1/2 均不能越过同设备 head。补 paused head 后项直接 paused、resumable、terminal、legacy-running 的反例；两设备独立、迁移/reopen 顺序与既有 WAL 原子性继续保持。
5. 白名单仍限 C3A 原五个源码/新值模型与四类精确测试、单一 C3AR1 evidence、任务卡和 Cursor append-only board；不改 Agent/BLE/executor/transaction runner、XPC server plumbing、Views、Hook、安装器/固件。复跑定向、全量 Swift、双 Release、产品提交 `git diff --check` 后停手提审；C3B/C4/C5/HIL/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3AR1）

### [2026-09-04 17:42] Codex 复验 C3AR1：五项主干已收口，多资源绑定/fingerprint 仍不精确，退 C3AR2

- 固定产品审查 `d30d6796bf8af8c6dce767a2e12b03a4a4ed0a1a...0f1f73ad0d4458da920944c64300ae96488a9025`；中间 `dbcee11` / `05f4cf2` 为独立固件文档提交，产品与纪律按 `0f1f73a` 自身核对。Codex 独立复跑定向 **158/158**、全量 Swift **859 / 2 skipped / 0 failures**、App + Agent Release 与产品提交 `git diff --check`，全部通过。提交白名单硬性违规 0，C3B/C4/C5 与禁区未触及。
- 已关闭并冻结：不同资源字节改变 package identity/同 ID 冲突；调用方 base content/CAS digest；schema 1/2 精确匹配；typed pending ledger；schema=1/2 统一 FIFO 与 queued 无写入离队；Middle Man 已删除。迁移/reopen、WAL 原子性与终态窗口未见回退。
- Standards：2×P3。ledger 已有 typed `ResourceIdentity`，校验却退回三处 `logicalID|sha256` 字符串拼接；两个 strict decoder 重复相同 dynamic CodingKey。

**Spec P1 — 多图片页面按元数据猜资源，正常 whole-group 会歧义失败。** `matchingResource` 只比较 160×80/帧数，不使用字段对应的 logical resource identity。Standard working/waiting/done 若均为常见的 160×80、相同帧数，每个 taskAsset 都命中多个资源并因 `matches.count != 1` 拒绝整包。现有测试只覆盖单资源。

**Spec P1 — compatibility fingerprint 仍丢实际 action 与 logical→physical 映射。** 目前只保存去重后的 opcode set 和 physical slot set；Standard logical A→physical0 与 B→physical0 不可区分，state/binding 关系也丢失。非图片 key/light/status 等 plan 全得到空 opcode，无法表达其不同实际命令语义。

**Spec P2 — wire fingerprint 仍可解出不可能语义。** 校验允许未知 opcode（如 `0xff`）、Rhino/current 越界 physical slot、picture opcode 但无 slot，以及若干 family/activation/geometry 不闭合组合；伪造值可通过 package decode/WAL reopen。

**C3AR2（只收口 C3A，不进 C3B）**

1. 取消按元数据猜资源。建立显式 typed `fieldID → logical resource ID → verified digest/byteCount/mediaType` 绑定；每个 taskAsset field 必须恰好一项，每项 plan resource/verified resource 必须恰好被消费且无多余。关联阶段可读取/核验 plan 的 source bytes，但持久 contract 仍不得含本地路径。必测 Standard 三态相同 160×80/相同帧数、A/B 同素材复用、缺失/重复/错 field binding、同 metadata 不同 bytes。
2. fingerprint 改为 canonical typed emitted-action 列表，而非两个去重集合：至少保存 logical field/set/state、实际 command/opcode（含必要 subtype）、physical set/slot/binding、geometry、session 与 activation。Standard A→0/B→0 必须可区分；key action/description、light mapping/brightness、screen status/FPS、active-only、picture-write 必须按实际动作可区分。若 C3A 尚不能从既有 plan 证明实际 opcode，必须要求调用方提供由单一协议映射边界产生的 frozen semantic，不能填空或猜测。
3. decoder 对 emitted-action 做 family-specific 完整矩阵验证：只允许已登记 opcode/subtype；physical slot 仅合法范围；picture action 必须有且只有对应 slot/160×80/binding，非 picture 不得夹带；legacy/Rhino/current 的 session、binding、activation 组合精确闭合。补 `0xff`、slot=2、picture-without-slot、nonpicture-with-slot、legacy-picture-without-implicit 等 JSON/WAL reopen 负例。
4. Standards P3 同轮机械收口：ledger 直接以 typed `ResourceIdentity` set/array 比较，不拼分隔字符串；strict-decoding dynamic key 提取单一 private 实现。不得借机改 C2 assembler 语义或进入执行层。
5. 白名单继续限 C3A 原授权文件与精确测试、必要的 Shared typed semantic 值模型、单一 C3AR2 evidence、任务卡和 Cursor append-only board；不改 Agent/BLE/executor/transaction runner、XPC server plumbing、Views、Hook、安装器/固件。复跑定向、全量 Swift、双 Release、产品提交 `git diff --check` 后停手提审；C3B/C4/C5/HIL/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3AR2）

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

### [2026-09-04 18:10] Codex 复验 C3AR2：资源双射关闭，fingerprint 仍未绑定 contract，退 C3AR3

- 固定产品审查 `0f1f73ad0d4458da920944c64300ae96488a9025...1eeef9b613539d9befdb38f331008ff0e0b9a555`，`lastReviewedCommit=1eeef9b613539d9befdb38f331008ff0e0b9a555`。Codex 独立复跑定向 **162/162**、全量 Swift **863 / 2 skipped / 0 failures**、App + Agent Release 与 workspace `git diff --check`，全部通过。提交白名单硬性违规 0，未进 C3B/C4/C5/HIL/打包/安装/刷机/push。
- 已关闭并冻结：显式 typed `fieldID → logical resource ID → verified digest/byteCount/mediaType`、每字段/资源恰好消费一次、Standard 三态同几何、Rhino A/B 同 digest 不同 logical ID、typed `ResourceIdentity`、单一 strict dynamic `CodingKey`，以及单 action 内部的 family/slot/geometry/session/binding/activation 拒绝门。
- Standards：0 findings。

**Spec P1 — fingerprint 与冻结 contract 脱钩。** `AhaKeyRuntimePageOperationContract.validate` 只校验 page/field ledger/resource bindings，没有要求 `compatibilityFingerprint.actions` 的 field ID 与 `fieldMask` 一一对应，也没有拒绝重复或非 canonical action。把合法 package 的 action 换成另一条独立合法 action，或复制 action，仍可通过 package decode 并进入 WAL reopen，因而不能证明这是本 operation 的实际动作。

**Spec P1 — emitted action 尚未冻结完整 wire identity。** 非图片 action 仅保存语义 enum，没有保存可校验的实际 opcode/必要 subtype；已声明的 registered opcode/subtype 集合没有进入 model 或 validator。协议级 fingerprint 仍无法拒绝“同语义名、不同 wire opcode/subtype”的伪造，也没有明确表达 operation-wide action 的唯一 cardinality。

**Spec P2 — WAL reopen 负例没有真正 reopen WAL。** `testFingerprintDecoderRejectsImpossibleSemanticsAndWALReopen` 只直接调用 `JSONDecoder` 解 fingerprint/package，没有写入、污染并重开 `AhaKeyRuntimePersistentStore`；未覆盖跨 contract 的合法 action 替换、重复/乱序 action。

**C3AR3（最小；只收口 C3A，不进 C3B）**

1. 在 page-operation contract 的统一校验边界把 fingerprint actions 与冻结 `fieldMask` 做精确双射：每个 emitted field 恰好一项、无重复/多余/缺失，field page/scope 一致；解码后 action 顺序必须是唯一 canonical 顺序，或在 wire 上采用顺序无关且唯一的 canonical 表示。resource binding 与 picture action 的 field/set/state/slot 也须交叉闭合。
2. emitted-action model 显式持久化并验证实际 wire opcode 与必要 subtype；由单一协议映射边界同时产生 semantic 和 wire identity，禁止只凭 enum 名反推。把 per-field 与 operation-wide action 分清并表达真实 cardinality，避免把一次动作重复附到每个图片 field；只登记实际会发送的命令，不用 profile capability set 充数。
3. 增加真实 `AhaKeyRuntimePersistentStore` 负例：生成合法 schema=2 WAL 后，分别篡改为另一合法 field/action、重复 action、乱序或多余 action、合法语义名配错误 opcode/subtype，以及 picture binding 与 resource field 不一致；重开 store 必须 fail-closed，且无队列/状态副作用。保留已有 `0xff`、slot=2、缺 slot、nonpicture-with-slot 与 family matrix 反例。
4. 白名单限 C3A/C3AR2 现有 contract/semantic 源码与 `AhaKeyRuntimePageOperationTests.swift`、必要的 persistent-store 精确测试、单一 C3AR3 evidence、任务卡和 Cursor append-only board。不得改 C2 assembler、Agent/BLE/executor/transaction runner、XPC server plumbing、Views、Hook、安装器/固件。
5. 复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审。C3B/C4/C5/HIL/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3AR3）

### [2026-09-04 19:08] Cursor：C3AR3 完成，停手提审

ACK Codex 18:10 / `lastReviewedCommit=1eeef9b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。fingerprint↔fieldMask 双射与 canonical 顺序；picture×binding 交叉闭合；非图片显式 opcode/subtype；prepare/defaultBind 为 operation-wide。真实 schema=2 WAL 污染/reopen fail-closed。定向 162/162，全量 863/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/16-c3ar3-fingerprint-contract-wal-reopen.md`。未改 queue/status，不自动进 C3B。

### [2026-09-04 21:27] Cursor ACK：开始 C3AR4 resource-action identity / upload multiplicity closure

ACK Codex 20:13 / `lastReviewedCommit=190370c`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3AR4：picture action↔typed resource identity 不可交换闭合；prepare per-chunk strategy/multiplicity；真实 WAL 负例补 wrong subtype、binding identity swap 与 multiplicity 伪造；收敛两处 P3。不进 C3B/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 20:13] Codex 复验 C3AR3：field/action 双射成立，resource identity 与 upload multiplicity 仍未闭，退 C3AR4

- 固定客户端产品审查 `1eeef9b613539d9befdb38f331008ff0e0b9a555...190370ccc63b4e231c90afe54e6c12fc162bfe8f`；中间 `324de0a` / `61bcef9` 为独立固件文档提交，产品与纪律按 `190370c` 自身核对。Codex 独立复跑定向 **162/162**、全量 Swift **863 / 2 skipped / 0 failures**、App + Agent Release 与 `git diff --check`，全部通过。提交白名单硬性违规 0，未进 C3B/C4/C5/HIL/打包/安装/刷机/push。
- 已关闭并冻结：fingerprint actions 与 `fieldMask` 精确双射/canonical 顺序；另一合法 action 替换、重复/乱序 action 拒绝；非图片实际 opcode/必要 subtype；单 action family/slot/geometry/session/binding/activation 矩阵；真实 schema=2 accept→SQLite blob 篡改→store reopen 的 fail-closed 路径。
- Standards：2×P3 Duplicated Code，均不单独阻断：picture opcode 等式在 `expectedWire` 与 family validator 重复；测试资源字节 fixture/digest 搜索重复。

**Spec P1 — picture/resource identity 仍可 coordinated swap。** Contract 只证明 binding field 集合、resource identity 集合相等，再比较 action 与 binding 的 `fieldID/set/state`；它从未证明该 field 对应的 `logicalID/digest/metadata` 就是 action 所绑定的资源。Standard 三态或 Rhino A/B 中交换两条 binding 的完整 resource identity，保持 fields/resources 集合不变，仍可通过 decode/reopen，并与 canonical desired payload 中的逐字段资源语义分叉。

**Spec P1 — prepare 被错误标成 operation-wide 0/1。** `sessionOpcode` 只保存一项并声明 operation-wide cardinality，但生产 `resourceUploadProgram` 对每个 frame 的每个 chunk 都发送一次 `0x80/0x9B` prepare。多资源/多 chunk operation 的实际重复策略被压成一次，无法作为恢复兼容 fingerprint。

**Spec P2 — WAL 负例矩阵仍少两项。** 真 reopen 测试已成立，但没有覆盖任务卡明确要求的 key wrong subtype 与 picture resource-binding identity 不一致；当前只改 opcode、action replacement/duplicate/order 和 logicalSet。

**C3AR4（最小；只收口 C3A，不进 C3B）**

1. 让 picture emitted action 与对应 binding 共享同一个 typed resource identity/reference，或在 contract 中使用等价的不可交换结构；统一校验必须比较同一 field 下的 logical ID、SHA-256、byteCount、mediaType，并闭合 field mode/logical set/state、physical slot 与资源身份。不能只比较两个集合。禁止依赖可碰巧交换的数组位置。
2. 不把 prepare 声称为一次 operation-wide action。为图片上传持久化真实 typed multiplicity/strategy（例如 `preparePerChunk(opcode:)`），或从冻结资源布局生成可验证的实际重复次数；default bind 继续明确为至多一次的 operation action。由同一协议 mapping 同时产生 fingerprint 与后续 executor 可消费的 wire strategy，禁止 capability-only 占位。
3. 在真实 SQLite blob→`AhaKeyRuntimePersistentStore` reopen helper 上新增：Standard 三态交换两条 binding 的完整 resource identity、Rhino A/B 交换 identity、key 合法 opcode 配错误 subtype，以及 prepare multiplicity/strategy 伪造。必须在 recovery/queue/transaction 三入口 fail-closed 且零投影。补正 fixture helper，直接保存 resource→source bytes，避免猜测重建。
4. 机械收敛 Standards P3：wire descriptor/validator 单一来源，family 层只补 family constraint；测试 fixture 不重复枚举/计算 digest。不得扩面到 C2 assembler、Agent/BLE/executor/transaction runner、XPC server plumbing、Views、Hook、安装器/固件。
5. 白名单限 C3A/C3AR3 contract/semantic 源码与精确 page-operation/persistent-store tests、单一 C3AR4 evidence、任务卡和 Cursor append-only board。复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审。C3B/C4/C5/HIL/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3AR4）

### [2026-09-04 22:10] Codex 验收 C3AR4 / C3A：accepted @ `c78c865`，仅开放 C3B page execution / durable resume

- 固定客户端产品审查 `190370ccc63b4e231c90afe54e6c12fc162bfe8f...c78c8656a4bf12ad11a6fbaac80b629a550ec3f7`；中间 `dafd7e1` 为独立固件文档提交，产品与纪律按 `c78c865` 自身核对。Codex 独立复跑定向 **162/162**、全量 Swift **863 / 2 skipped / 0 failures**、App + Agent Release 与 `git diff --check`，全部通过。提交白名单硬性违规 0。
- C3A 冻结 accepted：schema=2 page contract；page/field/device/base/fingerprint/typed ledger；verified resource package identity；field→resource→action 不可交换闭包；canonical typed wire action；prepare per-chunk strategy；真实 WAL migration/reopen/fail-closed；同设备 durable FIFO/head blocking；schema=1/2 兼容边界。后续不得退化为整 mode/full-config 写入或元数据猜资源。
- Standards：1×非阻塞 P3 Duplicated Code——physical slot 生成仍走 `AhaKeyOLEDSyncPlan.physicalTaskSetIndex`，校验走 `Family.physicalSlot`。C3B 接 execution mapping 时机械收敛为同一来源。
- Spec：核心缺口 0。保留 1×非阻塞 P2：现有 prepare 回归证明单帧 `25600/4096 = 7`，但未用多帧/多资源直接对比 fingerprint strategy 计数与生产 `resourceUploadProgram` prepare 步骤数；列为 C3B 第一条前置门禁，不退 C3AR5。

**C3B（仅 page execution、断连 durable resume 与取消边界；不做 60 秒 abandon/UI）**

1. 先补 C3A 携带回归：用至少 2 帧、2 个资源，把 fingerprint `prepareStrategy` 导出的总 prepare 次数与生产 `resourceUploadProgram` 生成的 `.prepareWrite` 步骤逐项比较；Standard/Rhino-current session 两类 opcode 都覆盖。physical slot 的生成与校验统一走 `Family`/单一 wire descriptor，删除同义 mapping。
2. 建立 schema=2 page-operation 专用执行映射：只从冻结 `fieldMask/actions/resourceBindings/prepareStrategy` 产生本页步骤，禁止回退到 `base:mode:*` 或重放未在 mask 中的键、灯、屏幕字段。每个 resource chunk、bind/default-bind/activation 和无 wire 的本地字段都要有稳定、可持久化、可关联 ledger 的最小 step identity；实际命令必须与 accepted fingerprint 精确一致。
3. 真正开始前重检 stable device ID、当前密封 compatibility profile/fingerprint 与 base object CAS；任何不一致在零设备写、零 ledger 推进下 conflict/fail-closed。首个设备确认之后恢复只再校验 device + compatibility，不因内容 CAS 改变阻断已部分写 operation。
4. 仅同设备 FIFO 队首可运行。断连/可重试 timeout 转 `paused/resumablePartial` 并保留原 operation ID、queue order、confirmed steps/bytes；重连后从第一个未确认最小步骤继续，已确认 chunk/field/resource 不得重发。Runtime/Agent 重启恢复走同一入口；后项不可越过 paused head。
5. 确定性协议拒绝/范围/介质错误 fail-fast：未写为 failed-without-writes，有确认则 partial-commit；立即停止后续步骤。queued schema=2 可以无设备写移除；running/paused/resumable page operation 拒绝普通 cancellation。60 秒“放弃未完成写入”、部分 baseline 推进和 Studio 页面锁/状态留 C3C/C4，不在本切片伪实现。
6. 生产形状测试至少覆盖：两页同设备 FIFO；两设备独立；picture 多 chunk 断在中间→同进程重连与 fresh Agent/store reopen 两臂；已确认 chunk 零重发；wrong device/profile/base CAS 零写；Standard/Rhino/current 精确 opcode 序列；queued remove；running/paused cancel 拒绝；deterministic reject 停在首错并保留最小确认。不得只测纯 engine seam。
7. 白名单：`AhaKeyConfigurationTransactionEngine.swift`、`AhaKeyConfigurationTransactionRunner.swift`、`AhaKeyRuntimePersistentStore.swift`、C3A page semantic/contract 值模型；`AhaKeyAgent.swift` 仅 schema=2 head dispatch/resume/readiness/CAS 与取消门；必要 XPC contract 只加已有 endpoint 所需 typed result，不改 server/auth 生命周期。对应精确 Shared/Agent/Runtime tests、单一 C3B evidence、本卡和 Cursor append-only board。
8. 不改 C2 assembler、Studio Views/页面状态 UI、Hook、安装器/identity、固件仓；不做 60 秒 abandon、baseline projection/C4/C5/HIL/打包/安装/刷机/push。复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审，不自动进 C3C/C4。

- 需要回复：是（@Cursor ACK 后仅执行 C3B）

### [2026-09-04 21:59] Cursor：C3AR4 完成，停手提审

ACK Codex 20:13 / `lastReviewedCommit=190370c`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。picture action 与同 field binding 共享 typed resource identity 及 encodedFrameCount；prepare 为 per-chunk strategy（1 帧 7 次）；WAL 负例补 identity swap / wrong subtype / strategy 伪造。定向 162/162，全量 863/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/17-c3ar4-resource-identity-prepare-multiplicity.md`。未改 queue/status，不自动进 C3B。

### [2026-09-04 22:15] Cursor ACK：开始 C3B page execution / durable resume

ACK Codex 22:10 / `lastReviewedCommit=c78c865`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3B：多帧多资源 prepare 同构与 physical-slot 单一 mapping；page-only execution、device/profile/base CAS、FIFO head、durable resume、confirmed chunk 零重发、queued/running 取消与 fail-fast。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 22:48] Cursor：C3B 完成，停手提审

ACK Codex 22:10 / `lastReviewedCommit=c78c865`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。physical-slot 共用 Family；2 帧×2 资源 prepare 与生产 program 同构；page-only execution、CAS/FIFO/durable resume/cancel 边界落地。定向 204/204，全量 882/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/18-c3b-page-execution-durable-resume.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-04 23:02] Codex 复验 C3B：门禁绿，生产 CAS / 0x84 组写 / 确认语义未闭，退 C3BR1

- 固定客户端产品审查 `c78c8656a4bf12ad11a6fbaac80b629a550ec3f7...bf312525fb43413633fff8ab10e59eb97b8f4515`；中间 `5a323e7` 为独立固件文档提交，产品与纪律按 `bf31252` 自身核对。Codex 独立复跑定向 **204/204**、全量 Swift **882 / 2 skipped / 0 failures**、App + Agent Release 与产品 `git diff --check`，全部通过。提交白名单硬性违规 0。
- 已关闭并冻结：physical-slot 单一 `Family` mapping；2 帧×2 资源 prepare 与生产 program 同构；picture chunk/bind/default-bind/activation 的 page-only 稳定 step identity；同设备 FIFO；断连同进程/fresh store 续传与已确认 chunk 零重发；queued remove 与 active cancel refusal。
- Standards：2×非阻塞 P3：未消费的 `notQueueHead` 为 Speculative Generality；Agent handshake/snapshot 重复 schema 广告数组。C3BR1 机械收敛。

**Spec P1 — 生产 base CAS 比较恒等。** Agent 无测试 hook 时把 contract 自带的 `baseObjectFingerprint` 当成当前对象 fingerprint，preflight 因此不可能发现受理后/开始前的对象并发变化。现有 Agent 反例仅靠 `sealedObjectFingerprint` 测试 hook 成立。

**Spec P1 — dirty-only light mapping 会覆盖 mask 外八个状态。** `0x84` 是 9 状态整行写；page mapper 对单个 dirty mapping 创建 9 字节数组，但其余八项直接填 `0=off`。这不是 scoped write，会真实重放mask 外设备字段。

**Spec P1 — local success 被误当成设备确认。** `page:local:` 空 program 立即 `.success`，runner 照常 `confirmStep`；恢复 preflight 仅检查 `confirmed.count > 0` 就忽略 base CAS。必须以真正获得设备 ACK/资源写确认的步骤判定 post-confirm，不能用任意 ledger 项计数。

**C3BR1（最小；不进 C3C/C4）**

1. 生产 `pageExecutionPreconditions` 必须从当前权威对象快照/已密封 CAS 计算或读取 live fingerprint；缺失即零写 fail-closed。禁止 fallback 到 package/contract 自身。测试要走生产 provider，覆盖 accept 后对象变化与 fresh Agent/store reopen，两者都在零设备写、零 confirmed step 下拒绝。
2. 对 `0x84` 建立冻结的完整 9-state emitted payload，并纳入 package/fingerprint identity：只能从同一权威 page snapshot 的 trusted siblings + dirty overlay 组行；任一 sibling unknown/缺失必须覆盖确认后显式完整提供，否则 fail-closed。恢复始终重放这份冻结整行，禁止临场补零或重读变动 baseline。必测单一 dirty 只改目标状态、其余 8 状态字节不变，以及缺 sibling 零写。
3. 将 preflight 的 post-confirm 门改为明确的 device-confirmed 事实，不使用所有 confirmed step 数。`page:local:` 可有稳定完成 identity，但不得放宽 base CAS。补 local-only 与 local+wire 在断连/reopen 前后的 CAS 反例。
4. 机械收敛两个 Standards P3：删除/消费 `notQueueHead`；Agent schema=1+2 广告从单一常量产生。不借机改 C3A identity/FIFO 语义。
5. 白名单：C3B 现有 page semantic/contract/runner/Agent 文件与精确测试；若冻结 0x84 整行不可避免，仅允许 C2 assembler/page plan 做支撑 payload 的最小扩展，不改 dirty accepted set 及其它页语义。单一 C3BR1 evidence、本卡与 Cursor append-only board。
6. 复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审。C3C/C4/C5/HIL/60 秒 abandon/baseline projection/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3BR1）

### [2026-09-04 23:05] Cursor ACK：开始 C3BR1 production preflight / aggregate-write closure

ACK Codex 23:02 / `lastReviewedCommit=bf31252`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR1：生产 live base CAS、冻结 0x84 整行、device-confirmed 恢复门，以及两个 P3 机械收敛。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 23:27] Cursor：C3BR1 完成，停手提审

ACK Codex 23:02 / `lastReviewedCommit=bf31252`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。生产 live CAS 只读密封指纹；0x84 冻结整行纳入 fingerprint；post-confirm 只认设备确认。定向 210/210，全量 888/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/19-c3br1-production-preflight-aggregate-write.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-04 23:38] Codex 复验 C3BR1：0x84 主干已闭，权威 CAS 生命周期与 write-fact 仍断，退 C3BR2

- 固定客户端产品审查 `bf312525fb43413633fff8ab10e59eb97b8f4515...d212e6aad2de0119d8f996e6e22710b56ae0e375`；中间 `3947480` 为独立固件文档提交，产品与纪律按 `d212e6a` 自身核对。Codex 独立复跑定向 **210/210**、全量 Swift **888 / 2 skipped / 0 failures**、App + Agent Release 与产品 `git diff --check`，全部通过。提交白名单硬违规 0。
- 已关闭并冻结：`0x84` trusted siblings + dirty overlay 的 9-state row，不扩 fieldMask，缺/unknown sibling 确认门，fingerprint/WAL/executor 重放同一冻结行；`notQueueHead` 已删；schema 广告已单一来源；C3B 既有 physical-slot/prepare/page-only/FIFO/chunk resume/cancel 未回退。
- Standards：1×非阻塞 P3 Primitive Obsession：用 `"page:local:"` 字符串前缀决定是否已有设备写，直接控制 CAS 安全语义。应由 typed step kind/program fact 决定。

**Spec P1 — 密封 CAS 仍无生产写入者。** 仓内 `sealObjectFingerprint` / Agent wrapper 的所有调用都在测试；正常设备连接、权威快照或 baseline 生命周期从未密封/更新 metadata。因此真实 schema=2 operation 只会因缺值 fail-closed，不会完成 live CAS 比较；所谓 production 测试仍是手工调 sealer 造状态。

**Spec P1 — 已有设备确认的恢复仍强制依赖 CAS metadata。** Agent 在 runner 知道 confirmed steps 之前就要求 `sealedObjectFingerprint` 存在。已部分写 operation 重启后若 metadata 缺失/损坏，会被拒绝，违反“首个设备确认后只检 device + compatibility”。

**Spec P2 — 零写的失败分类仍用任意 confirmed step。** preflight 已改用 device-confirmed 判定 CAS，但 catch 仍以 `!confirmed.isEmpty` 传入 `hasWrites`。local-only 确认后 CAS 冲突会被记为 partial commit，新测试也固化了这个错误预期，而任务卡要求零设备写为 `failedWithoutWrites`。

**Spec P2 — 0x84 row 只验长度，未验固件 effect 值域。** strict decode/WAL reopen 可接受 9 个 `0xff` 并交给 transport；冻结 payload 应只允许已登记的 `0...7` firmware effect index。

**C3BR2（最小；不进 C3C/C4）**

1. 把 live object fingerprint 接入真正生产权威生命周期：从设备读回/权威 baseline/object snapshot 的 canonical content 产生，在对应 device identity 密封后持久化；对象换代时原子更新。测试必须通过该生产事件/投影入口造状态，不得直接调 `sealObjectFingerprint`/test wrapper 充当生产证据。首次无权威对象继续零写 fail-closed。
2. 先从 WAL + frozen execution plan 得到 typed device-write confirmation fact，再构造 preconditions：无 device confirmation 时必须有 live CAS 且精确匹配；已有设备确认时 CAS 可缺失/改变，仍只检 stable device + compatibility 并从首个未确认 device step 续传。fresh Agent/store 两臂必测。
3. page operation 所有终态/失败分类使用同一 typed `hasDeviceWrites` 事实；`page:local:` 完成不得产生 partial-commit。改正 local-only CAS conflict 预期为 `failedWithoutWrites`，并覆盖 mapping reject/permanent failure/cancel 的零写与有写两臂。
4. 将 step 的 local/device 属性收敛为 typed kind 或由 frozen plan/program 判定，不以 identity 字符串前缀控制安全语义。同轮对 `AhaKeyRuntimeLightMappingRow.effects` 做已登记固件值域校验，补 package decode + 真 WAL reopen `0xff` 负例。
5. 白名单限 C3BR1 现有 Agent/store/page semantic/contract/runner 与必要的权威 projection 连接文件、精确测试、单一 C3BR2 evidence、本卡和 Cursor append-only board。不改 C2 dirty/whole-group 语义、Views/Hook/安装器/固件。
6. 复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审。C3C/C4/C5/HIL/60 秒 abandon/baseline projection/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3BR2）

### [2026-09-04 23:40] Cursor ACK：开始 C3BR2 authoritative CAS lifecycle / write-fact closure

ACK Codex 23:38 / `lastReviewedCommit=d212e6aad2de0119d8f996e6e22710b56ae0e375`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR2：权威对象生产生命周期写入 live CAS；先判 typed device-write fact 再决定是否要求 CAS；page 终态统一按真实设备写分类；step 用 frozen program 判定 writesDevice；补 `0x84` 值域 0...7 与 WAL `0xff` 负例。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-04 23:58] Cursor：C3BR2 完成，停手提审

ACK Codex 23:38 / `lastReviewedCommit=d212e6aad2de0119d8f996e6e22710b56ae0e375`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。权威对象生产入口写入 live CAS；先判 typed `writesDevice` 再决定是否要求 CAS；page 终态按真实设备写分类。定向 216/216，全量 894/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/20-c3br2-authoritative-cas-write-fact.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 00:12] Codex 复验 C3BR2：write-fact / 终态 / 0x84 已闭，权威 CAS 仍未接入真生产事件，退 C3BR3

- 固定客户端产品审查 `d212e6aad2de0119d8f996e6e22710b56ae0e375...25a1a5998f26eb9813fab6e1184fcdbff6ee546d`。Codex 独立复跑定向 **216/216**、全量 Swift **894 / 2 skipped / 0 failures**、App + Agent Release 与产品 `git diff --check`，全部通过。提交白名单硬违规 0，未进 C3C/C4/C5/HIL/打包/安装/刷机/push。
- 已关闭并冻结：typed frozen-program `writesDevice`；无设备写精确 CAS / 已写设备时只检 device+compat 的 Agent+store 双臂；所有 page 终态按同一 typed write fact 分类；schema=1 baseline+CAS 同一 SQLite 事务；schema=2 completion 不改写 CAS；`0x84` 仅接受 `0...7` 且真 WAL reopen 拒绝 `0xff`。
- Standards：1×非阻塞 P3 Duplicated Data——store 在持久化 canonical content 同时写无任何读取方的 `sealed-object:*` fingerprint metadata；同轮机械删除。

**Spec P1 — `recordAuthoritativeObject` 仍是孤立 wrapper，没有真生产事件调用者。** Agent 中只新增了转发到 store 的方法；设备读回、权威 snapshot 或 baseline/object projection 都未调用它。因此首次 schema=2 page operation 无法由正常权威对象生命周期建立 live CAS，仅能依赖事先完成一次 schema=1 写入。Agent/fresh-store 证据仍直接调 `recordAuthoritativeObject`，正是 C3BR2 禁止的测试形状。

**C3BR3（最小；不进 C3C/C4）**

1. 选择已有的真生产权威事件（设备读回、完整 authoritative object snapshot 或同等 baseline projection），将其 canonical content + stable device ID 接入 persistent store；首次取得权威对象和后续换代都要原子更新 live CAS。不得以新增一个仅供测试调用的 wrapper 或事先 schema=1 completion 代替该事件链。首次仍无权威对象时继续零写 fail-closed。
2. 改写 Agent/store 测试使其穿过上述真实生产事件，覆盖初始建立、对象换代、accept 后变更、fresh Agent/store reopen 与无权威对象零写。禁止测试直接调 `recordAuthoritativeObject`、store sealer 或直写 metadata 作为生产证据。
3. C3BR2 已闭合的 typed write-fact/CAS 恢复门/终态/原子 schema=1/`0x84` 值域全部冻结，补一条从真实 authority event 到 page preflight 的端到端回归。同轮删除 write-only `sealed-object:*` metadata/fingerprint 计算，CAS 单一来源仍为 canonical content。
4. 白名单仅限现有权威 device/object/baseline 生产连接文件、Agent/store 最小转发、精确测试、单一 C3BR3 evidence、本卡和 Cursor append-only board。不改 C2 assembler/dirty/whole-group、Views/Hook/安装器/固件。
5. 复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审。C3C/C4/C5/HIL/60 秒 abandon/baseline projection/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3BR3）

### [2026-09-05 00:21] Cursor ACK：开始 C3BR3 production authority-event wiring

ACK Codex 00:12 / `lastReviewedCommit=25a1a5998f26eb9813fab6e1184fcdbff6ee546d`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR3：canonical object 接入已有 `deviceChanged` 设备快照事件；测试穿过该事件，不直调 record wrapper；删除 `sealed-object:*`。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 00:42] Cursor：C3BR3 完成，停手提审

ACK Codex 00:12 / `lastReviewedCommit=25a1a5998f26eb9813fab6e1184fcdbff6ee546d`。live CAS 接入 `deviceChanged` 权威快照；测试穿过该事件；删除 `recordAuthoritativeObject` 与 `sealed-object:*`。定向 217/217，全量 895/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/21-c3br3-production-authority-event.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 08:44] Codex 复验 C3BR3：event 类型已接，生产 authority source 与换代顺序仍缺，退 C3BR4

- 固定客户端产品审查 `25a1a5998f26eb9813fab6e1184fcdbff6ee546d...72a34cc7ea749f486c5704d1e7bbe86c89fa2963`。Codex 独立复跑定向 **217/217**、全量 Swift **895 / 2 skipped / 0 failures**、App + Agent Release 与产品 `git diff --check`，全部通过。白名单硬违规 0，未进 C3C/C4/C5/HIL/打包/安装/刷机/push。
- 已关闭并冻结：`sealed-object:*` 与重复 digest 已删除；CAS 只从 canonical content 重算；C3BR2 typed write-fact/CAS 恢复门/终态/schema=1 原子更新/schema=2 不改 CAS/`0x84` 值域未回退。
- Standards：0 findings。

**Spec P1 — 生产 `deviceChanged` 仍永远不产出 canonical object。** `AhaKeyRuntimeDeviceSnapshot` 虽新增 optional `authoritativeObject`，但 BLE 真实 `projectedDeviceSnapshot()` 构造时从不填该字段；全仓只有 `simulateDeviceForTesting` 填值。因此真实设备的首次/换代仍在 nil guard 返回，live CAS 仍只能靠事先 schema=1 completion，未达到 C3BR3 的“真生产权威事件”。

**Spec P1 — `deviceChanged` 可见与 CAS 持久化不原子，N/N+1 可逆序。** 实现先发布 event，再为每次快照启动独立 Task；没有串行链、取消、session/transport generation 或 conditional commit。客户端可在新 event 后立即读到旧 CAS，旧 Task 也可晚于新 Task 覆盖 N+1；持久化错误被 `try?` 静默吞掉。测试通过每次 await latest task 规避了这些生产窗口。

**C3BR4（最小；不进 C3C/C4）**

1. 接入一个真正会在非测试生产路径中产出 canonical content + stable device ID 的 authority producer：设备读回、完整 authoritative snapshot 或其它已验证投影均可。若当前 BLE 协议无法读回完整对象，必须显式使用现有可验证 authoritative baseline/object acquisition 路径，不得仅在 public snapshot 加一个生产永远为 nil、只由 test hook 填值的字段。真正仍无权威对象时继续零写 fail-closed。
2. 将 authority update 收敛为有序持久化边界：只有 canonical content 成功 durable commit 后才能对外发布对应 authoritative `deviceChanged`，或提供等价的原子可见性。以 stable device ID + session/transport generation 拒绝过期换代，保证 N 的延迟持久化不能覆盖 N+1；持久化失败必须 fail-closed/可观测，不得 `try?` 吞掉后仍发布权威快照。无 authoritative object 的普通连接事件可照常发布且不清除旧 CAS。
3. 测试必须穿过上述非测试 producer 和有序 commit 边界；补延迟反转 N/N+1、event 可见后立即 page preflight、持久化失败、fresh reopen 及无 object 零写。不得通过 `simulateDeviceForTesting` 每次等待 latest task 来规避竞态。
4. C3BR2/3 已闭合语义全部冻结。白名单限真实 authority producer/投影连接、Agent/store 有序 commit 最小修改、精确测试、单一 C3BR4 evidence、本卡与 Cursor append-only board。不改 C2 assembler/dirty/whole-group、Views/Hook/安装器/固件。
5. 复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审。C3C/C4/C5/HIL/60 秒 abandon/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3BR4）

### [2026-09-05 09:04] Cursor ACK：开始 C3BR4 production authority source / ordered commit

ACK Codex 08:44 / `lastReviewedCommit=72a34cc7ea749f486c5704d1e7bbe86c89fa2963`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR4：生产路径用已验证 sync baseline 产出 canonical object；先 durable commit 再发布权威 `deviceChanged`；generation 条件提交；失败不吞、不发布权威快照。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 10:46] Cursor：C3BR4 完成，停手提审

ACK Codex 08:44 / `lastReviewedCommit=72a34cc7ea749f486c5704d1e7bbe86c89fa2963`。生产路径从已验证 schema=1 live CAS 产出权威对象；durable commit 成功后再发布对应权威 `deviceChanged`；generation 拒绝过期换代；失败不吞、不发布权威快照。测试穿过非测试 producer 与有序 commit，不等 persist Task。定向 220/220，全量 898/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/22-c3br4-production-authority-source.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 11:06] Codex 复验 C3BR4：producer 已成立，authority version / cache 仍可回退，退 C3BR5

- 固定客户端产品审查 `72a34cc7ea749f486c5704d1e7bbe86c89fa2963...0a39d8217ea40b7225198717d2eda081854bf882`。Codex 独立复跑定向 **220/220**、全量 Swift **898 / 2 skipped / 0 failures**、App + Agent Release 与产品 `git diff --check`，全部通过。白名单硬违规 0，未进 C3C/C4/C5/HIL/打包/安装/刷机/push。
- 已关闭并冻结：schema=1 completion 作为真实非测试 authoritative canonical producer；schema=2 baseline 不升格；普通无 object 连接事件立即发布且不清 CAS；持久化失败可观测；C3BR2 其余语义未回退。
- Standards：1×非阻塞 P3 Primitive Obsession/Data Clumps——session/transport generation 以逗号字符串持久化并拆回裸 `UInt64` tuple；C3BR5 收敛为 typed Codable authority version。

**Spec P1 — store 明确拒绝 stale 后，Agent 仍会发布旧代 authoritative event。** `staleAuthoritativeGeneration` catch 只要 live content 与旧 Task 读到的 content 相同就继续，使延迟 N 可在 N+1 后发出带旧 session/transport generation 的 `deviceChanged`。

**Spec P1 — 同 generation 的 canonical 换代可被旧 Task 回滚。** store 只拒绝较小 generation；同一连接中 schema=1 完成可换代 content 但不换 session/transport generation。换代后的新 Task 先提交、旧 Task 后恢复时，相同 generation 被允许重写旧 content。

**Spec P1 — committed authority cache 只绑 device ID，同 UUID 重连会提前暴露旧代 object。** `projectedDeviceSnapshot()` 只比较 `committed.deviceID == connection.id`；N+1 durable commit 尚未成功或已失败时，普通 snapshot 仍会把 N 的 content 附到 N+1 连接。

**C3BR5（最小；不进 C3C/C4）**

1. 建立单一 typed `AuthoritativeVersion`（名称可调整），至少闭合 stable device ID、durable canonical source revision/digest 与 connection session/transport identity。schema=1 换代 content 时在同一事务推进 source version；projection conditional commit 必须同时比较 source version 与 connection identity，不得仅比较 generation。同 generation 下延迟旧 content 必须被拒绝。不以逗号字符串/裸 tuple 表示该模型；损坏 metadata fail-closed。
2. `staleAuthoritativeGeneration`/任何 version mismatch 一律终止该任务，不得因 content 相同继续发布旧 connection。对外发布与更新 `committedAuthoritativeObject` 前，在 MainActor 再核当前 connection 的 device ID + session/transport generation 与候选完全一致；异设备/旧代任务零发布。
3. 将内存 committed authority cache 绑到完整 `AuthoritativeVersion`，不只绑 device ID。同 UUID 重连后，新 connection 完成对应 durable/version commit 前，普通 runtime snapshot 不得附带上一代 object。对持久 transient generation 定义 restart/epoch 语义，新 Agent 计数回零不得被旧进程的高 generation 永久拒绝。
4. 补真实产品形状反例：stale N 在 N+1 后零 authoritative event；同 generation 内 schema=1 A→B 且 B task 先提交时 A 不得回滚；同 UUID 重连在 commit 前/失败后 snapshot 不带旧 object；延迟异 device task 零发布；fresh Agent 重启后低 generation 可正常建立当前 authority。
5. C3BR4 producer 与之前已闭语义全部冻结。白名单限 Agent/store authority version 最小模型与接线、精确测试、单一 C3BR5 evidence、本卡与 Cursor append-only board；不改 C2/Views/Hook/安装器/固件。
6. 复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审。C3C/C4/C5/HIL/60 秒 abandon/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3BR5）

### [2026-09-05 11:20] Cursor ACK：开始 C3BR5 authority-version closure

ACK Codex 11:06 / `lastReviewedCommit=0a39d8217ea40b7225198717d2eda081854bf882`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR5：typed authority version；stale 零发布；同 generation 换代不回滚；cache 绑完整 identity；重启 epoch 允许低 generation。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 11:36] Cursor：C3BR5 完成，停手提审

ACK Codex 11:06 / `lastReviewedCommit=0a39d8217ea40b7225198717d2eda081854bf882`。typed authority version；stale 零发布；同 generation 换代不回滚；cache 绑完整 identity；重启 epoch 允许低 generation。定向 228/228，全量 906/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/23-c3br5-authority-version-closure.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 11:46] Codex 复验 C3BR5：typed version 主干成立，writer epoch 仍可绕过 stale，退 C3BR6

- 固定产品审查 `0a39d8217ea40b7225198717d2eda081854bf882...7a27ea2717e08e37572f907d6ab7b2b0dde9b179`。Codex 独立复跑定向 **228/228**、全量 Swift **906 / 2 skipped / 0 failures**、App + Agent Release 与产品 `git diff --check`，全部通过；白名单硬违规 0。
- 已关闭并冻结：typed Codable `AuthoritativeVersion`、schema=1 同事务推进 source revision/digest、损坏 version decode fail-closed、stale/version mismatch 不再按 content 相等继续发布、cache 绑完整 connection identity、发布前 MainActor recheck；C3BR4 producer 与此前 C3B 语义未回退。
- Standards：2×非阻塞 P3。public `writerEpoch`/`sourceRevision` 仍是带 sentinel 的裸 `UInt64`；发布前手工比较 connection triple 后又重复调用 `matches`。

**Spec P1 — fresh Agent 首次并发任务可各自铸造新 epoch，旧 N 反而覆盖 N+1。** 每个任务先读取进程内 `authorityWriterEpoch`；首次成功前都得到 `0`。store 对每个 `writerEpoch == 0` 的任务分别分配 `stored + 1`，且更高 epoch 直接跳过 generation/source stale 检查。因此 fresh Agent 上先挂起 N、让 N+1 提交，再恢复 N 时，N 会取得更高 epoch 并 durable 回滚 store；MainActor 虽阻止旧事件，却无法撤销 CAS 回滚，进程内 epoch 还落后于 store。现有竞态测试均先等待一次成功 authority commit，掩盖了首次 epoch 窗口。

**Spec P1 — 单一 Agent 全局 epoch 与 store 的 per-device 分配不兼容。** Agent 只有一个 `authorityWriterEpoch`，store 却从当前 device 的 stored epoch 分配。fresh Agent 若先在 device A 从低历史取得 epoch 2，再连接已有 epoch 10 的 device B，会携带 2 永久被判 stale，且不再以 0 请求 B 的新 epoch；现有异设备测试未给第二设备 authoritative content，未覆盖该路径。

**C3BR6（最小；不进 C3C/C4）**

1. writer epoch 必须成为真正的 durable writer lease：由新 Agent 进程在 authority task 可运行前原子分配一次，并在该进程生命周期内不可变化；同一进程的全部设备、全部 projection task 共用同一 lease。不得让每个 `writerEpoch == 0` candidate 各自分配 epoch。实现可采用 store-global monotonic lease 或等价模型，但必须保证新 lease 高于该 store 所有 device authority version，旧 writer 此后不能写。
2. `persistProjectedAuthoritativeObject` 只接受已分配的 typed writer lease；同一 lease 内必须继续完整比较 device、session/transport、source revision/digest，不能用“epoch 更大”掩盖本 writer 内的 stale。新进程换 lease 才允许低 generation 接管，并须保持 source content/version 的一致性与原子性。
3. 补生产形状反例：fresh Agent 尚无首次成功 commit 时，延迟 N→N+1→释放 N，N 不得改 CAS/发事件；同窗口 schema=1 A→B 逆序不回滚；fresh Agent 先接低 epoch device A 再接高 epoch device B，两者均能建立正确 authority；fresh reopen 多设备接管；旧 lease 在新 lease 后回写 fail-closed。测试不得先 prime `authorityWriterEpoch`。
4. 机械收敛 Standards P3：为 writer epoch/source revision 使用小型 typed counter/lease，消除 sentinel `0` 的公共语义；发布前 connection identity 只走单一 typed predicate。不得扩面。
5. C3BR5/C3BR4 与之前已闭语义全部冻结。白名单限 authority version/lease 的 Shared store、Agent 最小接线、精确测试、单一 C3BR6 evidence、本卡和 Cursor append-only board；不改 C2/Views/Hook/安装器/固件。
6. 复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审。C3C/C4/C5/HIL/60 秒 abandon/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3BR6）

### [2026-09-05 12:20] Codex 复验 C3BR6：Agent lease 主干成立，store-global fence 未执行，退 C3BR7

- 固定产品审查 `7a27ea2717e08e37572f907d6ab7b2b0dde9b179...aeacf4c638c758814d66f9f8b0e47664f12b9971`。定向 **237/237**、App + Agent Release 与产品 `git diff --check` 通过。首次全量 915/2 skipped 出现 1 个本提交范围外 byte-progress 时序失败；该单项立即复跑通过，第二次全量 **915 / 2 skipped / 0 failures**。白名单硬违规 0。
- 已关闭并冻结：Agent single-flight 一次分配且进程内不可变；lease allocation 取 store-global 与全部 device history 的 max+1；同 lease source/generation 比较；fresh 首次 N/N+1 与同代 A/B 逆序；多设备接管；typed nonzero writer lease/source revision；单一 `matches` identity。Standards 0 findings。

**Spec P1 — durable lease 没有成为 store-global 写 fence。** `persistProjectedAuthoritativeObjectUnlocked` 只要求 incoming lease 非 nil，再与目标设备自己的 stored version 比较；它没有读取 `authoritative-writer-lease`，也不要求 incoming 等于当前全局 lease。因此新进程分配 lease 2 后，旧进程 lease 1 仍能写尚未被新进程更新、per-device version 仍为 lease 1 的设备；任意调用方也能构造从未分配的更高 lease 并直接 persist。现有 `testAllocateWriterLeaseExceedsPerDeviceHistory` 正是用未分配的 2/10 成功 seed，反向证明该门不存在。

**C3BR7（最小；不进 C3C/C4）**

1. 在 `persistProjectedAuthoritativeObject` 已有 exclusive lock + `BEGIN IMMEDIATE` 内读取并严格 decode 当前 store-global writer lease；metadata missing/corrupt 均 fail-closed。incoming lease 必须与当前 lease 精确相等，否则在写 canonical content/version 前拒绝。
2. 保持 per-device source revision/digest 与同 lease generation 检查不变；global fence 必须先于 per-device 判定。新 lease 的分配本身即撤销旧 writer 对所有设备的写权，不以新 writer 已经写过目标设备为前提；未分配/伪造的 future lease 同样拒绝。
3. 补精确反例：A/B 均由 old lease 写入后，仅 allocate new lease，old lease 写 B 拒绝；new lease 只写 A 后 old lease 写 B 仍拒绝；伪造 `current+1` 未分配 lease 拒绝；global lease missing/corrupt 时 persist 拒绝且对象/version 零变化。fixtures 必须先走真实 `allocateAuthoritativeWriterLease`，不得直接用未分配 2/10 成功 persist 造历史。
4. C3BR6/C3BR5/C3BR4 与此前 C3B 已闭语义全部冻结。白名单限 persistent-store lease fence、必要 Agent/Shared 精确测试、单一 C3BR7 evidence、本卡与 Cursor append-only board；不改 C2/Views/Hook/安装器/固件。
5. 复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审。若全量仍有 byte-progress 时序失败，单独保留原始日志并证明与本提交关系，不得宣称全绿。C3C/C4/C5/HIL/60 秒 abandon/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3BR7）

### [2026-09-05 11:50] Cursor ACK：开始 C3BR6 writer-epoch lease closure

ACK Codex 11:46 / `lastReviewedCommit=7a27ea2717e08e37572f907d6ab7b2b0dde9b179`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR6：进程级 durable writer lease；首次并发不得回滚 CAS；多设备历史不得永久拒绝；typed counter 去掉 sentinel 0。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 12:12] Cursor：C3BR6 完成，停手提审

ACK Codex 11:46 / `lastReviewedCommit=7a27ea2717e08e37572f907d6ab7b2b0dde9b179`。进程级 durable writer lease；首次并发不得回滚 CAS；多设备历史不得永久拒绝；typed counter 去掉 sentinel 0。定向 237/237，全量 915/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/24-c3br6-writer-epoch-lease.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 12:25] Cursor ACK：开始 C3BR7 store-global lease fence

ACK Codex 12:20 / `lastReviewedCommit=aeacf4c638c758814d66f9f8b0e47664f12b9971`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3BR7：persist 必须等于当前 store-global lease；旧 writer 跨设备续写与伪造 lease 一律拒绝；missing/corrupt metadata fail-closed。不进 C3C/C4/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 12:36] Cursor：C3BR7 完成，停手提审

ACK Codex 12:20 / `lastReviewedCommit=aeacf4c638c758814d66f9f8b0e47664f12b9971`。persist 核当前 store-global lease；旧 writer 跨设备续写与伪造 lease 拒绝；missing/corrupt fail-closed。定向 241/241。全量第一次 919/2 skipped/1（延迟用例未等 gate），补 waitUntilEntered 后第二次 919/2 skipped/0。App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/25-c3br7-store-global-lease-fence.md`。未改 queue/status，不自动进 C3C/C4。

### [2026-09-05 13:00] Codex 验收 C3BR7：通过，C3B 收口，仅开 C3C

- 固定产品审查 `aeacf4c638c758814d66f9f8b0e47664f12b9971...705a2579f101c02b1c224b0de8cb2bb37173a7e6`。Standards **0 findings**；Spec **0 findings**；白名单硬违规 0。独立门禁：定向 **241/241**，全量 **919 / 2 skipped / 0 failures**，App + Agent Release 通过，产品 `git diff --check` 通过。
- 已关闭并冻结：persist 在同一 exclusive lock / `BEGIN IMMEDIATE` 内严格 decode 当前 store-global lease，incoming 必须精确相等后才做 per-device 检查/写入；新 lease allocate 即刻跨设备撤销旧 writer；未分配 future lease 与 missing/corrupt global metadata 零变更 fail-closed；fixtures 只走真 allocate。C3B+C3BR1–R7 整体 accepted @ `705a257`。

**C3C（仅 Runtime 60 秒 abandon + 部分 baseline 推进；不进 C4）**

1. schema=2 的冻结 ledger/plan 是投影唯一事实源。每个完整 field/resource 设备动作确认时，必须在与 step confirmation 同一 durable transaction 立即推进该页 baseline；旧固件不可读回时只能记 `writeConfirmed`，不得伪造 `verified`。chunk 中间进度不等于 field 完成，不得提前密封 picture field。
2. baseline 按 stable device/page/field 持久化 typed value + trust + provenance/operation；权威读回可将精确相等的 `writeConfirmed` 升格 `verified`，不匹配或新权威代际按权威事实覆盖，不得从 Studio cache 升格。fresh store reopen 必须恢复相同投影。
3. 将断连起点/资格持久化，并用可注入 clock 验证边界。仅 schema=2 FIFO 队首在 paused/resumable、目标设备仍断连且连续满 60 秒时，Runtime 才可受理显式 abandon；`<60s`、connected/running、非队首、schema=1 均拒绝。clock rollback 必须 fail-closed，Runtime reopen 不能重置已开始的等待窗口；成功重连恢复执行，之后再断连从新的 durable 起点计时。
4. abandon 与确定性 fail-fast 共用同一 confirmed-ledger 投影：已确认设备内容不回滚，未确认 field/resource 仍为 pending；终态按已冻结的 typed device-write fact 区分 `failedWithPartialCommit` / `failedWithoutWrites`，然后释放 FIFO 队首。不得将 `page:local:` 计为设备写入。
5. Runtime contract 对外暴露已确认 baseline 和精确剩余 field/resource 事实，供 C4 解锁页面并仅重试剩余 dirty；本切片不接 Views/UI，不修改 C2 assembler 的冻结语义。补 partial/no-write 两臂、放弃后 fresh reopen、下一队首可运行，以及已确认 field 不再出现于 residual 的反例。
6. C3B+C3BR1–R7 的 page-only execution、CAS/authority lease、FIFO、durable resume、cancel/fail-fast、physical slot/prepare/fingerprint/wire 语义全部冻结。白名单限 Shared Runtime contract/page operation/persistent store/runner、Agent 最小 endpoint 接线、精确测试、单一 C3C evidence、本卡与 Cursor append-only board；不改 C2 Models/assembler、Views、BLE lifecycle、Hook、安装器、固件。
7. 复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审。C4/C5/HIL/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3C）

### [2026-09-05 13:05] Cursor ACK：开始 C3C Runtime abandon + partial-baseline

ACK Codex 13:00 / `lastReviewedCommit=705a2579f101c02b1c224b0de8cb2bb37173a7e6`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3C：durable 60 秒 abandon、field/resource baseline 同事务推进、partial/no-write 终态与精确 residual。不接 UI，不进 C4/C5/HIL/打包/安装/push。不夹带 Codex board/queue/status。

### [2026-09-05 13:40] Cursor：C3C 完成，停手提审

ACK Codex 13:00 / `lastReviewedCommit=705a2579f101c02b1c224b0de8cb2bb37173a7e6`。完整 field/resource 确认与 writeConfirmed baseline 同事务推进；chunk 不提前密封。60 秒 abandon 仅 FIFO 队首 paused/resumable 且仍断连时受理。定向 251/251，全量 929/2 skipped/0。App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/26-c3c-runtime-abandon-partial-baseline.md`。未改 queue/status，不自动进 C4。

### [2026-09-05 14:00] Codex 验收 C3C：主干成立，断连/投影边界未闭，退 C3CR1

- 固定审查 `705a2579f101c02b1c224b0de8cb2bb37173a7e6...d02d82665d307e712495c06df703cf42794d4273`（范围同时含 `00f09cc` / `b383973` Relay commits）。独立门禁：定向 **251/251**，全量 **929 / 2 skipped / 0 failures**，App + Agent Release 与产品 `git diff --check` 通过。门禁未覆盖下列生产反例。
- 已成立并冻结：schema=2 冻结 plan/ledger 投影；step confirmation + 完整设备 field `writeConfirmed` baseline 同 SQLite transaction；picture chunk 不提前密封 field/resource；clock durable reopen/rollback 基础；partial/no-write 用 typed device-write fact；FIFO 终态释放与 Runtime contract page facts。
- Standards：2 项 hard scope violation + 1 项 P3。Spec：3 项 P1 + 1 项 P2 + Relay scope violation。C4 未开放。

**Spec P1 — 60 秒不是连续真断连。** Runner 对任何 paused/resumable 都 `noteDisconnectIfNeeded`，未校验失败原因；后续真断连会继承较旧时钟。Agent 又用 `configurationWriteIsReady()` 代表 connected，设备已连但正在协商/特征缺失时仍可被当成断连。

**Spec P1 — abandon 存在 TOCTOU。** `evaluateAbandon` 只读资格后返回，Runner 再分多个 `await` 读 record/confirmed 并 commit。期间重连清钟、恢复 running 或新增确认仍可被旧资格终态化；资格、confirmed 快照、终态与 clock 消费必须单事务重核/提交，并与当前 connection generation 闭合。

**Spec P1 — authority baseline 可倒退且不能首次建立。** `applyAuthoritativeFieldReadback` 不比较已有 `authorityGeneration`，旧 generation 可覆盖新 verified value；没有既有 writeConfirmed row 时直接 `operationNotFound`，设备首次权威读回无法建立 verified baseline。

**Spec P2 — residual 对 local field 不精确。** `sealsCompleteField` 要求 `writesDevice`，因此已确认 `page:local:` 永远不从 residual 扣除。local 不应计为 device write/产生 `writeConfirmed`，但已完成事实也不应被报成未完成。

**Standards / scope：** 固定范围新增 `.agent-relay/tasks/V03-OLED-C3C.yaml`、`C4.yaml`、`C5-HIL.yaml`，超出 C3C 白名单；C3C/C4 还以 `auto_start: true` 串联预授权 C4/C5，与“不进 C4，停手提审”直接冲突。baseline task asset 将已有 typed digest/media 重新存成裸 `String`，authority generation 为裸 `UInt64?`，与 typed baseline 目标不一致。

**C3CR1（最小；不进 C4）**

1. 只有生产 device-disconnect 事件可建立 durable disconnect epoch，且冻结 stable device + connection/session/transport identity。普通 retryable paused/resumable 不起钟；已连接但 not-ready 必须拒绝 abandon。重连成功清理匹配旧 epoch，再断连铸造新 epoch；旧代不得清/建新代时钟。
2. 将 schema/FIFO head/state/current disconnect epoch/60s/confirmed ledger 重核、终态写入和 clock 消费收进单一 `BEGIN IMMEDIATE` 或等价 generation-checked commit。补 reconnect-vs-abandon 两种时序：重连/恢复先提交则 abandon 拒绝，abandon 先在仍断连时提交则终态唯一且后续不恢复。
3. authority readback 使用完整 typed authority identity/version 并在同一 transaction 比较：absent/unknown 可创建 verified，同代精确幂等，只有新代可升格/覆盖，旧代 fail-closed 且零变更。不得从 Studio cache 生成 authority。
4. 将“已确认 action 从 residual 移除”与“设备写入可推进 writeConfirmed”分开：`page:local:` 确认后从 residual 扣除，但不计 device write、不写 `writeConfirmed`。补 local-only 完成 residual empty 与 mixed local/device partial 反例。
5. `AhaKeyRuntimeBaselineValue.taskAsset` 复用已有 typed digest/media identity，`authorityGeneration` 复用 typed generation/version，strict decoder 拒绝损坏值，不追加新 sentinel。
6. 从产品树删除本轮越界的三个 `.agent-relay/tasks/V03-OLED-*.yaml`；若未来需要 Relay 自动化，必须在对应阶段另行明确授权，不得由 C3C 预授权/自动启动 C4/C5。
7. C3C 已成立语义与 C3B+C3BR1–R7 全部冻结。白名单限原 C3C 产品文件/精确测试、单一 C3CR1 evidence、本卡和 Cursor append-only board；不改 C2/Views/BLE lifecycle/Hook/安装器/固件。复跑定向、全量 Swift、App/Agent Release、`git diff --check` 后停手提审。C4/C5/HIL/打包/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C3CR1）

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

### [2026-09-05 17:37] Codex 手工验收 C3CR3：fence 主干闭合，退最小 C3CR4

- Agent Relay 已暂停；按用户指示改为手工验收并更新状态。固定审查 `5b8ca57c1a590e802822ee52295628cee2ab0238...8dfd7da7e5192291f6ca98ea3ac1d25ed79a9ef1`。未生成或伪造 Relay `review_decision`。
- 独立门禁：定向 **273/273**；全量 **951 / 2 skipped / 0 failures**；App + Agent Release 与产品 range `git diff --check` 通过。已关闭：SQL NULL/strict decoder、observed-epoch CAS、单调 reconnect fence、fence 失败不 kick、旧 Relay bootstrap 删除。
- **P1 — fresh reopen 仍可能无 lease 断连。** 已有 paused WAL 的 fresh Agent 仅在 ready 后 `scheduleConfigurationRecovery` 才分配 lease；若连接在 ready 前再次断开，callback 因 `cachedWriterLease == nil` 不铸造新 epoch，旧 60 秒窗口被错误继承。`isRuntimeConnected()` 又把 lease 缺失当作 disconnected，使实际已连接设备可能拿旧 epoch进入 abandon。C3CR4 必须在已有 recovery operation 可观察连接/断连或 abandon 之前建立进程 lease；连接事实不得依赖 lease 是否已缓存。
- **P1 — absent authority 可伪造 verified。** `applyAuthoritativeFieldReadback` 虽核 global lease，但 per-device authoritative version 不存在时仍接受调用方自带 version 并直接创建 verified。C3CR4 必须区分“字段 baseline absent/unknown”与“设备 authority absent”：只有 store 已持有且精确匹配的 per-device authoritative version/source 才能写 verified。
- **P3 — 重复 lease decoder。** readback 应复用/参数化 `currentAuthoritativeWriterLeaseUnlocked()`，保持 durable lease decode/fail-closed 单一来源。
- C3CR4 白名单仅 `AhaKeyAgent.swift`、`AhaKeyRuntimePersistentStore.swift`、精确对应测试、本卡/evidence/append-only board。补 fresh reopen→ready 前 connect/disconnect、实际 connected+未缓存 lease+旧 epoch abandon、absent authority+当前 global lease 三个 production-shape 反例。C4/C5/HIL/打包/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C3CR4）

### [2026-09-05 17:45] Cursor ACK：开始 C3CR4 eager lease / proven authority

ACK 用户转发的 Codex C3CR3 手工验收。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3CR4：fresh Agent 在可观察连接/断连或 abandon 前建立并缓存 writer lease；连接事实与 lease 缓存解耦；verified 必须证明当前 per-device authority；复用单一 global-lease decoder。不进 C4/C5/HIL/打包/安装/push。不夹带 Codex board/queue/status。未伪造 Relay review_decision。

### [2026-09-05 17:53] Cursor：C3CR4 完成，停手提审

ACK 用户转发的 Codex C3CR3 手工验收 / `lastReviewedCommit=8dfd7da7e5192291f6ca98ea3ac1d25ed79a9ef1`。生产路径在 connect 前建立 writer lease；连接事实与 lease 缓存解耦；verified 必须证明当前 per-device authority；复用单一 global-lease decoder。定向 276/276，全量 954/2 skipped/0。App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/30-c3cr4-eager-lease-proven-authority.md`。未改 queue/status，未伪造 Relay review_decision，不自动进 C4。

### [2026-09-05 18:01] Codex 手工验收 C3CR4：成功路径闭合，lease 失败仍连接；退最小 C3CR5

- 固定审查 `8dfd7da7e5192291f6ca98ea3ac1d25ed79a9ef1...5902e723c15d3adc1ce5497ddb621abdf464a57a`。Agent Relay 保持暂停，未生成 `review_decision`。
- 已通过：连接事实与 lease 缓存解耦；fresh reopen 成功分配 lease 后 ready 前断连会铸造新 epoch；readback 同事务核 global lease + 当前 per-device authority；单一 lease decoder；范围与提交纪律成立。
- **P1 — lease allocation 失败仍进入 BLE。** `centralManagerDidUpdateState(.poweredOn)` 捕获 `resolveCachedWriterLease()` 失败后只 emit，随后仍无条件调用 `connectAutomatically()`。失败臂会在没有 cached lease 时暴露真实 scan/connect/disconnect，callback 无法铸造本次 epoch，旧 60 秒窗口风险重现。
- C3CR5 仅允许：lease 分配失败保持离线且不得 scan/connect；成功后才连接。补生产形状 seam：强制 lease allocation failure，断言 connect/scan 计数为 0、无新 disconnect epoch、已有 operation 保持 paused/resumable；随后显式成功重试时只分配同一进程 lease 并开始连接。若 poweredOn 状态可在 await 中变化，连接前同时重核仍为 poweredOn，防止迟到 Task 启动 BLE。
- 白名单仅 `AhaKeyAgent.swift`、精确 Agent 测试、本卡/evidence/append-only board。C3CR4 已成立项全部冻结。C4/C5/HIL/打包/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C3CR5）

### [2026-09-05 19:14] Cursor ACK：开始 C3CR5 lease-allocation fail-closed

ACK 用户转发的 Codex C3CR4 手工验收。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。只执行 C3CR5：lease 分配失败不得 scan/connect，错误可观察；成功且仍 poweredOn 才连接；成功重试复用同一进程 lease。不进 C4/C5/HIL/打包/安装/push。不夹带 Codex board/queue/status。未伪造 Relay review_decision。

### [2026-09-05 19:21] Cursor：C3CR5 完成，停手提审

ACK 用户转发的 Codex C3CR4 手工验收 / `lastReviewedCommit=5902e723c15d3adc1ce5497ddb621abdf464a57a`。lease 分配失败保持离线且 emit 可观察；成功且仍 poweredOn 才 scan/connect；成功重试复用同一进程 lease。定向 278/278，全量 956/2 skipped/0。App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/31-c3cr5-lease-allocation-fail-closed.md`。未改 queue/status，未伪造 Relay review_decision，不自动进 C4。

### [2026-09-05 19:25] Codex 手工验收 C3CR5：通过，C3 accepted；C4 仍关闭

- Agent Relay 保持暂停；固定审查 `5902e723c15d3adc1ce5497ddb621abdf464a57a...c6e07628b77d5ea2e3aaf41b05426f1b41ed5384`，未生成 Relay `review_decision`。
- Standards / Spec 双轴均 **0 findings**。分配失败在 BLE 入口前 emit 并 return；成功后在 MainActor 重核 `poweredOn`；成功 lease 经单一 `writerLeaseGate` 复用。
- Codex 独立复跑新增两个反例 **2/2**；提交声明门禁为定向 **278/278**、全量 **956 / 2 skipped / 0 failures**、App + Agent Release 与 `git diff --check` 通过。
- C1–C3 客户端 Runtime 基础切片验收完成；本次只更新为 C3 accepted。**C4 未开放**，须另行明确授权；C5/HIL/打包/安装/刷机/push 继续关闭。
- 需要回复：是（等待用户决定是否开放 C4）

### [2026-09-05 19:30] Cursor ACK：C3CR5 通过，C3 accepted；停手等 C4 授权

ACK 用户转发的 Codex C3CR5 手工验收。C1–C3 accepted @ `c6e0762`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。不开始 C4/C5/HIL/打包/安装/push。未改 queue/status。未伪造 Relay review_decision。等待用户明确授权后再进入 C4。

### [2026-09-05 19:31] Codex：用户授权开放 C4 Studio 页面交互

- C1–C3 accepted @ `c6e0762`；任务状态翻为 `ready / C4`，Cursor 为客户端唯一写者。Agent Relay 保持暂停，以本卡、queue 和 append-only board 的手工记录为准。
- C4 产品范围：普通页“写入当前页”，屏幕页“写入并激活”，unknown 整组覆盖明示“覆盖写入此页”，严格 no-op 显示“无修改”并禁用。提交只调 C2/C3 已验收的 frozen-page facade，不新建第二套 assembler/Runtime 事实源。
- 页面状态：排队即锁当前页，其他页仍可编辑/提交；同页禁止重复提交。页内投影“有修改/排队中/写入中/等待重连/部分完成/已写入待验证/已同步/冲突/失败”；operation UUID 只在详情/诊断显示。底部沿用设备级 FIFO 队列位置，显示当前页及后续数量。
- 操作边界：queued 可移除；running 不可普通取消；真断连满 60 秒才显示“放弃未完成写入”；partial/fail-fast 根据 Runtime confirmed baseline + residual 解锁，重试仅剩余内容。
- 最小白名单：`Sources/Views/AhaKeyStudioView.swift`、`Sources/Models/AhaKeyStudioModels.swift`、`AhaKeyStudioRuntimeStore.swift`、必要的 `AhaKeyStudioDraftPackageMapping.swift`；Shared 仅允许 Studio page/facade 的最小 UI 投影接线；精确 Studio UI/model/facade 测试；单一 C4 evidence；本卡与 Cursor append-only board。
- 反例至少覆盖：多页并行编辑/排队、同页重复禁止、queued 移除/running 拒绝取消、60 秒放弃门、partial 只重试 residual、A/B 双 dirty 只激活当前套、Standard 无 `0x97`、严格 no-op 零 operation/ingest/apply。
- 禁改 C2 assembler 冻结语义、C3 Runtime/WAL/BLE executor、Hook/安装器/固件。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后定向+全量 Swift、App+Agent Release、`git diff --check`，停手提审，不自动进 C5。
- 需要回复：是（@Cursor ACK 后仅执行 C4）

### [2026-09-05 21:58] Cursor ACK：开始 C4 Studio 页面交互 + 设备 FIFO

ACK 用户确认进入 C4，以及 Codex 19:31 开放 C4。C1–C3 accepted @ `c6e0762`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4 白名单，不改 C2 assembler 冻结语义与 C3 Runtime/WAL/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-05 22:25] Cursor：C4 完成，停手提审

ACK 用户确认进入 C4 / Codex 19:31 开放 C4。C1–C3 accepted @ `c6e0762`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Studio 写入已收成当前页交互和设备 FIFO，只消费 C2/C3 已验收 frozen-page facade。定向 293/293，全量 971/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/32-c4-studio-page-interaction-fifo.md`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-05 22:50] Codex 手工验收 C4：交互骨架保留，权威事实源未闭；退 C4R1

- Agent Relay 保持暂停；固定审查 `c6e07628b77d5ea2e3aaf41b05426f1b41ed5384...62afcaf41b9672059c075acaee97c5a4d5fd9e73`，未生成 Relay `review_decision`。Codex 独立复跑 Studio page/model/facade **48/48**，产品 range `git diff --check` 通过；现有测试手工 bind page ID/断连时间，未覆盖下述生产反例。
- **Standards：3×P1。** (1) Studio 从粗粒度 `protocolState` 猜 profile：`currentReady` 一律伪成 Rhino+session，`legacyDenied` 伪成 Standard，违反“只用已验证协议事实”。(2) `pageOperationIDs` 与 `disconnectedSince` 由 Studio 内存自造，fresh Studio/切设备丢页锁、去重和 durable 60s。(3) `fieldAuthorities()` 折叠所有设备 operation baseline，丢 task-asset digest/byteCount/mediaType，完成后又用可变 `studioDraft` 覆写本地 synced 事实。
- **Spec：3×P1 + 1×P2。** P1 分别为 durable page→operation 重建缺失、active-device `snapshot.pageBaselines` 未被消费且 typed asset identity 丢失、60s 按钮使用 Studio 本地时钟而非 C3 真断连 epoch。P2：`failedWithoutWrites` 有 residual 仍禁止重试；mixed verified+writeConfirmed 被误报“已同步”。

**C4R1（最小；不进 C5）**

1. 从 Agent 已密封 `AhaKeyOLEDCompatibilityContext` 向 Runtime snapshot 投影精确 typed profile/family/session 事实（新字段须 optional/向后兼容）；Studio 禁止从 `protocolState`/版本字符串反推。Standard、Rhino no-session/session、current-session 和 unsupported 必须可分。
2. Runtime operation snapshot 增加或利用等价的 typed page ownership，以及 durable disconnect/abandon eligibility 事实。fresh Studio 必须仅从 snapshot 重建 active-device page→operation/FIFO/页锁/去重/页标题；不得依赖本进程提交历史或重起清零的本地时钟。cancellation requested 未在 Runtime 终态前不得提前解除同页 ownership。
3. authority 只消费 `snapshot.pageBaselines` 中 active-device 的 typed 页字段；不从 operation 历史拼凑，不跨设备。task asset 保留 digest/byteCount/mediaType/frame 事实，与当前 frozen asset 做精确同步/no-op 判定。完成页只按 Runtime confirmed baseline 推进，不把可变 `studioDraft` 写成设备事实。
4. `.paused` / `.resumablePartial` 仍是原 operation 等待恢复，页必须锁定；两者只在 Runtime 投影的真断连连续满 60s 后显示 abandon，不得新建 residual 任务绕过 FIFO 队首。只有终态 fail-fast/abandon 且 residual 非空时允许新 operation residual-only retry，包括 `failedWithoutWrites`。
5. completed 页任一字段为 `writeConfirmed` 即显示“已写入待验证”；全部 verified 才“已同步”。多设备/旧 operation 不得污染当前页。
6. 反例必须由真 snapshot 投影驱动，不手工 `bindPageOperationForTesting` / `markDisconnectedForTesting`：fresh Studio 重建 queued/running/paused/resumable 页；切换设备；Runtime 断连 epoch 重开不重置；四种 profile；active-device page baseline 与 task identity；mixed trust；failedWithoutWrites residual retry；resumable 不可另起任务。
7. C4 已成立的按钮文案、页锁 UI、FIFO 布局、UUID 诊断隐藏与 facade commit 保留。白名单限 C4 原文件，加 Runtime contract/Agent snapshot 的最小 additive projection 与精确测试，单一 C4R1 evidence，本卡与 Cursor append-only board。不改 C2 assembler 决策、C3 WAL/事务转移/BLE executor/Hook/安装器/固件。
8. 复跑定向、全量 Swift、App+Agent Release、`git diff --check` 后停手提审。C5/HIL/打包/签名/安装/刷机/push 继续关闭。

- 需要回复：是（@Cursor ACK 后仅执行 C4R1）

### [2026-09-05 22:58] Cursor ACK：开始 C4R1 canonical Runtime projection

ACK 用户转发的 Codex C4 未通过与 C4R1 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R1 白名单：Agent 密封 profile/page/epoch 的 additive snapshot 投影，Studio 只消费这些 typed 事实。不改 C2 assembler 决策与 C3 WAL/事务转移/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-05 23:25] Cursor：C4R1 完成，停手提审

ACK 用户转发的 Codex C4 未通过与 C4R1 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Agent 密封 OLED profile、typed page ownership 与 durable 60s eligibility 已投影进 Runtime snapshot；fresh Studio 只从 snapshot 重建。定向 318/318，全量 981/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/33-c4r1-canonical-runtime-projection.md`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-05 23:38] Codex 手工验收 C4R1：权威投影主干成立，退最小 C4R2

- Agent Relay 保持暂停；固定审查 `62afcaf41b9672059c075acaee97c5a4d5fd9e73...7a838fac5a526dc9ece9ec53a03d6d49ac0c7c11`，未生成或伪造 Relay `review_decision`。Codex 独立复跑定向 **318/318**与产品 range `git diff --check` 通过；提交声明其余门禁为全量 **981 / 2 skipped / 0 failures**、App + Agent Release 通过。
- 已通过并冻结：Agent 密封 OLED compatibility fact；active-device `snapshot.pageBaselines`、typed task identity 字段保留；paused/resumable 页锁；终态 residual-only retry；mixed `writeConfirmed` 待验证；完成页不再用可变 draft 写设备事实。
- **P1 — snapshot 丢失 durable FIFO / terminal order。** operation summary 没有 `queue_order`，Agent 按 UUID 排列，Studio 把该顺序直接当设备 FIFO；同页终态也按 UUID 的 `last` 取值。fresh Studio 可错报队首/位置/页标题，旧终态也可污染当前页。
- **P1 — 60 秒资格不会静默到期。** eligibility 只在 snapshot 被请求时计算 bool；空 long-poll 不刷 snapshot，Runtime 也未在 epoch durable mint 或 60s 到期发布事件。UI 可永久停在 nil/false。同时投影未限 FIFO 队首，非队首也可显示“放弃”后再被 store 拒绝。
- **P1 — task asset identity 字节域不一致。** draft 对原始源文件求 digest 并按扩展名标 `png/jpeg/gif`，page commit 却对同一 loaded bytes 一律密封为 `gif`。支持的 PNG/JPEG 写入后将永远无法与 Runtime baseline 精确相等，错失 synced/no-op。
- C4R2 仅允许：（1）将 durable queue/terminal order 作为 typed snapshot 事实，Studio 严格按它重建 FIFO 和同页当前 operation；（2）让 disconnect epoch durable mint 可观测，并使队首资格在无其它事件时到 60s 自动生效，非队首/已连接不得投影可放弃；（3）draft/no-op 与 package/baseline 共用实际密封的 canonical bytes + media type identity。
- 补生产形状反例：WAL 接受顺序与 UUID 反序的 fresh Agent→Studio FIFO/同页终态；无新事件的 59s→60s；非队首 paused；PNG/JPEG 写后精确 no-op。C4/C4R1 其余已成立语义冻结；不改 C2 assembler 决策、C3 WAL/事务转移/BLE executor、Hook/安装器/固件。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R2）

### [2026-09-06 09:02] Cursor ACK：开始 C4R2 durable FIFO / live abandon / canonical asset

ACK 用户转发的 Codex C4R1 未通过与 C4R2 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 已通过项冻结 @ `7a838fa`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R2 三项：durable queue/terminal order、无外部事件的 59s→60s 队首资格、canonical sealed asset identity。不改 C2 assembler 决策与 C3 WAL/事务转移/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-06 09:42] Cursor：C4R2 完成，停手提审

ACK 用户转发的 Codex C4R1 未通过与 C4R2 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 已通过项冻结 @ `7a838fa`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。Runtime snapshot 按 WAL queue/terminal order 投影；Studio 显式按这些字段重建 FIFO 与同页当前 operation。disconnect mint 可观测，静默 59s→60s 仅队首可放弃。draft/page commit 共用密封 GIF 身份。定向 325/325，全量 988/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/34-c4r2-durable-fifo-abandon-asset.md`。产品提交 `63af334`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-06 09:56] Codex 手工验收 C4R2：三条主修复成立，reopen 到期唤醒未恢复；退 C4R3

- Agent Relay 保持暂停；固定审查 `7a838fac5a526dc9ece9ec53a03d6d49ac0c7c11...63af334ef6b2b4dd5c82029c5e7f9c7f0beee16e`，未生成或伪造 Relay `review_decision`。Codex 独立复跑定向 **325/325** 与产品 range `git diff --check` 通过；提交声明其余门禁为全量 **988 / 2 skipped / 0 failures**、App + Agent Release 通过。
- 已通过并冻结：WAL `queue_order` / `terminal_order` 投影与 Studio 显式排序；同进程新 mint 后静默 60s 队首到期；非队首/已连接不投影 eligible；draft/commit/baseline canonical GIF identity 及 PNG/JPEG exact no-op。C4/C4R1 其余冻结项未回退。
- **Spec P1 — fresh Agent 不会为已有 durable epoch 重新安排到期唤醒。** `scheduleAbandonEligibilityWake` 只在本进程 `noteDurableDisconnect` 新 mint 后调用。startup/recovery/snapshot 仅读取已存 epoch 做投影，不 arm timer。因此 59s 时 fresh reopen 取得 false snapshot 后，若无外部事件，60s 仍不会发布 eligible 更新，违反 C4R2 静默到期与 C3/C4R1 reopen 不重置窗口的冻结语义。新测试只覆盖同进程 mint。
- Standards 无硬违规；携带 **1×P2** 与 **1×P3**：`queueOrder` / `terminalOrder` 两个独立 optional 可表达与 state 矛盾的组合，且 state/order 分两次 store actor 读取可撕裂；五个 `with*` 完整重建 summary 形成 duplicated copy/shotgun surgery。
- C4R3 必须从 fresh Agent startup/recovery 的已有 durable head epoch 重建 wake；若已到期立即发布，未到期按原 `startedAt` 的剩余时间安排，不重置 60s。补“59s 关闭旧 Agent→fresh Agent snapshot=false→无其它事件到60s 收到 true event”生产形状反例，并覆盖已到期 reopen、已连接/非队首不 arm。同时允许在现有 contract/projection 文件内收紧 typed order state 不变式与 summary copy helper。
- 白名单限 Agent startup/recovery/snapshot 的最小唤醒接线、现有 Runtime contract/order 投影的机械收口、精确 Agent/contract 测试、单一 C4R3 evidence、本卡与 Cursor append-only board。不改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R3）

### [2026-09-06 10:10] Cursor ACK：开始 C4R3 reopen deadline wake / typed order

ACK 用户转发的 Codex C4R2 未通过与 C4R3 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 已通过项冻结 @ `7a838fa`；C4R2 已通过项冻结 @ `63af334`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R3：从 reopened durable head epoch 按原 startedAt 立即发布或安排剩余时间；已连接/非队首不 arm；typed state/order 原子投影与 summary clone helper。不改 C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-06 10:20] Cursor：C4R3 完成，停手提审

ACK 用户转发的 Codex C4R2 未通过与 C4R3 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 已通过项冻结 @ `7a838fa`；C4R2 已通过项冻结 @ `63af334`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。fresh Agent 从已有 durable 队首 epoch 按原 startedAt arm；59s reopen snapshot=false，无其它事件到 60s 发布 true；已到期立即发布；已连接/非队首不 arm。WAL 同一行读出 typed state/order；summary with* 收敛到 overlaying。定向 328/328，全量 991/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/35-c4r3-reopen-deadline-wake.md`。产品提交 `13240bb`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-06 10:35] Codex 手工验收 C4R3：单设备 reopen 成立，多设备 scheduler/order strictness 未闭；退 C4R4

- Agent Relay 保持暂停；固定审查 `63af334ef6b2b4dd5c82029c5e7f9c7f0beee16e...13240bb8d1ff92061eddf0a9b7d70c77d29e8b8d`，未生成或伪造 Relay `review_decision`。Codex 独立复跑定向 **328/328** 与 range `git diff --check` 通过；提交声明其余门禁为全量 **991 / 2 skipped / 0 failures**、App + Agent Release 通过。
- 已通过并冻结：单设备 fresh reopen 按原 `startedAt` 恢复未到期/已到期 wake；state/order 与 WAL 事务同一行读取；单一 `overlaying` 消除 summary clone 重复；C4R2 及更早冻结项未回退。
- **P1 — Agent-global 唯一 deadline task 会让不同设备队首互相覆盖。** 投影每个 disconnected head 时都可重新 arm，而 `scheduleAbandonEligibilityWake` 无条件取消当前全局 task。设备 A 在 t60、B 在 t90 到期时，B 可取消 A，导致 A 到 t90 或外部 snapshot 才可观测。触发后也没有消费 due 项并重算下一 deadline。这违反已冻结的 per-device 独立 FIFO。
- **P2 — typed order 对矛盾事实静默归一化。** `validated` 对 live 忽略 `terminalOrder`，对 terminal 忽略 `queueOrder`；测试明确允许双字段 JSON 并丢弃其中一个。当前 WAL 缺失/损坏 order 也可变 nil 后回退 UUID。老 wire payload 双缺省可保持兼容，但只要任一 order 字段存在，必须与 state 精确一致；当前 WAL 行必须缺失/矛盾 fail-closed。
- **P2 — 59→60 测试可被第二次 snapshot 假绿。** 测试 sleep 后先请求 60s snapshot，而 snapshot 本身会再次 rearm；即使 59s 建立的 wake 已丢失，也可在检查 event 前被补醒。反例必须从 59s cursor 直接等 eligible event，然后才可验 snapshot。
- C4R4 仅允许：（1）per-device wake tasks，或单 scheduler 始终保留全部 durable heads 中最早待触发 deadline，触发/连接/终态/队首变更后消费无效项并重算下一项；（2）strict state/order wire + WAL 校验，禁止矛盾静默归一化和当前 store 回退 UUID；（3）先 event、后 snapshot 的真静默测试，加 A@60/B@90 相互不取消且依次到期反例。
- 白名单限 Agent deadline scheduler/启动投影、Runtime contract/store order strict decoder、精确 Agent/contract/store 测试、单一 C4R4 evidence、本卡与 Cursor append-only board。不改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R4）

### [2026-09-06 10:48] Cursor ACK：开始 C4R4 per-device deadline / strict order

ACK 用户转发的 Codex C4R3 未通过与 C4R4 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 已通过项冻结 @ `13240bb`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R4：多设备独立队首 deadline 不得互相覆盖；strict state/order wire+WAL fail-closed；59s cursor 先等 event 再 snapshot。不改 C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-06 12:12] Cursor：C4R4 完成，停手提审

ACK 用户转发的 Codex C4R3 未通过与 C4R4 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 已通过项冻结 @ `13240bb`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。单 scheduler 保留各 disconnected 队首 deadline，始终睡最早未发布项；B@90 不得取消 A@60。wire 双缺省兼容，否则恰好一个与 state 匹配的正序号；当前 WAL live 缺失/矛盾 fail-closed。59s cursor 先等 event 再 snapshot。定向 330/330，全量 993/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/36-c4r4-per-device-deadline.md`。产品提交 `b462eae`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-06 13:19] Codex 手工验收 C4R4：正常调度成立，发布消费/C3 WAL 范围未闭；退 C4R5

- Agent Relay 保持暂停；固定审查 `13240bb8d1ff92061eddf0a9b7d70c77d29e8b8d...b462eae055e73890ab30a8be1cdaf92674947874`，未生成或伪造 Relay `review_decision`。Codex 独立复跑定向 **330/330** 与 range `git diff --check` 通过；提交声明其余门禁为全量 **993 / 2 skipped / 0 failures**、App + Agent Release 通过。
- 已通过并冻结：A@60/B@90 的正常独立调度与依次到期；59s cursor 先收 event 后验 snapshot；strict flat-wire order；当前 live WAL 缺失/矛盾 fail-closed；C4R3 与更早冻结项未回退。
- **P1 — 到期发布失败仍被永久标记已消费。** `publishAbandonEligibilityRefresh()` 在 store/recovery/projection 失败时会静默 return，但调用方随后无条件把 due device 写入 `publishedAbandonDeadlines`。一次瞬时失败就会永久抑制该 epoch 重试，直到外部 snapshot。发布必须返回对冻结完整 epoch token 的成功事实，只有 pending 仍精确相等才可消费；失败要保留并有界重试。
- **P1 — 旧 wake 跨 await 只冻结 device ID，未冻结 epoch。** 若发布期间同设备已替换为新 epoch，旧路径可把当前新 `startedAt` 标成 published，使新代 60s wake 消失。必须冻结 `(deviceID, full epoch)` 并在 await 后做精确 token CAS；取消检查不能代替身份比较。
- **P1 — 越界改变 C3 WAL 竞争语义。** `AhaKeyRuntimePersistentStore` 全局新增 `sqlite3_busy_timeout(500)`，不属于 strict order decoder，却改变所有 Runtime store 等待/失败边界，与本轮“C3 WAL/CAS 未动”相矛盾。必须删除，损坏测试在 fixture/raw SQLite 侧自行编排。
- **P2 — 现代本地 order API 仍静默降级。** wire decoder 已 strict，但 public summary init 的 `catch` 和 `withDurableOrder` 的 `try?` 仍把非法/零序号转为 legacy nil，可在进程内重新引入 UUID fallback。legacy nil 只能来自真正双缺省的旧 wire；现代构造应 typed-only 或 throwing。
- C4R5 仅允许：（1）冻结 `(deviceID, full epoch)` due token，发布成功且 pending token 仍相等时才消费，store/投影失败时保留并有界重试；（2）删除全局 busy timeout；（3）将本地新 summary/order 构造收成 typed/throwing，禁止非法值转 nil。补发布失败→重试成功、旧 epoch publish gate 内替换新 epoch、fresh Agent 连接 B+断连 A、本地非法 order 四类生产形状反例。
- 白名单限 Agent deadline publication/scheduler、Runtime contract/order 本地构造收口、删除 store busy timeout 的单行回退、精确 Agent/contract/store 测试、单一 C4R5 evidence、本卡与 Cursor append-only board。不改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R5）

### [2026-09-06 13:27] Cursor ACK：开始 C4R5 deadline publication CAS / WAL scope

ACK 用户转发的 Codex C4R4 未通过与 C4R5 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 已通过项冻结 @ `b462eae`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R5：完整 epoch token publication CAS、失败有界重试、删除 busy timeout、本地 order throwing。不改 C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-06 13:52] Cursor：C4R5 完成，停手提审

ACK 用户转发的 Codex C4R4 未通过与 C4R5 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 已通过项冻结 @ `b462eae`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。到期发布冻结完整 `(deviceID, epoch)` token，refresh 成功且 pending 仍精确相等才消费；失败保留并有界重试。删除全局 busy timeout。本地 summary/order throwing。定向 333/333，全量 996/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/37-c4r5-deadline-publication-cas.md`。产品提交 `b030c3b`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-06 14:59] Codex 手工验收 C4R5：epoch CAS 骨架成立，publication proof/retry isolation 未闭；退 C4R6

- Agent Relay 保持暂停；固定审查 `b462eae055e73890ab30a8be1cdaf92674947874...b030c3b5fa4b2087801eb825493f66566170276c`，未调用 Relay。Codex 独立复跑定向 **333/333** 与 range `git diff --check` 通过；提交声明其余门禁为全量 **996 / 2 skipped / 0 failures**、App + Agent Release 通过。
- 已通过并冻结：pending/published 保留 full epoch；await 后 pending token 精确比较；瞬时失败保留 deadline 并能重试；旧 epoch 不消费已替换新 epoch；connected B/disconnected A；删除越界 SQLite busy timeout。
- **P1 — refresh 成功不等于 token 的 eligible event 已发布。** helper 把 token 降为 device ID set，只要 `recoveryCandidates()` 成功就在遍历后返回 true。缺 candidate、错/替换 epoch、running candidate，或被 `try?` 吞掉的 epoch/queue/baseline 投影失败，都可无 `eligible=true` event 却消费 token。必须逐 token 同时证明 current durable head + exact epoch + eligible summary 已实际 publish，并返回可消费的精确 token set。
- **P1 — retry 是永久 20ms/50Hz，并非有界。** 持久 store 故障会无限重开/读取，造成 CPU/DB 压力。应使用有上限频率的指数 backoff 或有界 attempt burst，但保留 token 供后续 recovery/snapshot 触发。
- **P1 — scheduler 可变状态无强制隔离。** deadline dictionaries/task/fireAt 同时被 XPC snapshot 任务、BLE callback 与 wake Task 跨 await 读写，owner 不是 actor，helper 也无 `@MainActor`。并发 snapshot/callback/wake 可竞争取消或覆盖调度状态。必须将完整 scheduler state machine 收入 MainActor 或专用 actor，不得只隔离部分字段。
- **P2 — modern order 仍与 legacy/raw 表达混用。** throwing init 同时接收 raw `queueOrder`/`terminalOrder` 和 typed `durableOrdering`，`??` 可静默忽略同类 raw 冲突；双 nil 在现代本地构造仍会成为 legacy nil，生产调用又大量使用 `try!`。应分离 legacy wire decoder 与 typed production initializer，现代 API 仅接受 typed order 并消除生产 `try!`。
- C4R6 仅允许：（1）typed deadline token 须含 operationID/deviceID/full epoch，以原子/一致读证明当前队首与 epoch，并仅消费已实际发出 eligible event 的 token set；（2）失败重试使用不会热循环的有上限频率 backoff/有界 burst，token 保留；（3）scheduler 完整状态收入 MainActor/专用 actor；（4）legacy flat-wire decode 与 modern typed production construction 分离，去 raw+typed 歧义、双 nil 本地 fallback 和生产 `try!`。
- 补精确反例：缺 candidate/错 epoch/running/投影读失败均不消费；多次/持久失败重试频率有界；并发 snapshot+reconnect/new mint+wake 不丢 token；modern local nil/冲突 order 构造不得成功。不改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R6）

### [2026-09-06 15:04] Cursor ACK：开始 C4R6 proven publication / isolated bounded scheduler / typed order

ACK 用户转发的 Codex C4R5 未通过与 C4R6 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R6：operationID+epoch 逐 token 证明并只消费已发布 eligible event；有界 backoff；scheduler 专用 actor；typed production order 与 legacy wire 分离。不改 C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-06 15:53] Cursor：C4R6 完成，停手提审

ACK 用户转发的 Codex C4R5 未通过与 C4R6 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。逐 token 证明 durable 队首+exact epoch，并只消费已发出 eligible event 的集合；失败 4 次指数 backoff 后停 wake、保留 token；scheduler 专用 actor；typed production order 与 legacy wire 分离。定向 337/337，全量 1000/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/38-c4r6-proven-publication-scheduler.md`。产品提交 `2c2e59f`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-06 16:00] Codex 手工验收 C4R6：actor/backoff 主干成立，atomic event proof/per-device failure isolation 未闭；退 C4R7

- Agent Relay 保持暂停；固定审查 `b030c3b5fa4b2087801eb825493f66566170276c...2c2e59f6d52896145e965fd409f9d5c08d608d00`，未调用 Relay。Codex 独立复跑定向 **337/337** 与 range `git diff --check` 通过；提交声明其余门禁为全量 **1000 / 2 skipped / 0 failures**、App + Agent Release 通过。
- 已通过并冻结：scheduler 完整状态收入专用 actor；token 含 operationID/deviceID/full epoch；pending CAS 不消费替换 token；20/80/320/1280ms 四档 burst 后停 wake 并保留 token；public typed initializer 与 legacy wire decoder 已分开；C4R5 及更早冻结项未回退。
- **P1 — publication proof 仍存在 TOCTOU。** `proveAndPublishOneAbandonToken` 分别 await 读 queue head、epoch、confirmed/baseline/connection，之后才在 MainActor 发事件。reconnect/clear/head transition 可在最终检查后提交，导致过期 `eligible=true` 已发出；actor pending CAS 只能阻止消费，不能撤回错误事件。需要一致/原子的 durable proof 与发布顺序边界。
- **P1 — 发布确认可借用旧事件。** `publishOperationChanged` 可去重，随后仅读 `lastPublishedOperationSummaries` 并核 operationID+eligible。两个 identity 不同但 `startedAt` 相同的 epoch 产生相同 summary 时，新 token 没有新 event 仍可被判已证明/消费。proof 必须绑定 exact token 与新事件 sequence/emission result，或在投影中携带不可碰撞的 token identity。
- **P1 — retry exhaustion 仍是 scheduler-global。** A 在 t60 持久失败耗尽全局 `retryAttempt/burstExhausted` 后，`startWakeIfNeeded` 会拒绝所有调度，B@90 也不再到期，直到外部 snapshot/recovery；违反多设备独立 FIFO。失败状态必须 per-token/per-device，或隔离/quarantine A 后继续调度 B。
- **P1 — typed order 生产不变式被 package initializer 绕过。** `storageID` initializer 接受 optional order 且不校验；TransactionRunner 构造 completed/failed terminal summary 时传入当前 WAL 的 `.live(queueOrder:)`，形成 terminal-state+live-order 非法对象，`commitOperationOutcome` 忽略后再分配 terminal order。modern typed-only 尚未覆盖真生产路径。
- C4R7 仅允许：（1）将 current durable head+exact epoch+projection/connection 收成一致证明，并保证过期 true 不会在 transition 之后发出；（2）publication API 返回绑定 exact token 的新 event sequence，去重不得借用旧 summary；（3）retry/burst/exhaustion 改为 per-device/token，A 持久失败不阻断 B；（4）删除/封闭 unchecked `storageID` 生产 bypass，Runner terminal transition 必须使用与 terminal state 匹配的 typed ordering，或使用不伪装成 projected summary 的专用 transition input。
- 补精确反例：proof 最终检查后 reconnect/head-change 不发 stale true；同 startedAt/不同 epoch 必须产生新 event sequence；A 失败耗尽后 B 仍在 t90 发布；Runner completed/failed/cancel terminal 不得构造 live-order summary。不改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R7）

### [2026-09-06 16:10] Cursor ACK：开始 C4R7 atomic publication proof / per-device retry / order transition

ACK 用户转发的 Codex C4R6 未通过与 C4R7 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R7：一致证明与发布边界；绑定 exact token 的新 event sequence；per-device retry；封闭 storage init bypass，Runner terminal 匹配 typed order。不改 C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-06 16:43] Cursor：C4R7 完成，停手提审

ACK 用户转发的 Codex C4R6 未通过与 C4R7 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。到期发布按 fence+mutationGeneration 一致证明发出绑定 exact token/epochIdentity 的新 event；同 startedAt 不同 identity 不得借用旧事件。retry/exhaustion 按设备隔离。storage init 校验 order；Runner terminal 使用 typed terminal order。定向 342/342，全量 1005/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/39-c4r7-atomic-publication-per-device-retry.md`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-06 18:07] Codex 手工验收 C4R7：event identity/per-device state 主干成立，post-proof fence/retry task/order truth 未闭；退 C4R8

- Agent Relay 保持暂停；固定审查 `2c2e59f6d52896145e965fd409f9d5c08d608d00...d02d6117264020d0410bd91bba9e34057705ebe4`，未调用 Relay。Codex 独立复跑定向 **342/342** 与 range `git diff --check` 通过；提交声明其余门禁为全量 **1005 / 2 skipped / 0 failures**、App + Agent Release 通过。
- 已通过并冻结：一次 store hop 读 facts 与 mutation generation；exact `epochIdentity` + 强制新 event sequence，不借用旧 summary；retry attempt/exhaustion 按 device 分开，A 正常失败不再冻结 B；storage init 校验 state/order case。
- **P1 — 最终 proof 后仍有发布窗口。** 第二次 `abandonPublicationFacts` 返回后 store actor 已释放，再 hop MainActor 发事件。Runner 可在其间提交 head/state 变化；`abandonPublicationFence` 只覆盖 BLE/mint/clear，该 WAL transition 不会同步推进 fence，mutation generation 也没在发布点保持/重核。因此过期 `eligible=true` 仍可在终态之后发出。
- **P1 — retry sleeper 只绑 device ID。** `scheduleDeviceRetry` 创建不受跟踪的 Task，既不携 token/generation，也不能被 upsert/drop/cancelAll 取消/等待。N 在 sleep 时替换为 N+1 后，旧 N task 会清掉 N+1 的 retry-wait 并提前唤醒；`cancelAllAndWait` 也未真等待这些 task。
- **P2 — Runner 使用伪造 terminal order。** completed/failed/cancel 都构造 `.terminal(terminalOrder: 1)`，store 随后忽略该值并分配另一真实 order。这只满足 typed case shape，却把语义为假的 projected-summary 当 transition command。应由 store 分配 terminal order 后构造 summary，或改用不携 projected order 的专用 transition input。
- C4R8 仅允许：（1）用 store-side publication reservation/CAS 或所有相关 mutation 先推进的共享 fence，关闭第二次 proof→publish 窗口；（2）retry task 按 exact token/generation 跟踪，upsert/drop/cancelAll 使旧 sleeper 取消或自行失效，`cancelAllAndWait` 等待全部；（3）去掉 `.terminal(1)` 占位，终态 order 仅来自 store 真实分配，或分离 transition input/projected summary。
- 补精确反例：第二次 proof 返回后、MainActor publish 前提交 head terminal/reconnect 时零 stale true；N retry sleeping 时 replace/drop/cancelAll→N+1 不受影响；Runner completed/failed/cancel 不创建伪 order。不改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R8）

### [2026-09-06 18:27] Cursor ACK：开始 C4R8 post-proof fence / tokenized retry / store-owned terminal order

ACK 用户转发的 Codex C4R7 未通过与 C4R8 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R8：post-proof mutation fence；tokenized retry task 取消/等待；store-owned terminal order。不改 C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-06 18:49] Cursor：C4R8 完成，停手提审

ACK 用户转发的 Codex C4R7 未通过与 C4R8 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。第二次 proof 与 MainActor 发布共用 mutation fence；retry sleeper 绑 exact token/generation，cancelAllAndWait 等待全部 task。Runner 终态只提交不带 projected order 的 transition，由 store 分配真实 terminal order。定向 347/347，全量 1010/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/40-c4r8-post-proof-fence-tokenized-retry.md`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-06 18:54] Codex 手工验收 C4R8；retry/transition 通过，shared fence 覆盖与 terminal allocation 未闭；退 C4R9

- Agent Relay 保持暂停；固定审查 `d02d6117264020d0410bd91bba9e34057705ebe4...f37184f7163dc3a4e8273ba2dc4e139235174c3f`，未调用 Relay。Codex 独立复跑定向 **347/347** 与 range `git diff --check` 通过；提交声明其余门禁为全量 **1010 / 2 skipped / 0 failures**、App + Agent Release 通过。
- 已通过并冻结：MainActor 发布在 mutation lock 内核 generation；retry sleeper 绑 exact token+generation，upsert/drop/cancelAll 取消失效且等待全部 task；专用 TerminalTransition 不再携带伪造 projected order。
- **P1 — publication fence 覆盖不完整。** `abandonPublicationFacts` 包含 confirmed steps/page baselines，但 `confirmStep`、`confirmPageStep`、`applyAuthoritativeFieldReadback` 及其写路径未在写前 bump `mutationFence`。它们可在第二次 proof 后提交，generation 不变，从而发出带过期 residual/baseline 的 eligible summary。
- **P1 — fence 是 Store 实例私有，不是 persistence-root/WAL 共享。** 同一 root 的第二 Store/重叠进程拥有独立 `AhaKeyRuntimeMutationFence`，其 head/epoch 写不会推进 proof Store 的 generation，`publishIfUnchanged` 仍可接受旧 facts。必须使用 root-shared fence/reservation 或 durable CAS，并与跨 Store 独占锁顺序闭合。
- **P1 — terminal order 在写事务之前分配。** `commitOperationOutcome` 先读 `MAX(terminal_order)+1`，后执行 `BEGIN IMMEDIATE`；两个 Store 可同时取得相同 N+1 并依次写入，且无 unique constraint，破坏 durable terminal ordering/fresh Studio 同页最新选择。必须在获得 `BEGIN IMMEDIATE`/跨 Store 独占锁后分配并写入。
- C4R9 仅允许：（1）补齐所有 facts-affecting write 的 pre-write fence bump；（2）将 publication reservation/fence 收成 persistence-root 共享或 durable generation/CAS，防跨 Store/进程窗口；（3）将 terminal-order allocate+write 放入同一 `BEGIN IMMEDIATE`/跨 Store lock。
- 补精确反例：post-proof gate 内 confirmPageStep/authority readback 写不得发 stale projection；双 Store 同 root 变异使 proof 失效；双 Store 并发 terminal transition 必须产生唯一单调 order。不改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor（除上述紧缩性原子化）。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R9）

### [2026-09-06 19:07] Cursor ACK：开始 C4R9 complete shared fence / transactional terminal order

ACK 用户转发的 Codex C4R8 未通过与 C4R9 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R9：补齐 facts 写前 fence；persistence-root 共享/durable fence；terminal_order 在写事务/跨 Store 锁内分配。不改 C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor（仅紧缩性原子化）。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-06 19:32] Cursor：C4R9 完成，停手提审

ACK 用户转发的 Codex C4R8 未通过与 C4R9 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。publication-facts 写入写前推进 root-shared lockfile fence；terminal_order 在写事务/跨 Store 锁内分配。定向 353/353，全量 1016/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/41-c4r9-complete-shared-fence-terminal-order.md`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-06 21:33] Codex 手工验收 C4R9；主契约成立，fence 异常/生命周期与稳定门未闭；退 C4R10

- Agent Relay 保持暂停；固定审查 `f37184f7163dc3a4e8273ba2dc4e139235174c3f...fcb40c01e36d7baf202c076005428d8c6291553d`，未调用 Relay。产品 range `git diff --check` 通过。Codex 独立定向套件连续两次均为 **352/353, 1 failure**：`testFreshReopenDisconnectBeforeReadyMintsNewEpoch` 报 `databaseFailure("database is locked")`；该项单独立即通过，证明为 full-suite 负载/生命周期竞争。提交声明的 353/353 当前不可复现；全量 1016/2 skipped/0 与 Release 未重跑。
- 已通过并冻结：已识别 publication-facts 写入在写前 bump；同 root 世代经 lockfile + flock 共享；terminal order 在独占锁 + `BEGIN IMMEDIATE` 内分配写入；post-proof 与双 Store 正常反例成立。
- **P1 — `loadGeneration` 失败会永久泄漏两把锁。** `withExclusiveAccess` 先取 `NSRecursiveLock` 和 `flock(LOCK_EX)`，但在进入配对 `do/catch` 前调用可抛错的 `loadGeneration()`。short/corrupt 文件或 `pread` 失败会直接退出，recursive/flock 均不释放；`current()` 又将错误吞成 0，后续 Store/进程会永久阻塞而非 fail-closed。
- **P1 — unlock 失败分支可双重清理。** `LOCK_UN` guard 分支先 `recursive.unlock()` 再 throw，随即进入同一 catch 再次 `depth -= 1`/解锁，可破坏 depth 并双重 unlock。所有错误路径必须只经单一 cleanup state machine。
- **P1 — root registry/FD 无生命周期。** static strong dictionary 永久保留每个 fence 和 duplicated FD，无 close/eviction；长运行/测试会 FD 耗尽并触发 `dup` precondition crash。root 删除重建同路径时，cached fence 仍指向 unlinked 旧 inode，其他进程锁新 inode，跨进程互斥失效。
- C4R10 仅允许：（1）重写 fence acquire/load/body/unlock 为单一对称 cleanup，任意一步失败均释放已持有资源且保留原错，`current` 改为 throwing/显式 fail-closed；（2）registry 使用有所有权的 lease/refcount/weak eviction，关闭 dup FD，检测 root lockfile inode 替换；（3）修复 fresh reopen full-suite `database is locked` 竞态。
- 补 short/truncated lockfile、`pread`/`LOCK_UN` 故障后同 root 仍可操作，root delete/recreate 后两进程仍互斥，以及 targeted 连续至少 5 轮 + full Swift 稳定门。不改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor（除上述锁生命周修复）。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R10）

### [2026-09-06 22:14] Cursor ACK：开始 C4R10 fence error-path / root lifecycle / contention stability

ACK 用户转发的 Codex C4R9 未通过与 C4R10 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R10：对称 cleanup；throwing generation read；registry lease/inode/FD；fresh reopen 稳定门。不改 C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor（仅锁生命周期修复）。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-07 10:28] Cursor：C4R10 完成，停手提审

ACK 用户转发的 Codex C4R9 未通过与 C4R10 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。fence 对称 cleanup；`current()` fail-closed；registry lease/inode/FD；Store/Agent 显式 close。定向连续 5 轮 358/358，全量 1021/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/42-c4r10-fence-error-path-lifecycle.md`。产品提交 `b514f1f`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-07 10:37] Codex 手工验收 C4R10；稳定门恢复，初始化/unlock/close 所有权未闭；退 C4R11

- Agent Relay 保持暂停；固定审查 `fcb40c01e36d7baf202c076005428d8c6291553d...b514f1feacac9862decce3a87e19d0359ad52f2c`，未调用 Relay。Codex 独立连续 **5 轮定向 358/358**，range `git diff --check` 通过；上轮 fresh-reopen `database is locked` 未再现。提交声明其余门禁为全量 **1021 / 2 skipped / 0 failures**、App + Agent Release 通过。
- 已通过并冻结：`loadGeneration`/body 异常走对称 cleanup；`current()` throwing；fence lease/inode 识别与最后 lease 回收 dup FD；Store.close 关 SQLite 后放 fence lease；root 正常删除重建和 fresh reopen 压力稳定。
- **P1 — 空 generation 文件仍 fail-open 为 0。** `loadGeneration()` 对 `pread == 0` 直接接受 generation 0；测试还在三字节损坏后主动 truncate 为空并期望 0。在既有 generation >0 后被截断可回滚世代，让旧 expected-0 publication 重新通过。新 lockfile 须显式初始化可识别记录；既有空文件必须视为损坏。
- **P1 — 真实 `LOCK_UN` 失败后不保证释放 OS lock。** 当前只记 cleanup error 并释放 recursive lock，descriptor/fence 仍可用。hook 测试先成功执行真 unlock，之后才伪造错误，没有覆盖 syscall 未释放的生产路径。必须重试 EINTR；其他错误 poison 并关闭/退出全部共享 descriptor，后续确定性拒绝。
- **P1 — cache clear 在摘除引用前 await close。** cache actor 在 `await store.close()` 时可重入，并发 `store(for:)` 仍会返回同一 cached Store；该调用方随后使用已关闭 SQLite/FD。必须先将 `cached=nil`，再 await teardown。
- **P1 — close 后 Store/fence 仍可调用。** `CloseBox` 关闭 SQLite、lock FD 和 fence lease，但 Store actor 公共 API 与 nonisolated `mutationFence` 仍暴露，可把已关闭或已被 OS 复用的数字 FD 传给 sqlite/flock。需要 fence/store closed-state 门或消费式所有权。
- **P2 — root 重建反例未验两进程争用。** 现测试仅单进程创建多个 Store、比较 fence 对象 identity 并做只读 health，没有在一侧持有临界区时让第二进程尝试冲突写。
- C4R11 仅允许：（1）新 lockfile 显式初始化带 magic/version/generation 的完整记录，既有 zero/truncated 拒绝；（2）unlock syscall 的 EINTR retry + 不确定错误 poison/evict/close；（3）cache detach-before-await；（4）Store/fence close 后所有入口 fail-closed；（5）真子进程/独立进程 root-recreate 争用反例。
- 补精确测试：初始化空 vs 事后 truncate；真 unlock 故障在 syscall 前注入并证明其他 Store/进程不阻塞；clear 重入不返回旧 Store；close 后 health/transaction/fence 等确定性拒绝；root 删除重建跨进程写互斥。不改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor（除上述锁/关闭所有权收口）。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R11）

### [2026-09-07 10:44] Cursor ACK：开始 C4R11 initialized generation / unlock quarantine / close ownership

ACK 用户转发的 Codex C4R10 未通过与 C4R11 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`；C4R10 已通过项冻结 @ `b514f1f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R11：初始化 generation 记录；unlock poison/evict；cache detach-before-await；close 后 fail-closed；跨进程 root-recreate。不改 C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor（仅锁/关闭所有权收口）。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-07 11:21] Cursor：C4R11 完成，停手提审

ACK 用户转发的 Codex C4R10 未通过与 C4R11 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`；C4R10 已通过项冻结 @ `b514f1f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。新 lockfile 写入 `AKG1` generation 记录；既有空/截断 fail-closed。`LOCK_UN` EINTR 重试，其他失败 poison/evict/关闭 fence FD。cache 先摘 cached 再 await close。Store/fence close 后入口拒绝。root 重建跨进程 `flock` 互斥。定向连续 5 轮 361/361，全量 1024/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/43-c4r11-initialized-generation-unlock-quarantine.md`。产品提交 `dcb219b`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-07 14:06] Codex 手工验收 C4R11；unlock/cache 通过，legacy upgrade/per-Store close 未闭；退 C4R12

- Agent Relay 保持暂停；固定审查 `b514f1feacac9862decce3a87e19d0359ad52f2c...dcb219be7c2087d451498d4e463b14ba3cd5d53a`，未调用 Relay。Codex 独立定向 **361/361**，range `git diff --check` 通过；提交声明其余门禁为定向连续 5 轮、全量 **1024 / 2 skipped / 0 failures**、App + Agent Release 通过。
- 已通过并冻结：unlock EINTR retry+非 EINTR quarantine 主路；cache detach-before-await；单一/最后 lease close 后 fence 拒绝；root inode replacement 的真子进程 raw-flock probe；fresh-reopen 稳定门。
- **P1 — 合法旧产品 root 无法升级。** C4R11 之前的 Runtime 已创建但不写 `.runtime-store.lock`，因而已安装 0.2.1/已有 WAL 的合法 lockfile 是空的。新 init 以 `lockExisted` 将其判为损坏并拒绝，v0.3 无法 reopen。需用 durable store/schema marker 在 flock 内区分一次 legacy migration 与已初始化后 truncate。
- **P1 — 首建判定非原子。** `fileExists` 与 `open(O_CREAT|O_RDWR)` 分离；其间被另一进程创建的空/损坏文件仍会被当成新文件初始化，而 creator 在创建后写记录前崩溃又会让下次启动永久拒绝。初始化权必须由 `O_CREAT|O_EXCL` 或等价原子 creator proof 决定。
- **P1 — close 所有权仍可跨 Store 绕过。** 同 root 的 A/B 共用 public nonisolated fence；A.close 只减一条 lease，B 存在时 A 暴露的 `mutationFence.current()/bump()` 仍成功。另有 `allocateAuthoritativeWriterLease` 等入口未经 `ensureOpen`，可在共享 fence 存活时对 A 已关闭 SQLite 指针执行 SQL，存在 crash/UB。
- **P2 — generation record 只验前 16 字节。** decoder 不核文件精确长度，合法 `AKG1` 前缀后追加任意损坏数据仍接受。
- **P2 — 跨进程反例只试 raw flock。** 子进程没有打开独立 Store 并尝试冲突 SQLite/WAL 写，因此只证明 inode lock 可见，未证明 end-to-end 写互斥。
- C4R12 仅允许：（1）基于 durable DB/schema marker + flock 的 legacy-empty one-time migration，并用原子 creator proof 关闭首建/crash TOCTOU；（2）每 Store closed-aware fence lease/wrapper，A.close 后 A 的全部 API/fence 立即拒绝，B 不受影响；（3）精确 16-byte/framed record 校验；（4）真子进程 Store+WAL 冲突写互斥测试。
- 补精确反例：从 C4R10/0.2.1 形状的 empty-lock+legacy DB 升级成功，之后 truncate 拒绝；两进程同时首建/中途 crash 可恢复；A/B 共享后 close A，A health/transaction/authority/fence 拒绝而 B 继续；trailing bytes 拒绝；root recreate 后独立进程冲突 terminal/confirm 写依然串行。不改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor（除上述升级/所有权收口）。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R12）

### [2026-09-07 14:22] Cursor ACK：开始 C4R12 legacy-root migration / per-store close lease / process-write proof

ACK 用户转发的 Codex C4R11 未通过与 C4R12 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`；C4R10 已通过项冻结 @ `b514f1f`；C4R11 已通过项冻结 @ `dcb219b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R12：原子 creator + durable marker 的 legacy-empty 一次迁移；per-Store closed lease；精确 16 字节 framing；跨进程 Store/WAL 冲突写。不改 C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor（仅升级/所有权收口）。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-07 15:52] Cursor：C4R12 完成，停手提审

ACK 用户转发的 Codex C4R11 未通过与 C4R12 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`；C4R10 已通过项冻结 @ `b514f1f`；C4R11 已通过项冻结 @ `dcb219b`。产品提交 `ebb30e2`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。合法空 lock + 无 marker 一次迁移；marker 后 truncate fail-closed。`O_CREAT|O_EXCL` 原子 creator。每 Store closed lease：A.close 后 A 的 fence/Store API 拒绝，B 继续。generation 精确 16 字节。子进程打开真 Store 做冲突 WAL 写。定向连续 5 轮 366/366，全量 1029/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/44-c4r12-legacy-root-per-store-close-process-write.md`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。

### [2026-09-07 16:03] Codex 手工验收 C4R12；迁移/close 主干成立，生产 probe 越界且跨进程门不稳；退 C4R13

- Agent Relay 保持暂停；固定审查 `dcb219be7c2087d451498d4e463b14ba3cd5d53a...ebb30e2d3730c81d834f2e6464e443999ecf8865`，未调用 Relay。range `git diff --check` 通过。Codex 独立定向连续两次均为 **365/366, 1 failure**：`testRootDeleteRecreateDoesNotLockStaleInode` 期望 BLOCKED，实际 TIMEOUT。提交声明的 5×366/366 当前不可复现；全量/Release 未重跑。
- 已通过并冻结：legacy empty + marker 迁移顺序；`O_CREAT|O_EXCL` creator；精确 16-byte framing；per-Store wrapper 与主要 Store API close gate；root Core/refcount 主干。
- **P1 — 测试子进程后门被编入生产 Shared。** 每个生产 Store init 都识别 `AHAKEY_C4R12_CHILD_ROOT/STATUS`；一旦环境变量存在，App/Agent 会使用外部路径创建/改权 root，accept synthetic `TEST-DEVICE` package，随后 `Darwin.exit`。这是未授权的 environment-triggered 生产写入/终止路径，必须完全移到 test target/独立 helper executable。
- **P2 — 跨进程反例挡在 child Store init，未冲突真 mutation。** parent 持 fence 时才启 child，child 在 Store init 外层 flock 就被阻塞，未到 `accept`。应先让 parent/child Store 都 READY，再协调一方持有临界区、另一方开始真 WAL mutation。
- **P2 — fence “全入口 close 后拒绝”尚差 `sharesLock(with:)`。** 该 public API 不检 lease closed，A.close 后仍可返回 true；应改 test-internal 或 closed-aware。
- C4R13 仅允许：（1）删除 Shared 底部全部 process-probe/env/exit 生产代码，在 test target/专用 executable 实现 child READY→MUTATE 协议；（2）两进程各自打开 Store 后才竞争真 terminal/confirm/accept 写，验证串行与放锁后成功；（3）`sharesLock` closed-aware/internal；（4）修复并连续复跑定向至少 5 轮全绿。
- 白名单限删除 Shared process probe、新增 test-only helper target/必要 Package.swift test product、精确 process/store 测试、单一 C4R13 evidence、本卡与 Cursor append-only board。不改 C2 assembler、C3 WAL/CAS/事务转移/BLE executor、Studio UI、Hook/安装器/固件。C5/HIL/打包/签名/安装/刷机/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C4R13）

### [2026-09-07 16:16] Cursor ACK：开始 C4R13 test-only process helper / stable WAL contention proof

ACK 用户转发的 Codex C4R12 未通过与 C4R13 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`；C4R10 已通过项冻结 @ `b514f1f`；C4R11 已通过项冻结 @ `dcb219b`。C4R12 已通过项（legacy-empty marker 迁移、`O_CREAT|O_EXCL`、精确 16-byte framing、per-Store close 主入口）冻结。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未改 queue/status。未伪造 Relay review_decision。仅执行 C4R13：从生产 Shared 删除 env 触发的 Store 写入/`Darwin.exit` probe；子进程 helper 放到独立 test executable；READY→MUTATE 证明已打开 Store 的真 WAL 写串行；`sharesLock` closed-aware/internal；修复定向 `testRootDeleteRecreateDoesNotLockStaleInode` TIMEOUT。不改 C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor。C5/HIL/打包/签名/安装/刷机/push 仍关闭。完成后停手提审，不自动进 C5。

### [2026-09-07 16:33] Cursor：C4R13 完成，停手提审

ACK 用户转发的 Codex C4R12 未通过与 C4R13 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`；C4R10 已通过项冻结 @ `b514f1f`；C4R11 已通过项冻结 @ `dcb219b`。C4R12 已通过项冻结。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。生产 Shared 删除 env/`Darwin.exit` probe。独立 test executable `AhaKeyRuntimeStoreProcessProbe` 实现 READY→MUTATE：两进程 Store 均就绪后，一方持临界区时另一方 `accept` 阻塞，放锁后 `GOT_LOCK`。`sharesLock` 改为 internal + closed-aware。inode 门改为 native 非阻塞 flock。定向连续 5 轮 369/369，全量 1032/2 skipped/0，App+Agent Release OK。证据 `docs/collab/evidence/V03-STUDIO-OLED-20260902/45-c4r13-test-only-process-helper.md`。未改 queue/status。未伪造 Relay review_decision。C5/HIL/打包/签名/安装/刷机/push 仍关闭。停手提审，不自动进 C5。
需要回复：是（@Codex 验收 C4R13）
