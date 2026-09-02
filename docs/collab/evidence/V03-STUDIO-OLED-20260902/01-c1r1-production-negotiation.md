# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C1R1：生产协商与 fail-closed 路由

日期：2026-09-03 00:21–01:09 +08
ACK Codex `f35134a` / `lastReviewedCommit=4fda27b` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C2 UI assembler 或 HIL。未改 `queue.md` 状态。

## C1R1 行为

密封 `AhaKeyOLEDCompatibilityContext` 只能从 `AhaKeyReleaseNegotiationState` 构造，贯穿 Agent 协商、XPC ingest/apply preflight、planner、Plan、mapper、字节进度与事务 runner。禁止把 `protocolMode` / capabilities / profile 拼起来。

| 审查项 | 落地 |
|---|---|
| 生产路径固定 current | Agent planner/mapper/字节进度只读 `resolvedOLEDContext()`；mapper 不再缺省 `.current` |
| `.current + nil` | `AhaKeyTaskPictureProtocolPlan.make(.current, nil)` 返回 nil |
| 真 no-`0x99` Standard | 三次 `0x99` 无应答后发 `0x00` 再发 `0x94`（payload `mode=0,state=3`）；畸形 `0x99` 不回退 Standard；空 `AA BB 94 00 CC DD` 为 unknown，不是 Standard。不合成伪 v1 capability 帧 |
| set 几何 | planner 按**占用套数**（最高有资源的 set）和 `activeSet < setCount` 校验；JSON 仍冻结两套占位。Standard 占用 B 套 → `taskSetCountExceedsDevice`。mapper 只绑定 `setIndex < layout.setCount`，且 Standard 不发无 idle 槽的 `0x93 state=0` |
| 未知零 ingest/apply | Agent XPC ingest/apply 在 `store.accept` / `ingestResources` 前返回 `unsupported-protocol`；facade 抛 `unsupportedFirmware` 且 `requestLog=[]`；runner 在 `store.accept` 前抛 `unsupportedProtocol`。endpoint 测试断言 CAS 目录与 sqlite / WAL 零变化 |
| 完整命令序列 | Standard：`0x93 working`、`0x93 done`、`0x82(done 区间)`，禁止 `0x95/0x97/0x98/0x9A/0x9B`。Rhino dual-set：`0x95 set=0` idle/working/done 然后 `0x97 set=1`。current session `setCount=1`：`0x95 set=0` + `0x97 set=0`，无 `set=1`，资源步全是 `0x9B` |

`DeviceTransportCore` ready/reconnect 仍仅 current；Standard 通过 Agent 写前 context 放行，不调用 `negotiationFinished(.current)`。Studio Views/Models/assembler 未改。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyOLEDCompatibilityProfileTests|AhaKeyConfigurationPlannerTests|AhaKeyConfigurationStepMapperTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyFirmwareCapabilitiesTests|AhaKeyCaps14CrossContractTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyWireProgramTests|AhaKeyAgentRuntimeEndpointTests/testUnsupportedOLEDContextRejectsIngestAndApplyBeforeCASOrWAL|AhaKeyAgentRuntimeEndpointTests/testLegacyProbeFirmwareV1AndTaskPictureFrameYieldsStandardContext|AhaKeyAgentRuntimeEndpointTests/testFailedAcceptanceReturnsFailureNotAccepted'
# 158/158

swift test
# 781 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `4fda27b` / 调度 `f35134a`）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyOLEDCompatibilityProfile.swift`（密封 context、0x94 分类、写前 preflight）
- `AhaKeyConfigurationPlanner.swift`、`AhaKeyDeviceProgramSteps.swift`、`AhaKeyTaskPictureProtocolPlan.swift`、`AhaKeyConfigurationTransactionRunner.swift`
- `AhaKeyAgent.swift`（协商 context、legacy 实探、ingest/apply preflight）
- `AhaKeyStudioRuntimeFacade.swift`（写前 preflight；`installSnapshotForTesting` 不改 connection）
- 对应 Shared/Agent/facade 测试
- 本任务卡、`docs/collab/board.md`、本证据

未改 Studio Views/Models/assembler、Agent BLE lifecycle/重连、Hook、WAL 格式/XPC wire、`Package.swift`、安装器/identity。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/collab/taskcards/WBS-1-UNIFIED-FIRMWARE.md`、`docs/firmware-client-baseline-2026-08-22.md`。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw 二进制/截图。

## 结论

C1R1 完成，停手提审。不自动进 C2，不打包、不安装、不刷机。accepted 后再开 Studio scoped assembler。
