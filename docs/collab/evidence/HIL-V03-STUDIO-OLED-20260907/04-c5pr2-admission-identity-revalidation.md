# V03-C5-RELEASE-FEATURE-POLICY：C5PR2 admission identity and side-effect revalidation

日期：2026-09-07 21:22–21:35 +08
ACK Codex 21:17 C5PR1 未通过与 C5PR2 开放。产品基线 `30cfeb8`；工作起点 HEAD `5ec601f`（C5PR1）。执行 owner Cursor。Agent Relay 继续暂停。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未伪造 Relay `review_decision`。未自动进入 `USER-GATE-C5-SIGN-HIL`。未夹带 Store / Agent coordinator 修复。

## 行为

| 审查项 | 落地 |
|---|---|
| Identity | `ActiveDeviceAdmission.Identity = active device ID + Runtime-sealed OLED fact`。`requireLiveAdmission` 在每个 await 返回后立刻重核 identity/profile；不一致则 `unsupportedFirmware` / target mismatch `pageOperationIncomplete` |
| apply(modes:) | normalize / prepare / ingest / apply 每个副作用边界重核。携图请求在无 live proof 时零 transport |
| commitFrozenPage | seal / prepare / ingest / apply 同样重核。seal 改为 nonisolated，释放 actor |
| apply(package) | 图片意图从 typed desired（schema=1 `referencedResources`）或 page `resourceBindings` 判定，**不是** `resources.isEmpty`。引用与 metadata/binding 不闭合 → `pageOperationIncomplete`，零 transport |
| ingestResources | public API 必须 `targetDeviceID`；资格不得借用当前碰巧在线的另一台设备。空列表仍 no-op |

未改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、Studio View、Hook/安装器/固件、ReleaseIdentity 字节、policy 矩阵。

## 反例

- desired 引用图片但 package metadata `resources` 为空：即使有密封 Rhino fact，仍 `pageOperationIncomplete`，零 ingest/apply。
- public ingest 的 target ≠ active device：`pageOperationIncomplete`，零 CAS。
- 携图 apply 在 normalize 窗口撤销 OLED proof：`unsupportedFirmware`，零 transport。
- 携图 apply 在 normalize 窗口把 active device 切走：`pageOperationIncomplete`，零 transport。
- C4 携图 commit 在 seal 窗口撤销 proof：零 ingest/apply 计数。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyStudioPageInteractionTests|AhaKeyReleaseFeaturePolicyTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeDerivationTests'
# 97/97 passed（Facade 39/39）

swift test
# 连续两次：1050 tests / 2 skipped / 0 failures
# Codex 在 C5PR1 独立看到的 Store TIMEOUT 本机两次均通过。未修 Store。

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./scripts/check-release-identity.sh
# release identity ok；channel: "v0.2" / productVersion: "0.2.1"

git diff --check -- AhaKeyStudioRuntimeFacade.swift AhaKeyStudioRuntimeFacadeTests.swift
# DIFF_CHECK_OK
```

## 结论与下一精确 USER-GATE

C5PR2 admission identity / 副作用重核完成。停手。

下一门仍是 **USER-GATE-C5-SIGN-HIL**。不自动进入。HIL 15L 保持 `blocked / awaiting C5PR2` 直至本卡 accepted。
