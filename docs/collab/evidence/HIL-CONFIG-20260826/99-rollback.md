# HIL-CONFIG 2026-08-26 — 回滚记录

## 触发回滚原因
主会话 18:22 解决双 agent 冲突后沉默 1h20m；agent PID 44695 卡住 1h27m（0% CPU，状态 S，持 BLE lock，无证据产出）。
18:37 阻塞上报、18:42 接管声明均无回应。

## 回滚执行（19:44–19:46）
1. `launchctl bootout gui/$(id -u)/lab.jawa.ahakeyconfig.agent` — agent 进程终止，验证无残留。
2. 恢复 plist：`cp /tmp/lab.jawa.ahakeyconfig.agent.plist.bak ~/Library/LaunchAgents/lab.jawa.ahakeyconfig.agent.plist` — diff 确认与备份完全一致。
3. 恢复应用：`mv '/Applications/AhaKey Studio.app' '/Applications/AhaKey Studio.app.hil-new'` → `mv '/Applications/AhaKey Studio.app.hil-backup' '/Applications/AhaKey Studio.app'`。
4. 清理临时文件：`rm -rf '/Applications/AhaKey Studio.app.hil-new'`。

## 回滚验证
- `pgrep ahakeyconfig-agent`：无进程。
- `launchctl list | grep ahakeyconfig`：无服务。
- `launchctl print gui/$(id -u) | grep ahakeyconfig`：无残留。
- Plist diff 与备份 100% 匹配。

## 状态
HIL-CONFIG 因 agent 卡住阻塞，C1–C6 未执行。请求 Codex/用户裁决是否重新安排测试窗口。
