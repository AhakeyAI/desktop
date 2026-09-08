# V03-C5-RELEASE-FEATURE-POLICY：C5PR6 unavailable fence and reservation cleanup

日期：2026-09-08 15:49–16:08 +08
ACK Codex 15:41 C5PR5 未通过与 C5PR6 开放。产品基线 `30cfeb8`；工作起点 HEAD `ea92bd3`（C5PR5）。执行 owner Cursor。Agent Relay 继续暂停。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未伪造 Relay `review_decision`。未自动进入 `USER-GATE-C5-SIGN-HIL`。未夹带 Store / Agent coordinator 修复。

## 行为

| 审查项 | 落地 |
|---|---|
| Bluetooth unavailable 先撤销 admission | `centralManagerDidUpdateState` 非 poweredOn 与测试 seam 共用 `handleBluetoothUnavailable()`：先 `beginIdentityMutation()`，再 `transportCore.handle(.bluetoothUnavailable)`。不 `publish` live token，不依赖稍后 `didDisconnect` |
| shutdown 先撤销 admission | `shutdown()` 在 `bleLifecycle.shutdown`（`.shutdown` → idle）前同步 `beginIdentityMutation()`。live token 保持 nil 直至新连接完成已证明的 publish |
| Reservation discard / RAII | `discard` 幂等移除 outstanding；ingest/apply 在 `reserve` 后 `defer discard`。Store 构造、writer-lease、取消、成功/抛错后重放均不泄漏 |
| Mutation 清空 outstanding | `beginIdentityMutation()` 同时 `outstanding.removeAll()`，与 discard 一起保证有界 |

未改 C2 assembler、C3 WAL schema/事务执行/BLE wire、Studio View、Hook/安装器/固件、ReleaseIdentity 字节、policy 矩阵。未修 `testConcurrentAppliesFromTwoClientsSerializeAndDrain`。

## 反例

- 生产 `simulateBluetoothUnavailableForTesting`（与 `centralManagerDidUpdateState` 同一路径）在 reserve 前发起：Standard 特征与 sealed fact 仍可保留，旧 token ingest/apply 零 CAS/WAL。
- 写入已持 fence 锁时，生产 powered-off 必须等待写入完成；在途 CAS 成功，随后旧 token 零再写。
- 生产 `shutdown()` 在 reserve 前发起：ingest/apply 零 CAS/WAL。
- Store 构造失败、已缓存 writer-lease resolve 失败、reserve 后取消：各 8 轮 outstanding=0，CAS/WAL 不变；fence 层 32 次 abandon + 成功/抛错后 discard/重放均为 `staleReservation`。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyStudioPageInteractionTests|AhaKeyReleaseFeaturePolicyTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeDerivationTests'
# 100/100 passed

swift test --filter 'AhaKeyAgentRuntimeEndpointTests|AhaKeyAgentByteProgressTests|AhaKeyAgentPageExecutionTests'
# 116/116 passed（含 powered-off / shutdown / pre-write discard 反例）

swift test --filter 'AhaKeyAgentRuntimeEndpointTests|AhaKeyRuntimeProductionSeamTests'
# 62/62 passed。Codex 独立定向曾见 testConcurrentAppliesFromTwoClientsSerializeAndDrain flake；本机本轮未再现。未修该用例。

swift test
# 全量 #1：1070 / 2 skipped / 0 failures
# 全量 #2：1070 / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./ahakeyconfig-mac/scripts/check-release-identity.sh
# release identity ok；channel 仍为 v0.2 / productVersion 0.2.1

git diff --check -- <C5PR6 whitelist>
# DIFF_CHECK_OK
```

## 结论与下一精确 USER-GATE

C5PR6 unavailable fence and reservation cleanup 完成。停手。

下一门仍是 **USER-GATE-C5-SIGN-HIL**。不自动进入。HIL 15L 保持 `blocked / awaiting C5PR6` 直至本卡 accepted。
