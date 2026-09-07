# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R14：clean review range / MUTATING barrier / strict flock oracle

日期：2026-09-07 18:05–18:55 +08
ACK 用户转发的 Codex C4R13 未通过与 C4R14 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1–C4R12 已通过项冻结。C4R13 已通过项（生产 Shared 移除 env/`Darwin.exit` probe、独立 Tests helper、双 Store READY、放锁后 accept、`sharesLock` internal + close-aware）冻结。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。未改 Shared Store 语义。

## C4R14 行为

| 审查项 | 落地 |
|---|---|
| 净审查范围 | 相对 `ebb30e2` 只保留 C4R13/R14 产品/helper/测试/evidence 与 Cursor 当轮 append。`052b833` 夹带的 Codex/Zcode/firmware/old-status 从产品提交中撤出，保留为工作区手工 diff |
| MUTATING barrier | child 读到 `MUTATE` 后、调用 `accept` 前输出 `MUTATING`。parent 持锁期间先等到该 barrier，再断言 2.5s 内无 `GOT_LOCK`；放锁后 `GOT_LOCK` |
| flock oracle | `LOCK_EX\|LOCK_NB` 成功后必须 `LOCK_UN==0` 才报 `GOT_LOCK`。仅 `EWOULDBLOCK/EAGAIN` 报 `BLOCKED` 且 exit 0；`OPEN_FAILED`/`FLOCK_ERROR`/`UNLOCK_FAILED` 非零 |

C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor 未改。未改 Studio 已验收交互、Hook/安装器/固件。

## 反例

- `git diff --stat ebb30e2...<new>` 不含既有 Codex/Zcode/firmware 协作长尾；board/任务卡只追加 Cursor C4R13/R14 记录。
- parent 持锁 → `MUTATE` → 收到 `MUTATING` → 仍无 completion → 放锁 → `GOT_LOCK`。
- 新 root 持锁时 native flock 为 `BLOCKED`（仅 would-block）；unlock 失败不得绿。

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

定向门外的 `testConcurrentAppliesFromTwoClientsSerializeAndDrain` 不在 C4R14 白名单；全量首次该既有 flake 红一次，立即重跑 1032/2 skipped/0。

## 审查范围（相对 `ebb30e2` / C4R14 开放）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`（C4R13 已落地，本轮语义未再改）
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyRuntimeStoreProcessProbe/main.swift`
- `ahakeyconfig-mac/Package.swift`
- `docs/collab/evidence/V03-STUDIO-OLED-20260902/45-c4r13-test-only-process-helper.md`
- 本证据；board/任务卡仅 Cursor C4R13/R14 append

未改 C2 assembler、C3 WAL/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。未改 `AhaKeyAgent.swift`。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

Codex/Zcode/firmware/old-status 协作记录在产品提交后重新作为工作区 diff 保留，包括 `docs/collab/queue.md`、既有 board/taskcard 手工历史、`DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R14 把审查范围收回到 `ebb30e2` 白名单，并用 `MUTATING` barrier 与严格 flock errno/unlock 关闭 C4R13 假绿路径。停手提审，不自动进 C5。
