# 任务卡 V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR：两击提交必须走同一可观测编排

计划/WBS：v0.3 客户端 OLED 兼容 / C5 HIL 返工
状态：`ready / C5GR6`
执行 owner：DSH（人工打开会话执行；`OPS-DSH-REARM` 尚未验收）
验收：Codex
产品基线：`f2b462236ed357d6889228b01c5982c182f5eb2e`
前置：15K-F accepted @ `f2b4622`；C5ABR4 的正式 Studio 第二次覆盖仍零 WAL/零 `0x97`

## 现场事实

R4 使用 clean signed `f2b4622`，Picker 明确 B→A，避免默认值不触发 setter。按钮在第一次前已是“覆盖写入此页”；第一次点击返回确认 toast，第二次同按钮点击后 toast 不变、tx 仍 10、Agent 无 page apply/`0x97`。随后 AXPress 与已知 button index 复核也无变化。A/B digest 与 activeSet=1 未变，已回滚 official 0.2.1 (362)。证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/27-c5abr4-gitee-rhino-ab-switch.md`。

C5F host 测试证明真实 draft→snapshot→assembler 可产生 active-only plan，但测试手工依次调用 edit-intent ledger、confirmation ledger、Store/Facade，再手工分发 result；它没有调用 SwiftUI Button 的 `writeCurrentPage` 编排。R4 又没有 View 侧 submit-attempt trace，因此当前不能区分：

1. 第二次 AXPress 没有进入 Button action；
2. action 进入，但重算 identity/snapshot 后再次 requires/no-op；
3. action 进入 Facade 前被 View 本地状态挡住。

不得再根据 ledger helper 绿测直接猜修某个 Bool。

## 深模块设计

建立 `@MainActor AhaKeyStudioPageCommitCoordinator`（名称可等价）。它的 interface 接受一次 typed `SubmissionInput` 与一个 `CommitPort`；生产 adapter 调 `AhaKeyStudioRuntimeClient.commitFrozenPage`，测试 adapter 记录每次 snapshot/result。coordinator 内部拥有：

- confirmation ledger 与 edit-intent ledger；
- exact current context、single in-flight attempt、pending prompt 与 button/chrome projection；
- begin/result/failure 的一次性 fan-out；
- 非敏感 typed trace event。

View 不再分别调用两个 ledger，也不在一次点击里多次重新计算 `overwriteConfirmationIdentity` / snapshot。按钮 action 只调用 coordinator 的一个 submit interface；测试也只从该接口进入。

## 完成定义

1. 每次点击只冻结一次 `deviceID + session/transport generation + page/profile + selected set + fields/baselines + explicit intent`。同一 frozen input 同时用于 identity、overwrite decision、attempt token、Facade snapshot 与 result consumption；禁止一次点击中从多个 computed property 得到不同快照。
2. 第一次未确认提交返回 `.requiresOverwriteConfirmation` 后：coordinator pending 保持、`isSubmitting=false`、chrome/button 为“覆盖写入此页”、trace 有 `began(confirmed=false)` 与 `returned(requires)`。历史 operation/snapshot 更新不得消费它。
3. 第二次 exact 点击必须产生新的单次 attempt，snapshot `overwriteConfirmed=true`，调用 CommitPort 恰一次。若 port 返回 accepted，消费 pending/对应 edit intent并输出 accepted outcome；若返回 no-op/requires/error，必须在 UI 文案与 typed trace 中可区分，不能静默保留上一条 toast。
4. View 的 current chrome、disabled、toast/status 全部由 coordinator outcome 投影；`defer`/错误路径必须解除 submitting。SwiftUI Button 不得因 label 宽度、旧 operation、status 更新或双 ledger 分叉而丢第二击。
5. typed trace 仅含 pageID、attempt sequence、confirmed Bool、result/error category、是否调用 port；不得含资源字节、文件路径、用户文本或 secret。生产写入 Studio 现有 comm log/内存诊断，不能新增环境变量后门、退出路径或测试专用生产行为。
6. 保留 C5F 语义：无 Picker intent 的 authority 差异 no-op；显式 A 产生 only `screenActiveSet:0`；statusLine/B done 若等于 authority strict-no-op；资源为零。保留 C5ER1 stale/replay 因果。

## 必测反馈循环

- 用 recording CommitPort 从 coordinator interface 重放 R4：显式 B→A；第一次 port 返回 requires；插入历史 `844F52E4…` completed；第二次 port 返回 accepted。断言 click/action count=2、port count=2、第二 snapshot confirmed=true、最终 pending=nil、submitting=false、trace 顺序精确。
- 第二次分别返回 `.noOp`、再次 `.requires`、throw：UI outcome/trace 必须变化并准确点名；不得保持第一次 toast 冒充没触发。
- 第二击前 field/set/device/generation/profile 变化：旧 pending 作废，新的第一次必须 confirmed=false；A→B→A 不复活旧 attempt。
- 重放/乱序 result、历史 terminal、accepted 后的新 edit intent 不得被旧 result 清除。
- 真实 mapping + coordinator + Facade recording adapter：第二次 apply=1，fieldMask/values/actions 只有 activeSet，ingest=0/resource=0。
- 增加静态/接口门：View 不再直接持有或 fan-out 两个 ledger；Button action 只调用 coordinator。不得仅新增一个包裹函数而保留旧编排。
- 若完整 coordinator 测试在行为等价提取后即通过、无法重现零 port call，必须停手并报告“产品路径 host 绿，剩余为 AX/UI 激活问题”，不得虚构业务修复；此时另给可自动运行的 macOS UI smoke seam 与证据计划。

## 白名单与门禁

- 新增一个 Studio page-commit coordinator 文件，优先放 `Sources/Models/`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- 现有 `AhaKeyStudioPageModel.swift` / `AhaKeyStudioRuntimeStore.swift` 仅为收窄 ledger interface 或 adapter 所必需的改动
- coordinator/page-interaction/draft-mapping/confirmation 精确测试
- 本任务卡、当轮 evidence、`docs/collab/board.md` 的 DSH append-only 记录
- 定向、全量 Swift、App+Agent Release、identity、增量与 `5d1fe1d` 全范围 diff-check 全绿；提交白名单 range，停手提审。

## 非目标

不改 C2 assembler 决策、C3 schema/WAL/CAS/executor、Agent/BLE、ReleaseIdentity、安装器、固件或 HIL driver。不签名、不安装、不启动 HIL、不写设备、不刷机、不擦 EEPROM、不断电、不 push。C5G accepted 后仍须新的 A/B switch USER-GATE。

## 执行记录（append-only）

### [2026-09-10 19:45] Codex：R4 停点 accepted；开放 DSH C5G coordinator/trace 返工

- R4 第二次零 WAL/零 `0x97`，停止与 official 362 回滚成立；不宣称 A/B 切换通过。R4 授权已消费。
- C5F mapping/intent 绿测不能覆盖真实 View action；现有证据无法判定 action 未触发还是本地再次返回。仅开放 C5G，用单一 coordinator + recording port + typed trace 建立可执行反馈循环。
- official 0.2.1 (362) 已复核：唯一 owner pid 28484/runs=1，HIL rc=113；A/B digest 与 activeSet=1 未变。
- 15L=`blocked / awaiting C5G`。DSH 不得签名/安装/HIL/设备写；完成停手提审。
- 需要回复：是（@DSH ACK 后仅执行 C5G）

### [2026-09-10 23:16] DSH：C5G 完成，停手提审

- 新增 `Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`：`AhaKeyStudioPageSubmissionInput` 一次点击单次冻结（identity/overwrite decision/attempt/Facade snapshot/result consumption 全部同源）+ `CommitPort`（生产 adapter = Store `commitFrozenPage`）+ 单次 in-flight 守卫 + 两个 ledger 内部持有 + pending/chrome 投影 + typed trace（pageID/序号/confirmed/portCalled/类别/phase，无敏感内容；环形 64 条并写 Studio 现有 comm log）。
- View：删除两个 `@State` ledger 与 `isSubmittingCurrentPage`（改由 coordinator 投影）；按钮 action 只经 `coordinator.submit(input, port:)`；`makeSubmissionInput()` 每次点击只冻结一次；**await 后不再重算 identity**。C5ER1 stale/replay 因果由 `observeIdentity` 推进 revision + 作废 in-flight 保持，未回退。
- 现场发现（新增）：`projectAssembly(.requiresOverwriteConfirmation)` 自身即投影 `commitKind = .overwritePage`，故 R3/R4 记录的「按钮保持覆盖写入此页」**不能**作为 pending 已设置的证据；trace 用于补这个盲区。
- 三种停点现在可由下次 HIL 的 trace 区分（无 `began` = 未进 action；`began confirmed=false` = 再次 requires；`began confirmed=true` 但 result≠accepted = 停点在 Facade/语义层）。
- 门禁：定向 **199/199**；coordinator 专项 **11/11**；全量 Swift 第 2 次 **1162 / 2 skipped / 0**（第 1 次 2 个与本轮零交集的既有 flake：`testRootDeleteRecreateDoesNotLockStaleInode` TIMEOUT、`testConcurrentEncodeAndExchangeStress` busy，隔离复跑均通过）；App+Agent Release rc=0；`check-release-identity.sh` ok；`git diff --check` 通过。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push。提交不含 `board.md`/`queue.md` 的既有他人 diff（沿用 `f2b4622`/`adfe2a6` 惯例）。
- 如实报告（本卡第 50 行）：host 全绿**不等于** R4 的 HIL 症状已修复；真实停点仍须下一次 HIL 判定，本轮无法在 host 重现"零 port call"。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/28-c5g-page-commit-coordinator.md`
- 需要回复：是（@Codex 复核 `f2b4622..HEAD` 白名单：单次冻结/单次 in-flight/typed trace、View 无 ledger fan-out、C5ER1 未回退、定向与全量门禁）

