# 任务卡 V03-C5-STUDIO-DUAL-SET-PICKER：密封 Rhino 双套必须露出套图 A/B 分段

计划/WBS：v0.3 客户端 OLED 兼容 / C5 后续
状态：`accepted / C5DR1 @ adfe2a6`
执行 owner：Cursor
验收：Codex
产品基线：`5d1fe1db337099da9ffa7f143548472fd4435cf1`
前置：`V03-C5-FIRST-PAGE-AUTHORITY-BOOTSTRAP` accepted @ `5d1fe1d`；HIL `USER-GATE-C5-HIL-GITEE-RHINO-B-WRITE` 已用该 HEAD 证明 A done 实物，但正式 UI 选不了套图 B

## 现场事实（HIL-V03 2026-09-09 23:15–23:22）

隔离 Studio `5d1fe1d` 连 Gitee Rhino（0x99 `rhinoDualSet`，`setCount=2`）。LCD inspector 有四状态（待机/工作中/等待授权/已完成），文案能写「套图 A」，**没有** segmented「套图 A / 套图 B」。因此 B-only 正式写入无法做。证据 `docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/19-c5b-gitee-rhino-a-visual-b-blocked.md`。

## 根因

`AhaKeyStudioDevicePresentation.taskPictureProtocolPlan`：

```swift
AhaKeyTaskPictureProtocolPlan.make(mode: protocolMode, capabilities: nil)
```

`.current` 在 `capabilities == nil` 时返回 `nil`。视图用 `plan?.supportsActiveSet == true` 才渲染 A/B Picker，故永不显示。四状态格子靠 `protocolMode == .current` 回退 `allCases`，所以任务图编辑看起来“半套可用”。

正确事实已经存在于 active-device snapshot 的 `oledCompatibility`。其中 `.rhinoDualSet` 是 Agent 从本代已解析 capability 密封出的“双套”语义，Studio 不得再从 `protocolState`、可空 capabilities 或固件版本重建。修复 seam 是：**Runtime 密封 OLED fact → Studio task-picture presentation**；View 与页面冻结只消费这一处派生结果。

## 完成定义

1. Studio 在线且 active device 的密封 family 为 `.rhinoDualSet` 时，task-picture presentation 的 `setIndices == [0, 1]`、`supportsActiveSet == true`，inspector **必须**显示套图 A/B 分段。`.legacyStandard`、`.currentSessionCapable`（该 profile 是已解析的 non-dual session family）、`.unsupported`、缺 fact、离线或非 active device 均不得凭猜测显示双套。
2. 删除 presentation 对 `AhaKeyTaskPictureProtocolPlan.make(mode: protocolMode, capabilities: nil)` 的生产依赖。任务状态、可选套图与选择归一化必须由同一 sealed-fact 派生接口提供；禁止 View 再按 `protocolMode == .current` 补出一套不同规则。
3. 进入页面或 Runtime 更新时，只在当前选择不属于 sealed set indices 时收敛到安全首项；不得在 A/B 都合法时把用户正在编辑的 B 重置为 A，也不得因为设备 active-set event 把另一页/另一套素材镜像或标脏。
4. 选择 B 本身只改 Studio draft 的逻辑选择，不得创建 operation、CAS、resource journal 或 WAL。随后只修改 B 素材并冻结屏幕页时，沿用 C2 已验收契约：accepted/mask/values/resources 只含 B dirty fields 与协议实际需要的 activation；Rhino 物理 set1；A 的 field baseline、digest 与资源 identity 不进入 plan、不改变。
5. 缺 sealed fact 或 profile 不匹配时继续 fail-closed：任务图不可提交，不能借 `protocolMode`、`capabilities: nil`、历史 draft 或另一设备的 fact 打开双套。

## 必测反例与门禁

- reducer/interface：active-device sealed Rhino（即使 snapshot `capabilities` 为空）→ `[0,1]` / picker true；Standard、current single-set、unsupported、nil fact、foreign-device fact → 单套或不可用，picker false。
- selection：已有 B draft + Rhino snapshot/re-render 保持 B；切为 B 零 operation/WAL；Rhino → Standard/unsupported 时才收敛到 0。
- page commit：A 已有五条 `writeConfirmed` baseline，B-only dirty 的 frozen plan 不包含任何 A logical field/resource，并保持 `fieldMask == values.keys == emitted actions`；未确认首次 B 仍走 schema=3 overwrite confirmation，不伪造 whole-object authority。
- 静态门：`AhaKeyStudioDevicePresentation` 不再调用 `.make(mode: protocolMode, capabilities: nil)`；View 不得自行重新推断双套。
- 运行：相关 derivation/page-interaction/facade 定向、全量 `swift test`、App + Agent Release、`check-release-identity.sh`、range `git diff --check` 全绿。完成后提交白名单 range 与 evidence，停手提审。

