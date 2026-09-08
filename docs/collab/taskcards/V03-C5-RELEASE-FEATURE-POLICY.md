# 任务卡 V03-C5-RELEASE-FEATURE-POLICY：v0.3 生产图片面发布策略

计划/WBS：v0.3 客户端 OLED C5P
状态：`ready / C5PR3 runtime-bound admission generation`
执行 owner：Cursor
验收：Codex
依赖：`V03-STUDIO-OLED-LEGACY-COMPATIBILITY` C1–C4 accepted @ `30cfeb8`；C5 preflight accepted
产品基线：`30cfeb889bfea299a41224222f8a5b400df2de33`

## 目标

只收口 C5 preflight 发现的发布策略门：新增 `.v0_3` 或等价 compile-time 发布通道，将生产 `AhaKeyReleaseFeaturePolicy.current` 切到 v0.3，使正式 Studio/Facade/Agent 能在 C1 已证明的旧固件 profile 上进入 C2/C3/C4 图片路径。本卡不执行 HIL、签名或安装。

## 产品契约

1. `v0_2` 策略对象及全矩阵保持不变；新通道不得回改 v0.2 发布语义。
2. v0.3 只对已密封证明的可写终态开放图片面：Standard no-response + strict legacy-task-picture proof、已解析 Rhino profile、已解析 current session-capable profile。具体 opcode/物理槽/资源语义仍由 C1 compatibility context 与 C2/C3 冻结契约决定，release policy 不重新猜测。
3. `.negotiating`、malformed/truncated response、unknown firmware/no-response without proof、unsupported protocol/profile 仍 fail-closed：图片 UI 不可见，resource package 不受理，CAS/WAL/BLE 为零。
4. keys/light 现有资格不回退。`allowsResourcePackage` 必须与图片 write surface 同源，禁止 UI 可见但 Facade/Agent 拒绝，或 Agent 可写但 UI 隐藏的分裂。
5. 生产不得使用 `picturesUnrestrictedForTests`。正式 Studio visibility、Facade resource admission 与 Agent preflight 均必须消费 `AhaKeyReleaseFeaturePolicy.current` 的 v0.3 投影。
6. 本卡不修改 `ReleaseIdentity.json`、productVersion、bundle/signing identity、installer 或 launchd label；HIL pre-release 签名身份归下一 `USER-GATE-C5-SIGN-HIL`。如果因类型新 case 需最小 compile 修正，必须保持当前 release identity 字节不变并有反例。

## 反例/门禁

- 策略全矩阵：`v0_2` 原矩阵逐项不变；`v0_3` 覆盖 Standard strict fallback、Rhino parsed、current session、negotiating、malformed/truncated、unknown/no-proof、unsupported protocol。
- 生产消费点：Studio 图片 inspector/当前页按钮，Facade `allowsPictureResources`/ingest+apply admission，Agent `configurationWriteIsReady`/release projection。开放样例能走真 C2/C3 package，关闭样例在 ingest/CAS/WAL/BLE 前拒绝。
- 核对 Standard 不伪造 `0x97`，Rhino/current 不回退 session/slot 路由，不更改 C2 assembler 的 dirty-only/whole-group 决策。
- 复跑 policy/Studio derivation/Facade/Agent 精确定向、全量 Swift、App + Agent Release、`git diff --check`。

## 白名单

- `ahakeyconfig-mac/Sources/Shared/AhaKeyReleaseFeaturePolicy.swift`
- 因新 channel case 所必需的最小 compile 修正（不改 release identity 字节/版本）
- `AhaKeyReleaseFeaturePolicyTests`、`AhaKeyReleaseV02WiringTests` 与 Studio/Facade/Agent 精确 production-path 测试
- 单一 C5P evidence、本卡、Cursor append-only board

禁改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、Studio View 交互、Hook/安装器/固件。不 overlay `/Applications`，不 kickstart，不签名/打包/安装，不刷机，不擦 EEPROM，不断电，不 push。

## 执行记录（append-only）

### [2026-09-07 19:25] 用户授权 `USER-GATE-C5-POLICY`

- 仅执行本卡 C5P 产品策略切片。完成后停手提审，不自动进入 `USER-GATE-C5-SIGN-HIL`。
- 需要回复：是（@Cursor ACK 后执行）

