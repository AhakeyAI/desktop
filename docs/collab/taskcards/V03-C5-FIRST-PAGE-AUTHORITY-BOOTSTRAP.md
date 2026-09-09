# 任务卡 V03-C5-FIRST-PAGE-AUTHORITY-BOOTSTRAP：无 whole-object 读回设备的首次页面写入

计划/WBS：v0.3 客户端 OLED C5B
状态：`review / C5B field-baseline CAS bootstrap`
执行 owner：Cursor
验收：Codex
依赖：C5P/C5PR1–C5PR9 accepted @ `99a5b01`；C5S accepted；C5W Gitee Rhino 首写停点 accepted
产品基线：`99a5b016ceffd077631e637954bf4d2e0ecdb03f`

## 现场根因

Gitee Rhino `53cd0a97` 已由真实 0x99 能力帧密封为 `rhinoDualSet`；正式隔离 Studio 的 C2 assembler 已产出页面 `.write(plan)`。失败发生在 Facade `commitWritePlan`：设备无 `authoritativeObject`，无法构造 schema=2 `baseObjectFingerprint`，因此在 ingest/apply 前以 `pageOperationIncomplete` fail-closed。

旧固件无法读回完整配置对象；schema=1 成功写才会产生 whole-object authority，而 C4 正式 UI 已只提供页面提交。首次设备因此没有合法路径建立 schema=2 base。这是产品闭环缺口，不得用 HIL 操作规避。

## 目标与 deep Module

新增 `AhaKeyRuntimePageBaseAuthority`（或等价单一 deep Module）。它的 Interface 只回答一次页面提交使用哪种 durable base proof：

1. 已有 `authoritativeObject`：继续使用现有 whole-object fingerprint；schema=2 行为逐字不变。
2. 无 whole-object：只在用户已确认 `overwriteSemantic=true` 时使用 exact field-baseline CAS；合法页面写可推进 `writeConfirmed`，但不得伪造或建立 whole-object authority。
3. 其余情况 fail-closed，并返回可行动的 typed 结果，不再用泛化 `pageOperationIncomplete` 掩盖首次基线缺失。

Studio、Runtime acceptance、Runner/reopen 共用该 Interface；复杂度留在 Module implementation，不在 Facade/Agent/Store 复制判定。

## 冻结契约

### Typed base proof

- 新增诚实版本的 page contract（优先 schema=3；禁止把新 one-of 语义静默塞回已冻结 schema=2）。handshake/snapshot 广告从单一来源派生。
- base proof strict one-of：`objectFingerprint` 或 `fieldBaselines`。后者包含 page ID、exact canonical field mask，以及每字段 durable expectation（完整 baseline 行或显式 `absent` marker）的有序摘要。
- expectation 至少闭合 `deviceID/pageID/fieldID/value/trust/provenance/operationID/authorityVersion`；缺失行与 `.unknown` 必须区分。unknown key、重复/乱序、mask 不双射、错误 page/device/case shape 在 package decode 与真 WAL reopen 上 fail-closed。
- 禁止空串、零 digest、synthetic object、Studio draft hash 或 missing-object sentinel 冒充 whole-object fingerprint。

### 受理与执行 CAS

- field proof 只允许 `overwriteSemantic=true`，且只覆盖 `fieldMask == values.keys == emitted actions`。未确认 unknown 仍 `.requiresOverwriteConfirmation`，零 ingest/apply/CAS/WAL。
- Store durable acceptance 冻结 proof；Runner 在首个 device-confirmed 写之前原子重读并比较 exact field baselines。任一字段变化必须 conflict 且零设备写。
- 重叠 field-mask 的后继 operation 成为 FIFO 队首时必须重核；不同页面/不相交字段不得伪冲突。
- 首个 device-confirmed step 后恢复只检 device + compatibility，并按 confirmed ledger 续传；`page:local:` 不放宽 CAS。partial 只推进已确认字段，retry 只发 residual。
- 成功/partial 只写既有 typed page baselines（`writeConfirmed`；真实读回才升 `verified`）。新 page schema 完成不得创建、覆盖或提升 `authoritativeObject`；schema=1 authority 与 schema=2 object-CAS 不变。

### 首次页面 UI/Facade

- 复用 C4 按钮和两击覆盖确认；不新增后台自动写或隐式整机初始化。第一次要求覆盖，第二次冻结 exact field expectations 并提交 field-CAS contract。
- 资源仅在 field proof、compatibility、target、generation admission 全闭合后 ingest。旧 peer、baseline race、missing sibling/typed value/resource 必须零副作用。
- 旧 Runtime 未广告新 schema时显示“当前 Runtime 不支持首次页面基线写入”；baseline race 显示“设备页面基线已变化，请刷新后重试”。

## 反例与门禁

