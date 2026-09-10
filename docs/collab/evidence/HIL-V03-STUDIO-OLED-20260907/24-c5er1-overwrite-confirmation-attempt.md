# V03-C5-STUDIO-OVERWRITE-CONFIRMATION：C5ER1 attempt token

日期：2026-09-10 10:08–10:20 +08
ACK 用户 10:08 / Codex 01:52。产品基线 C5E `88e6003b39d317ddc547f5c6506d207fd6766dc7`。执行 owner Cursor。
Agent Relay 继续暂停。未 overlay `/Applications`、未签名/打包/安装、未 HIL、未设备写、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。15L 保持 `blocked / awaiting C5ER1`。

## 行为

| 审查项 | 落地 |
|---|---|
| attempt token | `beginAttempt(for:)` 铸造 opaque 单次 token，绑定 exact identity 与当时 `revision` |
| monotonic revision | `observeCurrentIdentity` 在任一 identity mutation（含 A→B→A）推进 revision 并清空 in-flight |
| result transition | `applyCommitResult` / `noteAttemptFailed` 同时核 token、当下 revision、current identity |
| stale `.requires` | 不得安装 pending；下一次 A 必须重新 `.requires`，再一次相同 A 才 confirmed |
| stale accepted/error/no-op | 不得消费另一 pending |
| P2 | 删除 `noteOperationsChanged`；历史 completed 不进入 ledger |
| View | `writeCurrentPage` 在 await 前 `beginAttempt`，返回后把 token 与当时 identity 交给 ledger |

C5E 冻结项未改：typed identity、pending「覆盖写入此页」、历史 completed 不清 pending、active-only `screenActiveSet:0` + `0x97` / 零 resource。

## 反例

- begin(A) → mutate B → mutate A → 旧 `.requires` 返回：pending 仍 nil
- device / session generation / transport generation / profile 来回同样作废
- 后开始的 attempt 替换 in-flight；旧 token 重放不得铸造或消费
- 捕获序列仍成立，且不再经过 operations 方法

## 门禁

```
swift test --filter 'AhaKeyStudioPageOverwriteConfirmationLedgerTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyStudioPackageAssemblerTests|AhaKeyStudioPageModelTests|AhaKeyStudioRuntimeFacadeTests'
# 165 passed

swift test
# 1143 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./scripts/check-release-identity.sh
# release identity ok；channel: "v0.2" / productVersion: "0.2.1"

git diff --check
git diff --check 88e6003
git diff --check 5d1fe1d
# DIFF_CHECK_OK
```

## 审查范围（相对 `88e6003`）

增量 `88e6003...HEAD`。全 range 仍为 `5d1fe1d...HEAD`。

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioPageOverwriteConfirmationLedgerTests.swift`
- 本证据；任务卡 Cursor ACK/完成记录

未改 `docs/collab/board.md` 进本提交：工作区该文件另有未提交固件协作记录，不吞入 C5ER1 range。

未改 C2 assembler 决策、C3 schema/WAL/CAS、Agent/BLE、ReleaseIdentity、`queue.md`。未签名/安装/HIL/设备写。C5ER1 accepted 后 A/B switch 仍须新的 USER-GATE。

## 结论

迟到异步结果不能再复活已作废确认。停手提审。