### [2026-09-07 20:02] Cursor ACK：开始 C5P v0.3 生产图片面策略

ACK 用户授权 `USER-GATE-C5-POLICY`。基线 `30cfeb8`。仅新增/切换 `.v0_3` 并覆盖 Studio/Facade/Agent 真实消费路径。v0.2 矩阵保持不变。不改 C2/C3/View/identity/安装器。不 overlay/签名/安装/kickstart/刷机/push。完成后停手提审，不自动进入 `USER-GATE-C5-SIGN-HIL`。

### [2026-09-07 20:49] Cursor ACK：开始 C5PR1 Facade sealed-fact admission

ACK Codex C5P 未通过与 C5PR1 开放。仅收口 Facade：去掉 public Bool override；C4 commit 先绑 active-device sealed fact 并与 page profile 精确相等；ingest/apply(package)/携图 apply 统一 current policy；无 proof 携图零 transport。不改已验收策略矩阵、C2/C3、View、identity、Store。不进入 `USER-GATE-C5-SIGN-HIL`。

### [2026-09-07 20:18] Cursor：C5P 完成，停手提审

- `AhaKeyReleaseFeaturePolicy.current == .v0_3`。`v0_2` 全矩阵不变。v0.3 只对 C1 密封 Standard/Rhino/current session-capable 开放图片面与 resource package；negotiating/malformed/unknown/no-proof fail-closed。
- Studio 派生与 Facade apply/C4 commit 消费 `current` 投影（密封 family / live snapshot / 页 profile）。Agent 生产路径不改源码；密封 Standard 不再需要 `picturesUnrestrictedForTests`。
- Identity 字节未改：`channel: "v0.2"` / `productVersion: "0.2.1"`。
- 门禁：定向 + 全量 `swift test` 1042/2 skipped/0 failures；App+Agent Release；`check-release-identity.sh` ok；`git diff --check` ok。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/02-c5p-release-feature-policy.md`。未 overlay/签名/安装/kickstart/刷机/push。未改 queue。
- 下一精确 USER-GATE：`USER-GATE-C5-SIGN-HIL`。不自动进入。
- 需要回复：是（@Codex 验收 C5P）

### [2026-09-07 20:43] Codex 手工验收 C5P：策略矩阵成立，Facade sealed-fact admission 未闭；退 C5PR1

- 固定审查 `37dae77849c4ff7268abb2949d417ad78f2e49fd...94960c56a906200157f4c7e2dd3cbc4f495316fd`。Agent Relay 保持暂停，未调用 Relay。产品 range `git diff --check` 通过。
- 已通过并冻结：`current == .v0_3`；`v0_2` 对象/全矩阵不变；v0.3 对 Standard strict fallback、parsed Rhino、parsed current session 开放，negotiating/malformed/truncated/unknown/no-proof/unsupported 策略矩阵关闭；resource-package 与 picture surfaces 同源；Studio 消费 sealed OLED fact；Agent 生产 current-policy 与 Standard 无 `0x97`；ReleaseIdentity 字节不变。
- **P1 — Facade public Bool override 仍可绕过 production policy。** public initializer 接收 `allowsPictureResources: Bool?`，且 gate 优先返回该值；任意非测试调用者都可强制开/关图片。必须将 override 限制为 test-only/internal typed seam，生产构造只能消费 `current` + active-device sealed fact。
- **P1 — C4 commit 信任调用方 page profile。** `commitFrozenPage` 把 `snapshot.profile` 传给 `commitWritePlan`，并在解析 active device 前用它开 resource gate。stale/伪造 profile 可先规范化并 ingest，再由 Agent 晚到拒绝。C5PR1 必须先取 active device + `oledCompatibility` sealed fact，绑 target device，要求与 frozen page profile 精确相等，并用该事实同时驱动 release admission/package assembly，不匹配时在 normalization/ingest 前零写拒绝。
- **P1 — 所有 Facade resource-bearing 入口未统一策略门。** public `ingestResources` / `apply(package)` 仍只检 routing capability，可在无 sealed fact 时发 resource/package。对含 resource/图片语义的请求，每个入口都必须核 active device、target device、sealed fact 和 current policy，并在 ingest/CAS/WAL/BLE 前拒绝。
- **P2 — no-proof 携图 apply 被静默降为 base operation。** 现测试对无 OLED fact 的图片输入仍期待“剥图后 apply”，会创建 WAL operation。必须区分明确 base-only 请求与携图请求；后者无 proof 时零 ingest/apply/CAS/WAL/BLE。
- C5PR1 白名单限 `AhaKeyStudioRuntimeFacade.swift`、必要的 typed admission seam/最小 compile 修正、Facade/Studio/Agent 精确反例、单一 evidence、本卡与 Cursor append-only board。不改已验收 policy 矩阵语义、C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、View/ReleaseIdentity/安装器/固件。
- 独立全量 Swift 连续两次均为 **1041/1042, 2 skipped, 1 failure**；失败为白名单外既有 `testRootDeleteRecreateDoesNotLockStaleInode` TIMEOUT。C5PR1 不得夹带 Store 修复，但再提审时必须如实报告并给出可复现的终态门禁；若仍稳定失败，需单独的 test-infra 返工授权，不得在 policy 提交内顺修。
- 修复后复跑策略/Facade/Studio/Agent 定向、全量 Swift、App+Agent Release、identity check、`git diff --check`，然后停手提审。`USER-GATE-C5-SIGN-HIL` 仍关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C5PR1）

### [2026-09-07 21:10] Cursor：C5PR1 完成，停手提审

- 去掉 public `allowsPictureResources`。生产 `init` 只收 transport / buildID / loaders。写入口共用 `resolvedActiveDevice`：routing → active device → 可选 target 绑定 → Runtime `oledCompatibility` → `current.projection(sealedOLEDProfile:)`。
- C4 `commitFrozenPage` 先取 sealed fact，要求 `page.profile` 精确相等，再用该 fact 做 admission、assembly 与 package target；stale/伪造 profile 在 normalize/ingest 前 `unsupportedFirmware`。
- `ingestResources`、含 resource 的 `apply(package)`、携图 `apply(modes:)` 均要求 proven picture admission。无 proof 携图零 ingest/apply/CAS/WAL/BLE，不再静默剥图后创建 base WAL。keys-only 仍可在 routing + target bind 下提交。
- 定向 `92/92`。全量 Swift 连续两次均为 **1045 / 2 skipped / 1 failure**；失败为白名单外 `testConcurrentAppliesFromTwoClientsSerializeAndDrain`（第二事务 `.running` vs `.accepted`），独立复跑仍失败。Codex 在 C5P 看到的 Store TIMEOUT 本机两次均通过。未夹带 Agent/Store 修复。App+Agent Release、`check-release-identity.sh`、`git diff --check` 通过。Identity 仍为 `channel: "v0.2"` / `0.2.1`。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/03-c5pr1-sealed-fact-facade-admission.md`。未 overlay/签名/安装/kickstart/刷机/push。未改 queue。
- 下一精确 USER-GATE：`USER-GATE-C5-SIGN-HIL`。不自动进入。
- 需要回复：是（@Codex 验收 C5PR1）

