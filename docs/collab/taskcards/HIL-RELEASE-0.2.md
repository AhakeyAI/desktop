# 任务卡 HIL-RELEASE-0.2：当前量产固件的 0.2 发布门禁

计划/WBS：6.0A / v0.2
状态：`blocked / 15F2 R2 installer recovery rework`
执行 owner：Cursor
验证协作者：Zcode（只读固件/协议证据）；Codex 验收
基线：0.2 兼容策略与 WBS 5.9A accepted 的不可变候选包
目标版本：v0.2 macOS Beta

目标：用当前量产固件和真实键盘证明 0.2 的已开放功能可用，并证明被延期的 OLED/统一固件功能不可进入。

## 用户现场要求

- 用户确认真实键盘、蓝牙环境、Developer ID 签名、登录/重启窗口和可安装候选 DMG。
- 本卡不刷固件，不执行 HIL-CONFIG 的断电事务测试。

## 验收矩阵

1. 干净安装、覆盖升级、登录重启、卸载/回滚；全程只有一个 Runtime/Agent owner。
2. BLE 连接、断连重连、Studio 隐藏与完全退出。
3. AI Hook 拨杆上=自动批准、下=手动批准；离线/异常时 fail-closed。
4. 防休眠与 AI 工具检测在 Studio 退出后继续。
5. 基础键位/灯效配置成功且包中无 OLED resource、`0x95`、`0x97`；重启后基础配置仍符合当前固件既有能力。
6. OLED/任务图入口不可见或只读，并明确提示需要 0.3 固件；不能通过深链/恢复草稿绕过。
7. 真实键盘连续 30 分钟 CPU/RSS；1.5 秒轮询相同状态零 UI 发布、零常规磁盘日志；后台响应不超过 2 秒。
8. 收集签名、版本、进程、协议、日志、CPU/RSS 和 UI 截图证据；无 P0/P1。

## 禁止事项

- 不在 HIL 卡里顺手改业务代码；发现缺陷另开返工卡。
- 不刷机、不跑 OLED C1-C6、不发布、不 push、不切正式渠道。

## 执行记录（append-only）

等待 0.2 候选包与用户真机/安装窗口。

### [2026-08-30 23:11] Cursor ACK：开始 Gate-0

ACK 用户解除 USER-GATE 与 Codex 调度。产品基线 `6649834`，兼容策略 `d9d2cbb`，Team ID `P2VFVRZK7P`。未改本卡状态字段或 queue。先做 Gate-0 只读预检与回滚快照；未通过前不签名、不安装、不改 `/Applications` 或登录项。不刷机、不跑 HIL-CONFIG C1–C6、不发布、不 push。

### [2026-08-30 23:16] Cursor：Gate-0 完成，冻结候选前 blocked

源码 worktree `6649834`、身份脚本、Developer ID `P2VFVRZK7P`、BLE 键盘 AhaKey 515C（HID 1/6）均通过。回滚快照已写入 `docs/collab/evidence/HIL-RELEASE-0.2-20260830/`。

进入步骤 2 前 blocked：无 notarytool keychain profile，不能公证 DMG。另有 HIL 残留占用 `lab.jawa.ahakeyconfig.runtime`（未回滚）、`/Applications` 0.1.0 密封已坏、先前 X1 地址未连接。未签名、未安装、未改登录项。

- 需要回复：是（@用户 提供 notarytool profile；@Codex 确认是否允许用 515C 代替 X1，以及步骤 3 前是否回滚 HIL label）

### [2026-08-30 23:41] Cursor ACK：开始冻结候选

用户已存入 `AhaKeyNotary` 并授权继续。在 detached worktree `6649834` 执行 `pack-release.sh`：Developer ID `Xinyang Zhang (P2VFVRZK7P)`、公证、staple、生成 DMG。不改业务代码、不安装、不改登录项、不刷机、不 push。

### [2026-08-30 23:53] Cursor：冻结候选产出，安装矩阵前 P0 blocked

`pack-release.sh` 成功：DMG SHA-256 `4426b3c9…ce793b`，公证 `9133cb9a-0b09-47a3-9946-acaa228d0b05` Accepted 且已 staple，版本 `0.2.0` (304)。`build.sh` 直出 App/Agent 满足冻结 requirement。

P0：DMG 内 Agent identifier 被 `package_dmg.sh` 重签成 `ahakeyconfig-agent`，不满足 `lab.jawa.ahakeyconfig`。本卡不改代码、不安装该 DMG。证据 `docs/collab/evidence/HIL-RELEASE-0.2-20260830/01-freeze-candidate.md`。

- 需要回复：是（@Codex 另开 `package_dmg.sh --identifier` 返工卡）

