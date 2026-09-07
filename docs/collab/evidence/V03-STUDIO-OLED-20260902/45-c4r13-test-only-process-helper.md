# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R13：test-only process helper / stable WAL contention proof

日期：2026-09-07 16:16–16:33 +08
ACK 用户转发的 Codex C4R12 未通过与 C4R13 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`；C4R10 已通过项冻结 @ `b514f1f`；C4R11 已通过项冻结 @ `dcb219b`。C4R12 已通过项冻结。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R13 行为

| 审查项 | 落地 |
|---|---|
| 生产 probe 删除 | Shared 不再包含 `AHAKEY_C4R12_CHILD_*`、`AhaKeyRuntimeStoreProcessWriteProbe` 或 `Darwin.exit`。Store init 不再识别测试环境变量 |
| test-only helper | 独立 executable `AhaKeyRuntimeStoreProcessProbe` 位于 `Tests/AhaKeyRuntimeStoreProcessProbe`，由 test target 依赖；不编入 App/Agent/Shared |
| READY→MUTATE | child 先 `Store()`+`health()` 再输出 `READY`；parent 持 `withExclusiveAccess` 后才发 `MUTATE`；child 此时才 `accept` 真 page-scoped WAL 写。持锁期间无输出，放锁后 `GOT_LOCK` |
| `sharesLock` | 改为 internal + `withStoreLease`。A.close 后 A 的 `sharesLock` 抛 `"mutation fence is closed"`；B 仍可 `sharesLock` |
| inode 门稳定 | `testRootDeleteRecreateDoesNotLockStaleInode` 只再用 native helper 的非阻塞 `flock`，不再在持锁期间拉起测试包/python |

C4/C4R1–C4R12 已成立语义冻结（legacy-empty marker 迁移、`O_CREAT\|O_EXCL`、精确 16-byte framing、per-Store close 主入口、unlock quarantine、root-shared generation 等）。C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor 未改行为。未改 Studio 已验收交互、Hook/安装器/固件。

## 反例

- 生产 `Sources/**/*.swift` 不含 `AHAKEY_C4R12` / process probe 符号；Store init 在设置这些环境变量后仍正常 `health()`，不退出、不写 synthetic package。
- parent/child 都打开同一 root 并 `READY` 后，parent 持 mutation 临界区时 child `accept` 阻塞；放锁后 child `GOT_LOCK`。
- A.close 后 A.`sharesLock` 拒绝；B.`sharesLock(with: B)` 仍成功。
- root 删除重建：旧 inode 对新 lockfile `GOT_LOCK`；新 fence 持锁时 raw `flock` 为 `BLOCKED`。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 连续 5 轮 369/369

swift test
# 1032 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

本轮全量首次即 1032/2 skipped/0。

## 审查范围（相对 `ebb30e2` / C4R13 开放）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyRuntimeStoreProcessProbe/main.swift`（新增）
- `ahakeyconfig-mac/Package.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。未改 `AhaKeyAgent.swift`。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R13 把跨进程 Store 竞争从生产 Shared 挪到独立测试 helper，并用 READY→MUTATE 证明已打开连接上的真 WAL 写串行；`sharesLock` 纳入 close 门。停手提审，不自动进 C5。
