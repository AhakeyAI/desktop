# V03-C5-STUDIO-DUAL-SET-PICKER：密封 Rhino 双套露出套图 A/B

日期：2026-09-09 23:35–23:50 +08
ACK 用户 23:34 / Codex 23:31。产品基线 `5d1fe1db337099da9ffa7f143548472fd4435cf1`。执行 owner Cursor。
Agent Relay 继续暂停；未伪造 `review_decision`。未 overlay `/Applications`、未签名/打包/安装、未 HIL、未设备写、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。15L 保持 `blocked / awaiting C5D`。本次 B-write 授权已消费，不得复用。

## 行为

| 审查项 | 落地 |
|---|---|
| Studio 生产入口 | `AhaKeyTaskPictureProtocolPlan.make(sealedFact:)` / `make(sealedProfile:)`。presentation 写入 `device.oledCompatibility`，不读 snapshot capabilities |
| `.rhinoDualSet` | `setIndices == [0, 1]`，`supportsActiveSet == true`，四状态；inspector 分段条件仍是 `plan?.supportsActiveSet` |
| `.legacyStandard` / `.currentSessionCapable` | `[0]`，picker false |
| 缺 fact / `.unsupported` / 离线 / 非 active | plan nil，任务图不可提交 |
| 删除错误 seam | `AhaKeyStudioDevicePresentation` 不再调用 `make(mode: protocolMode, capabilities: nil)` |
| View | 状态格子与 caption 只读 `supportedTaskDisplayStates`；Runtime 更新只收敛非法选择；删除 `reconcileActiveTaskPictureSetsFromDevice` |
| B-only 冻结契约 | 未改 C2 assembler。A 五条 `writeConfirmed` + dirty B done unknown → 未确认 `requiresOverwriteConfirmation`；确认后 mask 仅 B |

`make(mode:capabilities:)` 与 `make(_ context:)` 仍给 Agent/BLE/planner。Studio presentation 不得再走 `capabilities: nil`。

## 反例

- active-device 密封 Rhino、snapshot capabilities 为空 → `[0,1]` / picker true
- `.current` 且无 sealed fact → plan nil，即使 `protocolMode == .current`
- Standard / current session / nil / unsupported → 无双套
- 另一设备的 Rhino fact 不得打开 active device picker
- 离线投影丢弃已密封 Rhino plan
- 合法编辑 B（index 1）在 `[0,1]` 下保持 1；仅当 indices 收敛到 `[0]` 才回到 0
- 在线 Rhino 露出 picker 时零 FIFO / 零 screen operation
- A 已确认 baseline + 未确认首次 B → schema=3 overwrite confirmation，不伪造 whole-object

## 门禁

```
swift test --filter 'AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyStudioPackageAssemblerTests'
# 94 passed

swift test
# 加 page-interaction 两例前：1130 tests / 2 skipped / 0 failures
# 加两例后一次：1132 / 2 skipped / 1 failure
#   AhaKeyAgentRuntimeEndpointTests.testConcurrentAppliesFromTwoClientsSerializeAndDrain
#   （历史 flake：串行排队竞态；不在 C5D 白名单，未修）
# 该 case 单独复跑 passed
# 第二次全量：1132 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK（既有 NSLock/Sendable 警告，非本卡引入）

./scripts/check-release-identity.sh
# release identity ok；embedded JSON 未改 channel: "v0.2" / productVersion: "0.2.1"

git diff --check
# DIFF_CHECK_OK
```

Identity：`ReleaseIdentity.json` / embedded JSON 未改：`channel: "v0.2"`，`productVersion: "0.2.1"`。

## 审查范围（相对 `5d1fe1d`）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyTaskPictureProtocolPlan.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyTaskPictureProtocolPlanTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioRuntimeDerivationTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioPackageAssemblerTests.swift`
- 本证据；任务卡 Cursor ACK/完成记录

未改 `docs/collab/board.md` 进本提交：工作区该文件另有未提交固件 1.7B 协作记录（约 +803），不吞入 C5D range。C5D ACK/完成已写在任务卡与本证据；现场 board 末尾另有 append 供阅读。

未改 C2 assembler 规则、C3 schema/WAL/CAS/executor、Agent/BLE 协商、ReleaseIdentity、安装器、Hook、固件、`queue.md`。未签名/安装/HIL/设备写。

## 结论

C5D 把 Studio 套图 A/B 分段接到 active-device 密封 OLED fact。Rhino 必须露出 picker；Standard / session / 缺 fact / 离线 / 他机 fact fail-closed。选择 B 本身不创建 operation。停手提审。HIL B-only 真写仍需新 USER-GATE，且须等本卡 accepted。
