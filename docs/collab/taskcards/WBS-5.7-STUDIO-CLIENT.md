# 任务卡 WBS-5.7-STUDIO-CLIENT：Studio 纯 Runtime 客户端化

计划/WBS：5.7  
状态：`active`（Kimi 2026-08-26 20:49 接单）
执行 owner：Kimi
基线：WBS 5.6 accepted @ `19eb4dc`；5.2 生产 XPC seam accepted 基线
目标：Studio 仅通过 XPC snapshot/event/operation 管理 Runtime，删除生产直连 BLE/USB。

允许修改：`ahakeyconfig-mac/Sources/AhaKeyConfigApp.swift`、`Sources/Views/**`、`Sources/Models/**`、Studio 侧 `Sources/BLE/**`的退场/诊断改造、Shared 中新建/接入 Studio Runtime client/facade、对应 `Tests/**`，以及本卡/看板/实施计划指定段落。
禁止：不复制设备状态事实源；不保留隐藏生产直连 fallback；不改 Runtime wire v1.1；不改 `Sources/Agent/**` 业务实现、不修固件、不提前做 5.9 正式安装/升级链。
完成定义：snapshot 首屏；event cursor/断档刷新；operation 进度/取消/错误；诊断按需观察；Studio 退出不影响 Runtime；生产目标无 BLE/USB owner。  
测试：UI reducer、重连/重放/断档、Runtime 离线、取消、进程退出；完整 Swift 测试/Release build。  
前置：5.2、5.6 accepted。用户于 2026-08-26 裁决将原“HIL accepted 后开 5.7”改为“先 5.7 真实 UI 接线，再恢复 HIL”，避免依赖环。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。

### [2026-08-25 23:46] Codex 预登记 F-HIL2-1

- HIL-RUNTIME-2：Studio 直连 0x99 三次超时进受限模式（`ble-comm.log` ~23:39）；同固件 Agent 路径 v3 正常。本卡删除 Studio 生产直连时一并关闭。不在 5.6 修。

### [2026-08-26 20:34] Codex：转交 Kimi，晋级 ready

- 用户明确要求：将原 Cursor 的 WBS-5.7 交给 Kimi。Cursor 仅继续独立固件仓 WBS-1 1.2R1，不介入客户端文件。
- 当前真机回归确认 Studio UI 仍走旧直接 BLE 保存；Runtime Store 零写入。该结果只证明旧功能无回归，不算 HIL-CONFIG C1 事务引擎通过。
- 实施切片：
  1. 先建 Studio Runtime client/facade：handshake、snapshot 首屏、event cursor/replay/gap→snapshot、离线/重连状态。
  2. 将现有编辑状态组装为已冻结 `AhaKeyConfigurationPackage`；资源先 `ingestResources`，再 `apply`；用 operation/event 驱动进度、取消、错误和最终 snapshot。
  3. 从生产 UI 保存/连接路径删除 Studio BLE/USB owner 与隐藏 fallback。`Sources/BLE/**` 只可保留非生产诊断/迁移边界，不得在正常 Studio 生命周期扫描、连接或写设备。
  4. 保证 Studio 退出后 Runtime 已受理 operation 继续；诊断日志/RSSI 只按需观察；窗口隐藏无持续 UI 发布/动画。
  5. 先以 reducer/adapter 单测、断线/重放/缺口/取消、完整 Swift tests 和 Release App build 提审。真实 XPC+BLE C1–C6 回到 HIL-CONFIG 执行，不在本卡伪造通过。
- 5.9 安装器/MachServices 正式登记仍不在本卡；本机集成可按既有 runbook 使用可回滚的临时登记。
- Kimi ACK 后将卡翻 `active`；单会话独占客户端白名单。

### [2026-08-26 20:50] Kimi：接单，翻 active

- 基线确认：HEAD `802c618`（含 WBS-5.6 accepted `19eb4dc` 及 HIL 证据文档）。
- 按 20:34 五个切片顺序施工：切片 1 先做 Studio Runtime client/facade（handshake/snapshot/event cursor/replay/离线重连）。
- 本机集成沿用可回滚临时登记（正式 plist 的 MachServices 即为现状）；不动 Agent 业务实现与 wire v1.1。

### [2026-08-26 21:35] Kimi：五个切片完成，整卡提审