### [2026-09-10 23:29] Codex：C5G coordinator 主体成立，live identity / stale outcome 因果未闭；退 C5GR1

- C5G 产品提交固定为 `d310f41^...d310f41`（6 个白名单文件），独立定向 199/199、commit-local diff-check 通过。`f2b4622...d310f41` 中 `b5ace4f` / `eb4d6f7` 是 Codex/交接协作文档，不归因 DSH。
- **P1 pre-port stale input**：`submit` 用冻结 input 调 `confirmationLedger.observeCurrentIdentity(identity)` 并覆盖 coordinator 已观测的 live `currentIdentity`。若 Button 冻结后、MainActor Task 真运行前 live identity 已变化，旧 input 会被重新宣布为 current 并调用 port。
- **P1 post-await stale outcome**：await 中 identity mutation 虽会让两个 ledger 拒绝消费，coordinator 仍把旧 port result 转成正常 accepted/requires/no-op，记录 `.returned`、覆盖 `lastOutcome` 并返回给 View；View 再用 live `currentPageID/currentPageChrome` 显示旧页面结果。旧 accepted 可被显示成当前页“已入队”。现有 stale test 反而断言返回旧 `.requires`，固化错误。
- **仅开放 C5GR1**：Button action 必须同步进入 coordinator（例如非 async `start(input, port:)`），在返回事件循环前设置 single in-flight、sequence、`isSubmitting=true` 与 `began` trace，再由 coordinator 内部启动 async port。这样 trace 无 began 才能严格表示 action 未触发；不得把 coordinator.submit 放到 View 新建的 Task 后才开始。
- coordinator 不得从 input 覆盖 live identity。start 前要求 `currentIdentity == input.confirmationIdentity`；不匹配返回 typed superseded、port=0。View onAppear/identity change 必须先喂 current identity，冻结后至 start 的 scheduling gap 也要被拒绝。
- 保存 coordinator-owned monotonic observation revision；attempt 绑定该 revision。await 后若 revision/current identity/in-flight 任一不匹配，ledger 可做 stale cleanup，但对外只能记录 typed superseded trace：不得覆盖当前 `lastOutcome`/toast，不得把旧 accepted/requires/no-op/error 投影到 live page。View outcome 必须携带冻结 pageID，禁止 accepted 后读取 live `currentPageID/currentPageChrome`。
- **P2 trace exactness**：当前 began 同时 `portCalled=true` + `category=portNotCalled`。改为 associated-case trace 或严格状态矩阵；began 应表示 action 已进入但 port 尚未返回，port-invoked/returned/superseded 不得产生矛盾组合。静态/运行测试枚举拒绝非法组合。
- 必测：freeze A → observe B → start stale A，零 port；start A → port await → observe B→A → old accepted/requires/error，pending/edit intent/current outcome/toast 不变且 trace=superseded；页面 A await 时切 B，旧 accepted 不得用 B 标题。同步 start 调用后立即可见 began/isSubmitting，第二次同 tick 为 ignored、port 仍 1。
- C5G 已通过项冻结：单次 frozen input、coordinator 内双 ledger、recording/production port、非敏感 64-ring trace、View 无 direct ledger/Store bypass、真实 mapping→Facade active-only。完成提交 `db4eccd...<new>` 产品增量并同时给 `d310f41...<new>` 功能增量；复跑定向/全量/双 Release/identity/full diff-check，停手提审。
- Codex 已单独清理自身 `OPS-DSH-REARM.md` whitespace，提交 `db4eccd`；`git diff --check f2b4622..db4eccd` 与 `5d1fe1d..db4eccd` 现均通过，不需 DSH 修改该文件。
- 15L 保持 `blocked / awaiting C5GR1`；不得签名/安装/HIL/设备写/刷机/EEPROM/断电/push。
- 需要回复：是（@DSH ACK 后仅执行 C5GR1）

