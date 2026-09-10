# V03-C5-STUDIO-ACTIVE-SET-EDIT-INTENT：C5F typed edit intent

日期：2026-09-10 14:20–14:50 +08
ACK 用户 14:20。产品基线 C5ER1 `fe984e806c0be7e873a291c3f3994bbc0e53780d`。执行 owner Cursor。
Agent Relay 继续暂停。未 overlay `/Applications`、未签名/打包/安装、未 HIL、未设备写、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。15L 保持 `blocked / awaiting C5F`。

## 行为

| 审查项 | 落地 |
|---|---|
| typed ledger | `AhaKeyStudioPageEditIntentLedger` 绑定 device / session / transport generation / pageID / profile / fieldID / typed value |
| picker setter | `selectedOLEDGIFSetBinding` 登记 `.screenActiveSet(modeSlot:)`；Runtime snapshot、页面出现、draft reload 不登记 |
| frozen mapping | `isDirty = localValueDiff or exactExplicitIntent`；不得把 Runtime authority 写回 `lastSyncedDraft` |
| 无 picker | current/local A=0 + authority B=1 → assembler no-op |
| C5ABR3 组合 | current/local A=0、authority writeConfirmed set1、explicit A=0、overwrite=true → `fieldMask == values.keys == {screenActiveSet:0}`、`activateTaskSet=0`、仅 `0x97`、零 resource/statusLine |
| 因果消费 | 复用 C5ER1 attempt token；exact accepted/no-op 才清对应 fields；`.requiresOverwriteConfirmation` / error 保留；迟到结果与 identity 不匹配不得清新 intent |

## 反例

- detached 红测正式化：`testReturningToLocalBaselineStillEmitsAuthoritativeActiveSetDifference` 走真实 draft→ledger picker→snapshot→assembler
- 无 explicit intent 的同一组合 → no-op；再明确选 A → active-only write
- 用户 A→B 且 B 已是 authority → no-op；旧 A intent 不可复活；再选 A → 新 active-only write
- confirmation 两击：第一次 `.requiresOverwriteConfirmation`（ingest/apply=0）；历史 completed 不清 pending；第二次同 identity 进入 Facade apply=1、fieldMask=`{screenActiveSet:0}`
- error / identity mismatch / 迟到 accepted 不得清后来新 intent；C5ER1 confirmation token 不回退

## 门禁

```
swift test --filter 'AhaKeyStudioPageEditIntentLedgerTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyStudioPageOverwriteConfirmationLedgerTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyStudioPackageAssemblerTests|AhaKeyStudioPageModelTests|AhaKeyStudioRuntimeFacadeTests'
# 188 passed

swift test
# 1151 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./scripts/check-release-identity.sh
# release identity ok；channel: "v0.2" / productVersion: "0.2.1"

git diff --check
git diff --check fe984e8
git diff --check 5d1fe1d
# DIFF_CHECK_OK
```

## 审查范围（相对 `fe984e8`）

增量 `fe984e8...HEAD`。全 range 仍为 `5d1fe1d...HEAD`。

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioDraftPackageMapping.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioPageEditIntentLedgerTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioDraftPackageMappingTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- 本证据；任务卡 Cursor ACK/完成记录

未改 `docs/collab/board.md` 进本提交：工作区该文件另有未提交固件协作记录，不吞入 C5F range。

未改 C2 assembler 决策、C3 schema/WAL/CAS、Agent/BLE、ReleaseIdentity、`queue.md`。未签名/安装/HIL/设备写。C5F accepted 后 A/B switch 仍须新的 USER-GATE。

## 结论

用户明确选择 A 不再被 local lastSynced A 吞成 clean。停手提审。
