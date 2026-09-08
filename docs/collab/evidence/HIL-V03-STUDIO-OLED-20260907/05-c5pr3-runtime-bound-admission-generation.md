# V03-C5-RELEASE-FEATURE-POLICY：C5PR3 Runtime-bound admission generation

日期：2026-09-08 10:58–11:36 +08
ACK Codex 00:56 C5PR2 未通过与 C5PR3 开放。产品基线 `30cfeb8`；工作起点 HEAD `1d6e7bd`（C5PR2）。执行 owner Cursor。Agent Relay 继续暂停。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未伪造 Relay `review_decision`。未自动进入 `USER-GATE-C5-SIGN-HIL`。未夹带 Store / Agent coordinator 修复。

## 行为

| 审查项 | 落地 |
|---|---|
| Identity | `ActiveDeviceAdmission.Identity` 含 `deviceID + sessionGeneration + transportGeneration + sealed OLED fact`。同 UUID、同 fact 的 N→N+1 不再 ABA 相等 |
| Wire token | `AhaKeyRuntimeResourceAdmissionToken`（target + 两代际 + sealed fact）随 resource-bearing ingest/apply 进入 Runtime。ingest 请求为 `{ items, admission }` |
| Agent CAS-preflight | OLED ready 门之后、`makeRuntimeStore` / `ingestResources` 之前核 token；只读 MainActor 设备投影，不为核验打开 Store。图片 apply 无 token 或 token 失配 → `unsupported-protocol`，零 CAS/WAL |
| Facade transport | `exchangeIngest` / `exchangeApply` 各一次 live revalidation 后立刻发带 token 的请求；删除 ingest 返回后无 suspension 的重复重核 |
| keys-only | `.apply(package)` 仍可 `admission: nil`；不发 ingest |

未改 C2 assembler 决策、C3 WAL schema/事务执行/BLE executor、Studio View、Hook/安装器/固件、ReleaseIdentity 字节、policy 矩阵、Store 通用语义。

## 反例

- 同 UUID、同 OLED fact，normalize / prepare / seal 窗口把 `sessionGeneration` 或 `transportGeneration` 从 0 增到 1：Facade 拒绝，零 transport。
- ingest 在 `beforeIngestCAS` 阻塞期间切 session generation 或撤 OLED proof：Agent 拒绝，resources 目录与 sqlite 相对基线不变（无 CAS 对象写入）。
- 伪造 target 或过期 generation token：零 CAS。
- 合法当前 token：仍 ingest+apply 至 completed。
- keys-only apply 不携带 token 仍受理，不写 resources。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioOLEDPreflightTests|AhaKeyStudioPageInteractionTests|AhaKeyReleaseFeaturePolicyTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeDerivationTests'
# 100/100 passed（Facade 42/42；相对 C5PR2 的 97 新增 3 条跨代反例）

swift test --filter 'AhaKeyAgentRuntimeEndpointTests|AhaKeyAgentByteProgressTests|AhaKeyAgentPageExecutionTests'
# 108/108 passed（含新 CAS-preflight 反例；含 testConcurrentAppliesFromTwoClientsSerializeAndDrain）

swift test
# 全量 #1：1058 / 2 skipped / 0 failures
# 全量 #2：1058 / 2 skipped / 1 failure（suite 摘要；tail 未留下用例名。同会话定向曾见 testConcurrentAppliesFromTwoClientsSerializeAndDrain flake）
# 立即 #3：1058 / 2 skipped / 0 failures
# 未修 Store `testRootDeleteRecreateDoesNotLockStaleInode`，未修 Agent concurrent-apply。

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./scripts/check-release-identity.sh
# release identity ok；channel 仍为 v0.2 / productVersion 0.2.1

git diff --check -- <C5PR3 whitelist>
# DIFF_CHECK_OK
```

## 结论与下一精确 USER-GATE

C5PR3 Runtime-bound admission generation 完成。停手。

下一门仍是 **USER-GATE-C5-SIGN-HIL**。不自动进入。HIL 15L 保持 `blocked / awaiting C5PR3` 直至本卡 accepted。
