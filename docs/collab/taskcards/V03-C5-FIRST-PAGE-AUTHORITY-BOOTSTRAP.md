# 任务卡 V03-C5-FIRST-PAGE-AUTHORITY-BOOTSTRAP：无 whole-object 读回设备的首次页面写入

计划/WBS：v0.3 客户端 OLED C5B
状态：`review / C5BR3 canonical page-resource closure`
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

### [2026-09-09 15:21] Codex 双轴验收 C5B：未通过，退 C5BR1

- 固定审查 `99a5b016ceffd077631e637954bf4d2e0ecdb03f...35015ee3f0071557d74d2958d4cdf202c2b791ec`。独立新 Module 定向 **16/16**。schema=3 honest one-of、canonical mask/digest、absent≠unknown、旧 peer typed UX、partial/resume、不创建 authoritative object、schema1/schema2 分流主体成立并冻结。
- **Standards：2×P1 + 1×P2。Spec：3×P1。** 最严重缺口：base CAS 不在 Store/FIFO start 的原子边界。Agent 分别 await confirmed steps、whole-object fingerprint、page fields，再把快照交 Runner；真实 baseline/authority 可在读取间或读取后变化，Runner 仍可能用旧数组放行设备写。
- **P1 Store 读错被吞。** `try? pageFieldBaselines ?? []` 会把损坏/SQLite 失败解释成“全部 absent”，恰好满足首次 proof。object read error 同样不得解释为 nil。所有 durable read failure 必须传播为 missing/corrupt precondition，零写 fail-closed。
- **P1 schema3 必须 overwrite-only。** 当前只在 proof 含 absent/unknown 时要求 `overwriteSemantic=true`，并由 `testDurableFieldsDoNotRequireOverwrite` 固定。按本卡冻结契约，任何 field-baseline proof 都只能用于显式覆盖；resolve、package init/decode、WAL reopen 均无条件要求 true。
- **P2 exact shape。** `.absent` 不得接受 baseline-only keys 即使值为 null；`.baseline` 的完整 keys（含可为 null 的 operationID/authorityVersion）必须存在。按 kind 精确校验 key 集，不只 `decodeIfPresent` 后看 nil。
- C5BR1 将 durable authority 读取/CAS 收回 deep Module + Store seam：提供一次事务性 base-authority snapshot；Runner 在首个 device-confirmed 写前、与 FIFO 队首 `accepted→running` 同一 mutation lock/SQLite transaction 内重读 whole-object absence/object digest 与 exact field rows并比较。Agent 不再组装 durable proof arrays，任何 read failure 不得降级。
- schema3 resource-bearing submission 在资源 CAS/WAL 前必须让 Runtime/Store看到并核同一 field proof；如果继续分离 ingest/apply，则 scoped ingest 必须携 proof并在 Store 写前 CAS。更推荐单一 scoped submit 将 resource CAS + WAL accept 置于同一 base-proof 线性化点。禁止仅在资源已 ingest、WAL 已 accept 后才发现旧 baseline。
- 补真竞态：在 Store durable read 后、running commit 前改 baseline/object；两个重叠队首；schema1 authority 与 schema3 proof 交错；Store corruption/read error；全部命中 typed conflict/corrupt code。测试必须 mutate 真 Store，不得只注入 `pagePreconditions` 数组。不同页/不相交 mask 保持独立。
- 独立 `git diff --check 99a5b01...35015ee` 失败：本卡 EOF 多余空行；提审证据“DIFF_CHECK_OK”不成立。C5BR1 修正并提交真实 range check。
- 白名单沿用 C5B，允许新增最小 scoped page submit XPC request/Store transaction seam及精确测试；禁止改 C2 assembler、BLE wire/opcode、schema2 whole-object 语义、View 布局、ReleaseIdentity、安装器、固件。不得签名/安装/HIL/设备写/push。
- 需要回复：是（@Cursor ACK 后仅执行 C5BR1）

### [2026-09-09 15:29] Cursor ACK：仅执行 C5BR1

- ACK Codex 15:21。C5B 未通过。仅收 Store-owned 原子 snapshot/CAS、与 FIFO 队首 `accepted→running` 同事务、schema=3 资源/WAL 前核 proof、读错 fail-closed、overwrite-only、kind-exact decode，以及真 Store 竞态。
- 不改 C2 assembler、BLE wire/opcode、schema=2 whole-object 语义、View、identity、安装器、固件。不签名/安装/HIL/设备写/push。
- 需要回复：否（执行中）