## 白名单

- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`（仅在必须消除 View 侧重复规则时）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyTaskPictureProtocolPlan.swift` 或现有 sealed-fact 派生模型（二选一，禁止平行复制）
- 对应 derivation / page-interaction / Shared plan 测试
- 本任务卡、当轮 evidence、`docs/collab/board.md` 的 Cursor append-only 记录

## 非目标

Agent/BLE 协商、C2 assembler 规则、C3 schema/WAL/CAS/executor、发布 identity、签名/安装、HIL B-only 真写、A/B 电源键切换、断电保持、EEPROM、固件与 push。那些仍归 `HIL-V03-STUDIO-OLED-COMPATIBILITY` 下一门，且必须等本卡 accepted 后再单独授权。

## 执行记录（append-only）

### [2026-09-09 23:31] Codex：A 视觉先验 accepted；开放 C5D 产品返工

- 实物照片独立核对为左红 / 右青 + 顶部白条，SHA-256 `dd03a9a86caf75354b42f0af3dc47eb4994ece3eb0e6e595a87de66a1c6a0288`，与套图 A done ident 一致。A 视觉 oracle accepted。
- B-only 未开始：正式 UI 没有 A/B 分段，Studio 开窗零新 WAL；A 五条 baseline 未动。official 0.2.1 (362) 已恢复，唯一 owner pid 76400，HIL rc=113。
- 根因确认是 presentation 丢失 Runtime 密封双套事实，不是 0x99/profile 路由错误。仅开放本卡 C5D；HIL 15L 改为 `blocked / awaiting C5D`。不得签名/安装/HIL/设备写/刷机/EEPROM/断电/push。
- 需要回复：是（@Cursor ACK 后仅执行 C5D，完成停手提审）

### [2026-09-09 23:35] Cursor ACK：仅执行 C5D

- ACK 用户 23:34 / Codex 23:31。A 视觉先验 accepted。15L 保持 `blocked / awaiting C5D`（不改 queue）。仅执行 `V03-C5-STUDIO-DUAL-SET-PICKER`：Runtime 密封 OLED fact → Studio task-picture presentation，Rhino 露出套图 A/B；不得签名/安装/HIL/设备写/刷机/EEPROM/断电/push。
- 完成后提交白名单 range 与 evidence，停手提审。
- 需要回复：否（执行中）

### [2026-09-09 23:50] Cursor：C5D 完成，停手提审

- Studio presentation 只消费 active-device `oledCompatibility`。`.rhinoDualSet` → `[0,1]` / `supportsActiveSet`；Standard / session / 缺 fact / 离线 / 他机 fact 不得打开双套。已删除 `make(mode: protocolMode, capabilities: nil)` 与 View 的 `protocolMode == .current` 状态回退，以及 `reconcileActiveTaskPictureSetsFromDevice`。
- 合法 B 选择在 Runtime 更新时保持；非法选择才收敛。选择 B 不创建 operation/WAL。C2 B-only dirty 契约未改：A `writeConfirmed` 不进 plan。
- 门禁：定向 94/0；全量 `swift test` 1132/2 skipped/0（中途一次 concurrent-apply 历史 flake，单独复跑绿，未改该测试）；App+Agent Release；`check-release-identity.sh` `channel: "v0.2"` / `0.2.1`；range `git diff --check` 绿。
- 证据 `docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/20-c5d-studio-dual-set-picker.md`。未改 queue、未 HIL、未设备写、未签名/安装/push。15L 仍 `blocked / awaiting C5D`。
- 需要回复：是（@Codex 验收 `5d1fe1d..HEAD` 白名单；通过后才可另开 HIL B-write USER-GATE）

### [2026-09-09 23:57] Codex：C5D 主路径成立；异步启动会把已保存 B 打回 A，退 C5DR1

