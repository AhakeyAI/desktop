# V03-C5-RELEASE-FEATURE-POLICY：C5PR5 production mutation fence

日期：2026-09-08 15:04–15:20 +08
ACK Codex 14:46 C5PR4 未通过与 C5PR5 开放。产品基线 `30cfeb8`；工作起点 HEAD `1ce9eba`（C5PR4）。执行 owner Cursor。Agent Relay 继续暂停。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未伪造 Relay `review_decision`。未自动进入 `USER-GATE-C5-SIGN-HIL`。未夹带 Store / Agent coordinator 修复。

## 行为

| 审查项 | 落地 |
|---|---|
| 生产 mutation 先入 fence | `withAdmissionIdentityMutation` 在改 peripheral/OLED fact/device identity/transport generation **之前**同步 `beginIdentityMutation()`。`publishDeviceChangedIfNeeded` 只异步发事件并 `publish` 新 live token |
| 写优先 | 写请求持 `withReservedWrite` 锁时，生产 OLED reset/disconnect 在改变事实前等待；写入完成后再作废 live token |
| Reservation 单次消费 | reservation 带 opaque UUID；锁内先 `remove` 再执行 body。成功、抛错后重放均为 `staleReservation` |
| Nested strict decode | token 内 `sealedOLEDFact`、request 内 items 拒绝未知键/缺字段/错误 shape，不扩大无关 leaf 全局 Codable |

未改 C2 assembler、C3 WAL schema/事务执行/BLE wire、Studio View、Hook/安装器/固件、ReleaseIdentity 字节、policy 矩阵。

## 反例

- 生产 `simulateOLEDConnectionResetForTesting`（与 didConnect/didDisconnect 同一套清场）在 post-reserve barrier 发起，同时阻塞 deviceChanged 发布：ingest/apply 零 CAS/WAL。
- 写入已持 fence 锁时，生产 OLED reset 必须等待写入完成，无死锁；CAS 已写入。
- 同一 reservation 第二次 `withReservedWrite`、body 抛错后重放、`beginIdentityMutation` 后旧凭证均为 `staleReservation`。
- nested fact/item 未知键、缺字段、错误 shape → `corruptRuntimeFact`。
- 合法当前 token、keys-only、既有校验前切代/撤 proof 不回退。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyStudioPageInteractionTests|AhaKeyReleaseFeaturePolicyTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeDerivationTests'
# 100/100 passed

swift test --filter 'AhaKeyAgentRuntimeEndpointTests|AhaKeyAgentByteProgressTests|AhaKeyAgentPageExecutionTests'
# 112/112 passed（含生产 delayed-publish 反例；含 testConcurrentAppliesFromTwoClientsSerializeAndDrain）

swift test
# 全量 #1：1065 / 2 skipped / 0 failures
# 全量 #2：1065 / 2 skipped / 0 failures
# Codex 独立定向曾见 testConcurrentAppliesFromTwoClientsSerializeAndDrain flake；本机两轮全量未再现。未修该用例。

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./scripts/check-release-identity.sh
# release identity ok；channel 仍为 v0.2 / productVersion 0.2.1

git diff --check -- <C5PR5 whitelist>
# DIFF_CHECK_OK
```

## 结论与下一精确 USER-GATE

C5PR5 production mutation fence 完成。停手。

下一门仍是 **USER-GATE-C5-SIGN-HIL**。不自动进入。HIL 15L 保持 `blocked / awaiting C5PR5` 直至本卡 accepted。
