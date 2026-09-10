# 任务卡 V03-C5-STUDIO-ACTIVE-SET-EDIT-INTENT：设备套图选择不能被旧 local baseline 吞掉

计划/WBS：v0.3 客户端 OLED 兼容 / C5 HIL 返工
状态：`ready / C5F`
执行 owner：Cursor
验收：Codex
产品基线：`fe984e806c0be7e873a291c3f3994bbc0e53780d`
前置：15K-E accepted @ `fe984e8`；C5ABR3 已证明 confirmation ledger UI 两击成立，但第二击仍零 WAL

## 现场事实

Gitee Rhino 当前 Runtime baseline `screenActiveSet:0 == 1`。隔离 Studio `fe984e8` 中用户明确选择 A=0：第一次 page-base 提示覆盖确认、按钮保持“覆盖写入此页”；第二次点击仍零 WAL、零 `0x97`。A/B resource digest 未变，已回滚 official 0.2.1 (362)。证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/25-c5abr3-gitee-rhino-ab-switch.md`。

截图同时显示 picker=A，但旧 status 文案仍是“套图 B”，footer 有 4 项未同步。C5ER1 的 active-only test 手工构造 `screenActiveSet.isDirty=true`，没有经过真实 `AhaKeyStudioDraft.frozenPageSnapshot`。

## 已复现根因

Codex 在 detached `fe984e8` 临时 worktree 运行确定性红测（临时 worktree已删除）：

```text
swift test --filter C5ABR3DiagnosticTests/testReturningToLocalBaselineStillEmitsAuthoritativeActiveSetDifference
Executed 1 test, with 1 failure
failed - device is set1, so choosing A/set0 must emit an active-set-only write even when local lastSynced is A
```

最小输入：current draft A=0、local `lastSyncedDraft` A=0、Runtime authority `writeConfirmed` set1、用户刚明确选择 A、overwrite=true。`frozenPageSnapshot` 只用 `current != lastSynced` 计算 `isDirty`，因此 activeSet 被标为 clean；assembler 返回 no-op。confirmation ledger 正常也没有动作可提交。

## 设计约束

`lastSyncedDraft` 只负责用户值差异，Runtime field authority 只负责设备事实。不能简单把所有 `current != authority` 都标 dirty，否则设备物理切套或新连接会被 Studio 草稿自动反写。缺的是“用户本次明确选择 active set”的 typed edit intent。

修复 seam 固定为：**Studio 编辑事件 → typed field edit intent → frozen page mapping**。View 不得直接拼 `isDirty`，assembler 不改 accepted/emitted 规则，也不得把 Runtime authority 写回 `lastSyncedDraft` 冒充本地同步事实。

## 完成定义

1. 用 typed `AhaKeyStudioPageEditIntentLedger`（名称可等价）记录用户显式编辑的 field/value identity，至少绑定 active device、session/transport generation、pageID、fieldID 与当前 typed value。套图 Picker setter 选择 A/B 时登记 `.screenActiveSet(modeSlot:)`；Runtime active-set snapshot、页面出现、draft migration/reload 不得登记用户 intent。
2. `frozenPageSnapshot` 接收本页 typed explicit intents，字段 `isDirty = localValueDiff || exactExplicitIntent`。显式 A=0 即使等于旧 local baseline，也必须被接受；但 authority 已等于 A 时继续由 strict-no-op 过滤，零操作。
3. 未发生用户 picker 事件时，current/local A=0、authority B=1 必须保持 no-op，禁止仅因设备事实不同自动回写。用户 A→B 且 B 已是 authority 时也应 no-op，并使旧 A intent 不可复活。
4. intent 必须有因果消费：`.accepted` 的 exact frozen attempt 才清对应 fields；`.requiresOverwriteConfirmation` 保留；字段/套图/device/generation/profile/page 变化作废不匹配 intent；迟到 accepted/no-op/error 不得清除后来新 intent。可复用 C5ER1 attempt/revision 语义，禁止再造不相容 token 系统。
5. C5ABR3 真实组合必须产生 active-set-only plan：current/local A=0、authority set1、explicit intent A=0、overwrite confirmed → `fieldMask == values.keys == {screenActiveSet:0}`、`activateTaskSet=0`、真实 action 仅 `0x97 set0`、resources/statusLine/A/B task assets 均不进入 plan。
6. 页面 statusLine 或 B done 虽在 local draft 中保留，只要与 Runtime `writeConfirmed` authority 精确相等就必须 strict-no-op，不能把 active-only 切换扩成 local/status/resource 重写。

## 必测反例与反馈循环

- 先把上述 detached 红测正式化，必须在修复前红、修复后绿；测试必须走真实 draft→snapshot→assembler，不得手工构造 `isDirty=true`。
- 无 explicit intent 的同一 current/local/authority 组合 → no-op；显式 A → active-only write；A→B（authority=B）→ no-op；再 A → 新 active-only write。
- 物理/Runtime activeSet B event、fresh Studio、切 device/mode 不得产生 explicit intent 或 WAL。
- confirmation 两击集成：真实 mapping 得到第一次 `.requiresOverwriteConfirmation`，第二次同 identity 进入 Facade fake/transport 并形成 accepted；历史 completed 不清 prompt。断言 exchange/apply 调用次数，不能只手工喂 ledger result。
- accepted 前后用户又切套、换 device/generation/profile 的 barrier 反例，旧结果不得清新 intent；C5ER1 confirmation token 不回退。
- C5D/C5DR1 picker、B-only resource closure、A/B digest 与 schema3 authority 既有测试全绿。

## 白名单与门禁

- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioDraftPackageMapping.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift` 或一个现有 Studio page-interaction seam（只允许一份 intent ledger）
- 对应 draft-mapping/page-interaction/confirmation/facade 测试
- 本任务卡、当轮 evidence、`docs/collab/board.md` Cursor append-only 记录
- 定向、全量 `swift test`、App + Agent Release、identity、增量/全范围 `git diff --check` 全绿；提交白名单 range 后停手提审。

