# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C1R4：source-generation ingress

日期：2026-09-03 17:57–18:05 +08
ACK Codex 17:48 / `lastReviewedCommit=fedd52e` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C2。未改 `queue.md`。本提交不含验收前已有的 Codex board/queue/status/裁决 diff。

## C1R4 行为

| 审查项 | 落地 |
|---|---|
| subscription 不可变关联 | 在 `setNotifyValue` 时冻结 `{generation, peripheralID}` 为 `oledNotifySubscription`；reset 撤销。真实 `didUpdateValueFor` 只把这份关联交给协商 handler，不读当前请求或 global generation |
| source 校验 | `shouldAcceptOLEDResponse` 要求回调 `sourceGeneration`/`sourcePeripheralID` 与 in-flight 一致，且 source generation 仍是当前代 |
| 同 UUID 跨代反例 | UUID X：N 发请求，N+1 重连并再进入同 awaiting；`sourceGeneration=N` 的合法 `0x99`/`0x94` 不改 context/capabilities/malformed/phase/version/routing。N+1 合法帧仍完成协商（0x99→Rhino，0x94→Standard） |
| 异 UUID 反例 | C1R3 不同 UUID 测试保留 |

C1R3 durable ingest/apply 三特征门、current-ready、Shared 唯一 10B parser 未改。P2 opcode Bool 未做。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyOLEDCompatibilityProfileTests|AhaKeyConfigurationPlannerTests|AhaKeyConfigurationStepMapperTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyFirmwareCapabilitiesTests|AhaKeyCaps14CrossContractTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyWireProgramTests|AhaKeyTaskPictureCommandTests|AhaKeyAgentRuntimeEndpointTests/testUnsupportedOLEDContextRejectsIngestAndApplyBeforeCASOrWAL|AhaKeyAgentRuntimeEndpointTests/testLegacyProbeFirmwareV1AndTaskPictureFrameYieldsStandardContext|AhaKeyAgentRuntimeEndpointTests/testFailedAcceptanceReturnsFailureNotAccepted|AhaKeyAgentRuntimeEndpointTests/testStandardSealedContextExecutesCommandsAndChunksWithoutCurrentReady|AhaKeyAgentRuntimeEndpointTests/testDisconnectClearsOLEDContextAndRejectsIngestApplyWithZeroCASWALChange|AhaKeyAgentRuntimeEndpointTests/testStaleOLEDTimeoutAndNotifyDoNotResealPreviousProfile|AhaKeyAgentRuntimeEndpointTests/testLegacyTaskPictureErrorFrameDoesNotYieldStandard|AhaKeyAgentRuntimeEndpointTests/testSamePhaseStaleNotifyFromPreviousPeripheralDoesNotSealNewGeneration|AhaKeyAgentRuntimeEndpointTests/testStandardMissingCharacteristicRejectsIngestApplyWithZeroCASWALChange|AhaKeyAgentRuntimeEndpointTests/testSameUUIDStaleGenerationNotifyDoesNotSealReconnectedAwaitingPhase'
# 174/174

swift test
# 790 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `fedd52e` / 调度 17:48）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`（subscription source-generation ingress）
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift`（同 UUID 跨代反例）
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 Shared parser/profile、BLE protocol、durable ready、`DeviceTransportCore`、BLE lifecycle、Hook、WAL/XPC wire、UI/assembler、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的 board/任务卡 C1R4 裁决与 status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C1R4 完成，停手提审。不自动进 C2，不打包、不安装、不刷机。
