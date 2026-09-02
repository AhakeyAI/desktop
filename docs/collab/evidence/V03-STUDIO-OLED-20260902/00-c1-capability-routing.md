# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C1：能力识别与 planner/opcode 路由

日期：2026-09-02 23:45–23:58 +08
ACK Codex `526e09d` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C2 UI assembler 或 HIL。未改 `queue.md` 状态。

## C1 行为

单一 `AhaKeyOLEDCompatibilityProfile`，输入只能是已验证的 capability / 协议事实，禁止用固件版本字符串猜测：

| 剖面 | 识别 | 图片 opcode |
|---|---|---|
| `legacyStandard` | 无 `0x99`、固件 1.x、且 0x94 证实任务图 | `0x80`、`0x82`、`0x93`；禁止 `0x95/0x97/0x98/0x9A/0x9B` |
| `rhinoDualSet` | 已解析 protocol v3 + `setCount ≥ 2`（Gitee/Local 14/22/26B） | `0x80`；`0x9B/0x9A` 仅当 session 明确广告；`0x95` + `0x97`；禁止 `0x98`、`0x82`、`0x93` |
| `currentSessionCapable` | 已解析 v3 + session flag 且非双套 | `0x9B/0x9A` + `0x95/0x97`；禁止裸 `0x80`、`0x82`、`0x93`、`0x98` |
| `unsupported` | 协商中、畸形/短帧、零计数、未知 v3、`.legacy` 混 v3 caps、`.legacyBaseOnly` | 零图片 opcode；`allowsConfigurationPlan == false` |

planner `plan(...)` 与 mapper `program` / `baseConfigurationProgram` 在写入前走同一剖面。未知或畸形能力 fail-closed，不生成 ingest/apply 程序。`AhaKeyTaskPictureProtocolPlan.make(.current, nil)` 仍保留旧 UI 默认（双套可编辑）；带 caps 时 fail-closed，除非剖面允许。

机械配套：`AhaKeyDeviceProgramStep.bindDefaultPicture`（0x82）与 `bindLegacyTaskPicture`（0x93），以及 `AhaKeyWireProgram` 编码。Agent BLE lifecycle / Hook / WAL/XPC wire / 安装器 identity 未改；mapper `profile:` 默认解析，避免 Agent 签名变化。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyOLEDCompatibilityProfileTests|AhaKeyFirmwareCapabilitiesTests|AhaKeyConfigurationPlannerTests|AhaKeyConfigurationStepMapperTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyWireProgramTests'
# 101/101

swift test --filter 'AhaKeyCaps14CrossContractTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyReleaseV02WiringTests|AhaKeyReleaseFeaturePolicyTests'
# 28/28

swift test
# 774 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK
```

定向未回退：`AhaKeyOLEDCompatibilityProfileTests` 13/13；capabilities 13/13（含 14/22/26B → Rhino dual-set）；planner 24/24；step mapper 20/20（Standard / Rhino / current session / unsupported 零程序）；protocol plan 22/22；wire 9/9（含 0x82/0x93 字节）；caps14 5/5；Hook 三态 4/4；XPC client 14/14。旧键盘 `0,0` 不参与 C1 失败判定。

本卡范围 `git diff --check` 通过。

## 审查范围（相对 `526e09d` / 产品基线 `1ed560b`）

新增：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyOLEDCompatibilityProfile.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyOLEDCompatibilityProfileTests.swift`

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationPlanner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyDeviceProgramSteps.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyTaskPictureProtocolPlan.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyWireProgram.swift`（穷尽 switch 编码 0x82/0x93）
- 对应 `Tests/AhaKeyConfigSharedTests/*Capabilities*`、`*Planner*`、`*StepMapper*`、`*TaskPictureProtocolPlan*`、`*WireProgram*`
- 本任务卡、`docs/collab/board.md`、本证据

未改 Studio Views/Models/facade assembler、Agent BLE lifecycle、Hook、WAL/XPC 生产路径、`Package.swift`、安装器。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/collab/taskcards/WBS-1-UNIFIED-FIRMWARE.md`、`docs/firmware-client-baseline-2026-08-22.md`。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw 二进制/截图。

## 结论

C1 完成，停手提审。不自动进 C2，不打包、不安装、不刷机。accepted 后再开 Studio scoped assembler。
