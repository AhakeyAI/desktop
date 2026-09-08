# V03-C5-RELEASE-FEATURE-POLICY：C5PR9 remove ticketless publish bypass

日期：2026-09-08 20:42–22:49 +08
ACK Codex 20:40 C5PR8 未通过最终验收与 C5PR9 开放。产品基线 `30cfeb8`；工作起点 HEAD `acd7fc9`（C5PR8）。执行 owner Cursor。Agent Relay 继续暂停。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未伪造 Relay `review_decision`。未自动进入 `USER-GATE-C5-SIGN-HIL`。未夹带 Store / concurrent-apply / inode 修复。C5PR6 cleanup、C5PR7 nil-ticket、C5PR8 causal ticket 未回退。未改 Agent 生产行为。

## 行为

| 审查项 | 落地 |
|---|---|
| 删除 ticketless publish | `AhaKeyRuntimeAdmissionFence` 不再公开 `publish(_ token:)`；只保留 ticketed CAS `publish(_:ticket:)` |
| 测试统一走 mutation ticket | Shared reservation 测试改用 `beginIdentityMutation()` 返回的 ticket 再 CAS publish |
| 产品源码门禁 | `testProductSourcesHaveNoTicketlessAdmissionPublish` 扫描 `Sources/`：fence 无单参 publish，且 `resourceAdmissionFence.publish(` 参数必须含 `ticket:` |

未改 Agent 生产路径、C2 assembler、C3 WAL schema/事务执行/BLE wire、Studio View、Hook/安装器/固件、ReleaseIdentity 字节、policy 矩阵。未修 `testConcurrentAppliesFromTwoClientsSerializeAndDrain`，未修 `testRootDeleteRecreateDoesNotLockStaleInode`。

## 反例

- 无 ticket 的 live publish 在产品源码中不存在；删除该 overload 后产品无法编译调用。
- stale/adjacent ticket CAS、revoke、reservation cleanup 仍成立。
- C5PR8 pre-ticket / fresh proof / nil-ticket 普通事件保持冻结（本轮不改 Agent）。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyStudioPageInteractionTests|AhaKeyReleaseFeaturePolicyTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeDerivationTests'
# 100/100 passed

swift test --filter 'AhaKeyAgentRuntimeEndpointTests|AhaKeyAgentByteProgressTests|AhaKeyAgentPageExecutionTests'
# 121/121 passed

swift test --filter 'AhaKeyAgentRuntimeEndpointTests|AhaKeyRuntimeProductionSeamTests'
# 70/70 passed

swift test
# 全量 #1：1078 / 2 skipped / 0 failures
# 中间复跑失败仅为已披露 testConcurrentAppliesFromTwoClientsSerializeAndDrain
# 与既有 testRootDeleteRecreateDoesNotLockStaleInode，未夹带修复
# 全量 #2：1078 / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./ahakeyconfig-mac/scripts/check-release-identity.sh
# release identity ok；channel 仍为 v0.2 / productVersion 0.2.1

git diff --check -- <C5PR9 whitelist>
# DIFF_CHECK_OK
```

## 结论与下一精确 USER-GATE

C5PR9 删除 ticketless admission publish 完成。停手。

下一门仍是 **USER-GATE-C5-SIGN-HIL**。不自动进入。HIL 15L 保持 `blocked / awaiting C5PR9` 直至本卡 accepted。