- HEAD：`ccab003`（验收范围 `802c618...ccab003`）。
- 切片 1（`5b68f3b`）：`AhaKeyStudioRuntimeFacade`（Shared）——handshake→snapshot 首屏→event cursor 跟随→断档 snapshotRequired 重取快照→离线退避重连；6 项状态机测试。
- 切片 2（`bfc0848`）：`AhaKeyStudioPackageAssembler`（Shared 纯函数）+ Models 薄映射 + facade `apply`/`requestCancellation`。设计要点：资源 ingest 用 GIF 源字节（受理层要求 CGImageSource 可解析源图，RGB565 编码归 Agent 侧）；idle 槽与 defaultAnimation 镜像约束组装期 fail-fast；17 项新测试。
- 切片 3（`4eddb26`）：删除 Studio 生产 BLE/USB owner——`AhaKeyBLEManager`/`AhaKeyUSBHIDTransport` 删除，新建 `AhaKeyStudioRuntimeClient`（Models，@MainActor ObservableObject，包装 facade 投影）作为视图唯一事实源；保存路径改为 `applyDraft`→facade.apply→operation 终态轮询；取消走 requestCancellation；无隐藏直连 fallback；净删约 3000 行。10 项派生单测。
- 切片 4（`ccab003`）：Studio 退出仅断开 facade（不 cancel 已受理 operation）；诊断日志只含 Studio 侧事件、按需观察；窗口移除停 GIF 预览时钟。
- 无法派生字段处置（均删或静态化）：RSSI/型号/设备改名/LED 测试/协议 TX-RX 调试/flash 空间管理 UI。
- 自动门禁：452 tests / 2 skipped / 0 failures；Release `AhaKeyConfig` 与 `ahakeyconfig-agent` 均构建通过；git diff --check 干净。
- 真实 XPC+BLE C1–C6 归 HIL-CONFIG（draft，待用户重新批准真机窗口）。

### [2026-08-26 22:16] Codex 复验：整卡暂不 accepted，最小 R1

- `lastReviewedCommit: ccab003040adcf31834ae0fa5bcb99cabef24a70`；验收范围 `802c618...ccab003`。Studio BLE/USB owner 删除、draft 组装、资源 ingest/apply 接线及窗口 GIF timer 收尾方向成立，保留这些成果。
- Standards：生产目标已不再引用 `AhaKeyBLEManager`/`AhaKeyUSBHIDTransport`，`git diff --check` 通过；但事件循环没有空闲等待，违反后台零空转的性能边界。
- Spec 阻塞：
  1. **P1：生产 XPC server 没有实现首屏和事件路径。** `AhaKeyAgent.startXPCServer()` 的 handshake 只广告 configuration/snapshot/diagnostics，实际 handler 只处理 apply/ingest/cancel；`.snapshot` 和 `.events` 都返回 `unsupported-request`，且未广告 `.eventReplay`。因此真实 Studio 在握手后无法取得首屏，必然反复 offline/reconnect；FakeTransport 绿不能替代生产双端测试。
  2. **P1：event replay 只推进 cursor，不更新 snapshot。** `followEvents()` 未归并 `deviceChanged`、`operationChanged`、policy/lifecycle/permission 等 payload，也未在非空事件后重取权威 snapshot；`AhaKeyStudioRuntimeClient` 的设备状态和 `lastApplyOperation` 永远停在首屏，进度/终态/设备变化不会进入 UI。
  3. **P1：空事件响应形成无等待 XPC 紧循环。** production replay 是立即返回的 bounded replay，不是 long-poll；`.events([])` 当前直接 `continue`，会持续占用 CPU/XPC。必须加入可取消、可测试的空闲等待或实现服务端 long-poll；隐藏窗口不得产生 UI 发布，后台状态响应仍须不超过 2 秒。
  4. **P1：apply 在事务终态后才返回 operation ID。** Agent handler 先 `await applyConfigurationPackage` 跑完整个事务，再返回 `.operationAccepted`；Studio 在此之前拿不到 ID，因而无法展示运行中进度或对在途事务发取消。受理必须先 durable accept 并立即返回 ID，执行在 Agent 自有生命周期中异步继续，进度/终态进入 snapshot/event。
  5. **P2：已申报的测试门禁不可稳定复现。** Codex 于 22:15 独立运行 `swift test --filter AhaKeyStudioRuntimeFacadeTests`，13 项中 `testGapTriggersSnapshotResync` 失败（未观察到 `.resyncing` 瞬态）。测试需使用确定性同步/事件序列，不以调度时序碰运气。
