# V03-C5-RELEASE-FEATURE-POLICY：C5PR7 publication epoch CAS

日期：2026-09-08 16:24–16:36 +08
ACK Codex 16:18 C5PR6 未通过与 C5PR7 开放。产品基线 `30cfeb8`；工作起点 HEAD `3e9e245`（C5PR6）。执行 owner Cursor。Agent Relay 继续暂停。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未伪造 Relay `review_decision`。未自动进入 `USER-GATE-C5-SIGN-HIL`。未夹带 Store / concurrent-apply 修复。C5PR6 reservation cleanup 未回退。

## 行为

| 审查项 | 落地 |
|---|---|
| Publication ticket CAS | identity mutation 后同步取样 `publicationTicket()`；迟到 `publish(_:ticket:)` 在 epoch 已前进时 no-op |
| 普通事件不恢复 admission | status / authoritative-object / 无 ticket 的 `publishDeviceChangedIfNeeded` 只发 UI 事件，不 `fence.publish` |
| Proven-only live token | 仅当前 snapshot 含 writable sealed fact（非 unsupported）才 publish live token；否则 ticketed publish nil |
| unavailable/shutdown | 只 `beginIdentityMutation`，不发 live-token ticket；旧排队 publication 遇较新 revoke no-op |

未改 C2 assembler、C3 WAL schema/事务执行/BLE wire、Studio View、Hook/安装器/固件、ReleaseIdentity 字节、policy 矩阵。未修 `testConcurrentAppliesFromTwoClientsSerializeAndDrain`。

## 反例

- 先排队旧 admission-bound publication，再同步 powered-off / shutdown，最后释放旧 publication：fence 仍 nil，ingest/apply 零 CAS/WAL。
- revoke 后普通 deviceChanged：不恢复 live token，零 CAS。
- 新代 simulateDevice proof 可恢复 admission；旧 publication 释放后不得覆盖新代。
- fence 层 stale ticket 在 `beginIdentityMutation` 后 publish 失败且 live 保持 nil。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyStudioPageInteractionTests|AhaKeyReleaseFeaturePolicyTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeDerivationTests'
# 100/100 passed

swift test --filter 'AhaKeyAgentRuntimeEndpointTests|AhaKeyAgentByteProgressTests|AhaKeyAgentPageExecutionTests'
# 首跑 119/1：失败为已披露 testConcurrentAppliesFromTwoClientsSerializeAndDrain flake
# 立即复跑 119/119 passed

swift test
# 全量 #1：1074 / 2 skipped / 0 failures
# 全量 #2：1074 / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./ahakeyconfig-mac/scripts/check-release-identity.sh
# release identity ok；channel 仍为 v0.2 / productVersion 0.2.1

git diff --check -- <C5PR7 whitelist>
# DIFF_CHECK_OK
```

## 结论与下一精确 USER-GATE

C5PR7 publication epoch CAS 完成。停手。

下一门仍是 **USER-GATE-C5-SIGN-HIL**。不自动进入。HIL 15L 保持 `blocked / awaiting C5PR7` 直至本卡 accepted。
