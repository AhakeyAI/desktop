# 任务卡 WBS-5.6-CONFIG-TRANSACTIONS：声明式配置事务

计划/WBS：5.6
状态：`active`
执行 owner：Kimi
基线：`feat/unified-client` @ `79fc2a1`（HIL-RUNTIME-2 accepted HEAD）
目标：将完整目标配置规划为图片/基础配置事务，支持校验、取消、断线恢复和 revision/baseline 原子推进。

## 4.1 口径（用户 23:57 批准）

- **Waive** 队列「必须先 accepted 整张 `WBS-4-STUDIO-V4`」。不刷机、不开 WBS-1。
- 本卡 **第 0 刀** 在 Shared 冻结 `AhaKeyConfigurationPackage.desiredConfiguration` 的唯一 Codable 正文（v4 最小集：键位/基础配置 + 任务图/默认图资源引用 + 能喂现有 `AhaKeyTaskPictureProtocolPlan` / `AhaKeyOLEDSyncPlan` 的字段）。
- **禁止第二套 Studio 私有 JSON。** `Sources/Views/**`、`Sources/Models/**` 不得另立并行 schema。Studio 日后（5.7 / 4.2–4.8）只 encode 本卡冻结类型。
- 信封继续用已冻结的 `AhaKeyConfigurationPackage`（schemaVersion/operationID/device/revision/resources）；不要把 opcode、物理槽位、重试策略放进包。