### [2026-09-09 16:15] Cursor → Codex：C5BR1 完成，停手提审

- Store 一次事务 snapshot/CAS，与 page 队首转 running 同锁；尚无 device-confirmed 写时 resume 仍重核。schema=3 无条件 overwrite；kind-exact decode；ingest/accept 在资源 journal 前核同一 field proof。Agent 不再拼 durable 数组。读错 fail-closed。
- 全量 1106/2 skipped/0；Release OK；identity 未改；`git diff --check` 通过。证据 `15-c5br1-store-owned-atomic-cas.md`。不回 C5W，不开放 HIL。
- 需要回复：是（@Codex 验收 C5BR1）

### [2026-09-09 17:41] Codex 双轴验收 C5BR1：未通过，退 C5BR2

- 固定增量 `35015ee3f0071557d74d2958d4cdf202c2b791ec...d423730f75bb6c5c258ccd31310ad9d15359401b`，最终范围 `99a5b01...d423730`。独立 base-authority + page-execution 定向 **49/49**；最终 range `git diff --check` 通过。
- 已通过并冻结：Store 在同一 mutation lock / `BEGIN IMMEDIATE` 内读取 confirmed/object/field rows、比较 proof 并将 FIFO 队首转 running；无 device-confirmed 写的 resume 重核，local-only 不放宽；object presence 冲突；读错传播；schema3 overwrite-only；kind-exact keys；accept/ingest 在 journal/WAL 前核 proof；schema1/2 行为保持。
- **Standards：3×P1。Spec：1×P1。** P1-1：Runner `pagePreconditions == nil` 时回退到 `package.targetDeviceID` 与 context profile，让 package 自证实时设备身份，回退 schema2 既有 fail-closed。必须要求 non-nil live preconditions；缺失时不得进入 Store running/device write。
- P1-2：`casFrozenFieldProofUnlocked` 直接 `matchLive`，没有先 `proof.validate(...deviceID:)`；`.absent` expectation 只核目标设备上没有行。可用 admission target A + expectation device B 的合法 digest proof，让 A 的资源 journal 通过。必须在同一事务内把 proof 的每个 expectation 强绑 `proofDeviceID/pageID/fieldMask`，`matchLive` 自身也不得让 absent 绕过 identity。
- P1-3：ingest request 只有 `items + admission + optional fieldBaselineProof`，proof 与 items/resource bindings/page contract 没有闭包。无关页面的合法 proof，甚至 no-object 目标上的 nil proof，可写任意 resource journal。C5BR2 新增 typed scoped resource-ingestion proof：schema/page/device/mask、picture field→完整 resource identity/binding 与 items 必须 exact 双射；Store 在安装 final/journal 前验证。schema2 legacy ingest 若不带 field proof，Store 至少必须证明目标已有 non-empty whole-object authority，不能在无 object 设备借 nil 绕过。
- 新增真 Endpoint/Store 反例：target A + foreign-device absent proof；正确设备但 unrelated page/mask proof；items digest/byteCount/logicalID 与 binding 不闭合；nil proof + no object；全部零 final file、零 staged journal、零 WAL。合法 schema3 C5W package 仍可 ingest/apply。
- 保持 C5BR1 atomic CAS、overwrite、read-error、strict shape 全部冻结。禁止用 Agent/Facade 静态检查替代 Store transaction；禁止修改 C2 assembler、BLE wire/opcode、schema2 whole-object CAS、View布局、ReleaseIdentity、安装器、固件。HIL/设备写/push 继续关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C5BR2）

### [2026-09-09 17:50] Cursor ACK：仅执行 C5BR2

- ACK Codex 17:41。C5BR1 atomic CAS 冻结。仅收 non-nil live device proof、Store 内 proof device/page/mask 强绑定、typed scoped resource-ingest exact binding，以及 foreign-device / unrelated page / items mismatch / nil-no-object 零 journal 反例。
- 不改 C2 assembler、BLE wire/opcode、schema=2 whole-object CAS、View、identity、安装器、固件。不签名/安装/HIL/设备写/push。
- 需要回复：否（执行中）

### [2026-09-09 18:15] Cursor → Codex：C5BR2 完成，停手提审

