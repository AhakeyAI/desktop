# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C2R4：whole-group 覆盖确认与 selected 范围闭包

日期：2026-09-04 07:22–07:35 +08
ACK Codex 07:27 / `lastReviewedCommit=893486dadfa5f15ef0e8e677db8c10e2faf57426` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C2R4 行为

| 审查项 | 落地 |
|---|---|
| Standard whole-group 确认 | `writingPictures && wholeGroup` 在扩入 required siblings **之前**要求 `overwriteConfirmed`。verified dirty picture 补 unknown siblings 未确认 → `.requiresOverwriteConfirmation`；确认后 `overwriteSemantic=true` |
| 扩入后重核 | 扩入 required 后重新核验整个 emitted set 的 unknown 与 typed consumability；缺可信 payload → `missingTrustedPageCache` |
| frozen selected 范围 | picture 或 dirty activeSet 时 `selectedTaskSet ∈ 0...1`，禁止 clamp 后继续写/激活。`scopedScreenActivation` 对越界 selected 返回 nil |
| Standard activeSet | dirty activeSet 在 emitted-filter 前做 typed/range/consistency 校验。合法 activeSet-only 仍 `.noOp`；malformed/越界 fail-closed |
| 单一 FieldActionKind | typed 校验、emitted 过滤、动作生成、空动作判断均由 `actionKind(of:)` 驱动 |
| production-shape | 真实 draft→snapshot：Standard picture+active、current activeSet-only、malformed typed、picture-only selected=-1/2、unknown siblings 未确认/确认 |

既有 C1/C2/C2R1/C2R2/C2R3 冻结行为保留。不实现 operation UUID/FIFO/续传/baseline 推进（C3），不改 Views（C4）。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests'
# 84/84

swift test
# 837 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `893486d` / 调度 07:27）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPackageAssembler.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyOLEDSyncPlan.swift`
- 对应精确测试（assembler / mapping / OLEDSyncPlan）
- 本证据；board/任务卡仅追加 Cursor 执行记录

`AhaKeyStudioPageModel.swift`、`AhaKeyStudioRuntimeFacade.swift`、`AhaKeyStudioDraftPackageMapping.swift` 本轮无产品 diff。未改 Agent/BLE/XPC/CAS/WAL、Views、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的 C2R4 裁决与 status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C2R4 完成，停手提审。不自动进 C3，不打包、不安装、不刷机。
