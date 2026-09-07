# 任务卡 V03-C5-RELEASE-FEATURE-POLICY：v0.3 生产图片面发布策略

计划/WBS：v0.3 客户端 OLED C5P
状态：`ready / USER-GATE-C5-POLICY authorized`
执行 owner：Cursor
验收：Codex
依赖：`V03-STUDIO-OLED-LEGACY-COMPATIBILITY` C1–C4 accepted @ `30cfeb8`；C5 preflight accepted
产品基线：`30cfeb889bfea299a41224222f8a5b400df2de33`

## 目标

只收口 C5 preflight 发现的发布策略门：新增 `.v0_3` 或等价 compile-time 发布通道，将生产 `AhaKeyReleaseFeaturePolicy.current` 切到 v0.3，使正式 Studio/Facade/Agent 能在 C1 已证明的旧固件 profile 上进入 C2/C3/C4 图片路径。本卡不执行 HIL、签名或安装。

## 产品契约

1. `v0_2` 策略对象及全矩阵保持不变；新通道不得回改 v0.2 发布语义。
2. v0.3 只对已密封证明的可写终态开放图片面：Standard no-response + strict legacy-task-picture proof、已解析 Rhino profile、已解析 current session-capable profile。具体 opcode/物理槽/资源语义仍由 C1 compatibility context 与 C2/C3 冻结契约决定，release policy 不重新猜测。
3. `.negotiating`、malformed/truncated response、unknown firmware/no-response without proof、unsupported protocol/profile 仍 fail-closed：图片 UI 不可见，resource package 不受理，CAS/WAL/BLE 为零。
4. keys/light 现有资格不回退。`allowsResourcePackage` 必须与图片 write surface 同源，禁止 UI 可见但 Facade/Agent 拒绝，或 Agent 可写但 UI 隐藏的分裂。
5. 生产不得使用 `picturesUnrestrictedForTests`。正式 Studio visibility、Facade resource admission 与 Agent preflight 均必须消费 `AhaKeyReleaseFeaturePolicy.current` 的 v0.3 投影。
6. 本卡不修改 `ReleaseIdentity.json`、productVersion、bundle/signing identity、installer 或 launchd label；HIL pre-release 签名身份归下一 `USER-GATE-C5-SIGN-HIL`。如果因类型新 case 需最小 compile 修正，必须保持当前 release identity 字节不变并有反例。

## 反例/门禁

- 策略全矩阵：`v0_2` 原矩阵逐项不变；`v0_3` 覆盖 Standard strict fallback、Rhino parsed、current session、negotiating、malformed/truncated、unknown/no-proof、unsupported protocol。
- 生产消费点：Studio 图片 inspector/当前页按钮，Facade `allowsPictureResources`/ingest+apply admission，Agent `configurationWriteIsReady`/release projection。开放样例能走真 C2/C3 package，关闭样例在 ingest/CAS/WAL/BLE 前拒绝。
- 核对 Standard 不伪造 `0x97`，Rhino/current 不回退 session/slot 路由，不更改 C2 assembler 的 dirty-only/whole-group 决策。
- 复跑 policy/Studio derivation/Facade/Agent 精确定向、全量 Swift、App + Agent Release、`git diff --check`。

## 白名单

- `ahakeyconfig-mac/Sources/Shared/AhaKeyReleaseFeaturePolicy.swift`
- 因新 channel case 所必需的最小 compile 修正（不改 release identity 字节/版本）
- `AhaKeyReleaseFeaturePolicyTests`、`AhaKeyReleaseV02WiringTests` 与 Studio/Facade/Agent 精确 production-path 测试
- 单一 C5P evidence、本卡、Cursor append-only board

禁改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor、Studio View 交互、Hook/安装器/固件。不 overlay `/Applications`，不 kickstart，不签名/打包/安装，不刷机，不擦 EEPROM，不断电，不 push。

## 执行记录（append-only）

### [2026-09-07 19:25] 用户授权 `USER-GATE-C5-POLICY`

- 仅执行本卡 C5P 产品策略切片。完成后停手提审，不自动进入 `USER-GATE-C5-SIGN-HIL`。
- 需要回复：是（@Cursor ACK 后执行）

### [2026-09-07 20:02] Cursor ACK：开始 C5P v0.3 生产图片面策略

ACK 用户授权 `USER-GATE-C5-POLICY`。基线 `30cfeb8`。仅新增/切换 `.v0_3` 并覆盖 Studio/Facade/Agent 真实消费路径。v0.2 矩阵保持不变。不改 C2/C3/View/identity/安装器。不 overlay/签名/安装/kickstart/刷机/push。完成后停手提审，不自动进入 `USER-GATE-C5-SIGN-HIL`。

### [2026-09-07 20:18] Cursor：C5P 完成，停手提审

- `AhaKeyReleaseFeaturePolicy.current == .v0_3`。`v0_2` 全矩阵不变。v0.3 只对 C1 密封 Standard/Rhino/current session-capable 开放图片面与 resource package；negotiating/malformed/unknown/no-proof fail-closed。
- Studio 派生与 Facade apply/C4 commit 消费 `current` 投影（密封 family / live snapshot / 页 profile）。Agent 生产路径不改源码；密封 Standard 不再需要 `picturesUnrestrictedForTests`。
- Identity 字节未改：`channel: "v0.2"` / `productVersion: "0.2.1"`。
- 门禁：定向 + 全量 `swift test` 1042/2 skipped/0 failures；App+Agent Release；`check-release-identity.sh` ok；`git diff --check` ok。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/02-c5p-release-feature-policy.md`。未 overlay/签名/安装/kickstart/刷机/push。未改 queue。
- 下一精确 USER-GATE：`USER-GATE-C5-SIGN-HIL`。不自动进入。
- 需要回复：是（@Codex 验收 C5P）
