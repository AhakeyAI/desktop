# V03-C5-FIRST-PAGE-AUTHORITY-BOOTSTRAP：C5B field-baseline CAS

日期：2026-09-09 14:07–14:35 +08
ACK Codex 11:50 C5W 停点 accepted，开放最小 C5B。产品基线 `99a5b016ceffd077631e637954bf4d2e0ecdb03f`。执行 owner Cursor。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未 HIL、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未改 C2 assembler、C3 whole-object CAS、BLE opcode/slot/prepare/confirmation、View 布局、ReleaseIdentity、安装器、Hook 或固件。

## 行为

| 审查项 | 落地 |
|---|---|
| 单一 deep Module | `AhaKeyRuntimePageBaseAuthority` 只回答一次页面提交的 durable base proof：有 non-empty `authoritativeObject` → schema=2 object fingerprint；无 object → schema=3 field-baseline CAS |
| schema=3 诚实 one-of | 新 `fieldBaselineSchemaVersion=3`。handshake/snapshot 仍只读 `AhaKeyConfigurationPackage.advertisedSchemaVersions`（现 `[1,2,3]`）。schema=2 仍要求 `baseObjectFingerprint` 且禁止 `fieldBaselines`；schema=3 相反。空串/零 digest/双 proof/缺 proof fail-closed |
| field expectation | 每字段是完整 baseline 行或显式 `absent`。`.unknown` 行不是 absent。mask 必须 canonical 有序且与 expectation 双射。unknown key / 重复 / 乱序 / 错误 page/device 在 package decode 与真 WAL reopen 拒绝 |
| 首次 UI | 复用 C4 两击覆盖。未确认 unknown/absent 仍 `.requiresOverwriteConfirmation`，零 ingest/apply。旧 peer 未广告 schema=3 显示「当前 Runtime 不支持首次页面基线写入」。baseline race 显示「设备页面基线已变化，请刷新后重试」 |
| 完成不建 object | schema=3 完成只走既有 page field `writeConfirmed`；`commitOperationOutcome` / Agent `deviceChanged` 不创建或提升 `authoritativeObject`。schema=1 仍推进 object authority；schema=2 object-CAS 逐字保留 |

## 反例

- 无 object + 未覆盖确认：零 transport。
- 无 object + 覆盖确认 + 广告 schema=3：schema=3 apply，`fieldBaselines` 为 absent，无 object fingerprint。
- 旧 peer `[1,2]`：首次基线写拒绝，零 ingest/apply。
- 有 object：仍 schema=2，JSON 不含 `fieldBaselines`。
- accept 后 / start 前 live field 变化：`configurationFieldBaselineConflict`，零设备写，object 仍 nil。
- 不同页面并行：不伪冲突。
- 首个 picture device 步后断连再开：只续 residual，不因 object nil 退回首次全写；完成仍无 object。
- 损坏 digest/one-of/mask/unknown key：decode 与 WAL reopen 拒绝。
- Standard 不发 `0x97` / setActiveSet。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyRuntimePageBaseAuthorityTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyRuntimeContractTests'
# passed

swift test --filter 'AhaKeyAgentPageExecutionTests|AhaKeyRuntimePersistentStoreTests|AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyRuntimeProductionSeamTests'
# passed

swift test
# 1097 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

Identity：`ReleaseIdentity.json` / embedded JSON 未改：`channel: "v0.2"`，`productVersion: "0.2.1"`。`AhaKeyReleaseIdentity.current.channel == .v0_2`。

## 审查范围（相对 `99a5b01`）

本提交为 C5B 白名单冻结。审查 range 为 `99a5b01...HEAD`（本 commit）。

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageBaseAuthority.swift`（新增）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageOperation.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageSemantic.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioRuntimeFacade.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageBaseAuthorityTests.swift`（新增）
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioRuntimeFacadeTests.swift`
- 本证据；board / 本任务卡仅追加 Cursor ACK/完成记录

未改 C2 assembler/dirty-only/whole-group/emitted-action、C3 whole-object CAS 语义、BLE opcode/slot/prepare/confirmation、View 布局、Hook/安装器/固件、ReleaseIdentity 字节。未改 `queue.md` 状态。未签名/安装/HIL/设备写。

## 结论

C5B 给无 whole-object 读回设备补上诚实的 schema=3 field-baseline CAS，不伪造 `authoritativeObject`。停手提审，不自动回到 C5W。下一设备写入门仍为独立 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE-R1`。
