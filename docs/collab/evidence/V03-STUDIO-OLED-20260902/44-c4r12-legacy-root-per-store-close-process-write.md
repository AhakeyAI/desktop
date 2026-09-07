# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R12：legacy-root migration / per-store close lease / process-write proof

日期：2026-09-07 14:22–15:52 +08
ACK 用户转发的 Codex C4R11 未通过与 C4R12 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`；C4R10 已通过项冻结 @ `b514f1f`；C4R11 已通过项冻结 @ `dcb219b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R12 行为

| 审查项 | 落地 |
|---|---|
| 原子 creator | `open(O_CREAT\|O_EXCL\|O_RDWR)`；`EEXIST` 再 `O_RDWR`。不再用 `fileExists`→`open` 决定初始化权 |
| legacy empty 一次迁移 | 空 lock 且 SQLite `runtime_metadata.mutation_generation_initialized` 不存在 → 在 flock 内写 16 字节 `AKG1` generation 0 并落 marker。C4R11 已有合法 framed record 但无 marker → 只补 marker |
| 事后 truncate fail-closed | 已有 marker 后空 lock 抛 `"mutation generation record is empty"`，不得再次迁移。crash 在写记录前（空文件、无 marker）下次 reopen 可恢复 |
| per-Store close lease | `AhaKeyRuntimeMutationFence` 是 interned Core 的 per-Store wrapper。`A.close` 先 `invalidateStoreLease()` 再关 SQLite 再 `releaseLease()`。A 的 `current()`/`withExclusiveAccess` 立即 `"mutation fence is closed"`；B 仍用同一 Core |
| 全入口 ensureOpen | 全部 public Store API 与 `prepare()` 先 `ensureOpen()`。关闭后不得碰 A 的 SQLite 指针 |
| 精确 16 字节 framing | `fstat` 必须为 0 或 16；非 16 抛 `"mutation generation record length is invalid"`。persist 为 `pwrite` 16 + `ftruncate(16)` + `fsync` |
| 跨进程 Store/WAL 写 | 子进程以 env `AHAKEY_C4R12_CHILD_ROOT` 打开真 Store 并 `accept` 冲突 page-scoped package。生产路径 env 未设则为 no-op |

C4/C4R1–C4R11 已成立语义冻结（unlock EINTR retry / 非 EINTR quarantine、cache detach-before-await、最后一条 lease 关闭后 fence 拒绝、root inode 替换的 raw-flock probe、fresh-reopen 稳定门、facts 写前 bump、root-shared generation、事务内 `terminal_order`、MainActor publish lock、exact-token retry、TerminalTransition 等）。C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor 未改行为，仅收口 legacy-empty 迁移、close lease 与精确 framing。未改 Studio 已验收交互、Hook/安装器/固件。C4R10 的 8 字节记录仍按长度损坏拒绝，不迁移。

## 反例

- 0.2.1/C4R10 形状：空 `.runtime-store.lock` + 已有 DB、删除 marker 后 reopen 迁移为 16 字节 `AKG1` generation 0；再次 truncate 拒绝。
- `O_CREAT\|O_EXCL` 创建空 lock 后 crash（未写记录、无 marker）：reopen 恢复并写成 framed record。
- 合法 16 字节后追加尾随字节：`current()` 拒绝 `"length is invalid"`。
- A/B 共享 Core；`A.close` 后 A 的 fence/`health`/`transaction`/`allocateAuthoritativeWriterLease` 拒绝，B 继续 `health`/读事务。
- 两任务同时首建：共享同一 Core，lockfile 恰好 16 字节。
- root 删除重建：旧 inode 对新 lockfile `GOT_LOCK`；新 fence 持锁时 raw `flock` 与真 Store `accept` 均为 `BLOCKED`；放锁后独立进程 `GOT_LOCK`。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 连续 5 轮 366/366

swift test
# 1029 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

定向门外的 `testConcurrentAppliesFromTwoClientsSerializeAndDrain` 不在 C4R12 白名单，未改该测试。本轮全量首次即 1029/2 skipped/0。

## 审查范围（相对 `dcb219b` / C4R12 开放）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。未改 `AhaKeyAgent.swift`。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R12 让 0.2.1/C4R11 以前合法存在的空 lock 可以一次迁移，把首建权收成原子 creator，把每条 Store lease 的 close 与全部入口 fail-closed，并把 generation 记录钉成精确 16 字节；跨进程反例打开真 Store 做冲突 WAL 写。停手提审，不自动进 C5。