### [2026-09-10 23:53] DSH：C5GR1 完成，停手提审

- **Standards P1 闭环**：新增 `AhaKeyStudioPageCommitOutcome.isProjectable`；`.superseded` / `.ignoredInFlight` 一律不写 `lastOutcome`，View 对二者不更新 toast/status。旧 accepted/requires/error 不再可能被展示为当前页结果。
- **Standards P2 闭环**：`.began` 改为 `portCalled=false` + `category=.pending`；删除矛盾的 `portNotCalled`，新增 `.pending` / `.superseded` / `.inFlightRejected` 与 phase `.rejected`。新增**合法组合矩阵**双向测试（正向枚举已知路径产生的事件、反向拒绝矩阵外组合）。
- **Spec P1 闭环（live identity 所有权）**：`start` 不再调用 `observeCurrentIdentity`、不再写 `currentIdentity`；进 port 前校验 `currentIdentity == input.confirmationIdentity`，不匹配即 `.superseded` 且 port=0，live observation 不被 frozen input 覆盖。
- **Spec P1 闭环（post-await stale）**：新增 coordinator-owned `observationRevision`（仅 `observeIdentity` 递增）；attempt 绑定提交时 revision；await 后 revision 或 identity 任一不匹配即 `.superseded`——不 `applyCommitResult`、不写 `lastOutcome`、不更新 toast。A→B→A 往返同样失效。
- **任务卡原文闭环（摘要未含的两条）**：①拆为同步 `start(_:port:)` + 内部 async `finish(...)`；`start` 在返回事件循环前完成 clickCount / in-flight / sequence / `isSubmitting=true` / `began` trace，View 不再先建 Task，故「trace 无 `began`」严格等价于「action 未触发」；②新增 `AhaKeyStudioPageCommitProjection { pageID, outcome }`，View accepted 分支只用冻结 `projection.pageID`，静态门断言之。
- **测试**：coordinator 专项 11 → **20**（新增同步 start 可见性/同 tick 拒绝、前置不一致、stale requires/accepted/error、B→A 往返、冻结 pageID、trace 矩阵正反两向、有效结果仍投影）。
- **门禁**：定向 **208/208**；coordinator **20/20**；全量 Swift **1171 / 2 skipped / 0**（首次即通过，无 flake）；App+Agent Release rc=0；identity ok；本轮范围 `git diff --check` 通过。
- 已冻结项未破坏：单次 frozen input（且与展示 identity 同源）、coordinator 内双 ledger、View 无 ledger/Store bypass、recording+production port、非敏感 64-ring trace；真实 mapping→Facade active-only 用例已改为经 coordinator 走通。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
- 如实报告：`superseded` 语义与同步 start 时序是 host 可判定的；R4 的真实停点仍须下一次 HIL 的 trace 判定。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/29-c5gr1-supersede-and-trace-consistency.md`
- 需要回复：是（@Codex 复核：同步 start 时序与 trace 矩阵、live identity 不被覆盖、post-await superseded 不投影、冻结 pageID 投影、定向 208/208 与全量 1171/0）

### [2026-09-11 09:02] Codex：C5GR1 生产 pre-port gate 仍被 View 绕过，退 C5GR2

- 固定 DSH 提交 `db4eccd...91c7aa8`，功能范围 `d310f41...91c7aa8`。独立定向复跑 208/208；`db4eccd` / `d310f41` / `f2b4622` / `5d1fe1d` 四范围 diff-check 均通过。
- **P1 production pre-port bypass**：View 冻结 input 后立即 `observeIdentity(input.confirmationIdentity)`，再调用 start。生产路径因此总会把 frozen input 重声明为 live，`currentIdentity == input.identity` guard 退化成恒真；onAppear 又未初始化 live identity。直接 coordinator 单测的 live=A/frozen=B 反例没有覆盖 View 旁路。
- **P1 stale status**：View 在 start 前先把 status 写成“正在提交当前页到 Runtime…”，而 pre-port superseded、in-flight rejected 与 post-await superseded 分支刻意不投影。结果 `isSubmitting=false` 后 UI 仍永久显示“正在提交”，违反 stale 不改当前 toast/status。
- **仅开放 C5GR2**：live identity 只能由 onAppear + `.onChange(overwriteConfirmationIdentity)` 发布；Button click path 禁止调用 `observeIdentity`。onAppear 在 refresh/intent context 就绪后显式 observe 当前 identity。start 对 frozen/live 不一致零 port、typed superseded；静态门须拒绝 `writeCurrentPage` 内任何 observe 调用。
- 不得在 start 前写“正在提交”到共享 status；提交中只用 coordinator `isSubmitting`/按钮投影，或由 coordinator 保存并在 superseded/rejected 后恢复 exact pre-attempt status。valid returned/failed 才更新结果文案。加 pre-port reject 与 post-await supersede 两臂，断言 status 原值逐字不变且 `isSubmitting=false`。
- **P2 trace 类型**：将 trace 改为 associated-case state（began / portInvoked / returned(result) / failed / superseded(before|afterPort) / rejected），再派生 phase/portCalled/category；禁止三个自由字段构造非法组合。若保留 validator，必须位于产品并穷举 phase×Bool×category 的完整笛卡尔补集；当前 7 个手写字符串不算反向穷举。
- 新增 `portInvoked` event：began 只证明 Button 同步进入；invoked 证明内部 Task 已实际调用 port。HIL 中 began 无 invoked = 内部调度/生命周期停点，invoked 无 returned = port hang，不能混称。
- **P2 生命周期**：coordinator 自己持有 in-flight Task 与结果 projection event/callback；领域 start interface 不得把 `Task` 句柄暴露给 View、再由 View 创建第二个 Task await。定义页面关闭/对象释放时的 cancellation/continuation policy，确保 port 悬挂不会永久保留 submitting/in-flight。
- counters/revision 使用 checked fail-closed increment 或 typed non-wrapping generation；不得继续用 `&+=` 让 observation revision 理论回绕。收窄无 consumer getter。
- C5GR1 已通过项冻结：同步 began、coordinator 双 ledger、single frozen input、post-await stale 不消费、frozen pageID、recording/production port、非敏感 bounded trace、active-only mapping。完成提交 `91c7aa8...<new>`，停手提审；不得进 HIL。
- 15L 保持 `blocked / awaiting C5GR2`。
- 需要回复：是（@DSH ACK 后仅执行 C5GR2）

### [2026-09-11 09:30] DSH：C5GR2 完成，停手提审

- **Spec P1（点击路径绕过 live gate）闭环**：移除 `writeCurrentPage` 内的 `observeIdentity` 调用；live identity **只**由 `onAppear`（在 refresh / intent context 就绪后）与 `.onChange(overwriteConfirmationIdentity)` 推进。静态门 `testClickPathDoesNotPublishLiveIdentityNorWriteStatusNorCreateTask` 直接断言 `writeCurrentPage` 函数体内不得出现 `observeIdentity`。
- **Spec P1（假提交文案）闭环**：点击路径不再写任何 status；提交中只由 coordinator `isSubmitting` 与按钮 label 投影；valid returned/failed 才更新结果文案，superseded/rejected 不触碰 status。静态门同时断言函数体内不出现「正在提交」。
- **Standards P2（trace 结构化）闭环**：改为 associated-case `AhaKeyStudioPageCommitTraceEvent`（began / portInvoked / returned(result) / failed / superseded(portInvoked) / rejected / cancelled），`phase`/`portInvoked`/`category`/`confirmed` 全部派生，矛盾组合在产品类型层不可构造。测试改为对**全部 case 的完全枚举**（14 行覆盖每个 case 的确认/未确认与 port 前后分支），删除原 7 个手写字符串的反向矩阵。
- **Standards P2（生命周期外泄）闭环**：`start` 返回值改为 `{ started, rejected(projection) }`，**不含 `Task`**；coordinator 自持 `inFlightTask`，终结结果经 `lastProjection` + 单调 `projectionRevision` 发布，View 用 `onChange` 消费——既不建 Task 也不需要闭包（同时避免与 `@StateObject` 形成引用环）。新增 `cancelInFlight()` 取消策略，View 在 `onDisappear` 调用；`isStale` 纳入 attempt 身份，迟到结果只产生 `.superseded`。
- **P3（回绕）闭环**：全部 `&+=` 改为 `Self.checkedIncrement`（checked fail-closed，溢出即 trap）。移除了无 consumer 的 `traceSnapshot()` getter。
- **卡片 L125（portInvoked）闭环**：新增 `.portInvoked` phase 与事件——`began` 只证明 Button 同步进入，`portInvoked` 证明内部 Task 已实际调用 port。两个新测试分别固化「有 began 无 portInvoked = 内部调度停点」与「有 portInvoked 无 returned = port 挂起」。
- **测试**：coordinator 专项 20 → **26**。
- **门禁**：定向 **214/214**；coordinator **26/26**；全量 Swift **1177 / 2 skipped / 0**（首次即通过）；App+Agent Release rc=0；identity ok；本轮范围 `git diff --check` 通过。
- 已冻结项未破坏：同步 began、双 ledger 内聚、single frozen input（且与展示 identity 同源）、post-await stale 不消费、冻结 pageID 投影、recording+production port、非敏感 bounded trace（64-ring）、active-only mapping。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
- 如实报告：结构化 trace、同步生命周期、取消策略与点击路径收口是 host 可判定的；R4 的真实停点仍须下一次 HIL 的 trace 判定。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/30-c5gr2-structured-trace-and-lifecycle.md`
- 需要回复：是（@Codex 复核：点击路径无 observe 且无 status 写、trace 关联类型与完全枚举、start 不含 Task 且取消策略生效、checked increment、定向 214/214 与全量 1177/0）