- 只授权最小 `5.7-R1`，允许在原白名单外最小修改 `Sources/Agent/AhaKeyAgent.swift` 及对应 Agent/XPC 测试，用于生产 snapshot/event/operation adapter；不得改 BLE 协议、wire v1.1 或固件：
  1. 建立 Agent 侧单一 production projection：从 reducer 快照、持久事务 Store、policy/lifecycle/permissions 生成 `AhaKeyRuntimeSnapshot`，并维护有界单调 event replay；handshake capability 与实际 handler 完全一致。
  2. `apply` 在 durable acceptance 成功后立即返回 operation ID；Agent 自有 task 执行事务，Studio 退出/连接断开不取消它。运行、取消请求和终态必须可从 snapshot/event 观察；失败受理不得伪装 accepted。
  3. facade 对非空事件要么正确 reducer 归并所有 payload，要么重取权威 snapshot 后原子发布；禁止只推进 cursor。空 replay 使用可注入的 idle wait/long-poll，正常空闲不得持续发布 UI 或写日志，响应目标 ≤2 秒。
  4. 新增真实生产 endpoint 集成测试（不能只用 FakeTransport）：handshake→snapshot→empty replay、deviceChanged、operationChanged、gap→snapshot、durable accept 立即回 ID、执行中取消、Studio disconnect 后 operation 继续。加入请求速率断言证明空 replay 不忙轮询。
  5. 修复 resync 测试确定性；重跑定向套件、全量 Swift tests、Release App+Agent build、`git diff --check`。新 commit 后停手整卡重提；HIL-CONFIG 继续 draft。

### [2026-08-26 22:38] Codex：R1 增补 WBS-1.3 capability 交叉契约

- Cursor 固件 1.3 的 14-byte `0x99` 正确关闭 factory/session 位并返回 `userSlotLimit=N`，但客户端 `AhaKeyFirmwareCapabilities.parse` 当前无条件把短帧 `factorySlotBase` 回退为 N，导致 planner 从容量末端开始分配，所有 `0x95` 都会被固件越界拒绝。
- Kimi 在本卡 R1 内负责客户端侧最小修复，Cursor 不碰客户端：14-byte frame 在 factory flag **关闭**时 `factorySlotBase=0`；若 factory flag 打开但缺扩展字段则继续 fail-closed，不得猜测 factory 布局。
- 增加使用固件 `tp_write_caps14` 精确 payload 的交叉 fixture 测试：解析得到 protocol=3、mode=4、set=2、state=4、factory base=0、user limit=N；planner 首个/末个合法分配不超过 N。不得改变 wire v1.1 或扩大到 1.4 factory assets。

### [2026-08-26 22:55] Kimi：R1 返工完成，整卡重提

- 新 HEAD：`7e0b9e2`（验收范围建议 `ccab003...7e0b9e2`）。
- 22:16 四项 P1 + 一项 P2 逐条落地：
  1. Agent production projection：`projectedRuntimeSnapshot()`（BLE 设备态/operations 来自 WAL+终态缓存/policy/lifecycle，eventSequence 单调）；capabilities 与 handler 一一对应（新增 .eventReplay）；集成测试逐项验证。
  2. 事件流：有界 replay buffer（256，gap→snapshotRequired）；.events 空批 long-poll ≤2s（可注入），新事件立即唤醒，请求率 ≤0.5/s；BLE 四处回调发布 deviceChanged。
  3. apply durable accept 后立即返回 operationAccepted；执行在 Agent 自有 Task（不挂 XPC 连接生命周期）；运行中可取消（.requested/.alreadyFinished/.notFound 真实返回）；受理失败不伪装。
  4. facade：非空事件批重取权威快照并原子发布（snapshot+cursor 同次 update）；空批可注入 idle 间隔；resync 测试改确定性同步（publishHookForTesting），连跑 4 轮 0 失败。
  5. 真实 endpoint 集成测试 9 项（真实 SessionEndpoint+JSON 编解码+真实 Agent handler；MachService 双进程受沙盒限制，NSXPCConnection 层由 5.2 smoke 覆盖，文件头已注明替代层级）。
- 门禁：462 tests / 2 skipped / 0 failures；Release App+Agent 构建通过；diff 干净。
- 范围外事项：Cursor 22:51 提到 caps14 客户端解析「归 5.7-R1」，但 22:16 五条完成定义未含此项；请 Codex 裁决是否另开小卡。
- HIL-CONFIG 保持 draft；不生成安装候选（待 R1 验收 + 用户批准）。

### [2026-08-26 23:18] Codex：R1 主体成立，退回最后一个最小 R2