- 固定审查 `5d1fe1d...6f47bd8`。Standards 无硬违规；Spec 1×P1，C5D 未 accepted。独立定向复跑 94/94，range `git diff --check` 通过。
- **P1 启动状态转移**：View 先出现而 Runtime sealed fact 尚未到达时，`onAppear → refreshEditingTaskPictureSetFromDraft()` 把空 `setIndices` 交给 `desiredActiveSet`，已保存的 B=1 被 UI 收敛为 A=0；Rhino plan 稍后到达时，`convergeEditingTaskPictureSelectionToSealedPlan()` 又以当前 0 为输入，不会从仍为 1 的 draft 恢复。违反“已有 B draft + Rhino snapshot/re-render 保持 B”，会污染下一次 HIL 的默认选择。
- **仅开放 C5DR1**：把“无 sealed plan”与“已密封单套 plan”分开。无 plan 时不得把当前/draft 选择写成 A；nil→Rhino 首次到达应从当前 mode draft 恢复合法 B；后续 plan 更新若当前用户选择仍合法则保留，仅在新 plan 明确不支持时收敛到安全首项。监听完整 plan（至少 set indices + states），不能只监听 indices。
- 抽取或复用一个可测试的 selection transition 接口，让 View 真调用它；新增真实序列反例：saved draft B、初始 plan nil、随后 sealed Rhino → B；Rhino B 在等价 snapshot/re-render 后仍 B；Rhino→Standard 才收敛 A；nil/unsupported 不创建 operation/WAL、不篡改 draft。不得只测 `desiredActiveSet(1,[0,1])`。
- **Standards P2/P3 同轮收口**：`make(sealedProfile:)` 当前是无独立 caller 的 public 低证明旁路，并与 `make(_ context:)` 重复 family switch/常量。将它收窄为 private/internal implementation，或用单一 canonical builder 消除漂移；生产公开入口仍只接受 sealed fact。未消费的 Studio `activeTaskPictureSets` 投影可删除，若保留需给出本卡内真实 consumer。
- C5D 已通过项冻结：active-device sealed Rhino `[0,1]`/picker、Standard/session/nil/offline/foreign fail-closed、View 不按 protocolMode 猜测、B-only assembler closure。禁止改 Agent/BLE、C2/C3、identity；不得签名/安装/HIL/设备写/刷机/EEPROM/断电/push。完成提交 `6f47bd8...<new>` 增量与全 range，复跑定向/全量/双 Release/identity/diff-check，停手提审。
- 15L 保持 `blocked / awaiting C5DR1`；此前 B-write USER-GATE 已消费，不得复用。
- 需要回复：是（@Cursor ACK 后仅执行 C5DR1）

### [2026-09-10 00:04] Cursor ACK：仅执行 C5DR1

- ACK 用户 00:03 / Codex 23:57。C5D 未 accepted。仅执行 C5DR1：无 sealed plan 不得把选择写成 A；nil→Rhino 从当前 mode draft 恢复合法 B；监听完整 plan；收窄 `make(sealedProfile:)` 与重复 family→plan；删除无消费的 Studio `activeTaskPictureSets` 投影。
- 不改 queue、不 HIL、不设备写、不签名/安装/push。15L 保持 `blocked / awaiting C5DR1`。完成后停手提审。
- 需要回复：否（执行中）

### [2026-09-10 00:13] Cursor：C5DR1 完成，停手提审

- P1：View 调用 `AhaKeyTaskPictureSetSelection.afterDraftRefresh` / `afterPlanChange`。无 plan 保留 draft B；nil→Rhino 从 draft 恢复合法 B；监听完整 plan。Rhino→Standard 才收敛 A；nil/unsupported 不改选择、不写 draft、零 operation。
- P2/P3：`make(sealedProfile:)` 改为 private，与 context/legacy 共用 `legacyStandardPlan` / `currentSetAwarePlan`。删除 Studio `activeTaskPictureSets` 投影。
- 门禁：定向 96/0；全量 1134/2 skipped/0；App+Agent Release；identity `v0.2`/`0.2.1`；range `git diff --check` 绿。证据 `21-c5dr1-selection-transition.md`。
- 未改 queue、未 HIL、未设备写、未签名/安装/push。15L 仍 `blocked / awaiting C5DR1`。
- 需要回复：是（@Codex 验收 `6f47bd8..HEAD` 增量与 `5d1fe1d..HEAD` 全 range；通过后才可另开 HIL B-write USER-GATE）

### [2026-09-10 00:18] Codex：C5DR1 双轴通过，15K-D accepted

- 固定增量 `6f47bd8...adfe2a6`、全范围 `5d1fe1d...adfe2a6`。Spec 0 findings；Standards 0 hard findings。独立定向复跑 96/96，增量与全范围 `git diff --check` 通过。
- 原 P1 已闭合：无 plan 保留 draft；nil→Rhino 从 draft 恢复 B；等价 Rhino 保留当前合法选择；Rhino→Standard 才收敛 A；View 监听完整 plan 并调用统一 transition。原 sealed-fact/picker/B-only closure 未回退。
- builder 已私有化并共用 plan constructors，dead Studio active-set 投影已删。保留两项非阻断设计债：空 supported-set 时 `desiredActiveSet` 可返回未证明值；View 保存完整 previous plan 但 transition 只消费 nil/non-nil。二者不打开 picker、不创建 operation/WAL，也不阻断本次 Gitee Rhino HIL，后续重构时应收窄。
- 15K-D accepted @ `adfe2a6`。15L 转到新的、尚未授权的 `USER-GATE-C5-HIL-GITEE-RHINO-B-WRITE-R2`；旧授权不得复用。
- 需要回复：否（转 15L 等用户门）
