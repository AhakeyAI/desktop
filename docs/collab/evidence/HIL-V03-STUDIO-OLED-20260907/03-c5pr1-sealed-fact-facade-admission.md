# V03-C5-RELEASE-FEATURE-POLICY：C5PR1 Facade sealed-fact admission

日期：2026-09-07 20:49–21:10 +08
ACK Codex 20:43 C5P 未通过与 C5PR1 开放。产品基线 `30cfeb8`；工作起点 HEAD `94960c5`（C5P）。执行 owner Cursor。Agent Relay 继续暂停。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未伪造 Relay `review_decision`。未自动进入 `USER-GATE-C5-SIGN-HIL`。未夹带 Store / Agent coordinator 修复。

## 行为

| 审查项 | 落地 |
|---|---|
| Public Bool | 删除 `allowsPictureResources` / `pictureResourceOverride`。生产 `init` 只收 transport / buildID / loaders。全仓无该符号 |
| 统一 admission | `resolvedActiveDevice(boundTarget:)`：routing capability → 必须有 snapshot + active device → 可选 target 必须等于 active → profile = `oledCompatibility?.profile ?? .unsupported` → `AhaKeyReleaseFeaturePolicy.current.projection(sealedOLEDProfile:)` |
| 携图门 | `rejectUnprovenPictureAdmission`：必须有非空 `oledCompatibility` **且** `projection.allowsResourcePackage`，否则 `unsupportedFirmware`，发生在 normalize / ingest / CAS / WAL / BLE 之前 |
| apply(modes) | 绑 `targetDeviceID`。存在 `localFileURL` 视为携图：无 proof 零 transport。keys-only 不静默剥图，仍可在 routing + target bind 下 apply |
| ingestResources | 空列表 no-op。非空必须 proven picture admission |
| apply(package) | 绑 `package.targetDeviceID`。`package.resources` 非空必须 proven picture admission |
| C4 commit | 先 resolve active-device sealed fact；`page.profile == admission.profile` 否则 `unsupportedFirmware`；assembly / package target / picture gate 都用该 fact，不用调用方 stale profile 授权 |

未改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、Studio View、Hook/安装器/固件、ReleaseIdentity 字节、policy 矩阵。`picturesUnrestrictedForTests` 仍仅测试可见。

## 反例

- 无 sealed OLED fact 的携图 `apply(modes:)`：`unsupportedFirmware`，request log / ingest / apply 均为空。
- 无 proof 的畸形携图草稿：同样零 transport，不得剥图后创建 base WAL。
- 仅 routing、无 fact 的 `ingestResources` / 含 resource 的 `apply(package)`：拒绝且零 transport。
- C4 frozen page `.legacyStandard` vs active-device Rhino fact：assemble/ingest 前拒绝。
- 密封 Rhino fact + v0.3 current：携图 apply 仍 ingest+apply 含图片，不需要 public Bool。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyStudioPageInteractionTests|AhaKeyReleaseFeaturePolicyTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeDerivationTests'
# 92/92 passed；Facade 34/34；policy/wiring/derivation 未回退

swift test
# 连续两次：1045 tests / 2 skipped / 1 failure
# 两次失败均为白名单外 AhaKeyAgentRuntimeEndpointTests.testConcurrentAppliesFromTwoClientsSerializeAndDrain
# （闸门未放行时第二事务为 .running，断言期望 .accepted）
# 独立复跑该用例仍失败。C5P 上 Codex 报告的 Store TIMEOUT
# （testRootDeleteRecreateDoesNotLockStaleInode）本机两次均通过。未修 Agent/Store。

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./scripts/check-release-identity.sh
# release identity ok；channel: "v0.2" / productVersion: "0.2.1"

git diff --check -- AhaKeyStudioRuntimeFacade.swift AhaKeyStudioRuntimeFacadeTests.swift AhaKeyStudioOLEDPreflightTests.swift
# DIFF_CHECK_OK
```

## 结论与下一精确 USER-GATE

C5PR1 Facade sealed-fact admission 完成。停手。

下一门仍是 **USER-GATE-C5-SIGN-HIL**。不自动进入。HIL 15L 保持 `blocked / awaiting C5PR1 acceptance` 直至本卡 accepted。
