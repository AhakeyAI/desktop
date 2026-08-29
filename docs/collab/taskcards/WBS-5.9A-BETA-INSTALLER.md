# 任务卡 WBS-5.9A-BETA-INSTALLER：0.2 最小签名安装链

计划/WBS：5.9A / 0.2
状态：`draft`
执行 owner：Cursor（Codex 验收）
基线：`RELEASE-0.2-COMPATIBILITY` accepted 后冻结
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