### [2026-09-11 11:31] Codex：C5GR2 pre-port cancel fence 与 trace 类型仍未闭，退 C5GR3

- 固定范围 `91c7aa8...26e955b`。点击路径无 observe/status/Task、onAppear live identity、同步 began、post-await superseded、冻结 pageID、checked increment 主体成立。独立定向复跑 214/214，五范围 diff-check 通过。
- **P1 start→Task scheduling window**：start 同步校验后创建内部 Task；Task 真运行时 `finish` 先递增 portCall、标 portInvoked 并调用 port，直到 port 返回才核 stale。start 后、Task 调度前 identity/revision 变化仍会进入真实 Facade，违反 pre-port stale 零写。
- **P1 cancellation fence**：`cancelInFlight()` 仅 cancel Task 并立即清 attempt/slot，允许新 start；Swift cancellation 是协作式，旧 Task 若尚未调度仍会调用 port，若已进入 port且 port 忽略取消则旧副作用仍在运行。新 attempt 可与旧 port 并行，破坏 single-in-flight；旧 Task 还会写共享 `inFlightPortInvoked`，污染新 attempt 的 cancel trace。
- **仅开放 C5GR3**：内部 Task 在任何 `portCallCount`、portInvoked trace 或 port 调用前，必须在 MainActor 同一 transition 核 `Task.isCancelled + exact in-flight attempt + observationRevision + currentIdentity`。失败只记 superseded/cancelled(portInvoked=false)，port count=0。
- 把 in-flight 状态收成 per-attempt typed record（attempt/sequence/page/confirmed/revision/phase/cancelRequested），禁止用共享 page/confirmed/portInvoked booleans让旧 Task改写新 attempt。
- cancel-before-port：同步取消后可安全释放 slot，Task 的 pre-port fence 保证永不调用 port。cancel-after-portInvoked：记录 cancel requested、解除 UI submitting可选，但**执行占用必须保留到 port 真返回/throw**；期间新 start 必须 rejected。port 返回后只做 cancelled/superseded cleanup，不消费 ledger、不投影旧 result，随后才释放 slot。不得以 `Task.cancel()` 本身作为 port 已终止证明。
- coordinator-owned Task 不得与 coordinator 构成 hung retain cycle。Task 执行 port await 时不能强持有 self；把 port invocation 收成不捕获 coordinator 的静态/独立 async 段，返回后 weak self 收口。定义 deinit/close 行为并测试：释放 coordinator 会 cancel Task；忽略取消的 gated port 不应阻止 coordinator deinit。
- **P2 trace 封闭**：`.returned` 不得接受完整 category enum；改为 return-only associated result（accepted/noOp/requires/missing/unsupported）或直接关联 typed commit result。`.returned(pending/failed/superseded/rejected/cancelled)` 必须在编译类型上不可构造，而非靠 14 行样本。测试覆盖每个 return result 与所有事件 case。
- 必测：start A 后 identity B 再让内部 Task 调度，零 port、superseded(false)；began 后 cancel-before-schedule，零 port；portInvoked 后 cancel，第二 start rejected 直到旧 gated port 返回；旧返回不清/改新 pending/intent/outcome。weak coordinator 释放 + hung/ignore-cancel port 无 retain cycle。C5GR2 portInvoked HIL 判读与 valid 两击不得回退。
- 完成提交 `26e955b...<new>`，复跑定向/全量/双 Release/identity/full diff-check，停手提审。15L 继续关闭。
- 需要回复：是（@DSH ACK 后仅执行 C5GR3）

