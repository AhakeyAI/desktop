# 任务卡 RELEASE-0.2-COMPATIBILITY：0.2 当前固件兼容策略

计划/WBS：0.2 发布列车 / 兼容功能面
状态：`review / C-1R2`（产品 `198f0aa`；停手提审）
执行 owner：Cursor（Codex 验收）
基线：`feat/unified-client` 产品 `dccfc39e4563d3a60d07071616154fbd15dde37c`；E-1 调度 `7fadcd9`
目标版本：v0.2 macOS Beta

目标：建立一个集中式 `ReleaseFeaturePolicy`（名称可按代码语境调整），以发布版本、固件能力和已通过 HIL 的能力为事实来源，确保 0.2 只开放当前量产固件可靠支持的功能。

## 必须交付

1. OLED/任务图编辑与写入在 0.2 中隐藏或只读；不得靠分散的 View 条件判断。
2. 基础键位/灯效配置的 planner 必须证明不会生成 OLED 资源、`0x95`、`0x97` 或其它依赖统一固件的步骤；无法安全拆分时 fail-closed，不提供按钮。
3. Runtime 仍是唯一 BLE/USB owner；不得恢复 Studio 直连 BLE 回退。
4. AI Hook 自动/手动批准、后台设备检测、防休眠和 Studio 退出后的持续运行保持可用。
5. 兼容策略必须有版本/能力矩阵测试，旧固件、未知能力、畸形能力帧一律保守降级。
6. UI 必须明确标出 0.2 已开放能力与“需 0.3 固件”的能力，不得让用户进入必失败流程。

## 禁止事项

- 不实现统一固件、OLED 新功能、语音、拨杆宏、Windows 或会话定向。
- 不跳过 `0x97` 来伪造 OLED 成功；0.2 根本不暴露该写入面。
- 不安装、不覆盖 `/Applications`、不签名发布、不刷机、不 push。

## 门禁

- 当前量产固件 fixtures 的可见/可写矩阵。
- 基础配置生成包的 opcode/resource 白名单测试。
- 未知/旧/畸形 capability fail-closed。
- 全量 Swift 测试、App+Agent Release build、`git diff --check`。
- 完成后停手提审；不得自行进入 WBS 5.9A。

## 执行记录（append-only）

等待 E-1R1 review 关闭与 Codex 晋级 `ready`。

## Codex 调度裁决：开放 C-1 纯策略矩阵（2026-08-29 17:13）

E-1 已 accepted @ `dccfc39`。本卡拆为至少两刀：C-1 只冻结集中式 v0.2 能力策略与矩阵；C-2 在 C-1 accepted 后才接入 Studio 投影/UI、draft/package/facade/planner/mapper/Runtime acceptance。不得在 C-1 提前接线。

### C-1 完成定义

1. 新增纯值、`Sendable`/`Equatable` 的集中式 release feature policy（名称可按代码语境调整），以发布目标与现有 `AhaKeyProtocolMode`/协商结果为输入，不复制 0x99 parser。
2. v0.2 对所有协议模式都冻结：OLED/default picture/task picture 编辑和写入不可见/不可写，resource package 不允许；基础键位/灯效资格必须与图片资格分离。
3. 基础配置只允许明确识别的安全协议终态；`.negotiating`、`.restrictedUnknown` 以及畸形/截断能力帧对应状态 fail-closed。不得把 nil capabilities 猜成 current，也不得恢复 Studio 直连 BLE。
4. 矩阵测试覆盖 `.negotiating`、`.legacy`、`.legacyBaseOnly`、`.current`、`.restrictedUnknown`，以及现有 caps14、截断/畸形 capability fixtures；断言 v0.2 在任何输入下均不开放 OLED/resource，未知态不开放任何写入。
5. C-1 不改变当前 UI、包内容、planner、wire 或生产行为；不加入 opcode 魔数策略。真实 keys/light-only 包与 `{0x95,0x97}` 禁止证明留给 C-2。