### [2026-08-31 00:08] Codex（GPT-5.6 代审）：P0 成立，并扩大为两个候选拒绝点

- 独立复核 `6649834`、`11bc323` 与本机冻结 DMG：版本/hash/notary Accepted/staple/Gatekeeper 记录一致；DMG 内 Agent identifier=`ahakeyconfig-agent`，冻结 requirement rc=3。现有 DMG 不得安装，停手正确。
- 影响口径修正：XPC server 的 peer requirement 校验的是 Studio 客户端，当前证据不能证明 Agent identifier 单独必然造成 Runtime 断连。可直接证明的是 5.9A 候选 checklist 会在 mutation 前拒绝坏 Agent identity。
- 另一个 P0：最终 DMG 没有 App 同级 `LaunchAgent.plist`；生产 `inspectCandidate` 会先得到 companion 缺失，并以 `machServiceMissing` 拒绝。因此返工不能只给 codesign 增加 `--identifier`。
- 已开 `HIL-RELEASE-0.2-PACKAGING-REWORK`：同时修复二次签名 identifier、DMG companion 内容，并增加 notarization 前与 staple 后的最终只读挂载 fail-closed verifier。返工 accepted 且新候选证据 accepted 前，本卡保持 blocked，不进入安装矩阵。
- 需要回复：是（@Cursor ACK 新返工卡；不得安装旧 DMG）

### [2026-08-31 12:07] Codex：15F1 accepted，开放重新冻结候选；安装仍未开放

- packaging 产品修复 accepted @ `3b287beecf34c3f2d433631610f8e8c8f85c9149`。从该产品提交的 clean detached worktree 重新运行正式 `pack-release.sh`，使用既有 Team `P2VFVRZK7P` 与 `AhaKeyNotary`。
- 本阶段只允许：构建 0.2.0、Developer ID 签名、公证、staple，以及 `verify-release-dmg.sh --expect-developer-id` 的公证前/后只读挂载验证；记录 App/Agent identifier、Team、frozen requirement、companion exact、版本、SHA-256、notary submission ID、staple/Gatekeeper 与挂载 detach 证据。
- 新候选必须有新的 SHA；旧 `4426b3c9…ce793b` 不得复用或安装。完成证据包后停手提审；Codex accepted 新候选证据前，不得执行首次安装、覆盖升级、登录重启、卸载重装或任何 `/Applications`/LaunchAgent/login-item mutation。
- 需要回复：是（@Cursor ACK 后只执行 candidate refreeze，完成后停手提审）

### [2026-08-31 12:11] Cursor ACK：开始 candidate refreeze

ACK Codex 12:07。15F1 accepted @ `3b287be`。从 clean detached worktree 跑正式 `pack-release.sh`（Developer ID `P2VFVRZK7P`、`AhaKeyNotary`），公证前后只读挂载校验。旧 SHA `4426b3c9…ce793b` 不安装。新证据 accepted 前不安装、不改 `/Applications` 或登录项、不 push。

### [2026-08-31 12:15] Cursor：candidate refreeze 完成，停手提审（未安装）

detached worktree `/tmp/ahakey-hil-release-02-3b287be` @ `3b287be` 跑 `pack-release.sh`。公证前/staple 后 `verify-release-dmg.sh --expect-developer-id` 均 `release dmg ok`。只读挂载复核 App/Agent identifier、Team、冻结 requirement、companion exact 后 detach rc=0。

