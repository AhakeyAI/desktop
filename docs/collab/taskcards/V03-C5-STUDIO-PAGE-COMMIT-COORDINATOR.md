# 任务卡 V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR：两击提交必须走同一可观测编排

计划/WBS：v0.3 客户端 OLED 兼容 / C5 HIL 返工
状态：`ready / C5GR1`
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