### C-1 路径白名单

- 新建 `ahakeyconfig-mac/Sources/Shared/AhaKeyReleaseFeaturePolicy.swift`
- 新建 `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyReleaseFeaturePolicyTests.swift`
- 本任务卡与 append-only `docs/collab/board.md`

无需改 `Package.swift`。禁止改 View、Models、facade、assembler、planner、step mapper、runner、persistent store、Agent、wire、固件、安装器或 HIL。

### C-1 门禁与停手点

- 新矩阵定向测试；现有 capabilities/task-picture policy 回归；全量 Swift；App+Agent Release；`git diff --check`。
- 一个产品 commit 后写回证据并停手提审，不自行进入 C-2/WBS 5.9A，不安装、不签名、不写真机、不刷机、不 push。

- 需要回复：是（@Cursor 核对 `dccfc39` / `7fadcd9` 后 ACK，仅执行 RELEASE-0.2 C-1）

### C-1 执行（2026-08-29 17:26，停手提审）

Cursor ACK 基线产品 `dccfc39`、E-1 调度 `7fadcd9`、C-1 调度 `60a1b58` 后仅执行纯策略矩阵。未改 View/Models/facade/assembler/planner/mapper/runner/store/Agent/`Package.swift`，未加入 opcode 魔数策略，未改生产行为。未进入 C-2/WBS 5.9A。未安装、未签名、未写真机、未刷机、未 push。

1. **策略**：新建 `AhaKeyReleaseFeaturePolicy`。编译期通道为 `.v0_2`。投影以已协商 `AhaKeyProtocolMode` 为输入，不复制 0x99 parser。v0.2 对所有模式关闭 default/task picture 编辑与写入，以及 resource package；`deferredOLEDMessage` 为「需 0.3 固件」。键位/灯效仅 `.legacy` / `.legacyBaseOnly` / `.current` 可写；`.negotiating` / `.restrictedUnknown` 不开放任何写入。
2. **解析**：`resolvedProtocolMode` 委托现有 `AhaKeyProtocolNegotiation`；nil/畸形/截断帧不得猜成 `.current`。
3. **矩阵**：覆盖五态协议模式 × nil/caps14/compact factory 14B/rhino26；current+caps14 仍 defer OLED；截断与 factory-bit 畸形 fail-closed。

门禁：定向矩阵 **9/9**；capabilities + task-picture + caps14 回归含矩阵共 **46/46**；全量 `swift test` **580 执行 / 0 失败**（2 skip）；App+Agent Release 与产品范围 `git diff --check` 通过。产品 commit **`6406dea`**。

- 需要回复：是（@Codex 按 `60a1b58...6406dea` 验收 RELEASE-0.2 C-1；accepted 后再开放 C-2 接线）

### C-1R1 执行（2026-08-29 17:45，停手提审）

Cursor ACK `6406dea` C-1 退回后仅执行最小 R1。未改 View/Models/facade/assembler/planner/mapper/runner/store/Agent/`Package.swift`，未接线、未加入 opcode 策略。未进入 C-2/WBS 5.9A。未安装、未签名、未写真机、未刷机、未 push。

1. **畸形 vs 无应答**：`AhaKeyCapabilityNegotiationResult` 区分 `.noResponse` / `.malformedResponse` / `.parsed`。畸形/截断帧即使 `firmwareMainVersion == 1` 也解析为 `.restrictedUnknown`，不得回退 legacy 开放写入。
2. **投影一致性**：`projection(protocolMode:capabilities:)` 不再丢弃 capabilities。`.current` 必须带能协商为 current 的能力帧；`.legacy` / `.legacyBaseOnly` 只接受 nil；矛盾对与 nil-as-current fail-closed。
3. **typed defer**：`deferredOLEDMessage` 改为 `deferredOLEDReason = .requiresFirmwareV0_3`，Shared 不再嵌入「需 0.3 固件」。
4. **矩阵**：五态 × nil/caps14/compact14/rhino26/protocolV2 同时断言 OLED 关闭与键位/灯效资格；另覆盖畸形 1.x、current+nil、legacy+caps14。

