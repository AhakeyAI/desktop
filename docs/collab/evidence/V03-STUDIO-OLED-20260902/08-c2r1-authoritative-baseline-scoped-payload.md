# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C2R1：authoritative baseline 与 complete scoped payload

日期：2026-09-03 20:32–20:45 +08
ACK Codex 20:28 / `lastReviewedCommit=2fc0523` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3/C4/C5/HIL。未改 `queue.md`。本提交不含验收前已有的 Codex board/queue/status/裁决 diff。

## C2R1 行为

| 审查项 | 落地 |
|---|---|
| 权威 baseline 分离 | `AhaKeyStudioFieldAuthority` 携带 device value + trust + provenance。`lastSyncedDraft` 只比用户 dirty；nil 不得 fallback 到 `self`。local/absent 不能升格为 verified |
| unknown 不得 no-op | `isStrictNoOp` 不再看 `isDirty`。unknown 即使标 clean 也不是 no-op；Rhino/Standard dirty unknown 一律 `requiresOverwriteConfirmation` |
| 整组完整性 | ownership `requiredFields` 按 profile+选中逻辑套列出必需字段；确认后仍缺则 `missingTrustedPageCache`，不猜测补齐 |
| typed field value | `AhaKeyStudioFieldValue` 为 keyAction/text/optionalText/integer/taskAsset；assembler 不再拼/拆 fingerprint |
| 单一 ownership | `fieldIDs` / `requiredFields` / `isWritable` 驱动 mapping 与 assembler。lever/power 从可写集排除，提交 `unsupportedPage` |
| scoped payload | `AhaKeyStudioScopedWritePlan.values` 带每个写入字段的 typed 值 |
| Standard 单套 | 逻辑 A/B 映射到物理 set 0；不产生 set-1 资源，`writeTaskSetB=false` |

既有 Rhino B-only、其它页 dirty 丢弃、不镜像 idle、zero transport call 保留。不实现 operation UUID/FIFO/续传/baseline 推进（C3），不改 Views（C4）。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests'
# 64/64

swift test
# 817 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `2fc0523` / 调度 20:28）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPackageAssembler.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyOLEDSyncPlan.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioDraftPackageMapping.swift`
- 对应 5 个精确测试（含 C2R1 反例）
- 本证据；board/任务卡仅追加 Cursor 执行记录

`AhaKeyStudioRuntimeFacade.swift` 本轮无产品 diff（仍只返回 assembly，ingest/apply=0）。未改 Agent/BLE/XPC/CAS/WAL、Views、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的任务卡 C2R1 裁决与 status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C2R1 完成，停手提审。不自动进 C3，不打包、不安装、不刷机。