### [2026-09-11 11:58] DSH：C5GR3 完成，停手提审

- **Spec P1（scheduling window）闭环**：新增 `admitPortEntry(_:)`——内部 Task 在**任何** `portCallCount` / `portInvoked` trace / port 调用之前，于 MainActor 同一 transition 核 `Task.isCancelled` + exact in-flight execution + `observationRevision` + `currentIdentity`；失败只记 superseded/cancelled(`portInvoked=false`)、port 计数为 0。
- **Standards P1（cancel fence）闭环**：取消后旧 Task 即使被调度，`admitPortEntry` 先判 `inFlight === execution`，已被释放即直接返回——零调用、零 trace；另有 `cancelRequested` 双重保险。
- **Standards P1（slot 过早释放）闭环**：port 已进入时**保留** per-attempt 执行占用，直到旧 port 真正返回/抛错；期间新 `start` 一律 `.rejected(.ignoredInFlight)`。`Task.cancel()` 不再被当作副作用已停止的证明。**语义变更**：取消结算结果由 `.superseded` 改为 `.cancelled`（`.superseded` 保留给 live identity 变化路径）；UI `isSubmitting` 仍在取消时立即置 false（卡片允许「解除 UI submitting 可选」），但执行占用保留。
- **卡片原文（per-attempt typed record）闭环**：新增 `AhaKeyStudioPageCommitExecution`，把 attempt/identity/revisionAtSubmit/sequence/pageID/confirmed/snapshot/retryResidual/port 与 `portInvoked`/`cancelRequested` 全部收成 per-attempt 状态；旧 Task 不可能改写新 attempt。
- **Standards P2（保留环）闭环**：port 调用段不捕获 coordinator——仅在 `self?.admitPortEntry(...)`（同步）与 `self?.settle(...)`（await 之后）短暂强持有，await 期间只持有 execution 与 port。新增 `deinit { inFlightTask?.cancel() }`。新增 `testCoordinatorDeallocatesDespiteHungIgnoringCancelPort` 证明忽略取消的挂起 port 不阻止释放。
- **Standards P2（returned 封闭）闭环**：新增 `AhaKeyStudioPageCommitReturnedResult`（仅 6 个返回结果）；`.returned` 只接受该类型，`returned(pending/failed/superseded/rejected/cancelled)` **编译期不可构造**；测试断言 6 个返回结果全部枚举。
- **必测四项全部落地**：`testIdentityChangeBeforeInternalTaskSchedulingCallsNoPort`（零 port、superseded(false)）、`testCancelBeforePortInvokedCallsNoPort`（began 后取消、零调用）、`testCancelAfterPortInvokedKeepsSlotUntilPortReturns`（第二 start rejected 直到旧 gated port 返回）、`testCancelledLateResultDoesNotMutatePendingOrIntent`（旧返回不改 pending/intent/outcome）、`testCoordinatorDeallocatesDespiteHungIgnoringCancelPort`（无 retain cycle）。
- **测试**：coordinator 专项 26 → **30**。
- **门禁**：定向 **218/218**；coordinator **30/30**；全量 Swift 第 3 次 **1181 / 2 skipped / 0**；App+Agent Release rc=0；identity ok；本轮范围 `git diff --check` 通过。**如实记录**：全量前两次各有 flake（`AhaKeyAgentRuntimeEndpointTests.testConcurrentAppliesFromTwoClientsSerializeAndDrain` 第 1 次；`AhaKeyRuntimePersistentStoreTests.testRootDeleteRecreateDoesNotLockStaleInode` 第 1、2 次 TIMEOUT，即 Codex 在 C4R13/C4R14 已点名的既有问题），两者隔离复跑均通过、与本轮零文件交集。
- View 本轮**零改动**：取消策略与 pre-port fence 全部收在 coordinator 内部。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
- 如实报告：取消语义、执行占用保留、retain-cycle 释放与 returned 类型封闭均为 host 可判定；R4 的真实停点仍须下一次 HIL 的 trace 判定。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/31-c5gr3-cancel-fence-and-execution-slot.md`
- 需要回复：是（@Codex 复核：双次 pre-port fence、cancel-before-port 零调用、cancel-after-port 保留 slot 且新 start rejected、hung port 无保留环、returned 类型封闭、定向 218/218 与全量 1181/0；并请确认 §2 的取消语义变更）

### [2026-09-11 12:12] Codex：取消投影语义可接受；执行槽随 coordinator 销毁仍可丢失，退 C5GR4

- 固定范围 `26e955b...85966b4`。双次 pre-port fence、cancel-before-port 零调用、同 coordinator cancel-after-port 保留 slot、per-attempt record、无 Task→coordinator retain cycle 主体成立。独立定向复跑 218/218，六范围 diff-check 通过。
- **取消语义裁决**：对外 projection/outcome 用 `.cancelled` 表示用户取消是正确的；旧 port 返回被丢弃可记 terminal discard。不得声称 superseded 只代表 identity change，需在 typed trace 中区分 cancel-request / cancel-settled 或明确 discard cause。
- **P1 cross-coordinator execution fence**：当前 slot 只活在 View-lifetime coordinator。port 已进入并忽略取消时，测试要求 coordinator 可释放；释放后 slot 同时消失，新 View/coordinator 可在旧 port 尚未返回时启动第二次写。`deinit Task.cancel()` 不能证明副作用停止，破坏 cancel-after-port serialization。
- **仅开放 C5GR4**：把 port 执行占用上移到 app-lifetime/shared owner（优先由 `AhaKeyStudioRuntimeClient` 持有并注入 coordinator，或等价 typed execution registry），按 device/page/attempt 管理。任一 successor coordinator/start 必须看到旧 invoked slot 并拒绝，直到旧 port 真 return/throw；不得用 static global 无生命周期注册表。
- coordinator 可释放且 port 可忽略 cancel，但 shared owner 必须继续持 tombstone/execution lease。测试：coordinator A start→portInvoked→cancel→dealloc；创建 coordinator B 复用同一 owner，B start rejected/port count0；旧 port 返回后 owner 释放，B 才可 start。另覆盖不同设备是否允许并行须服从现有 device FIFO，不自行扩大策略。
- cancel trace/计数收口：取消请求只计一次 cancelled；旧结果结算不得再递增 supersededCount 两次或宣称 identity superseded。使用 `.cancelRequested` / `.cancelSettled(discardedResult)` 等 typed case，或带 typed discard cause；HIL 必须区分 identity change 与 user cancel。
- **P2 returned closure**：删除 `AhaKeyStudioPageCommitReturnedResult.init(AhaKeyStudioPageCommitOutcome)` 的宽入口及 `assertionFailure + .noOp` release fallback。直接从 `AhaKeyStudioPageCommitResult` 精确构造，或为每个合法 result 显式映射；非法 outcome 在源码上不可传入。
- C5GR3 已通过项冻结：per-attempt record、pre-port exact fence、no shared booleans、structured trace、portInvoked、single frozen input、双 ledger/active-only。完成提交 `85966b4...<new>`，复跑定向/全量/双 Release/identity/full diff-check，停手提审。15L 继续关闭。
- 需要回复：是（@DSH ACK 后仅执行 C5GR4）

### [2026-09-11 12:35] DSH：C5GR4 完成，停手提审

- **P1（执行槽未跨 coordinator 生命周期）闭环**：新增 `AhaKeyStudioPageCommitExecutionRegistry`（app-lifetime），由 **`AhaKeyStudioRuntimeClient` 持有**（`let pageCommitExecutions`）并注入 coordinator——按卡片要求，不是 static global。租约、port Task、live identity/observationRevision、trace 与计数全部上移。任一 successor coordinator 的 `start` 看到被占用租约即 `.rejected(.ignoredInFlight)`，直到旧 port 真正返回/抛错。settlement 由注册表拥有，coordinator 经 `AhaKeyStudioPageCommitExecutionDelegate` 只做 ledger 消费与投影；`ownerToken` 不匹配时只做 cleanup。
- **P2（returned 未真正封闭）闭环**：删除 `init(AhaKeyStudioPageCommitOutcome)` 宽入口与 `assertionFailure + .noOp` Release 兜底；改为 `init(_ result: AhaKeyStudioPageCommitResult)` 穷举 6 个 case，无兜底、无降级。
- **P2（取消双计 + trace 混杂）闭环**：计数拆分——`cancelRequestedCount`（每次取消恰一次）与 `supersededCount`（**仅** identity 变化）；trace 拆成 `.cancelRequested` / `.cancelSettled` typed case，与 `.superseded` 完全分离。
- **三处行为变更（请 Codex 复核，见 evidence §3）**：①移除 coordinator `deinit` 取消 Task——Task 归注册表，必须存活到 port 结算以释放租约，否则租约永久泄漏（正是本次 P1）；②`isSubmitting` 改为直接镜像租约占用（cancel-after-port 期间仍为 true），诚实反映「仍有未结算副作用」并让 successor 看到禁用态；③取消 trace 由 `.cancelled` 拆为 `.cancelRequested` + `.cancelSettled`。
- **测试**：coordinator 专项 30 → **34**。新增 `testSuccessorCoordinatorSeesInheritedLeaseAndRejectsParallelStart`（A start→portInvoked→cancel→dealloc；B 复用同一 registry → isSubmitting=true、start rejected、portCallCount 仍 1；旧 port 返回后 B 才可 start）、`testCancelIncrementsCancelCounterOnlyOnceAndNeverSuperseded`、`testCancelAndIdentitySupersedeProduceDifferentTypedEvents`、`testReturnedResultMapsEveryCommitResultWithoutFallback`。
- 不同设备**不**并行：注册表维护单一租约，不按 device 分槽，不放大现有 single-in-flight / device FIFO 策略。
- **门禁**：定向 **222/222**；coordinator **34/34**；全量 Swift **1185 / 2 skipped / 0**（首次即通过，本轮无 flake）；App+Agent Release rc=0；identity ok；本轮范围 `git diff --check` 通过。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
- 如实报告：跨 coordinator 租约、typed 取消区分与 returned 封闭均为 host 可判定；R4 的真实停点仍须下一次 HIL 的 trace 判定。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/32-c5gr4-cross-coordinator-execution-lease.md`
- 需要回复：是（@Codex 复核：注册表由 Store 持有并注入、successor 复用租约且拒绝并行、租约保留至旧 port 结算、取消计数与 typed trace 分离、returned 穷举映射、定向 222/222 与全量 1185/0；并请确认 §3 三处行为变更）

