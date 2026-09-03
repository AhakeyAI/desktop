# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C2R2：emitted-plan exactness 与 Standard legacy 3 态

日期：2026-09-03 21:00–21:10 +08
ACK Codex 20:56 / `lastReviewedCommit=2e8e294` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C2R2 行为

| 审查项 | 落地 |
|---|---|
| Standard required 三态 | `requiredFields` 由 C1 `AhaKeyTaskPictureProtocolPlan.make(.standard).states` 派生，即 `legacyStates = working/waiting/done`。不使用 `TaskDisplayState.allCases`，不把 idle 纳入必需/mask/values/resources |
| required typed asset | `.write` 前每个 required/accepted task asset 必须是 typed asset、URL 存在、frame count > 0、160×80、identifier 可构造；任一失败 `missingTrustedPageCache`，不返回部分 `.write` |
| dirty-only accepted set | 受理集仅 `isDirty && !isStrictNoOp`。空集 `.noOp`。dirty unknown 需确认，确认后仍只写 dirty。Standard 整组只扩选中逻辑套的 required legacy states |
| emitted plan 一致 | 先过滤 logical fields，再派生 `fieldMask`/`values`/resources；`fieldMask == Set(values.keys) == acceptedIDs`。Standard A+B 选 B：mask/values 只有 B 的 legacy states，resources 全部 physical set0，A 不留 plan |
| 单一 ownership | 一份 descriptor registry 派生 `page(for:)`、`fieldIDs(on:)`、`isWritable`、`requiredFields`（writable 门禁 + C1 protocol plan） |

既有 device authority、typed value、key/light payload、lever/power `unsupportedPage`、无 physical set-1、Rhino B-only、其它页 dirty 丢弃、zero transport call 保留。不实现 operation UUID/FIFO/续传/baseline 推进（C3），不改 Views（C4）。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests'
# 68/68

swift test
# 821 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `2e8e294` / 调度 20:56）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPackageAssembler.swift`
- 对应精确测试（mapping / assembler / page model）
- 本证据；board/任务卡仅追加 Cursor 执行记录

`AhaKeyOLEDSyncPlan.swift`、`AhaKeyStudioRuntimeFacade.swift`、`AhaKeyStudioDraftPackageMapping.swift` 本轮无产品 diff。未改 Agent/BLE/XPC/CAS/WAL、Views、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的 C2R2 裁决与 status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C2R2 完成，停手提审。不自动进 C3，不打包、不安装、不刷机。