## 非目标

不改 C2 assembler 决策、C3 schema/WAL/CAS/executor、Agent/BLE、ReleaseIdentity、安装器或固件。不签名、不安装、不启动 HIL、不写设备、不刷机、不擦 EEPROM、不断电、不 push。C5F accepted 后仍须新的 A/B switch USER-GATE。

## 执行记录（append-only）

### [2026-09-10 11:38] Codex：R3 停点 accepted；根因红测锁定 edit intent，开放 C5F

- R3 第一次确认 UI 成立，第二次零 WAL/零 `0x97`；未继续点击、未旁路、未改资源，按停止条件回滚正确。本门不通过。
- detached `fe984e8` 真 draft-mapping 红测稳定失败，证明 authoritative set1 + 用户选 A 被 local lastSynced A 吞成 clean；不是 confirmation ledger 再次误消费。
- official 0.2.1 (362) 已复核：唯一 owner pid 45003/runs=1，HIL rc=113；A/B digest 与 activeSet=1 未变。
- 仅开放 C5F 产品返工。15L=`blocked / awaiting C5F`；R3 授权已消费。
- 需要回复：是（@Cursor ACK 后仅执行 C5F，完成停手提审）

### [2026-09-10 14:20] Cursor ACK：仅执行 C5F

- ACK 用户 14:20。仅执行本卡：typed `AhaKeyStudioPageEditIntentLedger` 进入 `frozenPageSnapshot`；picker setter 登记 `.screenActiveSet`；exact accepted attempt 才消费；无 picker 事件的 authority 差异仍 no-op。不改 assembler 决策/C3/Agent/BLE。不签名、不 HIL、不写设备、不刷机、不 push。完成后停手提审。
- 需要回复：否（执行中）

### [2026-09-10 14:50] Cursor：C5F 完成，停手提审

- `V03-C5-STUDIO-ACTIVE-SET-EDIT-INTENT` C5F：`AhaKeyStudioPageEditIntentLedger` 记录 picker `.screenActiveSet`；`frozenPageSnapshot` 以 `localValueDiff || exactExplicitIntent` 标脏。无 picker 事件时 authority set1 仍 no-op；明确选 A 即使 local lastSynced 为 A 也发 active-only `0x97`。
- 复用 C5ER1 attempt token；exact accepted/no-op 才清对应 fields；`.requiresOverwriteConfirmation` / error 保留；迟到结果与 identity 不匹配不得清新 intent。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/26-c5f-active-set-edit-intent.md`。未改 queue / C2 / C3 / Agent。未 HIL。停手提审。
