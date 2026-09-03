# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C1R6：immutable callback-object identity

日期：2026-09-03 19:37–19:47 +08
ACK Codex 19:33 / `lastReviewedCommit=a384285` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C2。未改 `queue.md`。本提交不含验收前已有的 Codex board/queue/status/裁决 diff。

## C1R6 行为

| 审查项 | 落地 |
|---|---|
| 不可覆写 association | 冻结 `OLEDNotifySource` 一次性绑到 callback 对象。同一对象再绑不同代时只把既有 binding 标为 `ambiguous`，不覆写为新代 |
| 生产 ingress | `didUpdateValueFor` 只把本次 `characteristic` 交给 `ingestOLEDNegotiationNotify` → `resolveOLEDNotifySource(attachedTo:)`。未知 / ambiguous / invalid 拒绝。不再用 peripheral 当前关联兜底 |
| 测试走对象链 | arm/ingest 接收 callback identity 对象，不传 token/generation。同对象 N→N+1 复用的合法 `0x99`/`0x94` 零变化；全新 identity 仍完成协商；未知/失效 identity 拒绝 |
| 有界账本 | Agent 不再持有 token source map 或 revoked set。身份活在对象 association 上，弱集只跟踪仍存活对象。64 次 bind/reset/invalidate 后释放对象计数为 0；同一存活对象计数为 1 |

C1R3 durable ingest/apply 三特征门、current-ready、Shared 唯一 10B parser，以及 C1R4 handler 三重校验未改。P2 opcode Bool 未做。P3 classifier/dispatcher 重复分类不扩面。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyOLEDCompatibilityProfileTests|AhaKeyConfigurationPlannerTests|AhaKeyConfigurationStepMapperTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyFirmwareCapabilitiesTests|AhaKeyCaps14CrossContractTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyWireProgramTests|AhaKeyTaskPictureCommandTests|AhaKeyAgentRuntimeEndpointTests/testUnsupportedOLEDContextRejectsIngestAndApplyBeforeCASOrWAL|AhaKeyAgentRuntimeEndpointTests/testLegacyProbeFirmwareV1AndTaskPictureFrameYieldsStandardContext|AhaKeyAgentRuntimeEndpointTests/testFailedAcceptanceReturnsFailureNotAccepted|AhaKeyAgentRuntimeEndpointTests/testStandardSealedContextExecutesCommandsAndChunksWithoutCurrentReady|AhaKeyAgentRuntimeEndpointTests/testDisconnectClearsOLEDContextAndRejectsIngestApplyWithZeroCASWALChange|AhaKeyAgentRuntimeEndpointTests/testStaleOLEDTimeoutAndNotifyDoNotResealPreviousProfile|AhaKeyAgentRuntimeEndpointTests/testLegacyTaskPictureErrorFrameDoesNotYieldStandard|AhaKeyAgentRuntimeEndpointTests/testSamePhaseStaleNotifyFromPreviousPeripheralDoesNotSealNewGeneration|AhaKeyAgentRuntimeEndpointTests/testStandardMissingCharacteristicRejectsIngestApplyWithZeroCASWALChange|AhaKeyAgentRuntimeEndpointTests/testSameUUIDStaleCallbackIdentityDoesNotSealReconnectedAwaitingPhase|AhaKeyAgentRuntimeEndpointTests/testRepeatedOLEDNotifyBindResetDoesNotGrowIdentityLedger'
# 175/175

swift test
# 791 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `a384285` / 调度 19:33）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`（callback 对象不可覆写 source + 有界弱集）
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift`（对象 identity→ingest、复用 fail-closed、有界账本）
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 Shared parser/profile、BLE protocol、durable ready、`DeviceTransportCore`、BLE lifecycle、Hook、WAL/XPC wire、UI/assembler、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的任务卡 C1R6 裁决与 status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C1R6 完成，停手提审。不自动进 C2，不打包、不安装、不刷机。
