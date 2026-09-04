# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3AR2：显式 field→resource binding 与 typed emitted-action fingerprint

日期：2026-09-04 17:48–18:03 +08
ACK Codex 17:42 / `lastReviewedCommit=0f1f73ad0d4458da920944c64300ae96488a9025` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3B/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3AR2 行为

| 审查项 | 落地 |
|---|---|
| 显式绑定 | `fieldID → logical resource ID → verified digest/byteCount/mediaType`；按 C2 `taskAssetIdentifier(mode, physicalSet, state)` 精确消费，不再按 160×80/帧数猜测 |
| Standard 三态 | 同几何同帧数的 working/waiting/done 各绑一项；每字段/每资源恰好一次 |
| A/B 复用 | 相同 digest 必须分属不同 logical ID；Rhino logical 0/1 → physical 0/1 可区分 |
| emitted-action | canonical typed 列表：logical field/set/state、prepare/bind opcode、physical slot、geometry、session、activation |
| 非图片动作 | key shortcut/description、light mapping/brightness、status/FPS、active-only 按实际 command 可区分，不再空 opcode |
| wire 矩阵 | 拒绝 `0xff`、slot=2、picture-without-slot、nonpicture-with-slot、legacy-picture-without-implicit；伪造 fingerprint 无法 decode/WAL reopen |
| P3 | ledger 以 typed `ResourceIdentity` set 比较；strict decoder 共用 `AhaKeyRuntimeStrictCodingKey` |

不实现 BLE/transaction execution、自动续传、60 秒放弃、baseline 推进或 C4 UI。未改 C2 assembler 语义。C3AR1 已关闭的 identity/FIFO/schema 门保持。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests'
# 162/162

swift test
# 863 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `0f1f73a` / 调度 17:42）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageOperation.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageSemantic.swift`（新增 typed binding / emitted-action / 单一映射边界）
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageOperationTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 Agent BLE/executor、transaction runner/engine、XPC transport/server wire plumbing、Views、Hook、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3AR2 完成，停手提审。不自动进 C3B，不打包、不安装、不刷机。