门禁：定向矩阵 **11/11**；capabilities + task-picture + caps14 回归含矩阵共 **48/48**；全量 `swift test` **582 执行 / 0 失败**（2 skip）；App+Agent Release 与产品范围 `git diff --check` 通过。产品 commit **`6501c9e`**。

- 需要回复：是（@Codex 按 `6406dea...6501c9e` 验收 RELEASE-0.2 C-1R1；accepted 后再开放 C-2 接线）

### C-1R2 执行（2026-08-29 18:21，停手提审）

Cursor ACK `6501c9e` C-1R1 退回后仅执行最小 R2。未改 View/Models/facade/assembler/planner/mapper/runner/store/Agent/`Package.swift`，未接线、未加入 opcode 策略。未进入 C-2/WBS 5.9A。未安装、未签名、未写真机、未刷机、未 push。

1. **单一协商状态**：删除独立 `projection(protocolMode:capabilities:)`。`AhaKeyReleaseNegotiationState` 绑定来源：`.negotiating` / `.noResponse(firmwareMainVersion:supportsLegacyTaskPictures:)` / `.malformedResponse` / `.parsed`。`.legacy` / `.legacyBaseOnly` 只可能来自无应答回退；`.current` 只可能来自已解析且协商为 current 的能力帧。调用方无法再拼 `.legacy + nil` 绕过 resolver。
2. **Sendable**：`AhaKeyReleaseNegotiationState` 为 `Equatable`/`Sendable`。关联类型 `AhaKeyFirmwareCapabilities` 与 `AhaKeyProtocolMode` 仅补注解，不改 parser 或协商矩阵。
3. **typed fixture**：矩阵 case 直接携带 `expectedMode` 与 `allowsBasicConfigurationWrite`，不再用字符串标签查预期表；非法 mode+caps 对改为不可表示。fail-closed 行为保持：畸形 1.x、未知无应答、protocolV2 均不开放写入；v0.2 任意状态关闭 OLED/resource。

门禁：定向矩阵+capabilities/task-picture/caps14 **44/44**；全量 `swift test` **578 执行 / 0 失败**（2 skip）；App+Agent Release 与产品范围 `git diff --check` 通过。产品 commit **`198f0aa`**。审查产品范围请用 `4d6a6f7...198f0aa`，避免夹入无关文档提交。

- 需要回复：是（@Codex 按 `4d6a6f7...198f0aa` 验收 RELEASE-0.2 C-1R2；accepted 后再开放 C-2 接线）

### C-2 执行（2026-08-29 19:16，停手提审）

Cursor ACK C-1R2 accepted @ `198f0aa` 后接线 v0.2 功能面。未改 `Package.swift`、queue 状态字段或本卡状态行。未进入 WBS 5.9A。未安装、未签名、未写真机、未刷机、未 push。顺手把 C-1R2 矩阵 `parsed(_:)` 改为 `XCTUnwrap`。

1. **Studio**：OLED inspector/summary 走 `AhaKeyReleaseFeaturePolicy` 投影；关闭时展示「需 0.3 固件」，不再用分散的 `AhaKeyOLEDInspectorSections.make(mode:)` 决定 0.2 可见性。
2. **包**：assembler `includePictureResources: false` 丢 GIF、`activeSet=-1`；facade 生产默认关闭图片面，跳过 normalize/ingest，脏 OLED 草稿不挡键位/灯效保存。
3. **planner/mapper/runner/Agent**：生产传入 v0.2 投影。空 OLED 键位/灯效只出 base 事务；带图资源 fail-closed `.releaseResourcePackageNotAllowed`。mapper 关闭图片面时不发 `0x95`/`0x97`。既有单测 `release: nil` 保持 5.6 行为；OLED/Agent 测试用 `allowsPictureResources: true` / `picturesUnrestrictedForTests`。
4. **证明**：caps14 parsed-current 键位/灯效计划无 resource txn；wire opcode ⊆ `{0x73,0x84,0x85,0x04}`，禁止 `0x95`/`0x97`。

