# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C2R3：emitted-action exactness 与 typed payload 校验

日期：2026-09-04 07:01–07:14 +08
ACK Codex 21:28 / `lastReviewedCommit=011513f` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C2R3 行为

| 审查项 | 落地 |
|---|---|
| Standard activeSet-only | `screenActiveSet` 不在 Standard emitted set（无 `0x97`）。仅 dirty activeSet → `.noOp`，零 ingest/apply/transport |
| Standard picture + activeSet | picture 写入才记录协议内隐式激活（`activateTaskSet`、`emitsSetActiveSetOpcode=false`）；mask/values 不含 `screenActiveSet` |
| Rhino/current activeSet-only | 精确产生允许的 `0x97`：mask/values 只有 activeSet，无 resource，`emitsSetActiveSetOpcode=true` |
| typed payload | 每个 writable field 在 `.write` 前校验预期 case。status=`text`，FPS/activeSet=`integer`，key/light 为各自 typed case，task asset=`taskAsset`。类型错配、activeSet 越界或与 frozen selection 不一致 → `missingTrustedPageCache` |
| 零动作 | `fieldMask == values.keys == 实际 emitted logical actions`；无资源/status/FPS/`0x97`/key-light 时不得 `.write` |

既有 C1/C2/C2R1/C2R2 冻结行为保留。不实现 operation UUID/FIFO/续传/baseline 推进（C3），不改 Views（C4）。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests'
# 75/75

swift test
# 828 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `011513f` / 调度 21:28）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPackageAssembler.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyOLEDSyncPlan.swift`
- 对应精确测试（assembler / mapping / OLEDSyncPlan / facade）
- 本证据；board/任务卡仅追加 Cursor 执行记录

`AhaKeyStudioPageModel.swift`、`AhaKeyStudioRuntimeFacade.swift`、`AhaKeyStudioDraftPackageMapping.swift` 本轮无产品 diff。未改 Agent/BLE/XPC/CAS/WAL、Views、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的 C2R3 裁决与 status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C2R3 完成，停手提审。不自动进 C3，不打包、不安装、不刷机。
