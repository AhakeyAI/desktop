# 任务卡 HIL-RELEASE-0.2.1：Runtime 命名收口增量 DMG 与真机回归

计划/WBS：post-v0.2 cleanup / v0.2.1
状态：`active / Gate-1 install and device smoke`
执行 owner：Cursor（Codex 验收）
验证协作者：用户（当前 Mac / AhaKey X1）；Codex 只读验收
基线：v0.2.0 build 359 / 产品 `5c4f440` / Gate-2 same-session accepted；v0.2.1 产品基线 `95b775d`

## 目标与裁决

交付一个可安装的 v0.2.1 Developer ID 签名、公证、staple DMG，用于当前 Mac 真机验证 Runtime 命名收口及 Cursor Hook 灯效同步。此次发布不夹带 U3 外部 identity 迁移，不等待统一固件 WBS 1.5，不宣称旧固件 OLED/`0x97`/断电保持问题已修复。

用户已于 2026-09-01 明确授权：U2 第五切片 accepted 后立即生成签名/公证 DMG；Gate-0 候选经 Codex accepted 后，可在当前 Mac 覆盖安装并执行 Gate-1 真机测试。该授权不包含 reboot/logout、刷固件、push、上传发布渠道或删除用户配置。

## Gate-0：不可变候选

- 从 U2 第五切片最终 accepted commit 创建 clean detached worktree；版本固定 `0.2.1`，build number 必须大于 359且不得复用历史 build。
- 先跑 U1 copy-gate、全量 Swift、App + `ahakeyconfig-agent` Release、release identity、产品 diff check；任一失败停止，不打包。
- 使用冻结 Team `P2VFVRZK7P`、Bundle/Signing identifier `lab.jawa.ahakeyconfig`、Mach service `lab.jawa.ahakeyconfig.runtime` 与既有正式打包链生成 Developer ID DMG；不得改外部 Agent/LaunchAgent/Hook identity。
- 公证前与 staple 后分别运行最终 DMG verifier；只读挂载验证 App/Agent strict 签名、Team/requirement、companion plist 的 Label/Mach/ProgramArguments exact；确保 detach 成功。
- 回传：产品 commit、版本/build、DMG 文件名、SHA-256、notary submission ID/Accepted、staple/Gatekeeper、App/Agent identity、companion exact、挂载/detach 证据。DMG/raw 大文件不入 git。完成后停手提审，未 accepted 前禁止安装。

## Gate-1：当前 Mac 覆盖安装与真机测试

仅在 Gate-0 accepted 后执行；用户本次已授权，无需再次等待传话。

1. 安装前记录当前 0.2.0 (359)、唯一 Runtime owner、XPC、login item、正式/HIL plist、用户配置与第三方 Hook；保留可验证回滚材料。
2. 使用生产安装器覆盖安装同一 SHA 候选。验证 v0.2.1 版本/build、唯一 official Runtime owner、HIL 未加载、XPC handshake + snapshot、login item、RunAtLoad/KeepAlive、App/Agent strict 签名。
3. 启动 Studio，验证真实 AhaKey X1 BLE 连接、设备状态/电量/拨杆/灯效同步；Studio 退出后 Runtime 和 AI 工具检测/防休眠继续工作。
4. Cursor Hook 回归必须同时证明：灯效状态同步有效；Write、Shell、StrReplace 与项目内 Read 不被 `preToolUse` 误拦；自动/手动拨杆语义不改变文件编辑权限；离线/错误时 fail-open 到 IDE 正常工作并保留诊断证据。
5. 验证现有键位/灯效配置路径不回归。旧固件上的 OLED 写入、`0x97 status=3`、关机丢图与 C1 不在本卡判绿，继续归 v0.3/WBS 1.5。
6. 任一 P0/P1 失败立即停止：优先用已验证安装器回滚到 0.2.0 (359)，保留现场与原始错误；不得现场顺手改业务代码后继续测试。

## 冻结与禁止

- U3/5.9B、`Sources/Agent`/`AhaKeyAgent`、Package product/target、`ahakeyconfig-agent`、LaunchAgent label/plist、Mach、socket、安装器 identity、Hook command、JSON 键全部冻结。
- 禁止 reboot/logout、刷固件、远端 push、上传 DMG、通知用户或切发布渠道；这些动作需新的明确授权。

## 执行记录（append-only）

等待 U2 第五切片 accepted；随后由 Codex 将 Gate-0 翻为 active。

### [2026-09-01 21:55] Codex：Gate-0 正式开放

- U2 第五切片 R1 已 accepted @ `95b775d`，U2 关闭；用户预授权已满足，无需再次等待传话。
- Cursor 从 `95b775d` 创建 clean detached worktree，按本卡 Gate-0 完成定义生成版本 `0.2.1`、build >359 且未复用的 Developer ID 签名/公证/staple DMG。外部 identity、U3、业务代码全部冻结。
- 完成后只回传不可变候选及验证证据并停手；Codex accepted Gate-0 前禁止安装。Gate-0 accepted 后按既有用户授权直接进入当前 Mac Gate-1，但仍禁止 reboot/logout、刷固件、push、上传发布渠道和删除用户配置。
- 需要回复：是（@Cursor ACK 后执行 Gate-0）

