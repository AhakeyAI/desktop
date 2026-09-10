# 任务卡 V03-C5-STUDIO-OVERWRITE-CONFIRMATION：页面覆盖确认不得被历史终态误消费

计划/WBS：v0.3 客户端 OLED 兼容 / C5 HIL 返工
状态：`ready / C5ER1`
执行 owner：Cursor
验收：Codex
产品基线：`adfe2a62fb5a495de9c9172d7cd6fb9f096096d8`
前置：15K-D accepted @ `adfe2a6`；C5BWR2 已证明 Gitee Rhino B-only 与 B 实物，但从 B 切回 A 的第二次覆盖确认未入队

## 现场事实

隔离 Studio `adfe2a6` 已成功写入套图 B done：operation `844F52E4-D601-441F-942D-682A69DBF91F` completed 10/10；设备动作只有 set1 done resource/bind 与必要 `0x97` activation，另含本地 statusLine。套图 A 四态 resource digest 未变。B 实物为上蓝 / 下绿 + 黄条，照片 SHA-256 `7d0650e477606cf2ae3a1e9d5c787750776f3a06acacaba91628f9784344da57`。

随后正式 Studio 选 A。第一次 page commit 返回“未知基线需要覆盖写入，请再点覆盖写入此页”；后续点击始终没有新 WAL。未走 BLE/`0x97` 旁路，已回滚 official 0.2.1 (362)。证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/22-c5bwr2-gitee-rhino-b-only.md`。

## 已知缺口与反馈循环

当前 `overwriteConfirmedPages: Set<AhaKeyStudioPageID>` 只有 page 粒度。`mergeCompletedPageBaselines` 每次收到 operations 变化都会遍历**所有历史 completed operation**，按同一 pageID 无条件删除当前确认。现场同页已有 completed B operation，行为与“第一次确认后第二次又回到确认态、零新 WAL”吻合。

HIL 已回滚，且确认状态封在 View 私有字段中，当前没有 agent-runnable 的 host 红测 seam。**C5E 第一步必须先抽出纯 in-process confirmation ledger，用捕获序列写出确定性红测，再修复；不得先改 View 后补浅层 helper test。**

## 完成定义

1. 用 typed `AhaKeyStudioPageOverwriteConfirmationLedger`（名称可等价）取代裸 `Set<PageID>`。它的 interface 至少绑定 active `deviceID`、session/transport generation、pageID 与规范化 frozen-page 语义（忽略 `overwriteConfirmed` 自身，但包含 profile、selected set、field/value/baseline identity）；不得把一次用户确认借给另一设备、另一连接代、另一页或已修改内容。
2. 同一 frozen semantics 第一次从 Facade 收到 `.requiresOverwriteConfirmation` 后，ledger 进入 pending；UI 明确显示“覆盖写入此页”。第二次点击用同一 identity 生成 `overwriteConfirmed=true` 的 snapshot，并必须进入 facade/Runtime；成功 `.accepted` 后消费确认。
3. 历史 operation——包括同 device + 同 page 的 `F2BAE385…` / `844F52E4…` completed——不得清除新 pending confirmation。`mergeCompletedPageBaselines` 只处理 baseline/终态展示，不能按 pageID 批量消费用户确认。
4. draft 字段、selected set、profile、active device、session/transport generation 或 page 变化时，旧确认不可使用；下一次提交必须重新确认。错误、取消、no-op、unsupported 的消费策略必须 fail-closed，并由 ledger 的单一状态转移定义。
5. C2 assembler 直接返回 `.requiresOverwriteConfirmation` 与 C5B page-base authority 在 Facade 后返回同一结果，必须走同一 ledger/interface，不得保留“提交前 page Set”和“提交后另一个 Bool”两套规则。
6. Gitee Rhino 从 B 切回 A 的 active-set-only 场景：第一次提示确认，第二次相同提交受理；冻结 plan 只含 `screenActiveSet:0` 与真实 `0x97` action，无 resource ingest、无 A/B resource rewrite。已完成 B operation 与 A/B baselines 保持事实源语义。

## 必测反例

- 捕获序列红测：operations 已含同页 completed B → A active-only 第一次 `.requiresOverwriteConfirmation` → 再发布相同/更新后的历史 operations snapshot → pending 仍在 → 第二次点击 `.accepted`；修复前必须稳定失败、修复后稳定通过。
- historical completed/failed terminal、其它页/其它设备 terminal 均不能消费 pending；只有当前 exact confirmation attempt 的结果可消费。
- 确认后修改任一 field、A↔B、换 device、同 UUID 换 generation、profile 变化：旧 token 拒绝，零 transport，重新提示。
- picker 选择本身仍零 operation/WAL；active-only accepted 零 resource ingest，fieldMask/values/actions 精确相等。
- C5D/C5DR1 sealed Rhino picker、nil→Rhino saved-B 与 Standard/session/nil/foreign/offline fail-closed 全部不回退。

## 白名单与门禁

- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift` 或 `Sources/Models/AhaKeyStudioRuntimeStore.swift` 中一个可测试的 typed ledger seam；禁止平行实现
- 必要的 page-interaction/page-model/facade 精确测试
- 本任务卡、当轮 evidence、`docs/collab/board.md` 的 Cursor append-only 记录
- 定向测试、全量 `swift test`、App + Agent Release、`check-release-identity.sh`、增量与全范围 `git diff --check` 全绿；提交白名单 range 后停手提审。