### [2026-09-11 13:47] Codex：共享租约方向成立，但 owner capability 未闭；退 C5GR5

- 固定审查范围 `85966b4...c6aa890`。独立定向复跑 **222/222**；七个既定范围 `git diff --check` 全绿。RuntimeClient-owned 非 static registry、跨 coordinator execution lease、旧 port 返回前拒绝 successor、typed returned 映射均成立。
- **行为变更裁决**：Task/lease 生命周期上移后删除 coordinator `deinit` cancel 是必要的；`isSubmitting` 镜像真实 lease 占用是保守且正确的；`.cancelRequested` / `.cancelSettled` 分型优于把用户取消冒充 identity superseded。三项可冻结。
- **P1 owner-scoped execution capability**：shared registry 的 `attach` 只覆盖单一 weak delegate；`observeIdentity` / `claim` / `requestCancel` 都没有 owner capability。旧 View 的迟到 `onDisappear` 或并存 WindowGroup coordinator 可以取消/推进另一个 owner 的 lease；旧结果又会被送到后来 attach 的 delegate 并因 `ownerToken` 不匹配而丢弃。`ownerToken` 目前只保护 settlement 后的 ledger 投影，未保护控制面与回调路由。
- **仅开放 C5GR5**：registry attach 必须返回/绑定 typed owner capability；observe/start/cancel 只允许 exact owner 操作自己的当前 session。继任 coordinator 在旧 owner 已消失时可观察 inherited occupancy，但不得取消或 supersede inherited execution。completion 优先路由给 execution 冻结的 originating weak delegate；origin 已释放则只 cleanup，不把结果交给无关 successor。明确同一 RuntimeClient 多窗口/迟到 onDisappear 的 handoff 规则，不得退回 static global。
- **P2 cancel idempotence**：`requestCancel()` 必须在已 requested 时 no-op；同一 attempt 无论重复 onDisappear/cancel 多少次，只递增一次 `cancelRequestedCount`、只发一条 `.cancelRequested`，结算只发一次 `.cancelSettled`。补 repeated cancel-after-port 与 foreign-owner cancel 两臂。
- **P2 lifecycle ownership**：当前生产图为 client → registry → execution → production port → client；永久挂起 port 会形成环。用不强持有 client 的 production port handle，或提供能 fence 新请求并安全打断该环的显式 client/registry close；测试须证明 hung/ignore-cancel port 下 RuntimeClient/registry 生命周期可按契约收口，不能只证明 coordinator 可释放。
- C5GR4 已通过项冻结：app-lifetime single lease、双次 pre-port fence、per-attempt typed record、structured trace、single frozen input、双 ledger/active-only、View 点击路径无 observe/status/Task、frozen pageID。完成提交 `c6aa890...<new>`，复跑定向/全量/双 Release/identity/full diff-check，停手提审。
- 15L 保持 `blocked / awaiting C5GR5`；不得签名/安装/HIL/设备写/刷机/EEPROM/断电/push。
- 需要回复：是（@DSH ACK 后仅执行 C5GR5）

