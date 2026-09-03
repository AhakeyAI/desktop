# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C2：page-diff model 与 scoped assembler

日期：2026-09-03 20:04–20:18 +08
ACK Codex 20:00 / `lastReviewedCommit=7f87db3` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3/C4/C5/HIL。未改 `queue.md`。本提交不含验收前已有的 Codex board/queue/status/裁决 diff。

## C2 行为

| 审查项 | 落地 |
|---|---|
| 唯一字段归属 | `AhaKeyStudioFieldOwnership.page(for:)`：每个 field ID 只映射一个 page/object ID（key/lights/screen/lever/power） |
| 三级 baseline | `verified` / `writeConfirmed` / `unknown`。严格 no-op 仅 verified 等值，或与同一次写入精确相同的 writeConfirmed；dirty + unknown 永不为 no-op |
| 单页冻结快照 | assembler 只读 `pageID` 上的字段；其它页 dirty 直接丢弃。mapping 的 `frozenPageSnapshot` 同样只导出本页 |
| 零差异 recording seam | `submitFrozenPage` 只返回 assembly，不 ingest/apply、不创建 Runtime operation。`pageSubmitRecordingCountsForTesting()` 与 transport requestLog 均为 0 |
| A/B 独立 dirty | 哪套 dirty 写哪套；两套 dirty 都写；只激活用户 `selectedTaskSet`。`bindsDefaultAnimation = false`，不镜像 idle |
| Standard 不伪造 `0x97` | `scopedScreenActivation` 对 `.legacyStandard` 设 `emitsSetActiveSetOpcode = false` |
| 整组 / unknown | Standard 整组协议且 dirty unknown → `requiresOverwriteConfirmation`；缺可信页缓存 → `missingTrustedPageCache`；unsupported → 不组包 |

既有 `assemble(modes:)` / `apply(modes:scope:)` v0.2 路径未改。不实现 operation UUID/FIFO/续传/baseline 推进（C3），不改 Views（C4）。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests'
# 53/53

swift test
# 806 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `7f87db3` / 调度 20:00）

新增：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioPageModelTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioDraftPackageMappingTests.swift`

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPackageAssembler.swift`（scoped assembler）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyOLEDSyncPlan.swift`（scoped 激活，Standard 不发 `0x97`）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioRuntimeFacade.swift`（pre-submit recording seam）
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioDraftPackageMapping.swift`（单页冻结映射）
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioPackageAssemblerTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyOLEDSyncPlanTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioRuntimeFacadeTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 Agent/BLE/XPC/CAS/WAL、Views、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/collab/taskcards/WBS-1-UNIFIED-FIRMWARE.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的任务卡 C2 裁决与 status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C2 完成，停手提审。不自动进 C3，不打包、不安装、不刷机。
