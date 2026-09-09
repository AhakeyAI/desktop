# V03-C5-FIRST-PAGE-AUTHORITY-BOOTSTRAP：C5BR3 canonical page-resource closure

日期：2026-09-09 21:15–21:32 +08
ACK Codex 20:43 C5BR2 未通过，退 C5BR3。产品基线 `99a5b016ceffd077631e637954bf4d2e0ecdb03f`；C5B 父提交 `35015ee3f0071557d74d2958d4cdf202c2b791ec`；C5BR1 冻结 `d423730f75bb6c5c258ccd31310ad9d15359401b`；C5BR2 冻结 `7113ce42c7feb397b1a62627ad4792bb387bd697`。执行 owner Cursor。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未 HIL、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未改 C2 assembler、C3 whole-object 比较语义、BLE opcode/slot/prepare/confirmation、View 布局、ReleaseIdentity、安装器、Hook 或固件。C5BR2 live/target/nil 门与 C5BR1 atomic CAS 保持冻结。

## 行为

| 审查项 | 落地 |
|---|---|
| scoped ingest 携带完整冻结 page package | `AhaKeyRuntimeScopedResourceIngestionProof` 只含 `package`。`make(package:)` / decode 调用现有 `pageOperation.validate(matchingDevice:resources:)`，不再自写浅 binding 规则 |
| 单一 contract validator | Store ingest 在同一 `BEGIN IMMEDIATE` 内先 `scopedProof.validate(items:targetDeviceID:)`，再 `acceptanceValidator.validate(package:resources:)`，再 `casFrozenPageProofUnlocked` |
| schema=3 CAS | 使用该 package 的 field proof；与 accept/start 同一 durable CAS |
| schema=2 fingerprint CAS | 比较 live object hash 与 package `baseObjectFingerprint`，不再只证明“存在某个 object” |
| 完整 resource identity | items 与 package resources/bindings 双射：canonical logicalID、SHA、byteCount、mediaType、encodedFrameCount；bytes digest/count 闭合。actions/physical slot/prepare/ledger 由 page contract validator 闭合 |
| schema-dependent key shape | schema=2 禁止 `fieldBaselines`（含显式 null），必须存在非空 `baseObjectFingerprint`；schema=3 禁止 object fingerprint key，必须存在非空 `fieldBaselines` |

## 反例

- 非 canonical logical ID（即使 resources/bindings/actions/ledger 一并改写）：decode fail-closed，零 journal/WAL。
- mediaType swap、encodedFrameCount swap/0：零 journal/WAL。
- physical slot swap、action command swap、prepare strategy opcode swap：零 journal/WAL。
- schema=2 stale object fingerprint：`pageBaseObjectConflict`，零 journal/WAL。
- schema=2 `"fieldBaselines": null`：package/XPC decode fail-closed，零 journal/WAL。
- 合法 schema=2 图片 package：匹配 object fingerprint 后仍可 ingest+apply。
- 合法 schema=3 图片 package：仍可 ingest+apply；完成后 fields=`writeConfirmed`，`authoritativeObject` 仍 nil。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyRuntimePageBaseAuthorityTests|AhaKeyRuntimePageExecutionTests'
# 41 + 24 passed

swift test --filter 'AhaKeyRuntimePersistentStoreTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimeContractTests'
# passed

swift test --filter 'AhaKeyAgentPageExecutionTests|AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyRuntimeProductionSeamTests|AhaKeyAgentRuntimeEndpointTests|AhaKeyAgentByteProgressTests'
# passed

swift test
# 1124 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

Identity：`ReleaseIdentity.json` / embedded JSON 未改：`channel: "v0.2"`，`productVersion: "0.2.1"`。

## 审查范围（相对 `99a5b01`）

C5BR3 增量父提交为 `7113ce4`。审查 range 为 `99a5b01...HEAD`（含 C5B/C5BR1/C5BR2）以及 `7113ce4...HEAD`（本 commit）。

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageBaseAuthority.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageOperation.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageBaseAuthorityTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeProductionSeamTests.swift`
- 本证据；board / 本任务卡仅追加 Cursor ACK/完成记录

未改 C2 assembler/dirty-only/whole-group/emitted-action、C3 whole-object 比较语义、BLE opcode/slot/prepare/confirmation、View 布局、Hook/安装器/固件、ReleaseIdentity 字节。未改 `queue.md`。未签名/安装/HIL/设备写。

## 结论

C5BR3 删除浅 scoped-proof validator。资源 ingest 携带完整冻结 page package，复用单一 page contract validator，并把 schema=2 ingest CAS 收到冻结 object fingerprint。停手提审，不自动回到 C5W。下一设备写入门仍为独立 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE-R1`。
