# V03-C5-STUDIO-DUAL-SET-PICKER：C5DR1 启动选择转移

日期：2026-09-10 00:04–00:13 +08
ACK 用户 00:03 / Codex 23:57。产品基线 `5d1fe1db337099da9ffa7f143548472fd4435cf1`；C5D 父提交 `6f47bd8541e289ded26b6bcebd2aa10bb7cade84`。执行 owner Cursor。
Agent Relay 继续暂停。未 overlay `/Applications`、未签名/打包/安装、未 HIL、未设备写、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。15L 保持 `blocked / awaiting C5DR1`。旧 B-write 授权不得复用。

## 行为

| 审查项 | 落地 |
|---|---|
| P1 无 plan | `afterDraftRefresh` 空 indices 保留 draft，不得写成 A |
| P1 nil→Rhino | `afterPlanChange(previous:nil)` 从当前 mode draft 恢复合法 B，即使 UI 已被写成 0 |
| P1 等价刷新 | 已有 Rhino plan 时保留仍合法的用户选择 |
| P1 Rhino→Standard | 才收敛到 0 |
| P1 监听 | View 监听完整 `taskPictureProtocolPlan`，不再只听 `setIndices`；`protocolMode` 不再改选择 |
| P2/P3 builder | `make(sealedProfile:)` 收为 private；family 常量走 `legacyStandardPlan` / `currentSetAwarePlan`；公开 Studio 入口仍只 `make(sealedFact:)` |
| P3 投影 | 删除 Studio `activeTaskPictureSets` presentation/store 投影（Agent/Runtime state 未动） |

View 只调用 `afterDraftRefresh` / `afterPlanChange`，不在 View 内另写一套归一化。nil/unsupported 不创建 operation/WAL、不写 draft。

## 反例

- saved draft B + 初始 plan nil 的 onAppear → 仍为 1
- UI 已被写成 0、draft 仍为 1、随后 sealed Rhino → 恢复 1
- Rhino B 等价 snapshot/re-render 仍为 1
- 用户已选 A 的等价 Rhino 刷新保持 0
- Rhino→Standard 收敛 0
- Rhino→nil/unsupported 保持 1，零 FIFO / 零 screen operation
- C5D 冻结项仍成立：active-device Rhino `[0,1]`、Standard/session/nil/offline/foreign fail-closed、B-only assembler

## 门禁

```
swift test --filter 'AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyStudioPackageAssemblerTests'
# 96 passed

swift test
# 1134 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./scripts/check-release-identity.sh
# release identity ok；channel: "v0.2" / productVersion: "0.2.1"

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `6f47bd8`）

增量 `6f47bd8...HEAD`。全 range 仍为 `5d1fe1d...HEAD`。

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyTaskPictureProtocolPlan.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyTaskPictureProtocolPlanTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioRuntimeDerivationTests.swift`
- 本证据；任务卡 Cursor ACK/完成记录

未改 `docs/collab/board.md` 进本提交：工作区该文件另有未提交固件协作记录，不吞入 C5DR1 range。C5DR1 ACK/完成写在任务卡与本证据。

未改 C2 assembler、C3 schema/WAL/CAS、Agent/BLE 协商、ReleaseIdentity、`queue.md`。未签名/安装/HIL/设备写。

## 结论

C5DR1 把无 plan 与已密封单套分开：启动不得把 saved B 打成 A；nil→Rhino 从 draft 恢复 B。停手提审。HIL B-only 仍需本卡 accepted 后的新 USER-GATE。