- `lastReviewedCommit: 7e0b9e20b42d83d63e8d6c25108c9bb9c8926a70`；固定代码范围 `41b23dc...7e0b9e2`。Codex 独立复跑 production endpoint 9/9、facade 14/14 均通过，`git diff --check` 干净。R1 的 production snapshot/events、有界 replay、durable accept 即返 ID、Agent 异步执行、取消及 facade 原子重取方向保留。
- 本卡不能 accepted，以下为一次性收口的 R2，不再拆散：
  1. **P1：正常周期状态没有发布到 Runtime。** `0x00` 回包在 reducer 更新 `coreSnapshot` 后未调用 `publishDeviceChangedIfNeeded()`；因此电量、工作模式、灯效、拨杆等真实变化不会触发 event，Studio 仍停在旧值。只在 reducer 结果确有变化时发布一次；相同状态零 UI 发布。同时删除每轮相同状态的 `emit("← status …")` 常规日志，只保留状态变化和错误，满足 1.5 秒后台轮询“零常规日志”。
  2. **P1：连续/并发 apply 的 durable accepted 可能永久滞留。** 当前每次 accept 都新建 Task，后一个遇到 `configurationRecoveryInFlight` 直接 busy 退出，前一个完成后不会排空 WAL，只能等下次重连；多个 XPC session 又可并发读写非隔离的 `cachedRuntimeStore`/单飞标志。改为 Agent 自有、单一隔离的串行执行协调器/worker：所有 durable accepted 入队，worker 持续排空；不得覆盖在途 Task，不得让两个 BLE runner 并行。补双客户端同时提交、首个阻塞/第二个受理/随后两者均终态的确定性测试。
  3. **P1：Runtime schema 广告自相矛盾。** handshake 写死 `[3]`，当前 `AhaKeyConfigurationPackage.currentSchemaVersion` 与 snapshot 默认却是 `[1]`。以当前包 schema 单一来源生成 handshake/snapshot，并在 endpoint 测试断言二者一致且包含实际提交包版本；不得继续写裸常量。
  4. **P1：22:38 已生效并由 Kimi ACK 的 caps14 交叉契约未实现。** 使用固件精确 fixture `03 04 02 04 33 00 c8 00 20 01 00 00 00 00`；factory flag 关闭时 `factorySlotBase=0`，`userSlotLimit=288`；factory flag 打开但仅 14 bytes 时 parse 必须 fail-closed。补 planner 首个/末个合法范围与 288 越界拒绝测试。
  5. **P2：long-poll 有 lost-wakeup 窗口。** “检查空缓冲”与“登记 waiter”分属两次 main 调度，夹缝事件会令请求白等完整 2 秒。把 waiter 注册与二次 replay 检查收敛到同一隔离临界区，补可控交错测试；新事件响应仍以不超过 2 秒为门禁。
- lifecycle/permissions 真实来源不在本轮扩大：沿用此前“权限等非设备遥测可暂时独立”的裁决；真实 NSXPC connection invalidation 组合证据进入 HIL-CONFIG/签名 smoke，不以进程内 wrapper 冒充。
- 允许最小修改：本卡既有白名单、`Sources/Agent/AhaKeyAgent.swift`，必要时可在 Shared 新建一个小型隔离执行/投影协调器及对应测试；禁止改 wire v1.1、BLE opcode、固件、安装器或进入 HIL。完成后跑定向测试、全量 Swift、App+Agent Release、diff check，新 commit 停手整卡重提。

### [2026-08-26 23:19] Codex：哈希更正

- 上条 `lastReviewedCommit` 的完整值录入有误；正确值为 `7e0b9e264b52e721320ab125046fd4bf59b79994`。范围与 R2 裁决不变。

### [2026-08-26 23:35] Kimi：R2 收口完成，整卡重提

- 新 HEAD：`4171111`（验收范围 `7e0b9e2...4171111`）。
- 23:18 五条逐条落地：
  1. 状态轮询：0x00 回包 reducer 更新后调 publishDeviceChangedIfNeeded()（投影去重，确有变化才发布一次）；相同状态轮询零常规日志（常规 emit 已删，保留状态变化/错误）。
  2. 串行执行协调器：新 Shared actor `AhaKeyConfigurationExecutionCoordinator`（单 worker、kick 幂等、趟内排空 WAL、趟间接续）；删除 configurationExecutionTask/configurationRecoveryInFlight；cachedRuntimeStore 收敛进 actor 隔离缓存。双客户端并发测试：首个阻塞、第二个受理、maxConcurrent==1、放行后双双 completed。
  3. schema 同源：handshake=[AhaKeyConfigurationPackage.currentSchemaVersion]，与 snapshot 默认同源；endpoint 测试断言 handshake==snapshot==实交包 schema。
  4. caps14 交叉契约：精确 fixture 03 04 02 04 33 00 c8 00 20 01 00 00 00 00 → factorySlotBase=0/userSlotLimit=288；factoryOn+14B fail-closed（parse nil）；planner 首槽=帧0/末槽=240（270≤288）、300>288 越界拒绝。
  5. long-poll lost-wakeup：waiter 登记+二次复查收敛同一 MainActor 临界区，夹缝事件立即返回；≤2s 门禁保留。
- 门禁：471 tests / 2 skipped / 0 failures（连跑 2 轮）；Release App+Agent 通过；diff 干净。
- 风险声明：factory flag 位 1<<2 由两份 fixture 反推（0x3F/0x33），固件位布局文档化后需对齐；解析 fail-closed，最坏拒绝协商。
- 未安装、未进 HIL；HIL-CONFIG 保持 draft。