- 版本 `0.2.0` (323)
- SHA-256 `0c3ec9a6f5031e2497be786d32a4d5ba4d02bd474e5b7e124f04201b92f33618`（≠ 旧 `4426b3c9…ce793b`）
- notary `bbf43bac-3a71-4b57-bfbb-87554a2de96f` Accepted；staple/Gatekeeper `Notarized Developer ID`
- App 与 Agent identifier 均为 `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，冻结 requirement rc=0
- DMG 根有 App 同级 `LaunchAgent.plist`，MachServices/ProgramArguments exact

未安装、未改 `/Applications` 或登录项、未 push。证据 `docs/collab/evidence/HIL-RELEASE-0.2-20260831/02-refreeze-candidate.md`。

- 需要回复：是（@Codex 验收新候选证据；accepted 前不得进入安装矩阵）

### [2026-08-31 12:19] Codex：candidate refreeze accepted；安装矩阵等用户门禁

- 固定证据提交 `12c51cb0dd841b6f05eae44ea5a5272fc96658b0`，源码 worktree `3b287beecf34c3f2d433631610f8e8c8f85c9149`，`lastReviewedCommit=12c51cb0dd841b6f05eae44ea5a5272fc96658b0`。只有协作卡/看板/证据，无业务代码或安装状态改动。
- Codex 在本机对 DMG `0c3ec9a6f5031e2497be786d32a4d5ba4d02bd474e5b7e124f04201b92f33618` 独立重算 SHA-256，并复跑 `hdiutil verify`、`stapler validate`、Gatekeeper 与 `verify-release-dmg.sh --expect-developer-id`；全部通过。版本 0.2.0 (323)，App/Agent identifier=`lab.jawa.ahakeyconfig`、Team=`P2VFVRZK7P`、companion exact，notary `bbf43bac-3a71-4b57-bfbb-87554a2de96f` Accepted。
- 新候选 accepted，且是唯一允许进入本卡安装矩阵的包。旧 SHA `4426b3c9…ce793b` 仍永久禁用。
- 下一步将更改 `/Applications`、受管 LaunchAgent/login-item 并停启旧 official/HIL owner，属 USER-GATE。未收到用户明确安装授权前，Cursor 停手；不得安装、覆盖升级、重启登录项或卸载回滚。
- 需要回复：是（@用户 确认是否现在启动 0.2 安装/HIL 矩阵）

### [2026-08-31 12:22] Codex：用户已授权安装，开放 Gate-1

- 用户明确回复“允许安装”。本轮唯一候选仍是 0.2.0 (323) DMG SHA `0c3ec9a6f5031e2497be786d32a4d5ba4d02bd474e5b7e124f04201b92f33618`；安装前必须再次校验 SHA，不得使用旧 SHA。
- Gate-1 允许：对当前 App、official/HIL plist、login-item 和 launchd owner 做可回滚快照；使用已验收候选执行安装/覆盖升级；立即验证版本/签名、唯一 Runtime owner、XPC handshake/snapshot、Studio 启动与 BLE 基本连接。
- 安装前快照或候选检查失败必须零 mutation 停手；安装后任一 P0/P1、多 owner、XPC 失败或回滚异常立即停手提审，不在 HIL 卡改业务代码。
- 用户本次只明确授权“安装”；**登出/重启、卸载、故障注入与回滚演练仍未开放**。Gate-1 完成后停手回传，由 Codex 验收后再申请下一门禁。不刷机、不跑 OLED/HIL-CONFIG、不 push/发布。
- 需要回复：是（@Cursor ACK 后仅执行 Gate-1 install + immediate smoke）

### [2026-08-31 12:45] Codex：Gate-1 P0 验收，现场恢复等新 USER-GATE

- 固定证据 `133385e3d47b9d924863a4820148281015334b06`，`lastReviewedCommit=133385e3d47b9d924863a4820148281015334b06`。现场只读红灯复现为：当前 0.2 App `codesign --verify --strict` rc=0，0.1 backup rc=1，official/HIL `launchctl print` 均 rc=113；与证据完全一致。
- 原始 apply 错误定位到 official bootstrap：安装步骤为 `bootout HIL → installApp → writePlist → bootstrap official → loginItem`；现场 App/plist 已变、login item 仍 false，rollback 又在 restoreApp 处立即失败，因此不可能是 bootstrap 之后的步骤。另外 `launchctl print-disabled gui/501` 明确显示 `lab.jawa.ahakeyconfig.agent => disabled`，而生产安装器只会 bootstrap，不处理 persistent disabled override。
- P0 是三个组合缺陷：(1) 安装前没有快照/转移 official disabled 状态；(2) 明知 previous App 密封已坏仍承诺 exact rollback，且 restore 必须重过当前签名策略；(3) `rollbackFailed` 丢弃 original apply error。已拆出 `HIL-RELEASE-0.2-INSTALLER-RECOVERY-REWORK`，HIL 卡不改业务代码。
- 当前最小现场恢复为 fail-forward：保留 0.1 backup 和 zip 不动；对 official label 执行 enable，再 bootstrap 已安装且已验证的 0.2 Agent；然后验证唯一 owner、XPC handshake/snapshot。成功前不启动 Studio、不测 BLE、不注册 login item、不删 backup。若 official bootstrap 仍失败，立即收集未被覆盖的原始 launchctl 错误并停手，不自动重试/卸载/回灌。
- 上述 enable/bootstrap 是失败后的新系统 mutation，不沿用之前的安装授权。未获用户新确认前保持零 owner 现场，不删 backup、不 bootstrap、不启动 Studio。
- 需要回复：是（@用户 是否授权上述 fail-forward enable + bootstrap 恢复）

### [2026-08-31 12:29] Cursor ACK：开始 Gate-1 install + immediate smoke

ACK Codex 12:22 / `190cc84`。安装前快照；只装 SHA `0c3ec9a6f5031e2497be786d32a4d5ba4d02bd474e5b7e124f04201b92f33618`。不重启、不卸载、不刷机、不 push。完成后停手提审。

### [2026-08-31 12:37] Cursor：Gate-1 rollbackFailed，停手提审

生产安装器 upgrade 后 `rollbackFailed(appIntegrityFailed)`。现场：0.2.0 (323) App 已就位且签名通过，0.1.0 backup 残留，正式 plist 已更新，零 Runtime owner。未开 Studio / XPC / BLE。不改业务代码，不再 mutation。证据 `docs/collab/evidence/HIL-RELEASE-0.2-20260831/03-gate1-install.md`。

- 需要回复：是（@Codex 裁决恢复/收尾）

### [2026-08-31 14:01] Cursor：fail-forward 未授权；转 15F2 R1

Codex 12:45 的 enable/bootstrap 恢复仍待用户明确授权。本会话不 enable、不 bootstrap、不删 backup。开始安装器返工卡 R1。

### [2026-08-31 14:03] Cursor ACK：开始最小 fail-forward 恢复

用户 14:03 明确“允许”。enable official + bootstrap 0.2 Agent + 唯一 owner/XPC。不删 backup、不注册登录项、不启 Studio、不测 BLE。

### [2026-08-31 14:06] Cursor：fail-forward enable + bootstrap 完成

enable official rc=0；bootstrap 正式 plist rc=0。唯一 owner `lab.jawa.ahakeyconfig.agent` pid=6602；HIL 未加载。XPC positive handshake+snapshot exit 0。backup/zip 保留，未启 Studio、未测 BLE、未加登录项。证据 `docs/collab/evidence/HIL-RELEASE-0.2-20260831/04-gate1-fail-forward.md`。

- 需要回复：是（@Codex 验收 fail-forward）

### [2026-08-31 14:13] Codex：fail-forward Runtime 现场恢复 accepted；Gate-1 安装器仍未通过

- 固定证据提交 `9b4b4075d22055216bfef470e280fc203c59665f`，`lastReviewedCommit=9b4b4075d22055216bfef470e280fc203c59665f`。Codex 独立只读复验：`/Applications/AhaKey Studio.app` 为 0.2.0 (323)，Developer ID/Team/identifier 有效；official label 为 enabled，仅 `lab.jawa.ahakeyconfig.agent` 一个 owner（pid 6602），HIL rc=113；Developer ID smoke client 重跑 handshake+snapshot `RESULT: ok`。
- 边界与证据一致：损坏的 0.1 `.ahakey-backup` 与 Gate-1 zip 均保留；Studio 未添加登录项；未启动 Studio GUI，未测 BLE，未删 backup，未 push。
- **裁决分开：Runtime 现场恢复 accepted，Gate-1 仍 blocked。** 这次 fail-forward 只证明已安装的 0.2 Agent 能正常运行；不能把生产安装器的 `rollbackFailed` 改判为成功，也没有完成 Gate-1 的 Studio 启动/BLE smoke。
- 依赖转为 15F2 R1：Cursor 继续只在 `HIL-RELEASE-0.2-INSTALLER-RECOVERY-REWORK` 白名单内收口 disabled-state、nonRestorable App 和 original+compensation 双错误。R1 提审前不再改系统；R1 accepted 后再单独申请新的安装器重跑窗口，随后才做 Studio/BLE smoke。
- 需要回复：否（Runtime 现场已稳定；等 15F2 R1 提审）

### [2026-08-31 14:21] Cursor ACK：Gate-1 仍 blocked；转 15F2 R1

ACK Codex 14:13。Runtime 现场不再 mutation。安装器返工完成前提审，不申请安装窗口。

### [2026-08-31 14:33] Cursor：15F2 R1 提审；Gate-1 仍等安装器验收

安装器返工已提交 Codex。本卡不改系统、不重跑安装、不做 Studio/BLE smoke。

### [2026-08-31 15:44] Cursor ACK：15F2 R2 开始；安装器重跑仍禁止

ACK Codex 15:36。本卡不改系统、不重跑安装。

### [2026-08-31 15:51] Cursor：15F2 R2 提审；安装器重跑仍禁止

R2 已提交 Codex。本卡不改系统、不重跑安装。

### [2026-08-31 16:06] Cursor ACK：15F2 R3 开始；安装器重跑仍禁止

ACK Codex 16:02。本卡不改系统、不重跑安装。

### [2026-08-31 16:23] Cursor：15F2 R3 提审；安装器重跑仍禁止

R3 已提交 Codex。本卡不改系统、不重跑安装。
