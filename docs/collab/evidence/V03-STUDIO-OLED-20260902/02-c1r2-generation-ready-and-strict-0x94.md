# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C1R2：连接代际清场与 Standard 真执行门

日期：2026-09-03 15:11–15:50 +08
ACK Codex `d9bdf11` / `lastReviewedCommit=b676b85` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C2 UI assembler 或 HIL。未改 `queue.md` 状态。

## C1R2 行为

| 审查项 | 落地 |
|---|---|
| 连接代际清场 | `didConnect` / `didDisconnect` 原子递增 `oledConnectionGeneration` 并清空 context、capabilities、malformed、probe phase/version；`dataChar` 随 command/notify 一并释放。timeout 带 generation token，过期 callback 零状态变化 |
| context-aware ready | 受理、step、command、chunk 共用 `configurationWriteIsReady()`：current 仍要 `transportCore.isReady` + 三特征；Standard 只要求本代际已密封且 peripheral/command/data 可用，不要求 current-ready |
| 严格 `0x94` | envelope + opcode + `status=0` + 精确 10B legacy payload；mode/state 必须回显探测查询（mode=0, state=done）。错误 status、wrong echo、过长垃圾、短包、空 ACK 均为 unsupported |
| 生产形状测试 | Standard 从 no-0x99 实探到真 executor 完成 command/chunk（`isReady=false`）；断连后协商窗口 ingest/apply=`unsupported-protocol` 且 CAS/WAL 零变化；过期 timeout/notify 不回填旧 profile；错误 `0x94` 不进入 Standard |

`DeviceTransportCore` ready/reconnect 仍仅 current。LED `0x90` 门控未改。Studio Views/Models/assembler、Hook、WAL 格式/XPC wire、安装器未改。P2 opcode Bool 收敛未做。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyOLEDCompatibilityProfileTests|AhaKeyConfigurationPlannerTests|AhaKeyConfigurationStepMapperTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyFirmwareCapabilitiesTests|AhaKeyCaps14CrossContractTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyWireProgramTests|AhaKeyAgentRuntimeEndpointTests/testUnsupportedOLEDContextRejectsIngestAndApplyBeforeCASOrWAL|AhaKeyAgentRuntimeEndpointTests/testLegacyProbeFirmwareV1AndTaskPictureFrameYieldsStandardContext|AhaKeyAgentRuntimeEndpointTests/testFailedAcceptanceReturnsFailureNotAccepted|AhaKeyAgentRuntimeEndpointTests/testStandardSealedContextExecutesCommandsAndChunksWithoutCurrentReady|AhaKeyAgentRuntimeEndpointTests/testDisconnectClearsOLEDContextAndRejectsIngestApplyWithZeroCASWALChange|AhaKeyAgentRuntimeEndpointTests/testStaleOLEDTimeoutAndNotifyDoNotResealPreviousProfile|AhaKeyAgentRuntimeEndpointTests/testLegacyTaskPictureErrorFrameDoesNotYieldStandard'
# 163/163

swift test
# 786 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `b676b85` / 调度 `d9bdf11`）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`（generation 清场、context-aware ready、timeout 隔离）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyOLEDCompatibilityProfile.swift`（严格 0x94）
- 对应 OLED profile 测试与 Agent endpoint 测试
- 本任务卡、`docs/collab/board.md`、本证据

未改 BLE lifecycle/回连策略、Hook、WAL/XPC wire、UI/assembler、`Package.swift`、安装器/identity。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/collab/taskcards/WBS-1-UNIFIED-FIRMWARE.md`、`docs/firmware-client-baseline-2026-08-22.md`。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw 二进制/截图。

## 结论

C1R2 完成，停手提审。不自动进 C2，不打包、不安装、不刷机。accepted 后再开页面级 assembler。
