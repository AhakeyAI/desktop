# V03-C5-STUDIO-OVERWRITE-CONFIRMATION：C5E 覆盖确认 ledger

日期：2026-09-10 01:23–01:40 +08
ACK 用户 01:23 / Codex 01:18。产品基线 `adfe2a62fb5a495de9c9172d7cd6fb9f096096d8`。执行 owner Cursor。
Agent Relay 继续暂停。未 overlay `/Applications`、未签名/打包/安装、未 HIL、未设备写、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。15L 保持 `blocked / awaiting C5E`。R2 授权已消费。

## 行为

| 审查项 | 落地 |
|---|---|
| typed ledger | `AhaKeyStudioPageOverwriteConfirmationLedger` 绑定 deviceID、session/transport generation、pageID、规范化 frozen semantics（忽略 `overwriteConfirmed`） |
| 单一 seam | View 去掉 `Set<PageID>`；Assembler 与 Facade 的 `.requiresOverwriteConfirmation` 都走 `applyCommitResult` |
| pending UI | pending 期间 chrome 强制 `覆盖写入此页`，即使 assembler 已是 `.write` / `写入并激活` |
| 第二次提交 | `shouldSubmitConfirmed` 才把 snapshot 的 `overwriteConfirmed=true` 送入 Facade |
| 历史 operation | `noteOperationsChanged` 不消费 pending；`mergeCompletedPageBaselines` 只更新展示，不再按 pageID 删除确认 |
| 身份变化 | draft 字段、A↔B、device、generation、profile、page 变化经 `observeCurrentIdentity` 丢弃旧 token |
| fail-closed | no-op / unsupported / missing cache / 抛错均清 pending |

View 只调用 ledger 的 `identity` / `shouldSubmitConfirmed` / `applyCommitResult` / `noteOperationsChanged` / `observeCurrentIdentity` / `applyingPendingPrompt`，不再另写一套 page Set。

## 反例

- 捕获序列：同页已有 completed `F2BAE385…` / `844F52E4…` → A active-only 第一次 `.requiresOverwriteConfirmation` → 再发布历史 operations → pending 仍在 → 第二次 `.accepted`
- 确认后的 plan 仅 `screenActiveSet:0`、真实 `0x97`、零 resource、不写 A/B 套图
- 其它页 / 其它设备 / failed terminal 不能消费 pending
- 改字段、切套图、换 device、换 generation、改 profile 后旧 token 拒绝
- no-op / unsupported / 失败 fail-closed
- C5D/C5DR1 picker 与 sealed Rhino fail-closed 未回退

## 门禁

```
swift test --filter 'AhaKeyStudioPageOverwriteConfirmationLedgerTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests|AhaKeyTaskPictureProtocolPlanTests|AhaKeyStudioPackageAssemblerTests|AhaKeyStudioPageModelTests|AhaKeyStudioRuntimeFacadeTests'
# 161 passed

swift test
# 1139 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./scripts/check-release-identity.sh
# release identity ok；channel: "v0.2" / productVersion: "0.2.1"

git diff --check
git diff --check adfe2a6
git diff --check 5d1fe1d
# DIFF_CHECK_OK
```

## 审查范围（相对 `adfe2a6`）

增量 `adfe2a6...HEAD`。全 range 仍为 `5d1fe1d...HEAD`。

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioPageOverwriteConfirmationLedgerTests.swift`
- 本证据；任务卡 Cursor ACK/完成记录

未改 `docs/collab/board.md` 进本提交：工作区该文件另有未提交固件协作记录，不吞入 C5E range。C5E ACK/完成写在任务卡与本证据。

未改 C2 assembler 决策、C3 schema/WAL/CAS、Agent/BLE、ReleaseIdentity、`queue.md`。未签名/安装/HIL/设备写。C5E accepted 后 A/B switch 仍须新的 USER-GATE。

## 结论

C5E 把覆盖确认从 page Set 收成 typed frozen identity ledger。历史同页 completed 不再清 pending；Gitee Rhino B→A active-set-only 可第二次进入 Facade。停手提审。