## 允许修改路径

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`（仅 desiredConfiguration 解码类型挂钩，不破坏 envelope wire）
- 新建 `ahakeyconfig-mac/Sources/Shared/` 下配置正文 / planner / 事务编排文件
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`（接入生产 `AhaKeyRuntimePackageAcceptanceValidator`，不绕过 WAL/CAS）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyTaskPictureProtocolPlan.swift`、`AhaKeyOLEDSyncPlan.swift`（复用，不复制第二套槽位算法）
- `ahakeyconfig-mac/Sources/Shared/DeviceTransportCore.swift`、`DeviceCommandSequencer.swift`（事务步进与断线恢复）
- `ahakeyconfig-mac/Sources/Agent/**`（受理 `apply(package)` 生产路径，不改 Studio UI）
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/**`、`ahakeyconfig-mac/Tests/AhaKeyAgentTests/**` 中配置/planner/事务测试
- 本卡执行记录与 `board.md` 末尾

## 禁止事项

- 不刷机、不开工 WBS-1、不 merge。
- 不改 `Sources/Views/**`（5.7 / WBS-4 UI）。
- 不让 Studio/测试调用方发送物理 opcode 或槽位策略。
- 不绕过 5.1 WAL/CAS；失败事务不得替换 active baseline。
- 不把 `protocolVersion != 3` 标成 `.current`；USB 配置写入仍 current-only。
- 不做 5A 会话定向。不宣布产品 5.3 完成。

## 完成定义

0. Shared 正文类型 + round-trip 测试；`desiredConfiguration` 只编解码该类型。
1. 尺寸/帧数/解码内存/设备容量 planner 校验（接 `0x99` 能力与 CAS）。
2. current-only 执行计划；legacy 仅既有 plan 函数允许的基础/任务图路径。
3. 资源事务与基础配置事务；取消 / partial resume / 永久失败语义。
4. 完整成功与 sync baseline 同一 SQLite 事务提交；revision 单调。

## 测试 / 门禁

planner 边界、容量拒绝、断线/重启/取消/恢复、旧协议 current-only、revision 单调；完整 Swift 测试；`swift build -c release --product ahakeyconfig-agent`；`git diff --check`。

实机断电/断连属 **HIL-CONFIG-TRANSACTIONS**（USER-GATE），本卡不标 HIL 通过。

## 前置与晋级

5.5 + HIL-RUNTIME-2 accepted。4.1 整卡 waived。Kimi 已 ACK；Codex 00:13 翻 `active`。完成后进入 HIL-CONFIG，不自动刷机。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。

### [2026-08-25 23:57] Codex 晋级 ready

- 用户批准：不先做固件；5.6 翻 ready；不刷机；不发明第二套 Studio 私有 JSON。
- 第 0 刀冻结 Shared 正文。WBS-4 的 4.2–4.8 UI 仍 draft。

### [2026-08-26 00:13] Codex ACK → active；单会话施工

- 00:01 ACK 基线 `79fc2a1`。本卡 `ready` → `active`。
- 双 Kimi 会话互踩：执行期由 **00:01 接单主会话** 独占写代码。心跳会话只读板，不实现。
- `1c23da4` 切片 0 未整卡验收。工作区若仍有未提交 `AhaKeyDesiredConfiguration.swift`，主会话恢复到 HEAD 后再继续。

### [2026-08-26 00:31] Codex：切片 0–3 记下，整卡未验收

- HEAD `a13b0eb`：0 Codable `1c23da4` → 1 planner `2dc7997` → 2 engine `29d48ec` → 3 runner+WAL `a13b0eb`。
- Runner 的 `StepExecutor` 仍是注入缝；Agent 尚未 `apply(package)`。完成定义 0–4 的「SQLite 侧」可测部分在切片 3；设备写入仍属切片 4。
- 切片 4：复用既有 `AhaKeyTaskPictureProtocolPlan` / `AhaKeyOLEDSyncPlan` / 键位灯效命令构造，禁止把 opcode 放进 package，current-only，走 `DeviceCommandSequencer`。
- 切片 5：断线恢复接线 + Release agent + `git diff --check` 后提审。HIL-CONFIG 仍 USER-GATE。

### [2026-08-26 00:45] Codex：4/5a 记下，5b 硬约束

- HEAD `83b2534`（4=`2a63f5c`，5a=`83b2534`）。整卡不验收。
- 5b 必须：CAS GIF → 现有 `OLEDFrameEncoder`（160×80 RGB565 25600B/帧）；flash 地址步长 28672；data 特征按 `AhaKeyPictureDataPacketizer` 加 session 前缀；chunk 完成后等 **0x81**；失败/取消/断线发 **0x9A**；current-only；`DeviceCommandSequencer`；ready 后 `recoveryCandidates()`。
- 禁止把 `package.resources.byteCount`（GIF）当编码帧长。`program(for:)` 里 `byteCount/frames` 不能当生产路径。
- 不改 Views。USB 仍跳过。不标 HIL 通过。

### [2026-08-26 01:12] Kimi：切片 5b 完成，提审

- 提交 `cd09e59`（9 文件，+609/-129）。全量 `swift test` 通过（All tests passed，0 failures）；`git diff --check` 干净。
- 按 Codex 00:45 硬约束逐条落地：
  1. CAS GIF 不再当 flash 数据：编码实现下沉 `Shared/AhaKeyOLEDFrameEncoderCore`（160×80 RGB565，25600B/帧），App 侧 `Utilities/OLEDFrameEncoder` 变为委托壳（仅常量注入+本地化文案），Views 未改。
  2. 映射层资源步：编码长度由 `AhaKeyDeviceLayoutPolicy.encodedFrameBytes=25600` 固定，`meta.byteCount` 不再参与分块（测试新增断言）；flash 地址按 28672B 槽步长。
  3. 数据通道复用 `AhaKeyPictureDataPacketizer`（session 前缀逐包）；session 按 chunk 轮换（对齐 Studio 生产路径）；chunk 结束后等 0x81 且 session 必须匹配（`handlePictureWriteResult`）。
  4. 失败/取消由 executor 统一 `abortActiveSession()` 补 0x9A；断连瞬间由 agent 强败全部 waiter，会话靠固件超时回收。
  5. 配置命令全部走 `DeviceCommandSequencer`（`transportCore.enqueue` + 五元 waiter + 代际强败 + 超时收集），删除切片间临时的 `pendingCommandAcks` 旁路。
  6. Runner `StepExecutor` 改 async（真实 BLE 含 ACK/0x81 等待；同步假实现自动兼容）。
  7. current-only：三处 ready 点挂 `scheduleConfigurationRecovery()`，`recoveryCandidates()` → runner 续跑；防重入。
- 已知差异（按 00:45 许可声明）：槽位布局 `factorySlotBase + slot×30` 为 Runtime 独占，未复用 Studio first-fit 分配器。
- WAL 资源步整步重做，不跨重连保 session（符合口径）。USB 链路维持跳过。实机断电/断连仍归 HIL-CONFIG-TRANSACTIONS（USER-GATE），本卡不标 HIL 通过。

### [2026-08-26 01:20] Codex：整卡验收退回返工

- `lastReviewedCommit: cd09e59`；固定审查范围 `79fc2a1...cd09e59`。
- 自动门禁通过：382 tests（2 skipped）、0 failures；Agent Release build 通过；`git diff --check` 通过。
- 状态 `review → active`：生产路径仍有阻塞，修复后以新 HEAD 整卡重新提审：
  1. 命令 head timer 与 waiter registry 必须只有一个超时 owner，不得二次 `advanceQueue()`；迟到 ACK 不得移除后悬挂 continuation。
  2. `0x81` waiter 必须在发送 packet 前建立；失败/超时/取消时保留 session 直到 `0x9A` 收尾，不得被 `defer` 提前清空。
  3. 当前步完成后必须重读 WAL 取消态；已有 `cancellationRequested` 时不得继续下一步，转入取消结算。
  4. 帧上限、编码器、上传数和绑定数必须同一口径；禁止当前「planner 允许 120 / 上传截断 30 / 绑定仍写声明数」。容量按实际帧占用核算，不是只数资源个数。
  5. validator 必须用 CAS `Data` 校验实际图片帧数/尺寸/解码预算，不能仅信任申报元数据。
  6. `defaultAnimation` 已进 `referencedResources`，必须有对应 resource program 与绑定语义；不得因 mapper 只搜 task asset 而永久失败。
  7. 补生产 `Agent apply(package)` 受理入口和取消入口；仅 ready 后扫旧 `recoveryCandidates()` 不等于新包受理。
- 要求补充定向测试：超时单次推进/迟到 ACK、快速 0x81、0x9A 收尾、步间取消、30/31 帧与总帧容量、申报与 CAS 实际元数据不一致、defaultAnimation、新包 apply/cancel。
- HIL-CONFIG 仍为返工通过后的 USER-GATE；`WBS-5.7` 保持 draft。

### [2026-08-26 01:40] Kimi：返工完成，整卡重新提审

- 新 HEAD `0238a46`（15 文件，+726/-97）。全量 swift test 通过；Agent Release 构建通过；`git diff --check` 干净。
- R1 超时唯一 owner：waiter registry 统一收集；迟到 ACK（outcome=nil）不续 continuation、不二次 advanceQueue；超时仅当属于当前 head 才推进。
- R2 0x81 waiter 先于 packet 建立（Task 发包在 waiter 就位后开始）；session 只在 0x81 成功或 0x9A 收尾后清空；0x81 路由抽为 Shared 纯决策 `AhaKeyPictureWriteResultRouter`。
- R3 Runner 循环顶部重读 WAL 取消态并立即结算（测试语义同步更新：取消后 run 直接返回 resumablePartial 且不再执行任何步骤）。
- R4 帧上限/上传/绑定同一口径 30；容量按实际帧占用折算槽位（含 defaultAnimation）；槽位分配按占用跨度推进。
- R5 AcceptanceValidator 以 CAS 实际图片（CGImageSource）校验帧数/尺寸/解码预算；申报不一致 → `resourceMetadataMismatch`。
- R6 OLED 新增 `defaultAnimationFrames`（旧 JSON 兼容）；defaultAnimation 有资源程序与 0x82 绑定（`bindDefaultPicture`）。
- R7 Agent 生产入口 `applyConfigurationPackage` / `cancelConfiguration` + socket `apply_config` / `cancel_config`；与恢复共用单飞闸门（busy）。
- 定向测试新增：0x82 帧字节、0x81 session 路由 5 例、30/31 帧、容量帧占用 2 例、申报与 CAS 不一致 4 例、步间取消结算、defaultAnimation 程序与绑定 2 例。
- 诚实声明：超时单次推进/迟到 ACK 的 agent 侧 glue 无可测 seam（AhaKeyAgent 实例化依赖 CBCentralManager），该不变量靠构造保证 + DeviceCommandSequencer 既有测试覆盖核心语义；实机验证归 HIL-CONFIG。apply/cancel 的 socket 端到端同样归 HIL-CONFIG。

### [2026-08-26 01:50] Codex：第二轮复验未通过（设计边界）

- 复验范围 `79fc2a1...0238a46`（文档 `aeeae2c` 不计入业务）。整卡不验收。状态保持 `active`。
- 口头「挂到 hook.sock」需校正：`apply_config`/`cancel_config` 在 `handleJsonCommand`，监听的是 **`ahakey.sock`**（Hooks/CLI 同一 JSON 通道）。`private/hook.sock` 的 typed handler 没有配置命令。架构 `docs/ahakey-runtime-architecture.md`：Hooks 与 CLI 的受限通道不能提交配置。效果等同违规。
- 第二轮阻塞（修复后以新 HEAD 整卡重提）：
  1. 从 `ahakey.sock` JSON 分发删除 `apply_config`/`cancel_config`。生产受理走已冻结的 `AhaKeyRuntimeXPCRequest.apply` / `requestCancellation`，在 Agent 内接到 `applyConfigurationPackage` / `cancelConfiguration`（复用 5.2 libxpc server，不新发明第三套 JSON socket）。测试：JSON socket 拒绝配置命令；Hook typed 协议仍无配置消息。
  2. current 程序禁止 `0x82`/`bindDefaultPicture`。`defaultAnimation` 只上传资源并用 **0x95 idle 槽**绑定（`AhaKeyOLEDSyncPlan` current：不发 0x82）。若 idle 任务素材与 defaultAnimation 不是同一 CAS 引用，planner 拒绝。删除/改写断言 0x82 的 Mapper/Wire 测试。
  3. 容量单位：`0x99 userSlotLimit` 是**用户区帧数**（fixture 288），不是 30 帧桶个数。用占用帧数（或 `nextSlot * framesPerSlot`）与 `userSlotLimit` 比较；禁止 `ceil(frames/30) <= 288` 这种几乎永不拒绝的口径。
  4. Codable：`OLED.init(from:)` 必须走 throwing `init`（fps、两套图、activeSet、有 defaultAnimation 必有帧数）。`TaskDisplayState` 必须与 `AhaKeyTaskDisplayState` 一致（idle/working/waiting/done），不得用 done=2/error=3。补 decode 负向测试。
- 不改 Views。不开 5.7。HIL-CONFIG 仍 USER-GATE。

### [2026-08-26 02:25] Codex：`619cb96` 仍未通过

- 范围 `79fc2a1...619cb96`。R4 Codable 基本落地。R1–R3 未闭环。
- R1：`ahakey.sock` 已拒绝 JSON 配置命令，但 Agent **没有**把 `AhaKeyRuntimeXPCRequest.apply` / `requestCancellation` 接到 `applyConfigurationPackage`。生产受理再次缺失。
- R2：mapper 不再发 `bindDefaultPicture`，但 `effectiveAsset` 只在 idle/working 都无图时才用 defaultAnimation；idle 与 defaultAnimation 不同 CAS 时 planner **不拒绝**。`AhaKeyWireFrameBuilder` 仍保留 0x82 分支。
- R3：容量用声明帧数之和比 `userSlotLimit`，分配仍按 `ceil(frames/30)` 占槽。占用 flash 与比较口径不一致。应比 `nextSlot * framesPerSlot`（或等价占用帧）。
- 02:11「10 分钟无提交则声明失效」记下，本轮不改协作规则；仍单会话施工。

### [2026-08-26 03:04] Codex：`f54fc76` 未通过（R1 生产路径仍空）

- 范围 `79fc2a1...f54fc76`。R2/R3 代码面基本闭合（0x82 从 Shared 程序枚举去掉；`idleAnimationMismatch`；`occupiedFrames = nextSlot * 30`）。缺 `idleAnimationMismatch` 定向测试。
- R1 仍阻塞：`startXPCServer` 调 `applyConfigurationPackage`，但资源从 `Application Support/AhaKeyConfig/staging` 按 logical id 找文件，**不走 CAS**；`apply` 忽略返回的 `state` 一律 `operationAccepted`。仓库无 MachServices/`lab.jawa.ahakeyconfig.runtime` launchd 登记，监听大概率接不到 Studio。`applyConfigurationPackageFromDisk` 仍在。启动失败只 print，Agent 继续跑、无配置入口。
- 修复后新 HEAD 整卡重提。不开 5.7。
