# V03-C5-RELEASE-FEATURE-POLICY：生产切到 v0.3 图片面策略

日期：2026-09-07 20:02–20:18 +08
ACK 用户授权 `USER-GATE-C5-POLICY`。产品基线 `30cfeb8`；工作起点 HEAD `37dae77`。C1–C4 accepted；C5 preflight accepted。执行 owner Cursor。Agent Relay 继续暂停。未 overlay `/Applications`、未 kickstart、未签名/打包/安装、未刷机、未擦 EEPROM、不断电、未 push。未改 `queue.md`。未伪造 Relay `review_decision`。未自动进入 `USER-GATE-C5-SIGN-HIL`。

## 行为

| 审查项 | 落地 |
|---|---|
| 新通道 | `AhaKeyReleaseChannel.v0_3`；`AhaKeyReleaseFeaturePolicy.v0_3` / `current = v0_3` |
| v0.2 矩阵 | `v0_2` 对象与全协商态投影不变：任何状态都关闭 default/task picture 与 resource package；keys/light 仍只留给带来源的安全终态 |
| v0.3 开放 | 仅 C1 已密封可写 profile：Standard no-response + strict 0x94 proof、parsed Rhino dual-set、parsed current session-capable。`allowsResourcePackage` 与 default/task picture surfaces 同源 |
| v0.3 fail-closed | negotiating、malformed/truncated、unknown/no-proof、legacyBaseOnly（无 picture proof）、unsupported protocol/profile：图片 UI 关闭，resource package 不受理 |
| Studio | 离线/缺 OLED 事实 → `.projection(.negotiating)` 关闭 inspector。在线密封 family → `projection(sealedOLEDProfile:)`，禁止从 protocolState 伪造 0x99 |
| Facade apply | 生产 `allowsPictureResources == nil` 时消费 live snapshot 密封事实；无事实则剥图走 keys-only |
| Facade C4 commit | 图片包资格消费页上已密封 profile 的 v0.3 投影；关闭时在 ingest 前 `unsupportedFirmware` |
| Agent | 生产已走 `current.projection(context.negotiation)`；本卡不改 Agent 源。密封 Standard 不再依赖 `picturesUnrestrictedForTests` |
| Identity | `ReleaseIdentity.json` / embedded JSON 未改：`channel: "v0.2"`，`productVersion: "0.2.1"`。`AhaKeyReleaseIdentity.current.channel == .v0_2` |

未改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、Studio View 交互、Hook/安装器/固件。`picturesUnrestrictedForTests` 仍仅测试可见。

## 反例

- v0.2 对 parsed current/Rhino 仍关闭 OLED；v0.3 对同一密封态开放，且 `allowsResourcePackage == allowsPictureWrites`。
- v0.3 + negotiating / malformed / no-proof / protocol v2 / v3 无 dual-set 且无 session flag：inspector 与 resource package 关闭。
- Studio 在线 + 缺 `oledCompatibility` 事实：inspector 关闭。在线 + Standard/Rhino/current 事实：inspector 与 resource package 打开。
- Facade 无 override、无密封事实：剥图、不 ingest。无 override + Rhino 事实：ingest+apply 含图片。C4 Rhino 页 commit 走 v0.3 投影，不再需要 `allowsPictureResources: true`。
- Agent 密封 Standard、不注入 unrestricted hook：图片包 apply 受理并完成。
- Standard mapper 在 v0.3 开放图片面后仍不发 `0x97` / `0x98` / `0x9B`。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyReleaseFeaturePolicyTests|AhaKeyReleaseV02WiringTests|AhaKeyStudioRuntimeDerivationTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentRuntimeEndpointTests/testV03SealedStandardAllowsPicturePackageWithoutUnrestrictedHook'
# policy/wiring/derivation/runner/agent 定向绿；Facade 先修 ingest 日志与 commit 投影后 31/31

swift test
# 1042 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

./scripts/check-release-identity.sh
# release identity ok

git diff --check -- <C5P product/test files>
# DIFF_CHECK_OK
```

## 结论与下一精确 USER-GATE

C5P 策略切片完成。停手。

下一门 **USER-GATE-C5-SIGN-HIL**：Developer ID 签名含本策略的候选、隔离 Runtime、唯一 owner、XPC。仍不覆盖 `/Applications`、不刷机、不擦 EEPROM、不断电。HIL 15L 保持 `blocked / awaiting C5P` 直至本卡 accepted。
