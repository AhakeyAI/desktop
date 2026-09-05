# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4：Studio 页面交互 + 设备 FIFO

日期：2026-09-05 21:58–22:25 +08
ACK 用户确认进入 C4，以及 Codex 19:31 开放 C4。C1–C3 accepted @ `c6e0762`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4 行为

| 审查项 | 落地 |
|---|---|
| 普通页 / 屏幕页 / 覆盖 / no-op | `AhaKeyStudioPageChrome`：写入当前页 / 写入并激活 / 覆盖写入此页 / 无修改（禁用） |
| 页锁 + 多页并行 | 排队/写入/等待重连锁当前页；其他页仍可编辑/提交 |
| 同页去重 | store `pageAlreadyInFlight`；映射存在即拒绝第二份 ingest/apply |
| 页内状态 | 有修改 / 排队中 / 写入中 / 等待重连 / 部分完成 / 已写入待验证 / 已同步 / 冲突 / 失败 |
| UUID | 只在权限诊断「页面写入」显示 |
| 底部 FIFO | 沿用 `snapshot.operations` 非终态顺序；显示当前页标题 + 后续数量 |
| queued 可移除 / running 拒绝取消 | `removeQueuedPage` 仅 `.accepted`；running 抛 `runningCannotBeCancelled`；`canCancelRunning` 恒为 false |
| 60s abandon | UI 与 Runtime 共用 `AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration`；未满 60s 不显示「放弃未完成写入」 |
| residual-only retry | `overlayResidualOnly` 把非 residual 收成 writeConfirmed no-op，再走同一 `commitFrozenPage` |
| 唯一写入口 | `submitFrozenPage` 仍只预检；真正提交只走 `commitFrozenPage` → 已验收 assembleScopedPage + assemblePageScopedPackage |

C2 assembler 冻结语义与 C3 Runtime/WAL/BLE executor 未改。未改 Hook/安装器/固件。

## 反例

- 多页并行：key 页 queued、灯条页 running 时，第三页仍 `canSubmit`；两页 `commitFrozenPage` 得到两个 operation。
- 同页重复禁止：非终态或已映射未入快照时 `pageAlreadyInFlight`。
- queued 移除 / running 拒绝取消：`.accepted` 走 `requestCancellation`；running 本地拒绝且不取消。
- 60 秒放弃门：断连 59s `canAbandon=false`；满 60s 才 `requestAbandon`。
- partial 只重试 residual：A/B 双 dirty 只留下套图 B residual 时，plan 仅 `writeTaskSetB` 并激活选中套。
- A/B 双 dirty 只激活当前套：同上，`activateTaskSet=1`。
- Standard 无 `0x97`：`legacyStandard` overwrite write plan `emitsSetActiveSetOpcode=false`。
- 严格 no-op：`commitFrozenPage` 对 verified 等值快照 ingest=0、apply=0、无 operation；未知未确认覆盖同样零 transport。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests'
# 293/293

swift test
# 971 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `c6e0762` / C4 开放）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioRuntimeFacade.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioModels.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioPageModelTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioRuntimeFacadeTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 Runtime/WAL/BLE executor、Hook/安装器/固件。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4 把 Studio 写入收成当前页交互和设备 FIFO，只消费 C2/C3 已验收事实源。停手提审，不自动进 C5。