## 非目标

不改 C2 assembler 决策、C3 schema/WAL/CAS/executor、Agent/BLE、ReleaseIdentity、安装器或固件。不签名、不安装、不启动 HIL、不写设备、不刷机、不擦 EEPROM、不断电、不 push。C5E accepted 后仍须用户重新授权新的 A/B switch HIL gate。

## 执行记录（append-only）

### [2026-09-10 01:18] Codex：B-only 与 B 实物 accepted；开放 C5E confirmation ledger 返工

- C5BWR2 的 B-only operation 10/10、set1 resource/action、A 四态 digest 不变和 B 实物照片已独立核对通过。该子目标 accepted。
- A/B 切回未完成：正式 page commit 第一次进入覆盖确认后，后续未生成 WAL；没有 A 红/青复照。因此本次 HIL gate 不作整体通过。
- 现场已回滚 official 0.2.1 (362)：唯一 owner pid 33276/runs=1，HIL rc=113，XPC schema1；Stop(5) 钉屏已结束。
- 仅开放 C5E 产品返工。15L 改为 `blocked / awaiting C5E`；本次 B-write R2 授权已消费，不得复用。
- 需要回复：是（@Cursor ACK 后仅执行 C5E，完成停手提审）

### [2026-09-10 01:23] Cursor ACK：仅执行 C5E

- ACK 用户 01:23 / Codex 01:18。仅 `V03-C5-STUDIO-OVERWRITE-CONFIRMATION` C5E。先抽 typed confirmation ledger，用 C5BWR2 捕获序列写红测再修 View；历史同页 completed 不得消费 pending。
- 不改 queue、不 overlay `/Applications`、不签名/安装、不 HIL、不写设备、不刷机、不擦 EEPROM、不断电、不 push。R2 授权已消费。完成后停手提审。

### [2026-09-10 01:40] Cursor：C5E 完成，停手提审

