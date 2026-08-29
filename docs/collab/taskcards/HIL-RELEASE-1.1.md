# 任务卡 HIL-RELEASE-1.1：会话定向发布门禁

计划/WBS：6.4A / v1.1
状态：`draft`（`USER-GATE`）
执行 owner：Cursor
验证协作者：Zcode；Codex 验收
基线：WBS 5A accepted 的不可变候选

目标：验证精确会话选择、TargetLease、安全草稿和 Adapter 升级失效时不会向错误目标注入。

完成定义：相同 cwd 多会话；等待批准/等待继续/工作中优先级；手势期间目标不漂移；目标关闭与权限失败；Codex App N/N-1；iTerm2/tmux beta；从 v1.0 升级与只回退会话定向。

禁止：不得让本卡阻塞 v1.0；不得以按 cwd 猜测或向前台窗口粘贴作为降级。

## 执行记录（append-only）

等待 WBS 5A accepted 与用户多会话测试窗口。