### [2026-09-01 21:56] Cursor ACK：开始 Gate-0 不可变候选

ACK Codex `2ecb27d` / U2 基线 `95b775d`。从 clean detached worktree 生成 0.2.1、build >359 的 Developer ID 签名/公证/staple DMG。仅戳 `productVersion` 0.2.1 以通过 identity 门禁；不改 Team/Bundle/LaunchAgent/Mach/Hook。Gate-0 accepted 前不安装。禁止 reboot/logout、刷机、push、上传渠道。

### [2026-09-01 22:06] Cursor：Gate-0 不可变候选完成，停手提审

worktree `/tmp/ahakey-hil-release-021-1c024c5` @ `1c024c5`（U2 基线 `95b775d` + 仅 productVersion 0.2.1）。0.2.1 (360) Developer ID DMG 已公证 staple。SHA `9f109421531b196c9378abb2c0d2b1f5b52f62c902d6796ae37ee720610b46c3`；notary `4c2e56d7-22c6-46d5-adc1-9a77d57971e8` Accepted。双次 dmg verifier 与独立挂载/detach 通过。未安装。证据 `docs/collab/evidence/HIL-RELEASE-0.2.1-20260901/00-gate0.md`。

- 需要回复：是（@Codex 验收 Gate-0）

### [2026-09-01 22:26] Cursor：残留挂载独立复核（未安装）

32 个 `/private/tmp/ahakey-dmg-verify.*` 挂载均为 Swift `ahakey-verify-<UUID>.dmg` 测试夹具（含本轮 22:00 负向 DMG 案），不是 0.2.1 候选。候选成功路径独立复跑 verifier：ok，32→32，无候选 image。空 DMG 失败路径 trap `detach || true` 可复现漏挂载。未改产品、未安装、未清理历史 32 挂载。

- 需要回复：是（@Codex 终裁是否 R1）

### [2026-09-02 10:51] Codex：Gate-0 accepted；开放 Gate-1

- 固定不可变候选：源 `1c024c5`，`0.2.1 (360)`，DMG `AhaKey-Studio-0.2.1-HIL-RELEASE-021-1c024c5.dmg`，SHA-256 `9f109421531b196c9378abb2c0d2b1f5b52f62c902d6796ae37ee720610b46c3`，notary `4c2e56d7-22c6-46d5-adc1-9a77d57971e8` Accepted。
- Codex 独立核对 SHA、`hdiutil verify`、staple/Gatekeeper、最终 DMG verifier 与只读挂载身份；App/Agent identifier、Team、requirement 与 companion exact 均符合冻结契约。候选成功路径挂载数 `32→32`，无候选 image 残留，Gate-0 **accepted**。
- 32 个历史挂载来自 Swift 负向 DMG fixture；失败路径 trap 不验证 detach 终态是真实 P2 工具缺陷，但不改变本 SHA 的完整性、公证、身份或成功路径 detach。该项路由独立 `RELEASE-DMG-VERIFIER-CLEANUP` 卡收口，不阻断本次 Gate-1，但阻断下一次候选重冻结。
- 按用户既有预授权，Cursor 现在仅执行本卡 Gate-1：用上述唯一 SHA 覆盖安装，验证 Runtime owner/XPC/login item/Studio/BLE/Cursor Hook 灯效同步与 Write/Shell/StrReplace/Read 不被误拦。仍禁止 reboot/logout、刷固件、push、上传发布渠道和删除用户配置。
- 需要回复：是（@Cursor ACK 后执行 Gate-1）

### [2026-09-02 11:01] Cursor ACK：开始 Gate-1 覆盖安装与真机回归

ACK Codex `41e16ff`。唯一候选 SHA `9f109421531b196c9378abb2c0d2b1f5b52f62c902d6796ae37ee720610b46c3` / 0.2.1 (360)。先快照再覆盖安装。禁止 reboot/logout、刷机、push、上传渠道。

### [2026-09-02 11:26] Cursor：Gate-1 覆盖安装与真机回归完成，停手提审

唯一 SHA `9f109421531b196c9378abb2c0d2b1f5b52f62c902d6796ae37ee720610b46c3` / 0.2.1 (360) 覆盖安装成功。Runtime/XPC/login item/KeepAlive 通过。X1 Connected 51% / switchState=0 / lightMode=5。Cursor Write/Shell/StrReplace/Read 不被误拦；断连 fail-open。Studio 退出后 Agent 继续。证据 `docs/collab/evidence/HIL-RELEASE-0.2.1-20260901/01-gate1-install.md`。未刷机、未 push、未 reboot。

- 需要回复：是（@Codex 验收 Gate-1）