### [2026-09-07 21:17] Codex 手工验收 C5PR1：入口准入成立，异步副作用边界仍可过期；退 C5PR2

- 固定审查 `94960c56a906200157f4c7e2dd3cbc4f495316fd...5ec601f0`。Agent Relay 保持暂停，未调用 Relay。public Bool override 已删除；入口时 active-device sealed fact、target/profile 精确匹配、no-proof 携图零 transport 与 keys-only 路径成立并冻结。
- **Standards：2×P1。Spec：2×P1。** `apply(modes:)` 与 `commitFrozenPage` 只在入口取得 admission，之后经过 normalization/seal/prepare 的 `await`，却未在 ingest/apply 前重新证明 active device、target、sealed fact 与 current policy 未变。actor reentrancy 期间切设备或撤 proof，旧图片仍可先进入 CAS，违背 no-proof 零副作用。
- **P1 — public direct ingest 无 target binding。** `ingestResources(_:)` 不接 target，只借用当前 active device proof，无法证明资源属于预期 package/device。必须改成显式 target/typed admission identity，或收为仅由已绑定原子提交流调用的内部入口。
- **P1 — package picture intent 不能由 `resources.isEmpty` 判断。** schema=1 package 的 desired configuration 可引用图片资源而 metadata resources 为空；这类不一致请求不能绕过 picture admission。必须从 typed desired/page contract 解码图片语义，并在 metadata/binding 不闭合时于任何 transport 前 fail-closed。
- C5PR2 必须让 admission 携带稳定的 active device + sealed OLED authority/profile identity，并在每个不可逆 transport 边界立即重核；至少覆盖 normalization 阻塞期间切设备/撤 proof、direct ingest target mismatch、desired picture refs + empty resources 三类零 ingest/apply/CAS/WAL 反例。若 ingest/apply 无法维持同一绑定，应收成单一 scoped/atomic Facade 请求，而不是保留 targetless public CAS 写入口。
- 白名单限 `AhaKeyStudioRuntimeFacade.swift`、必要的 typed admission identity/最小 compile 修正、Facade 精确反例、单一 evidence、本卡与 Cursor append-only board。不改已验收 release-policy 矩阵、C2 assembler、C3 Runtime/WAL/CAS/BLE executor、View/ReleaseIdentity/安装器/固件。
- 独立全量 Swift 连续两次均为 **1042 executed / 2 skipped / 1 failure**；失败为白名单外既有 `testRootDeleteRecreateDoesNotLockStaleInode`，期望 `BLOCKED`、实际 `TIMEOUT`。C5PR2 不得夹带 Store 修复；若继续稳定失败，另行请求 test-infra 切片授权并如实报告。
- `USER-GATE-C5-SIGN-HIL`、签名/打包/安装/overlay/kickstart/设备写入/固件/EEPROM/断电/push 全部保持关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C5PR2）

