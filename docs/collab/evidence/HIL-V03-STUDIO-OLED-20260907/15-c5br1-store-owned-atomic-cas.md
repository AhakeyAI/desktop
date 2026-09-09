# V03-C5-FIRST-PAGE-AUTHORITY-BOOTSTRAP：C5BR1 Store-owned atomic base CAS

日期：2026-09-09 15:29–16:15 +08
ACK Codex 15:21 C5B 未通过，退 C5BR1。产品基线 `99a5b016ceffd077631e637954bf4d2e0ecdb03f`；C5B 父提交 `35015ee3f0071557d74d2958d4cdf202c2b791ec`。执行 owner Cursor。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未 HIL、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未改 C2 assembler、C3 whole-object 比较语义、BLE opcode/slot/prepare/confirmation、View 布局、ReleaseIdentity、安装器、Hook 或固件。

## 行为

| 审查项 | 落地 |
|---|---|
| Store 一次事务 snapshot/CAS | `pageBaseAuthoritySnapshotUnlocked` 在同一 `BEGIN IMMEDIATE` 读 confirmed steps、whole-object 与 field rows。空 object 视为损坏，读失败不得变成 absent |
| FIFO 队首转 running | `updateOperation` 在任意 page `→running` 且尚无 device-confirmed 写时，snapshot → 可选测试注入 → 重读 → `evaluateDurableCAS`，再 `UPDATE`。与队首 running 同锁 |
| schema=3 overwrite-only | `resolve`、package init/decode、WAL reopen 无条件要求 `overwriteSemantic=true`。删除 `testDurableFieldsDoNotRequireOverwrite` |
| kind-exact expectation | `.absent` 禁止 baseline-only keys（含显式 null）；`.baseline` 必须含完整 key 集，`operationID`/`authorityVersion` 可为 JSON null |
| 资源/WAL 前核 proof | schema=3 `accept` 与 scoped `ingestResources` 在 journal 前 CAS 同一 field proof |
| Agent 不再拼 durable 数组 | `pageExecutionPreconditions` 只给 live device/profile。Runner 只做 live compatibility；durable CAS 由 Store 拥有 |
| schema=3 完成 | 残余字段（含 `page:local:`）推进 `writeConfirmed`；不创建 `authoritativeObject`。schema=2 local 仍不写 field baseline |

## 反例

- accept 后 / start 前 committed field 变化：`configurationFieldBaselineConflict`，零设备写。
- snapshot 后、running commit 前同事务注入 field 行：同样 conflict，零设备写。
- 重叠 mask 第二队首：第一写密封后 fail-closed。
- schema=1 object 与 schema=3 absent proof 交错：`configurationPreflightConflict`。
- Store baseline 读失败：`pageBaseAuthorityUnreadable`，不得当 absent。
- stale ingest proof：`pageFieldBaselineConflict`，资源 journal 不存在。
- 仅 local 确认后改 whole-object：resume 仍 CAS（`page:local:` 不放宽）。
- 首个 device-confirmed 步后改 object：resume 续传。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyRuntimePageBaseAuthorityTests|AhaKeyRuntimePageExecutionTests'
# 25 + 24 passed

swift test --filter 'AhaKeyRuntimePersistentStoreTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimeContractTests'
# passed

swift test --filter 'AhaKeyAgentPageExecutionTests|AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyRuntimeProductionSeamTests'
# passed（全量复跑闭合）

swift test
# 1106 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

Identity：`ReleaseIdentity.json` / embedded JSON 未改：`channel: "v0.2"`，`productVersion: "0.2.1"`。

## 审查范围（相对 `99a5b01`）

C5BR1 增量父提交为 `35015ee`。审查 range 为 `99a5b01...HEAD`（含 C5B）以及 `35015ee...HEAD`（本 commit）。

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageBaseAuthority.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageOperation.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageSemantic.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeProductionSeam.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioRuntimeFacade.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageBaseAuthorityTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- 本证据；board / 本任务卡仅追加 Cursor ACK/完成记录

未改 C2 assembler/dirty-only/whole-group/emitted-action、C3 whole-object 比较语义、BLE opcode/slot/prepare/confirmation、View 布局、Hook/安装器/固件、ReleaseIdentity 字节。未改 `queue.md`。未签名/安装/HIL/设备写。

## 结论

C5BR1 把 durable base CAS 收进 Store/FIFO 队首转 running 的同一 mutation transaction，schema=3 无条件 overwrite，读错 fail-closed。停手提审，不自动回到 C5W。下一设备写入门仍为独立 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE-R1`。
