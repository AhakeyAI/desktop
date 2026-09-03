# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C2R5：post-filter whole-group 触发与 typed 矩阵补齐

日期：2026-09-04 07:51–07:57 +08
ACK Codex 07:49 / `lastReviewedCommit=652727b44394795c7e690ea1aeefccf667fccbdb` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C2R5 行为

| 审查项 | 落地 |
|---|---|
| post-filter whole-group | 先 emitted filter；空 accepted set 立即 `.noOp`。`writingPictures` 只由 post-filter emitted task assets 决定，之后才 confirmation / required expansion |
| Standard idle-only | 未确认不要求覆盖；确认后也不扩写 working/waiting/done。`.noOp`，零 transport |
| Standard 未选中逻辑套 dirty | 同样 `.noOp`，不改写 selected set |
| 真 emitted picture | 仍保留未确认/确认两臂、unknown siblings 重核、selected 范围门与精确 mask/action |
| typed 矩阵 | 真实 draft→snapshot 受控变异补齐 keyDescription / keyVoicePreset / lightMapping / taskAsset；与既有五类合计九类，均在 `.write` 前 `missingTrustedPageCache` |

既有 C1–C2R4 冻结行为保留。不实现 operation UUID/FIFO/续传/baseline 推进（C3），不改 Views（C4）。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests'
# 86/86

swift test
# 839 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `652727b` / 调度 07:49）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPackageAssembler.swift`
- 对应精确测试（assembler / mapping）
- 本证据；board/任务卡仅追加 Cursor 执行记录

`AhaKeyOLEDSyncPlan.swift`、`AhaKeyStudioPageModel.swift`、`AhaKeyStudioRuntimeFacade.swift`、`AhaKeyStudioDraftPackageMapping.swift` 本轮无产品 diff。未改 Agent/BLE/XPC/CAS/WAL、Views、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的 C2R5 裁决与 status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C2R5 完成，停手提审。不自动进 C3，不打包、不安装、不刷机。
