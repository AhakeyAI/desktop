# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3A：page-operation contract 与 WAL ledger / FIFO

日期：2026-09-04 08:09–14:42 +08
ACK Codex 08:08 / `lastReviewedCommit=18eb05554fecdcfea8d68d54559e0bb418da740a` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3B/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3A 行为

| 审查项 | 落地 |
|---|---|
| page-operation contract | schema=2 package 持久化 page scope、field mask、stable device ID、object/compatibility fingerprint 与 pending 确认 ledger |
| 旧 JSON / 旧记录 | schema=1 省略 `pageOperation`；v4 WAL 缺 `queue_order` 可迁移重开；旧语义恢复 |
| 新页面写证明 | 缺 page scope / mask / device / fingerprint 的 schema=2 请求 fail-closed，不猜测升级 |
| compatibility fingerprint | 只含协议族、实际 opcode、物理槽几何、session、activation；battery/RSSI/path/progress 等禁键拒绝 |
| operation-ID 冲突 | 同一 ID + 不同 canonical desired/page contract 拒绝；相同内容可幂等重放 |
| 同设备 FIFO | durable `queue_order`；paused head 阻塞后项 `.running`；两设备队列独立；崩溃重开顺序不变 |
| 旧 peer | snapshot 未广告 schema=2 时 facade 组装 fail-closed，零 ingest/apply/transport |
| C2 预检 | `submitFrozenPage` 仍只返回 scoped plan，零 Runtime operation |

不实现 BLE/transaction execution、自动续传、60 秒放弃、baseline 推进或 C4 UI。C2 冻结契约未回退。file-before-WAL、CAS 配额、事务原子性、终态窗口与既有 revision 语义未改执行路径。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests'
# 154/154

swift test
# 855 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `18eb055` / 调度 08:08）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageOperation.swift`（新增）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioRuntimeFacade.swift`（仅组装与旧 peer fail-closed）
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`（只读投影）
- 对应精确测试与新值模型测试
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 Agent BLE/executor、transaction runner/engine、XPC transport/server wire plumbing、Views、Hook、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3A 完成，停手提审。不自动进 C3B，不打包、不安装、不刷机。
