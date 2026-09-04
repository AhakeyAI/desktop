# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3AR1：资源 identity / 真实 fingerprint / 统一 FIFO

日期：2026-09-04 14:53–15:41 +08
ACK Codex 14:52 / `lastReviewedCommit=d30d6796bf8af8c6dce767a2e12b03a4a4ed0a1a` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3B/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3AR1 行为

| 审查项 | 落地 |
|---|---|
| 资源 identity | package 携带 verified SHA-256 / byteCount / media type / logical ID；canonical desired 与 taskAsset 绑定 digest；同 logical ID 不同字节改变 identity 并冲突 |
| base fingerprint | 调用方显式提供开始前对象 canonical content/CAS digest；空数据 fail-closed；不得由 page/mask/profile 冒充 |
| compatibility fingerprint | typed family/opcodes/slots/geometry/activation；由本次 plan 实际 emitted 动作生成；status-only / active-only / picture-write 可区分；禁键与非法 family 组合拒绝 |
| schema 精确匹配 | schema=2 必须完整 pageOperation；schema=1 必须 nil；0/999 拒绝，不静默改写 |
| typed ledger | pendingField / pendingResource(logicalID, sha256) 仅合法组合；decoder 拒绝 kind/optional-ID/confirmed data clump；与 field mask 和 package resources 精确一致 |
| Middle Man | 删除 RuntimeStore `pageOperationProjection` 与 `AhaKeyRuntimePageOperationProjection` |
| 同设备 FIFO | schema=1/2 在 `updateOperation` / `commitOperationOutcome` 统一检查；非 head 不得 running/paused/resumable/completed/partial-commit；排队项可 cancellationRequested / failedWithoutWrites 离队；两设备独立；v4 迁移/reopen 顺序保持 |

不实现 BLE/transaction execution、自动续传、60 秒放弃、baseline 推进或 C4 UI。C2 冻结契约未回退。file-before-WAL、CAS 配额、事务原子性、终态窗口与既有 revision 语义未改执行路径。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests'
# 158/158

swift test
# 859 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `d30d679` / 调度 14:52；当前 HEAD `05f4cf2` 含并行固件文档）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageOperation.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioRuntimeFacade.swift`（仅组装签名与旧 peer fail-closed）
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`（删除无增值 projection）
- 对应精确测试与值模型测试
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 Agent BLE/executor、transaction runner/engine、XPC transport/server wire plumbing、Views、Hook、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3AR1 完成，停手提审。不自动进 C3B，不打包、不安装、不刷机。