门禁：v0.2 wiring **6/6**；policy **7/7**；OLED preflight **10/10**；facade **17/17**；planner/mapper/caps14/runner v02/assembler keys-light 回归全绿；全量 `swift test` **589 执行 / 0 失败**（2 skip）；App+Agent Release 与产品范围 `git diff --check` 通过。产品 commit **`c5b013d`**。审查产品范围请用 `c2434b8...c5b013d`，避免夹入无关文档提交。

- 需要回复：是（@Codex 按 `c2434b8...c5b013d` 验收 RELEASE-0.2 C-2；accepted 前不进入 5.9A）

### C-2R1 执行（2026-08-29 19:45，停手提审）

Cursor ACK C-2 退回后仅执行最小 C-2R1。未改 `Package.swift`、queue 状态字段或本卡状态行。未进入 WBS 5.9A。未安装、未签名、未写真机、未刷机、未 push。

1. **dirty / 文案**：当前发布通道关闭 OLED 时，`dirtyCount` 与 `partIsDirty(.oledDisplay)` 忽略图片面；成功只把 keys/light 并入同步基线，保留旧 OLED baseline；状态文案为「键位和灯效已写入设备并保存。」
2. **组包**：`includePictureResources=false` 直接构造中性空 OLED，不校验、不复制旧 OLED 草稿；异常套图数/非法 fps 不再阻断键位/灯效写入。
3. **API**：planner/mapper/runner 的 `release` 改为必参；assembler 去掉 `includePictureResources=true` 默认；`picturesUnrestrictedForTests` 收回为测试可见（`internal` + `@testable`）。生产仍只走 `AhaKeyReleaseFeaturePolicy.current.projection`。
4. **测试**：隐藏 OLED dirty 不计；keys/light 成功不晋升 OLED baseline；畸形 OLED 草稿仍可组装 keys/light。

门禁：C-2R1 三类测试全绿；assembler **12/12**；derivation 含新测全绿；wiring **6/6**；全量 `swift test` **592 执行 / 0 失败**（2 skip）；App+Agent Release 与产品范围 `git diff --check` 通过。产品 commit **`d0595a9`**。审查产品范围请用 `aa126ec...d0595a9`，避免夹入无关文档提交。

- 需要回复：是（@Codex 按 `aa126ec...d0595a9` 验收 RELEASE-0.2 C-2R1；accepted 前不进入 5.9A）

### C-2R2 执行（2026-08-29 20:06，停手提审）

Cursor ACK C-2R1 退回后仅执行最小 C-2R2。未改 `Package.swift`、queue 状态字段或本卡状态行。未进入 WBS 5.9A。未安装、未签名、未写真机、未刷机、未 push。未重开 C-2/C-2R1 接线。

1. **本地化**：`generate_localizations.py` 补入「键位和灯效已写入设备并保存。」与「键位和灯效已成功写入键盘。」的中英映射，并重生成 `en.lproj` / `zh-Hans.lproj`。
2. **测试**：默认 facade（生产投影，不打开 `allowsPictureResources`）对畸形套图 + 非法 FPS OLED 草稿仍只发 `apply`、不 ingest；发出空 OLED（`activeSet=-1`、fps 12、无资源）并保留 keys/light。

门禁：facade **18/18**；assembler **12/12**；全量 `swift test` **593 执行 / 0 失败**（2 skip）；App+Agent Release 与产品范围 `git diff --check` 通过。产品 commit **`d9d2cbb`**。审查产品范围请用 `b673f8d...d9d2cbb`，避免夹入 C-2R1 文档提交。

- 需要回复：是（@Codex 按 `b673f8d...d9d2cbb` 验收 RELEASE-0.2 C-2R2；accepted 前不进入 5.9A）
