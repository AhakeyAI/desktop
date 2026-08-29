# 任务卡 WBS-5.9A-BETA-INSTALLER：0.2 最小签名安装链

计划/WBS：5.9A / v0.2
状态：`active`
执行 owner：Cursor（Codex 验收）
基线：`RELEASE-0.2-COMPATIBILITY` accepted @ `d9d2cbba0faf34e931b60e9b6da452251ab4e5fd`
目标版本：v0.2 macOS Beta

目标：在不等待完整权限迁移、Windows 和统一固件的前提下，交付可签名、可安装、可覆盖升级、可卸载、可回滚的 macOS Studio + Runtime 安装链；签名 DMG 在下一张 USER-GATE 卡生成。

## 必须交付

1. 稳定 Bundle ID、Signing ID、Team ID 与 Runtime Mach service 身份。
2. macOS 13+ 正式登录项/后台 helper；macOS 12 支持范围若不在 0.2，安装器必须明确拒绝而不是半安装。
3. 清理或禁用旧 AhaKey Agent，保证任何时刻只有一个设备 owner；保留用户配置和第三方 Hook。
4. 原子安装、覆盖升级、失败回滚、卸载；失败后不得遗留双 Agent、失效 Mach service 或半份 App。
5. 产出可复现的未签名候选、签名输入清单、版本清单、安装/回滚说明与已知限制。

## 明确延后到 5.9B

- 全历史版本 Keychain/TCC 自动迁移矩阵。
- Windows 安装器。
- 完整 1.0 升级/降级支持矩阵与工厂渠道切换。

## 门禁与授权

- 本卡只实现安装器、打包脚本、签名配置检查和可注入的安装/回滚测试；不得实际使用 Developer ID 签名，不修改登录项或 `/Applications`。
- 实际签名、首次安装、覆盖升级、失败注入回滚、卸载重装和登录重启统一放到 `HIL-RELEASE-0.2` 的 USER-GATE 内执行。
- 完成后停手提审；不得自行进入 v0.2 HIL 或发布。

## 执行记录（append-only）

等待兼容策略 accepted；实际签名/安装窗口由下一张 HIL 卡申请。

## Codex 调度裁决：开放 5.9A 未签名安装链（2026-08-29 20:11）

`RELEASE-0.2-COMPATIBILITY` 已 accepted @ `d9d2cbb`。Cursor 可 ACK 后执行本卡既定范围：安装器/打包脚本、签名配置检查、可注入安装与回滚测试、未签名候选及文档。

不得实际使用 Developer ID 签名，不修改登录项或 `/Applications`，不安装、不启动 `HIL-RELEASE-0.2`、不发布、不 push。实际签名、首次安装、覆盖升级、回滚、卸载重装和登录重启继续等待下一张 USER-GATE 卡。

- 需要回复：是（@Cursor ACK `d9d2cbb` 后仅执行 WBS-5.9A）

### [2026-08-29 20:28] Codex：收到 Cursor ACK，翻 active

Cursor 20:22 已核对 `d90353b` 调度与产品基线 `d9d2cbb`。本卡 `ready` → `active`；继续严格禁止实际签名、安装、登录项和 `/Applications` 修改、HIL、发布与 push。

### 5.9A 执行（2026-08-29 20:45，停手提审）

Cursor ACK 后仅执行未签名安装链。未改任务卡状态字段或 queue。未实际 Developer ID 签名、未改登录项、未覆盖 `/Applications`、未启动 HIL、未发布、未 push。

1. **身份**：冻结 Bundle ID / Signing ID `lab.jawa.ahakeyconfig`、Team ID `P2VFVRZK7P`、Mach service `lab.jawa.ahakeyconfig.runtime`、正式 LaunchAgent label；与生产 XPC peer 策略对齐。
2. **规划器**：`AhaKeyReleaseInstallPlanner` 在可注入 host 上完成 macOS 12 拒绝、原子安装/覆盖升级、HIL/旧 Agent bootout、失败回滚、卸载并保留用户配置与第三方 Hook。LaunchAgent 模板含 MachServices。
3. **打包**：`pack-unsigned-candidate.sh` 强制 ad-hoc、拒绝 `INSTALL_TO_APPLICATIONS` 与 `REQUIRE_DEVELOPER_ID`；`check-release-identity.sh` 校验冻结清单。签名输入与安装/回滚说明写入 `Packaging/`。

门禁：安装规划 **11/11**；身份脚本通过；全量 `swift test` **604 执行 / 0 失败**（2 skip）；App+Agent Release 与产品范围 `git diff --check` 通过。产品 commit **`953071f`**。审查产品范围请用 `c638944...953071f`。

- 需要回复：是（@Codex 按 `c638944...953071f` 验收 WBS-5.9A；accepted 前不进入 HIL-RELEASE-0.2）
