# 任务卡 WBS-5A-SESSION-ROUTING：最近待操作会话定向

计划/WBS：5A.1-5A.11  
状态：`draft`  
执行 owner：Kimi  
基线：基础版 WBS 5.9 accepted 后冻结  
目标：实现 session/turn/client/owner envelope、Registry/Selector/Lease 与 Codex App 精确目标 Adapter，错误目标时绝不注入。

允许修改：Runtime session routing、Hook envelope、Codex App Adapter、Terminal Adapter、测试/诊断；晋级时按子切片收敛白名单。  
禁止：不按 cwd 猜目标；不在 deep link/权限失败时降级向错误窗口输入；不让 5A 阻塞基础版发布。  
完成定义：5A.1-5A.11 每项有独立逻辑提交和测试；两个相同 cwd 不串线；手势期间 lease 目标不漂移；安全草稿/TTL/崩溃恢复；N/N-1；隐私化 session hash/latency。  
测试：Codex App join/navigation/activation receipt、目标关闭/权限失败、iTerm2/tmux beta、多会话错误注入、6.4A。  
前置：0.7、5.4、5.9 accepted。该大卡晋级前 Codex 必须拆成 5A.1-5A.11 子卡，当前卡只是完整 backlog 边界。

## 执行记录（append-only）

等待基础版与拆卡。