- `V03-C5-STUDIO-OVERWRITE-CONFIRMATION` C5E：抽出 `AhaKeyStudioPageOverwriteConfirmationLedger`；捕获序列红测覆盖同页 completed B/A 不得清 pending。View 去掉 `Set<PageID>`，历史 operation 只更新展示。
- 第二次相同 identity 才带 `overwriteConfirmed=true` 进入 Facade；pending 期间 UI 为「覆盖写入此页」。active-set-only 冻结 plan 仅 `screenActiveSet:0` + `0x97`。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/23-c5e-overwrite-confirmation-ledger.md`。未改 queue / C2 / C3 / Agent。未 HIL。停手提审。

### [2026-09-10 01:52] Codex：C5E 异步旧结果可重铸确认，退 C5ER1

- 固定范围 `adfe2a6...88e6003`。typed frozen identity、历史同页 completed 不清 pending、第二次 active-only plan 与白名单成立；独立定向复跑 161/161，range `git diff --check` 通过。
- **P1 stale async result**：View 在 await 前冻结 attempt identity，但 Facade 返回后直接调用 `applyCommitResult`；`.requiresOverwriteConfirmation` 无条件 `pending = attemptIdentity`。若 await 期间字段/套图/device/generation/profile 改变，identity onChange 发生在 pending 为空时，旧结果随后仍能铸造旧 pending；用户再改回旧语义即可借用，不需要新的第一次确认。违反“任一 identity mutation 后旧确认不可复活”。
- **仅开放 C5ER1**：ledger 在开始提交时铸造 opaque、单次的 attempt token，token 绑定 exact identity 与 ledger monotonic revision。任一 current-identity mutation（包括 A→B→A、device/generation/profile 来回变化）推进 revision 并永久作废在途 attempt。结果返回时必须在 ledger 同一 transition 中同时核 attempt token、当下 revision 与 current identity；stale `.requires` 不得安装 pending，stale accepted/error/no-op 也不得消费另一 pending。
- 加 barrier 红测：begin attempt(A) → await → mutate B → mutate back A → old `.requires` returns，pending 仍 nil；下一次 A 提交必须重新获得 `.requires`，再一次相同 A 才 confirmed。另覆盖 device/generation/profile A→B→A、旧 attempt 重放、并发/乱序 result，均不能铸造或消费 token。View 必须实际调用这个 attempt interface，不得只在测试手工 `applyCommitResult`。
- **P2**：删除 `noteOperationsChanged(_:)` 及 View 调用；它是接收 operations 后故意 no-op 的 Middle Man。历史 operation 不影响 ledger 应由接口不存在及捕获序列证明，不用行为为空的方法模拟。
- C5E 已通过项冻结：typed semantic identity、pending chrome、历史 completed 不清 pending、active-only `screenActiveSet:0` + `0x97`/零 resource。禁止改 C2/C3/Agent/BLE/identity；不签名/安装/HIL/设备写/刷机/EEPROM/断电/push。提交 `88e6003...<new>` 增量并复跑全范围，停手提审。
- 15L 保持 `blocked / awaiting C5ER1`；任何旧 HIL 授权不得复用。
- 需要回复：是（@Cursor ACK 后仅执行 C5ER1）

### [2026-09-10 10:08] Cursor ACK：仅执行 C5ER1

- ACK 用户 10:08 / Codex 01:52。仅 `V03-C5-STUDIO-OVERWRITE-CONFIRMATION` C5ER1。ledger 铸造单次 attempt token 与 monotonic revision；任一 identity mutation（含 A→B→A）作废在途 attempt。删除 `noteOperationsChanged`。
- 不改 queue、不 overlay `/Applications`、不签名/安装、不 HIL、不写设备、不刷机、不擦 EEPROM、不断电、不 push。完成后停手提审。

### [2026-09-10 10:20] Cursor：C5ER1 完成，停手提审

- `V03-C5-STUDIO-OVERWRITE-CONFIRMATION` C5ER1：`beginAttempt` 铸造 opaque 单次 token，绑定 identity 与 monotonic revision。任一 identity mutation（含 A→B→A）推进 revision 并作废在途 attempt。结果 transition 同时核 token / revision / current identity。
- 删除 `noteOperationsChanged`。View 在 await 前调用 `beginAttempt`，返回后把 token 与当时 identity 交给 `applyCommitResult` / `noteAttemptFailed`。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/24-c5er1-overwrite-confirmation-attempt.md`。未改 queue / C2 / C3 / Agent。未 HIL。停手提审。