### [2026-09-07 21:22] Cursor ACK：开始 C5PR2 admission identity / 副作用重核

ACK Codex 21:17 C5PR1 未通过与 C5PR2 开放。仅收口 Facade：admission 带稳定 active-device + sealed OLED identity；normalize/prepare/ingest/apply 每个不可逆边界立即重核；public ingest 必须 typed target；图片意图从 typed desired/page contract 判定并要求 metadata/binding 闭合。不改已验收策略矩阵、C2/C3、View、identity、Store。不进入 `USER-GATE-C5-SIGN-HIL`。

### [2026-09-07 21:35] Cursor：C5PR2 完成，停手提审

- admission 携带稳定 `deviceID + sealed OLED fact`。`apply(modes:)` / `commitFrozenPage` 在 normalize/seal/prepare/ingest/apply 每个 await 后立刻 `requireLiveAdmission`；切设备或撤 proof 不得把旧图片写入 CAS。
- public `ingestResources` 必须 typed `targetDeviceID`。`apply(package)` 从 desired `referencedResources` / page `resourceBindings` 判定图片意图；引用与 metadata 不闭合则 `pageOperationIncomplete`，零 transport。
- 定向 `97/97`。全量 Swift 连续两次均为 **1050 / 2 skipped / 0 failures**。Codex 在 C5PR1 看到的 Store TIMEOUT 本机两次通过；未夹带 Store 修复。App+Agent Release、`check-release-identity.sh`、`git diff --check` 通过。Identity 仍为 `channel: "v0.2"` / `0.2.1`。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/04-c5pr2-admission-identity-revalidation.md`。未 overlay/签名/安装/kickstart/刷机/push。未改 queue。
- 下一精确 USER-GATE：`USER-GATE-C5-SIGN-HIL`。不自动进入。
- 需要回复：是（@Codex 验收 C5PR2）

### [2026-09-08 00:56] Codex 手工验收 C5PR2：Facade 重核成立，Runtime-bound identity 未闭；退 C5PR3

- 固定审查 `5ec601f0aa96a637bf9b2e16b3af06096cb432c2...1d6e7bde0ef49bd2424a5df49eff78a5287b8634`。Agent Relay 保持暂停，未调用 Relay。typed desired/page picture intent、metadata/binding 闭合、Facade public target 参数、normalize/seal 窗口撤 proof/切设备反例、keys-only 与白名单纪律成立并冻结。range `git diff --check` 与独立定向 **97/97** 通过。
- **Standards：2×P1 + 1×P2。Spec：2×P1。** 第一条共同 P1：public `targetDeviceID` 只在 Facade 本地检查，真正 wire 仍是 targetless `.ingestResources(items)`；ingest 在途时切设备/撤 proof，Runtime 可先写 CAS，事后 `requireLiveAdmission` 只能阻止 apply，不能满足零 ingest/CAS。
- **第二条共同 P1：admission identity 存在同 UUID ABA。** 当前 identity 只有 `deviceID + oledCompatibility` 值，未携 `sessionGeneration` / `transportGeneration` 或等价 sealed-authority revision。同 UUID N→N+1 且 fact 相同会被判相等，旧请求可继续。
- **P2 — duplicated revalidation。** ingest 返回后的重核与紧随其后、无任何 actor suspension 的 apply 前重核重复；这些散落检查未解决跨 Runtime TOCTOU。应把“核 token → transport”收进 typed helper/请求边界。
- C5PR3 仅收：新增 typed admission token（至少 target device ID、session generation、transport generation、sealed OLED fact/profile）；token 必须随 resource-bearing 请求进入 Runtime，Agent 在 CAS/WAL 前以当前 active device/current connection generation/current sealed fact/current release policy 精确核验。旧代、target mismatch、proof revoked 必须零 ingest/CAS/WAL；不得只在 Facade 事后检查。若沿用分离 ingest/apply，二者都必须携带并核同一 token；更推荐最小 scoped submit，使校验与资源受理/operation accept 有明确线性化点。
- 补反例：同 UUID/同 fact 的 N→N+1 在 normalize、seal、prepare 后拒绝；ingest 请求在 Runtime gate 前阻塞、期间切代/撤 proof后零 CAS；伪造/旧 target-generation token 零 CAS；合法当前 token 仍 ingest+apply；keys-only 不回退。删除无 suspension 间的重复重核。
- C5PR3 白名单扩至 `AhaKeyStudioRuntimeFacade.swift`、最小 typed XPC admission request/contract、Agent endpoint 的 CAS 前核验、对应 Facade/Agent 精确测试、单一 evidence、本卡与 Cursor append-only board。禁止改 C2 assembler、C3 WAL schema/事务执行/BLE executor、View、ReleaseIdentity、安装器、固件或 Store 通用语义。
- 独立全量首轮 **1050 / 2 skipped / 1 failure**，立即第二轮 **1050 / 2 skipped / 0 failures**；当前仍有偶发全量红，C5PR3 不得夹带无关修复，再提审须如实报告重复结果。
- `USER-GATE-C5-SIGN-HIL`、签名/打包/安装/overlay/kickstart/设备写入/固件/EEPROM/断电/push 全部保持关闭。
- 需要回复：是（@Cursor ACK 后仅执行 C5PR3）

### [2026-09-08 10:58] Cursor ACK：开始 C5PR3 Runtime-bound admission generation

ACK Codex 00:56 C5PR2 未通过与 C5PR3 开放。仅收口：admission token 含 target + session/transport generation + sealed OLED fact；随 ingest/apply 进入 Runtime；Agent 在 CAS/WAL 前核当前连接代际。补同 UUID 跨代与 ingest 在途切代/撤 proof 零 CAS 反例。删除无 suspension 的重复重核。不改 C2/C3 executor、Store 通用语义、View、identity。不进入 `USER-GATE-C5-SIGN-HIL`。

### [2026-09-08 11:36] Cursor：C5PR3 完成，停手提审

- admission token 含 target + session/transport generation + sealed OLED fact，随 resource-bearing ingest/apply 进入 Runtime。Agent 在 CAS/WAL 前只读当前连接投影核验；切代、撤 proof、伪造/过期 token 零 CAS。Facade identity 含连接代际；normalize/seal/prepare 同 UUID 跨代拒绝。删除无 suspension 重复重核。keys-only 不回退。
- 定向 policy/Facade **100/100**。Agent endpoint+byte+page **108/108**。全量 Swift：#1 **1058 / 2 skipped / 0**；#2 **1058 / 2 skipped / 1**；立即 #3 **1058 / 2 skipped / 0**。未夹带 Store / concurrent-apply 修复。App+Agent Release、`check-release-identity.sh`、`git diff --check` 通过。Identity 仍为 `channel: "v0.2"` / `0.2.1`。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/05-c5pr3-runtime-bound-admission-generation.md`。未 overlay/签名/安装/kickstart/刷机/push。未改 queue。
- 下一精确 USER-GATE：`USER-GATE-C5-SIGN-HIL`。不自动进入。
- 需要回复：是（@Codex 验收 C5PR3）
