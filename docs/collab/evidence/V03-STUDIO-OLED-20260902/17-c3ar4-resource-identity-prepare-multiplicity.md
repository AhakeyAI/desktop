# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3AR4：resource identity 不可交换与 prepare per-chunk multiplicity

日期：2026-09-04 21:27–21:59 +08
ACK Codex 20:13 / `lastReviewedCommit=190370ccc63b4e231c90afe54e6c12fc162bfe8f` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3B/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3AR4 行为

| 审查项 | 落地 |
|---|---|
| picture action↔binding identity | 同一 `fieldID` 下比较 `logicalID` + SHA-256 + `byteCount` + `mediaType` 与 `encodedFrameCount`；canonical `taskAssetIdentifier(mode, physicalSlot, state)` 必须匹配。禁止只比 field/resource 集合或数组位置 |
| prepare multiplicity | fingerprint 以 `prepareStrategy {opcode, perChunk=true, encodedFrameBytes=25600, chunkBytes=4096}` 持久化；`prepareCount = encodedFrameCount * chunksPerFrame`（1 帧 = 7 次，与 `resourceUploadProgram` 同构）。default bind 仍至多一次 |
| family wire 单一来源 | `Family.pictureWire()` 是 prepare/bind/session/binding/activation 表；family validator 只对照该表，不再并列写 `0x93/0x95/0x80` |
| 真实 WAL reopen | 既有 helper 改为直接写 `resource → source bytes`；新增 Standard 三态 coordinated identity swap、Rhino A/B identity swap、key `0x73`+错误 subtype、prepare `perChunk=false` / opcode `255` / 非生产 `chunkBytes`。recovery/queue/transaction fail-closed，零投影 |

不实现 BLE/transaction execution、自动续传、60 秒放弃、baseline 推进或 C4 UI。未改 C2 assembler 语义、`AhaKeyDeviceProgramSteps`、Agent/XPC/Views。C3AR3 已关闭的 fieldMask 双射 / opcode / 真实 reopen 路径保持。

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

## 审查范围（相对 `190370c` / 调度 20:13）

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

C3AR4 完成，停手提审。不自动进 C3B，不打包、不安装、不刷机。
