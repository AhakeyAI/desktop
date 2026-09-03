# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C1R5：callback-addressable subscription identity

日期：2026-09-03 18:24–18:34 +08
ACK Codex 18:13 / `lastReviewedCommit=397c532` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C2。未改 `queue.md`。本提交不含验收前已有的 Codex board/queue/status/裁决 diff。

## C1R5 行为

| 审查项 | 落地 |
|---|---|
| callback-addressable 订阅 | 每次 `setNotifyValue` 铸造不可复用 token，映射冻结为 `{generation, peripheralID}`。旧 token 不得被新订阅改写成新代。token 附到本次 `CBPeripheral` / notify / command characteristic；对象复用时撤销旧 token，不覆写其 generation |
| 生产 ingress | `didUpdateValueFor` 从 callback 对象取 token，再经 `ingestOLEDNegotiationNotify` → `resolveOLEDNotifySource`。未知或已撤销 token 直接拒绝。reset 清 in-flight/phase，不 revoke-all |
| 测试不再注入 generation | `armOLEDAwaiting*` 返回订阅 token；旧/新 identity 与未知/已撤销 token 都走同一 ingest/resolver。无 token 的 `handleOLEDNotifyFrameForTesting` 不得反推当前订阅 |
| 同 UUID 跨代反例 | UUID X：旧 token 绑 N、新 token 绑 N+1。旧 identity 合法 `0x99`/`0x94` 及未知/已撤销 identity 不改 context/capabilities/malformed/phase/version/routing。新 identity 仍完成协商（0x99→Rhino，0x94→Standard） |
| 异 UUID 反例 | 改为用旧 arm 的 token 驱动，不再用当前槽 generation + 旧 peripheral |

C1R3 durable ingest/apply 三特征门、current-ready、Shared 唯一 10B parser，以及 C1R4 handler 三重校验未改。P2 opcode Bool 未做。P3 classifier/dispatcher 重复分类不扩面。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyOLEDCompatibilityProfileTests|AhaKeyConfigurationPlannerTests|AhaKeyConfigurationStepMapperTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyFirmwareCapabilitiesTests|AhaKeyCaps14CrossContractTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyWireProgramTests|AhaKeyTaskPictureCommandTests|AhaKeyAgentRuntimeEndpointTests/testUnsupportedOLEDContextRejectsIngestAndApplyBeforeCASOrWAL|AhaKeyAgentRuntimeEndpointTests/testLegacyProbeFirmwareV1AndTaskPictureFrameYieldsStandardContext|AhaKeyAgentRuntimeEndpointTests/testFailedAcceptanceReturnsFailureNotAccepted|AhaKeyAgentRuntimeEndpointTests/testStandardSealedContextExecutesCommandsAndChunksWithoutCurrentReady|AhaKeyAgentRuntimeEndpointTests/testDisconnectClearsOLEDContextAndRejectsIngestApplyWithZeroCASWALChange|AhaKeyAgentRuntimeEndpointTests/testStaleOLEDTimeoutAndNotifyDoNotResealPreviousProfile|AhaKeyAgentRuntimeEndpointTests/testLegacyTaskPictureErrorFrameDoesNotYieldStandard|AhaKeyAgentRuntimeEndpointTests/testSamePhaseStaleNotifyFromPreviousPeripheralDoesNotSealNewGeneration|AhaKeyAgentRuntimeEndpointTests/testStandardMissingCharacteristicRejectsIngestApplyWithZeroCASWALChange|AhaKeyAgentRuntimeEndpointTests/testSameUUIDStaleCallbackIdentityDoesNotSealReconnectedAwaitingPhase'
# 174/174

swift test
# 790 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `397c532` / 调度 18:13）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`（callback-addressable subscription token + 生产 ingest）
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift`（同 UUID 旧/新 callback identity，未知/已撤销）
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 Shared parser/profile、BLE protocol、durable ready、`DeviceTransportCore`、BLE lifecycle、Hook、WAL/XPC wire、UI/assembler、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的 board/任务卡 C1R5 裁决与 status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C1R5 完成，停手提审。不自动进 C2，不打包、不安装、不刷机。
