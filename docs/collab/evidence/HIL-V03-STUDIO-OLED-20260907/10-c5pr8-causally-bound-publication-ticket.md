# V03-C5-RELEASE-FEATURE-POLICY：C5PR8 causally-bound publication ticket

日期：2026-09-08 19:56–20:18 +08
ACK Codex 19:53 C5PR7 未通过与 C5PR8 开放。产品基线 `30cfeb8`；工作起点 HEAD `33c85fc`（C5PR7）。执行 owner Cursor。Agent Relay 继续暂停。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未伪造 Relay `review_decision`。未自动进入 `USER-GATE-C5-SIGN-HIL`。未夹带 Store / concurrent-apply 修复。C5PR6 reservation cleanup 与 C5PR7 nil-ticket 分流未回退。已删除事后重采 `publicationTicket()`。

## 行为

| 审查项 | 落地 |
|---|---|
| 同锁签发 ticket | `beginIdentityMutation()` 在同一把 fence lock 内 `live=nil`、`epoch+=1` 并返回 opaque ticket |
| 原路径携带 | `withAdmissionIdentityMutation` 返回该 ticket；生产 enqueue/publish 只显式携带它 |
| 禁止后采样 | 已移除 `publicationTicket()`；unavailable/shutdown 丢弃 ticket，只 revoke |
| pre-ticket gap | mutation body 完成后、enqueue 前插入 unavailable/shutdown：原 ticket CAS 失败，live 保持 nil |

未改 C2 assembler、C3 WAL schema/事务执行/BLE wire、Studio View、Hook/安装器/固件、ReleaseIdentity 字节、policy 矩阵。未修 `testConcurrentAppliesFromTwoClientsSerializeAndDrain`。

## 反例

- identity mutation body 已完成、尚未 enqueue 时暂停，再同步 powered-off / shutdown，恢复后携带原 ticket 发布：fence 仍 nil，ingest/apply 零 CAS/WAL。
- 相邻两次 `beginIdentityMutation` 的 ticket 不可互借；较旧 ticket publish 失败且不覆盖较新 live token。
- 新代 simulateDevice proof 可恢复 admission；pre-ticket 旧 ticket 释放后不得覆盖新代。
- C5PR7 post-ticket stale CAS、nil-ticket 普通事件隔离、C5PR6 reservation cleanup 保持成立。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyStudioPageInteractionTests|AhaKeyReleaseFeaturePolicyTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeDerivationTests'
# 100/100 passed

swift test --filter 'AhaKeyAgentRuntimeEndpointTests|AhaKeyAgentByteProgressTests|AhaKeyAgentPageExecutionTests'
# 首跑 121/1：失败为已披露 testConcurrentAppliesFromTwoClientsSerializeAndDrain flake
# 立即复跑 121/121 passed

swift test --filter 'AhaKeyAgentRuntimeEndpointTests|AhaKeyRuntimeProductionSeamTests'
# 69 tests / 1 failure：仍为已披露 concurrent-apply flake

swift test
# 全量 #1：1077 / 2 skipped / 0 failures
# 全量 #2：1077 / 2 skipped / 1 failure（已披露 concurrent-apply flake）
# 立即复跑：1077 / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./ahakeyconfig-mac/scripts/check-release-identity.sh
# release identity ok；channel 仍为 v0.2 / productVersion 0.2.1

git diff --check -- <C5PR8 whitelist>
# DIFF_CHECK_OK
```

## 结论与下一精确 USER-GATE

C5PR8 causally-bound publication ticket 完成。停手。

下一门仍是 **USER-GATE-C5-SIGN-HIL**。不自动进入。HIL 15L 保持 `blocked / awaiting C5PR8` 直至本卡 accepted。