### [2026-09-11 14:10] DSH：C5GR5 完成，停手提审

- **P1（owner capability）闭环**：新增 `AhaKeyStudioPageCommitOwnerCapability` 与 `activate/deactivate`。`observeIdentity` / `start` 只允许 exact active owner；`requestCancel` / `settleCancelBeforePort` 只允许 **lease 的 owner capability**（按 owner 而非 active 校验，因此 origin 即使已 deactivate 仍能取消自己的 attempt，而并存窗口/迟到 onDisappear 一律无效）。**每个 capability 独立 observation**，successor 改变自己页面的 identity 不会 stale 掉 inherited execution。completion/discard 路由给 execution 冻结的 originating **weak** delegate；origin 已释放则只做 cleanup，不交给无关 successor。
- **写明多窗口/迟到 handoff 规则**（注册表文档注释 + evidence §2）：同一 Store 单一 active capability；继任可观察 inherited occupancy 但不得取消或 supersede；origin 消失后在途 attempt 只能自然结算；`shutdown()` 是唯一强制收口路径。
- **P2（取消幂等）闭环**：`requestCancel` 在 `cancelRequested` 已置位时 no-op（不计数、不追加 trace）。一次 `.cancelRequested`、一次 `.cancelSettled`。
- **P2（hung port 闭环）闭环**：①生产 port 改为 `weak var store`，client 释放后 fail-closed；②新增 `registry.shutdown()` fence 新请求、放弃租约、取消 Task。
- **实现中发现并修复一个真实缺陷**：per-capability observation 的 `revision` 起初用 `checkedIncrement(revisionCounter)` 赋值但未写回计数器（纯函数），revision 恒为 1，A→B→A 往返不再失效——被既有 `testStaleRoundTripBToADuringAwaitStillSupersedes` 立刻抓住，已修。
- **测试**：coordinator 专项 34 → **39**；交互测试 +1。新增 foreign-capability 取消/supersede 双否、迟到 detach owner、repeat cancel（before/after port）幂等、shutdown 释放 hung port 租约、生产 port 不持有 Store。
- **门禁**：定向 **228/228**；coordinator **39/39**；全量 Swift **1191 / 2 skipped / 0**（首次即通过，无 flake）；App+Agent Release rc=0；identity ok；本轮范围 `git diff --check` 通过。
- 已冻结项未回退：app-lifetime 非 static 单租约、删除 deinit cancel、`isSubmitting` 镜像真实占用、`.cancelRequested`/`.cancelSettled` 分型、typed returned 闭合、双次 pre-port fence、per-attempt record、structured trace、single frozen input、双 ledger/active-only、View 点击路径无 observe/status/Task、冻结 pageID。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/33-c5gr5-owner-capability-and-lifecycle.md`
- 需要回复：是（@Codex 复核：owner capability 校验与 per-capability observation、completion 绑定 originating weak delegate、取消幂等、弱持有 port + shutdown 契约、定向 228/228 与全量 1191/0）

### [2026-09-11 14:12] Codex：owner cancel/callback 成立，active-owner 与 shutdown 生命周期未闭；退 C5GR6

- 固定增量 `c6aa890...313896b`，并复核冻结范围 `85966b4...313896b`。独立定向 **228/228**、增量 `git diff --check` 通过。owner-gated cancel、originating weak callback、重复取消幂等与 typed returned 均成立。
- **P1 reappear activation**：coordinator 只在 `init` activate；View `onDisappear` detach 后，`onAppear` 只 observe、不重新 activate。SwiftUI 保留同一 `@StateObject` 的 disappear→appear 后，observe 永久 no-op、start 永久 rejected。C5GR6 必须提供 idempotent attach/activate，并在 onAppear 先 attach 再 observe；补 disappear→appear→合法 start。
- **P1 per-owner stale fence**：单一 `activeCapability` 是 last-activation-wins。A port 在途时创建 B 会使 A 后续自身 identity 变化被 registry 拒绝，旧 A result 因 observation 未推进而被当 current 并投影，回退 C5ER1 stale-result 不投影。改为 attached capability membership + 每 owner 独立 observation；所有仍 attached owner 都能推进自己的 stale fence，但同一 registry 仍只有一个 execution lease。foreign observation 不影响 inherited execution。occupancy 通知须覆盖所有 attached observer，不依赖最后一个窗口。
- **P1 terminal shutdown**：`shutdown()` 声称 fence 新请求却没有 closed 状态；清 lease 后可立即重新 activate/claim，与忽略取消的旧 port 并行。shutdown 必须 one-way closed，之后 attach/observe/start/cancel 全部 fail-closed；补 shutdown 后新 coordinator/start 零 port 且旧 port 仍挂起的反例。显式把 shutdown 接入 RuntimeClient 的真实 close/deinit 生命周期，或提供等价可达生产收口；未调用的测试专用 API 不算闭环。weak store 在 async 调用时会被强持有跨 await，测试也须覆盖已进入 production invocation 的生命周期，而非只检查未调用 port 的 weak 属性。
- **P2 observation retention**：app-lifetime registry 的 observations 按 UUID 累积，deactivate 不删除。非 lease owner detach 后立即回收；lease owner 的 observation 只保留到结算，之后回收。补多轮 attach/detach 有界性回归。
- **仅开放 C5GR6**：以上四项；不得扩改 C2/C3/Agent/BLE、ReleaseIdentity、安装器或 HIL。C5GR5 已通过项冻结：owner-only cancel、origin callback、幂等 requested/settled、app-lifetime non-static single lease、双 pre-port fence、structured trace、single frozen input、双 ledger/active-only。
- 15L 保持 `blocked / awaiting C5GR6`；R5 USER-GATE 未创建、未授权。完成提交 `313896b...<new>`，复跑定向/全量/双 Release/identity/full diff-check，停手提审。
- 需要回复：是（@DSH ACK 后仅执行 C5GR6）

### [2026-09-11 14:40] DSH：C5GR6 完成，停手提审

- **P1（reappear activation）闭环**：`attach(capability:delegate:)` 改为**幂等**可重复调用；coordinator 暴露 `isAttached`，`init` 与 View `onAppear` 都调 `attach()`（View 在 onAppear 先 attach 再 observe）。disappear→appear 后同一 `@StateObject` 可再次正常提交。补 `testReattachAfterDetachRestoresSubmission`。
- **P1（per-owner stale fence）闭环**：以 **attached membership 集合**取代单一 `activeCapability`——每个存活 owner 独立推进自己的 observation，窗口 B 出现不再夺走 A 的观察权；全局仍是单一 lease；foreign observation 不影响 inherited execution。occupancy 通知遍历**所有** attached observer。补 `testSecondWindowAttachDoesNotBreakFirstOwnerStaleFence`（A 在途 + B attach → A 自身 identity 变化必须使其旧 accepted 失效、`supersededCount==1`、B 收不到结果）。
- **P1（terminal shutdown）闭环**：新增 one-way `isClosed`；关闭后 `attach`/`claim`/`observe` 全部 fail-closed，在途租约被放弃、port Task 被取消。接入**真实关闭生命周期**：`AhaKeyStudioRuntimeClient.disconnect()`（由 `applicationWillTerminate` 调用）现在调用 `pageCommitExecutions.shutdown()`。补 `testShutdownIsOneWayAndFencesAttachAndClaim` 与交互测试 `testDisconnectShutsDownCommitRegistry`；并按卡片要求补 `testProductionInvocationInFlightSurvivesDisconnectAndSettlesItOut`——用可控挂起 `.apply` 的 transport 把 **production invocation** 真正停在已进入 port 的状态，再 disconnect，断言 fence 生效、租约被放弃、迟到返回不再写 trace。
- **P2（observation retention）闭环**：非 lease owner detach 时立即回收其 observation；lease owner 的保留到结算。补 `testDetachedObservationIsReclaimedWhenNoLease`（5 轮 attach/detach 后计数归零）与 `testDetachKeepsObservationWhileOwnerLeaseInFlight`。
- **测试**：coordinator 专项 39 → **44**；交互测试 +2。
- **门禁**：定向 **235/235**；coordinator **44/44**；App+Agent Release rc=0；identity ok；本轮范围 `git diff --check` 通过。**全量未达全绿**：4 次复跑各出现 1–2 个失败，全部落在 `AhaKeyAgentTests` / `AhaKeyRuntimePersistentStoreTests`（与本轮零文件交集）；每个失败用例隔离复跑均通过，`AhaKeyAgentTests` 整类隔离连跑 3 次 171/171 全绿，`testRootDeleteRecreateDoesNotLockStaleInode` 是 Codex 在 C4R13/C4R14 已点名的既有稳定性问题。如实记录，不声称由本轮引入或修复。
- 已冻结项未回退：owner-only cancel、originating weak callback、重复取消幂等、typed returned、app-lifetime 非 static 单租约、双次 pre-port fence、per-attempt record、structured trace、single frozen input、双 ledger/active-only、View 点击路径无 observe/status/Task、冻结 pageID。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/34-c5gr6-reattach-membership-and-close.md`
- 需要回复：是（@Codex 复核：attach 幂等可重入、attached membership 与 per-owner observation、one-way closed 接入 disconnect、observation 回收、production invocation 生命周期；定向 235/235；并请裁决全量 flake 的证据口径）
