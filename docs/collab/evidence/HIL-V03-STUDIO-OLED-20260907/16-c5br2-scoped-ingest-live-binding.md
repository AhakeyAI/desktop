# V03-C5-FIRST-PAGE-AUTHORITY-BOOTSTRAP：C5BR2 scoped ingest / live-device binding

日期：2026-09-09 17:50–18:15 +08
ACK Codex 17:41 C5BR1 未通过，退 C5BR2。产品基线 `99a5b016ceffd077631e637954bf4d2e0ecdb03f`；C5B 父提交 `35015ee3f0071557d74d2958d4cdf202c2b791ec`；C5BR1 冻结 `d423730f75bb6c5c258ccd31310ad9d15359401b`。执行 owner Cursor。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未 HIL、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未改 C2 assembler、C3 whole-object 比较语义、BLE opcode/slot/prepare/confirmation、View 布局、ReleaseIdentity、安装器、Hook 或固件。C5BR1 atomic CAS / overwrite / read-error / kind-exact / schema=1/2 路径保持冻结。

## 行为

| 审查项 | 落地 |
|---|---|
| non-nil live preconditions | Runner `runPageScoped` 调用 `requireLiveCompatibility`。`pagePreconditions == nil` 不得回退 package/context，不得进入 Store `running` 或设备写 |
| Store 先 validate 再 matchLive | `casFrozenFieldProofUnlocked` 在同一 `BEGIN IMMEDIATE` 内对 `proofDeviceID/pageID/mask` 执行完整 `proof.validate`，再 `matchLive`。expectation `deviceID/pageID` 必须等于 admission target |
| typed scoped ingest proof | XPC `scopedProof` 携带 schema/page/device/canonical mask、picture field→resource binding 与 items exact 双射。Store 在安装 final/journal 前验证 |
| schema=2 / nil proof | 无 scoped proof 但有 admission `targetDeviceID` 时，目标必须已有 non-empty whole-object；无 object 不得用 nil proof 写 journal。无 target 的 Store 直连 ingest 仍供 schema=1 PersistentStore 测试 |

## 反例

- 缺失 live preconditions：`configurationPreflightConflict`，零设备写，不进 `running`。
- target A + foreign-device absent proof：`pageFieldBaselineConflict`，零 final file、零 staged journal、零 WAL。
- 正确设备但 unrelated page/mask proof：同样零 journal。
- items logicalID/digest/byteCount 与 binding 不闭合：同样零 journal。
- nil proof + 无 object：`pageBaseAuthorityUnreadable` / Agent `configuration.preflight-conflict`，零 journal。
- 合法 schema=3 C5W 图片 package：仍可 ingest+apply；完成后 fields=`writeConfirmed`，`authoritativeObject` 仍 nil。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyRuntimePageBaseAuthorityTests|AhaKeyRuntimePageExecutionTests'
# 31 + 24 passed

swift test --filter 'AhaKeyRuntimePersistentStoreTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimeContractTests'
# passed（PersistentStore inode 测试一次 TIMEOUT flake，复跑通过）

swift test --filter 'AhaKeyAgentPageExecutionTests|AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyRuntimeProductionSeamTests|AhaKeyAgentRuntimeEndpointTests|AhaKeyAgentByteProgressTests'
# passed

swift test
# 1113 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

Identity：`ReleaseIdentity.json` / embedded JSON 未改：`channel: "v0.2"`，`productVersion: "0.2.1"`。

## 审查范围（相对 `99a5b01`）

C5BR2 增量父提交为 `d423730`。审查 range 为 `99a5b01...HEAD`（含 C5B/C5BR1）以及 `d423730...HEAD`（本 commit）。

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageBaseAuthority.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeProductionSeam.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioRuntimeFacade.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageBaseAuthorityTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeProductionSeamTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentByteProgressTests.swift`
- 本证据；board / 本任务卡仅追加 Cursor ACK/完成记录

未改 C2 assembler/dirty-only/whole-group/emitted-action、C3 whole-object 比较语义、BLE opcode/slot/prepare/confirmation、View 布局、Hook/安装器/固件、ReleaseIdentity 字节。未改 `queue.md`。未签名/安装/HIL/设备写。

## 结论

C5BR2 要求 live device proof 不得由 package 自证，并把 scoped resource ingest 闭成 device/page/mask/binding/items 同一 Store 事务。停手提审，不自动回到 C5W。下一设备写入门仍为独立 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE-R1`。
