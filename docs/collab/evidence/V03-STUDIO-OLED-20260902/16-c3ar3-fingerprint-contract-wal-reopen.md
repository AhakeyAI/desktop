# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3AR3：fingerprint↔contract 双射、wire opcode 与真实 WAL reopen

日期：2026-09-04 18:46–19:08 +08
ACK Codex 18:10 / `lastReviewedCommit=1eeef9b613539d9befdb38f331008ff0e0b9a555` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3B/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3AR3 行为

| 审查项 | 落地 |
|---|---|
| fingerprint↔fieldMask 双射 | contract 统一校验要求 `compatibilityFingerprint.actions` 的 fieldID 与冻结 `fieldMask` 精确一一对应；拒绝重复、缺失、多余与非 canonical 顺序 |
| picture×binding 交叉闭合 | 每个 resource binding 必须有对应 picture action，且 field/set/state/slot 一致 |
| 实际 wire identity | 非图片 action 显式持久化 opcode/必要 subtype；key=`0x73`+`0x73/74/75`，light=`0x84/0x85`，active=`0x97`；status/FPS/voice 无设备命令则禁止携带 opcode，不得用 enum 名反推或填 capability set |
| operation-wide cardinality | prepare（`0x80/0x9B`）与 defaultBind（`0x82`）提升到 fingerprint 级 0/1，不再把一次 prepare 重复挂到每个图片 field；per-field picture 只登记 bind opcode |
| 真实 WAL reopen | 先 `accept` 合法 schema=2 包，再篡改 sqlite package blob，经 `AhaKeyRuntimePersistentStore` 重开；recovery/queue/transaction 全部 fail-closed，无队列投影 |
| 负例矩阵 | 替换为另一合法 action、重复 action、乱序、合法语义配错误 opcode、picture logicalSet 与 binding 不一致；保留 `0xff`/slot=2/缺 slot/nonpicture-with-slot/family activation 反例 |

不实现 BLE/transaction execution、自动续传、60 秒放弃、baseline 推进或 C4 UI。未改 C2 assembler 语义。C3AR2 已关闭的显式 binding / typed ResourceIdentity / 单 strict CodingKey 保持。

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

## 审查范围（相对 `1eeef9b` / 调度 18:10）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageOperation.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageSemantic.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageOperationTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 Agent BLE/executor、transaction runner/engine、XPC transport/server wire plumbing、Views、Hook、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3AR3 完成，停手提审。不自动进 C3B，不打包、不安装、不刷机。
