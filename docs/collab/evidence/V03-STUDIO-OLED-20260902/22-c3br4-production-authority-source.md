# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3BR4：生产权威对象来源与有序 durable commit

日期：2026-09-05 09:04–10:46 +08
ACK Codex 08:44 / `lastReviewedCommit=72a34cc7ea749f486c5704d1e7bbe86c89fa2963` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3C/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3BR4 行为

| 审查项 | 落地 |
|---|---|
| 生产 authority producer | BLE 无法读回完整对象。生产投影只从已验证 schema=1 acquisition 写入的 live CAS（`authoritative-object:<deviceID>`）取 canonical content，不把 schema=2 page `syncBaseline` 当权威对象。连接投影剥离测试传入的 `authoritativeObject`；带 object 的快照只在 durable commit 成功后由 `committedAuthoritativeObject` 填入 |
| 先 commit 再暴露权威事件 | 普通连接 `deviceChanged` 可立即发布且不带 object、不清除 CAS。对应权威快照只在 `persistProjectedAuthoritativeObject` 成功后再发布。失败 `emit`，不 `try?`，不发布带 object 的快照 |
| generation 条件提交 | store 按 device + session/transport generation 拒绝过期换代（`authoritative-generation:<deviceID>`）。延迟 N 不能覆盖 N+1；过期任务若 live content 已变则不暴露旧对象 |
| 测试穿过非测试路径 | `makeReadyAgent` 经 schema=1 complete 种子，再 `simulateDeviceForTesting`（不填 object、不等待 persist Task）。覆盖延迟 N/N+1、event 可见后立即 page preflight、persist 失败、fresh reopen、无 object 零写 |

C3BR2/3 已冻结：typed `writesDevice`、恢复 CAS 门、终态分类、schema=1 原子 baseline+CAS、schema=2 不改 CAS、`0x84` 值域 `0...7` / WAL `0xff` fail-closed、`sealed-object:*` 已删除。不实现 60 秒 abandon、逐字段 baseline projection、C4 UI。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 220/220

swift test
# 898 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `72a34cc` / 调度 08:44）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler/dirty/Views/Hook/安装器/固件。未改 `queue.md` 状态。未改 `AhaKeyRuntimeContract.swift`（C3BR3 已有 snapshot 字段）。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3BR4 让生产 `deviceChanged` 从已验证 live CAS 产出权威对象，并在 generation 条件 durable commit 成功后才暴露对应权威快照。停手提审，不自动进 C3C/C4。
