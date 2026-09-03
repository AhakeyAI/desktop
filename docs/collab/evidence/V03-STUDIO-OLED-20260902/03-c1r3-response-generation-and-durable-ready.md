# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C1R3：response 代际归属与 durable 受理门

日期：2026-09-03 17:22–17:40 +08
ACK Codex 17:12 / `lastReviewedCommit=400b81d` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C2 UI assembler 或 HIL。未改 `queue.md` 状态。

## C1R3 行为

| 审查项 | 落地 |
|---|---|
| notify/response 代际归属 | 每次 `0x99/0x00/0x94` 发送捕获 `{generation, peripheralID}`；所有 response handler 在解析或改状态前拒绝过期 generation / 非当前 peripheral。reset 清 in-flight |
| 同-phase 迟到反例 | 新 generation 重新进入相同 awaiting 后，旧 peripheral 的合法 `0x99` 与 `0x94` 不改变 context/capabilities/malformed/phase/version/routing |
| durable ingest/apply 门 | XPC `.apply` / `.ingestResources` 在 `makeRuntimeStore` / CAS / WAL 前调用同一 `configurationWriteIsReady()`。Standard 已密封与三特征就绪分开注入 |
| 三特征生产门 | 任一特征缺失 → ingest/apply=`not-ready`，CAS/WAL 零变化；三特征齐全且 `isReady=false` 时 Standard 可受理并完成真 command/chunk。current 仍要 current-ready |
| 单一 10B parser | `AhaKeyLegacyTaskPicturePayload.parse` 是唯一精确 10B LE 布局；classifier 先校验 envelope/status/长度再复用；App `parseTaskPictureStateResponse` 包装同一 parser，过长 payload 为 nil |

`DeviceTransportCore` ready/reconnect 仍仅 current。LED `0x90` 门控未改。Studio Views/Models/assembler、Hook、WAL 格式/XPC wire、安装器未改。P2 opcode Bool 收敛未做。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyOLEDCompatibilityProfileTests|AhaKeyConfigurationPlannerTests|AhaKeyConfigurationStepMapperTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyFirmwareCapabilitiesTests|AhaKeyCaps14CrossContractTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyWireProgramTests|AhaKeyTaskPictureCommandTests|AhaKeyAgentRuntimeEndpointTests/testUnsupportedOLEDContextRejectsIngestAndApplyBeforeCASOrWAL|AhaKeyAgentRuntimeEndpointTests/testLegacyProbeFirmwareV1AndTaskPictureFrameYieldsStandardContext|AhaKeyAgentRuntimeEndpointTests/testFailedAcceptanceReturnsFailureNotAccepted|AhaKeyAgentRuntimeEndpointTests/testStandardSealedContextExecutesCommandsAndChunksWithoutCurrentReady|AhaKeyAgentRuntimeEndpointTests/testDisconnectClearsOLEDContextAndRejectsIngestApplyWithZeroCASWALChange|AhaKeyAgentRuntimeEndpointTests/testStaleOLEDTimeoutAndNotifyDoNotResealPreviousProfile|AhaKeyAgentRuntimeEndpointTests/testLegacyTaskPictureErrorFrameDoesNotYieldStandard|AhaKeyAgentRuntimeEndpointTests/testSamePhaseStaleNotifyFromPreviousPeripheralDoesNotSealNewGeneration|AhaKeyAgentRuntimeEndpointTests/testStandardMissingCharacteristicRejectsIngestApplyWithZeroCASWALChange'
# 173/173

swift test
# 789 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `400b81d` / 调度 17:12）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`（in-flight generation+peripheral、XPC 共用 ready、三特征注入）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyOLEDCompatibilityProfile.swift`（唯一 10B parser）
- `ahakeyconfig-mac/Sources/BLE/AhaKeyProtocol.swift`（App 旧入口复用 Shared parser）
- 对应 OLED profile / protocol / Agent endpoint 测试
- 本任务卡、`docs/collab/board.md`、本证据

未改 BLE lifecycle/回连策略、Hook、WAL/XPC wire、UI/assembler、`Package.swift`、安装器/identity。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/collab/taskcards/WBS-1-UNIFIED-FIRMWARE.md`、`docs/firmware-client-baseline-2026-08-22.md`。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw 二进制/截图。

## 结论

C1R3 完成，停手提审。不自动进 C2，不打包、不安装、不刷机。accepted 后再开页面级 assembler。
