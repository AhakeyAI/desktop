# 任务卡 HIL-RELEASE-0.2：当前量产固件的 0.2 发布门禁

计划/WBS：6.0A / v0.2
状态：`draft`（`USER-GATE`）
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
