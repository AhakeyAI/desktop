# Firmware-driven Intake — Windows Harness v1.3

目标：Owner 只表达“开始联调下一阶段 Firmware”。DLA 从已绑定的只读 Firmware 仓主动发现正式证据，形成 Windows planned intake；Owner 不搬运本地已有工程事实。

## 事实优先级
1. Firmware Harness state / module / journey
2. formal checkpoint / gate receipt
3. candidate build / HEX identity
4. protocol contract
5. actual implementation
6. host / golden / regression tests
7. Firmware Owner UAT requirement

不得只按文件时间、目录名或“最新”字样选择功能。

## Cursor
`.ahakey-desktop-harness/firmware-sync.json` 保存 Windows 已消费到的 Firmware gate。首次 v1.3 安装若无 cursor，状态为 `uninitialized`。DLA 使用既有 Windows/Firmware evidence 做一次历史 reconcile；不要求 Owner 重新抄 gate/HEX/SHA。

## Commands
- `firmware-status --role DLA`：查看绑定与 cursor。
- `firmware-discover --role DLA [--limit N] [--json]`：只读扫描正式 gate 证据。
- `firmware-intake --id WD-002 --gate <firmware-relative-path> --role DLA`：写 Windows planned evidence binding；不创建正式 change、不 activate。
- `firmware-sync-baseline --gate ... --windows-change WD-001 --evidence-record <windows record> --role DLA`：首次历史 cursor reconcile。
- `firmware-mark-consumed --gate ... --windows-change WD-002 --evidence-record <windows record> --role DLA`：仅 CLOSED change 可推进 cursor。

所有路径必须位于绑定的 Firmware root 内；命令不执行 Firmware 脚本、不构建、不烧录、不修改 Firmware。

## Owner 何时介入
只有：
- 多个同等有效的新 formal gate，需要决定优先级；
- Firmware 证据不能决定 Windows 产品行为；
- 最终真实设备体验确认。

缺正式证据时，DLA 报告 Firmware-side blocker；不能让 Owner 手工重述仓库中已有数据，也不能由 Windows Harness 伪造缺失 gate。
