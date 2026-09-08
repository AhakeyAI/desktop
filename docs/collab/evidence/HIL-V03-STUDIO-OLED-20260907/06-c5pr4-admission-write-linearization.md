# V03-C5-RELEASE-FEATURE-POLICY：C5PR4 admission-write linearization

日期：2026-09-08 14:15–14:40 +08
ACK Codex 12:48 C5PR3 未通过与 C5PR4 开放。产品基线 `30cfeb8`；工作起点 HEAD `175e427`（C5PR3）。执行 owner Cursor。Agent Relay 继续暂停。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未伪造 Relay `review_decision`。未自动进入 `USER-GATE-C5-SIGN-HIL`。未夹带 Store / Agent coordinator 修复。

## 行为

| 审查项 | 落地 |
|---|---|
| Admission fence | `AhaKeyRuntimeAdmissionFence`：连接投影 `publish` 与 resource 写共享同一把锁。`reserve` 仅在 live token 精确相等时签发 reservation；`withReservedWrite` 在同一锁内复核 epoch 后才执行 Store 体 |
| Agent ingest | token 校验 → `reserve` → `afterResourceAdmissionReserved` barrier → `makeRuntimeStore` → reserved `ingestResources`。校验成功后、CAS 前的换代/撤 proof/target replacement 使 reservation 作废，零 CAS |
| Agent apply | 图片包同样 reserve + barrier；`resolveCachedWriterLease` 仍在 barrier 之后，但 accept 必须带同一 reservation。过期 reservation 零 WAL |
| Store scoped entry | `ingestResources` / `accept` 增加 `reservedBy:using:` 包装；无 reservation 的原方法与 WAL schema 不变 |
| Strict decode | `AhaKeyRuntimeResourceAdmissionToken` 与 `AhaKeyXPCResourceIngestionRequest` 拒绝未知键、缺字段、错误 shape，统一 `corruptRuntimeFact` |
| keys-only | 仍可 `admission: nil`，不走 fence |

未改 C2 assembler 决策、C3 WAL schema/事务执行/BLE executor、Studio View、Hook/安装器/固件、ReleaseIdentity 字节、policy 矩阵。Facade 无需适配。

## 反例

- ingest/apply 分别在 `afterResourceAdmissionReserved`（token 校验与 `reserve` 成功之后）阻塞，再提交同 UUID generation bump、proof revoke 或 target replacement：释放后零 CAS/WAL。
- 请求已进入 `withReservedWrite` 持锁时，同 UUID 换代必须等待写入完成；写入成功，无死锁。
- 合法当前 token：仍 ingest+apply。keys-only 不携带 token 仍受理。
- token/request：未知键、缺字段、错误 case shape → `corruptRuntimeFact`。
- 既有 `beforeIngestCAS`（校验前）切代/撤 proof 零 CAS 不回退。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyStudioPageInteractionTests|AhaKeyReleaseFeaturePolicyTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeDerivationTests'
# 100/100 passed

swift test --filter 'AhaKeyAgentRuntimeEndpointTests|AhaKeyAgentByteProgressTests|AhaKeyAgentPageExecutionTests'
# 111/111 passed（含 3 条 post-reservation 线性化反例；含 testConcurrentAppliesFromTwoClientsSerializeAndDrain）
# 同会话另一次定向曾 111/1 failure：testConcurrentAppliesFromTwoClientsSerializeAndDrain（白名单外既有 flake）；立即重跑 111/111

swift test
# 全量 #1：1063 / 2 skipped / 1 failure（tail 未留下用例名。同会话定向曾见 testConcurrentAppliesFromTwoClientsSerializeAndDrain flake）
# 全量 #2：1063 / 2 skipped / 0 failures
# 全量 #3：1063 / 2 skipped / 0 failures
# 未修 Store `testRootDeleteRecreateDoesNotLockStaleInode`，未修 Agent concurrent-apply。

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./scripts/check-release-identity.sh
# release identity ok；channel 仍为 v0.2 / productVersion 0.2.1

git diff --check -- <C5PR4 whitelist>
# DIFF_CHECK_OK
```

## 结论与下一精确 USER-GATE

C5PR4 admission-write linearization 完成。停手。

下一门仍是 **USER-GATE-C5-SIGN-HIL**。不自动进入。HIL 15L 保持 `blocked / awaiting C5PR4` 直至本卡 accepted。