1. C5W 转绿：sealed Gitee Rhino、无 object、0 page baseline、套图 A done PNG；未确认零 transport，确认后真 ingest+apply，完成后对应 fields=`writeConfirmed`，authoritative object 仍 nil。
2. 有 object 时 schema=2 package/WAL/fingerprint/steps golden 逐字不变；schema=1 completion 仍推进 object authority。
3. accept 后/start 前 baseline 改变、两个重叠 operation、不同页面并行、fresh Store/Agent reopen、local-only confirmation均按 CAS 规则结算。
4. 首个 picture field 确认后断连，重开只续未确认 chunk/field；baseline/residual 精确，不因 object nil 回到首次全写。
5. 损坏矩阵覆盖 absent↔unknown、value/trust/provenance/version/operationID、page/device/mask、重复/乱序、错误 one-of、伪造 digest；decode/WAL reopen 均拒绝。
6. 无 sealed fact、target/generation stale、旧 peer、Standard/Rhino/current wire 矩阵继续 fail-closed；Standard 不发 `0x97`。
7. 复跑 C2 assembler、C3 execution/reopen/partial、C4 interaction、Facade/Agent admission 定向；全量 Swift；App+Agent Release；identity check；`git diff --check`。

## 白名单

- `AhaKeyRuntimePageOperation.swift`
- `AhaKeyRuntimeContract.swift` / `AhaKeyRuntimeProductionSeam.swift` 的最小 schema 广告与 typed error
- `AhaKeyRuntimePersistentStore.swift`
- `AhaKeyConfigurationTransactionEngine.swift` 或现 page Runner 的精确 preflight seam
- `AhaKeyStudioRuntimeFacade.swift`
- `AhaKeyStudioPageModel.swift` / `AhaKeyStudioRuntimeStore.swift` 的最小 typed projection
- `AhaKeyAgent.swift` 的新 schema admission/错误映射最小接线
- 对应 Shared/Agent/Protocol tests、单一 C5B evidence、本卡、Cursor append-only board

禁止改 C2 ownership/dirty-only/whole-group/emitted-action 规则，禁止放宽 C3 whole-object CAS，禁止修改 BLE opcode/slot/prepare/confirmation semantics、View 布局、ReleaseIdentity、安装器、Hook 或固件。不得签名/安装/HIL/刷机/EEPROM/断电/push。

## 停点

产品提交与证据完成后停手提审，不自动回到 C5W。C5B accepted 后重新请求 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE-R1`，任何设备写入都需新授权。

## 执行记录（append-only）

### [2026-09-09 11:50] Codex：C5W 停点 accepted，开放最小 C5B 产品返工

- C5W 的设备/profile/正式 UI/fail-closed/零副作用与 official 362 回滚证据成立。根因为无 whole-object 读回设备缺少首次页面 base authority 路径。
- 仅执行本卡；不得通过 synthetic authoritative object、schema=1 隐式整机写或放宽 missing-CAS 修复。
- 需要回复：是（@Cursor ACK 后仅执行 C5B）

### [2026-09-09 14:07] Cursor ACK：仅执行 C5B

- ACK Codex 11:50。C5W 停点已验收，不是 profile 路由错误。真 0x99 = Gitee Rhino compact factory / `rhinoDualSet`；C2 已产出 `.write`；唯一阻塞 `authoritativeObject == nil`，拒绝在 ingest/apply 前。
- 仅执行本卡：单一 deep Module 管理 base proof；有 whole-object 冻结 schema=2；无 object 且用户确认覆盖后走 schema=3 field-baseline CAS。不伪造 `authoritativeObject`，不用 sentinel / Studio draft 冒充设备事实。不签名/安装/HIL/设备写/固件/EEPROM/断电/push。
- 需要回复：否（执行中）

### [2026-09-09 14:35] Cursor → Codex：C5B 完成，停手提审

- ACK Codex 11:50。单一 Module `AhaKeyRuntimePageBaseAuthority`：有 whole-object 冻结 schema=2；无 object 且用户覆盖确认后走 schema=3 field-baseline CAS。不伪造 `authoritativeObject`，不用 sentinel / Studio draft。
- 旧 peer 未广告 schema=3 → 「当前 Runtime 不支持首次页面基线写入」。baseline race → 「设备页面基线已变化，请刷新后重试」。完成/partial 只推进 typed `writeConfirmed`。
- 全量 Swift 1097/2 skipped/0 failures；App+Agent Release；identity 未改；`git diff --check` 通过。证据 `docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/14-c5b-first-page-authority-bootstrap.md`。
- 未签名/安装/HIL/设备写/固件/EEPROM/断电/push。不自动回到 C5W。下一设备写入门仍为独立 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE-R1`。
- 需要回复：是（@Codex 验收 C5B）

### [2026-09-09 14:42] Cursor：C5B 产品提交冻结

- 仅提交本卡白名单产品改动与单一 evidence / 本卡 / Cursor board 追加，供 `99a5b01...HEAD` 双轴验收。未夹带 queue / HIL 卡 / C5S/C5W 证据 / 其它脏文件。
- 需要回复：是（@Codex 按冻结 commit 验收 C5B）