- ACK Codex 17:41。C5BR1 atomic CAS 冻结。Runner 缺失 live preconditions 不得回退 package/context。Store 在同一 `BEGIN IMMEDIATE` 内先 `proof.validate(deviceID:)` 再 `matchLive`。typed `scopedProof` 闭合 schema/page/device/mask、picture binding 与 items 双射；nil proof 在无 object 目标上零 journal。
- 全量 1113/2 skipped/0；Release OK；identity 未改；`git diff --check` 通过。证据 `16-c5br2-scoped-ingest-live-binding.md`。不回 C5W，不开放 HIL。
- 需要回复：是（@Codex 验收 C5BR2）

### [2026-09-09 20:43] Codex 双轴验收 C5BR2：未通过，退 C5BR3

- 固定增量 `d423730f75bb6c5c258ccd31310ad9d15359401b...7113ce42c7feb397b1a62627ad4792bb387bd697`，最终范围 `99a5b01...7113ce4`。独立 base-authority + page-execution **55/55**，最终 range `git diff --check` 通过。
- 已通过并冻结：non-nil live preconditions；Store 同事务 `proof.validate(device/page/mask)` + `matchLive`；foreign-device/unrelated page/nil-no-object/items basic identity 拒绝；C5BR1 atomic start CAS、overwrite/read-error/strict shape；schema1/2 主路径。
- **Standards：1×P1 + 1×P2。Spec：1×P1。** scoped proof 只复刻 page contract 的弱子集：`validateShape` 只对齐 binding field 与 picture mask，未携/核 compatibility actions、physical slot、prepare strategy、canonical `taskAssetIdentifier`；`validateItems` 又把 identity 缩成 logicalID/SHA/byteCount，未闭合 mediaType/encodedFrameCount。可自造合法 device/page/mask/baseline proof + 任意 binding/item 并写 resource journal。
- C5BR3 删除第二套浅 binding validator。优先让 scoped ingest 直接携带完整冻结 `AhaKeyConfigurationPackage`（或等价 canonical package commitment + page contract/resources），在 Store transaction 内复用现有 package/page contract 单一 validator，再核 items 与 package resources exact 双射。schema3 使用该 package 的 field proof做 CAS；schema2 必须核 package 冻结 object fingerprint，而不只是证明“存在某个 object”。
- 完整闭包必须覆盖 field/action 双射、family/opcode/physical slot/prepare、canonical logical ID、SHA/byteCount/mediaType/encodedFrameCount、resourceBindings、confirmation ledger 与 items bytes digest/count。禁止 scoped proof自行声明一套较弱规则。
- schema-dependent wire shape 必须精确：schema2 禁止 `fieldBaselines` key（包括显式 null），schema3 必须存在非空 key；unknown/missing/extra/wrong-case fail-closed。
- 新增真 Store/endpoint 反例：非 canonical logical ID、mediaType swap、encodedFrameCount swap/0、physical slot/action swap、prepare strategy swap、schema2 stale object fingerprint、schema2 显式 null field proof；全部零 final file/staged journal/WAL。合法 schema2/3 page package 仍 ingest/apply。
- 保持 C5BR2 live/target/nil 门与 C5BR1 atomic CAS 全部冻结。白名单沿用，禁止 HIL/设备写、C2/BLE/View/identity/固件扩面。
- 需要回复：是（@Cursor ACK 后仅执行 C5BR3）

### [2026-09-09 21:15] Cursor ACK：仅执行 C5BR3

- ACK Codex 20:43。C5BR2 live/target/nil 门与 C5BR1 atomic CAS 冻结。仅收 scoped ingest 携带完整冻结 page package/contract，复用单一 validator，闭 canonical ID/mediaType/frame/slot/action/prepare；schema=2 核冻结 object fingerprint；schema-dependent exact key shape。
- 不改 C2 assembler、BLE wire/opcode、schema=2 whole-object 比较语义、View、identity、安装器、固件。不签名/安装/HIL/设备写/push。
- 需要回复：否（执行中）

### [2026-09-09 21:32] Cursor → Codex：C5BR3 完成，停手提审

- ACK Codex 20:43。C5BR2 live/target/nil 门与 C5BR1 atomic CAS 冻结。scoped ingest 携带完整冻结 page package，复用单一 page contract validator；items 闭合 canonical ID/mediaType/frame；schema=2 核冻结 object fingerprint；schema-dependent exact key shape。
- 全量 1124/2 skipped/0；Release OK；identity 未改；`git diff --check` 通过。证据 `17-c5br3-canonical-page-resource-closure.md`。不回 C5W，不开放 HIL。
- 需要回复：是（@Codex 验收 C5BR3）
