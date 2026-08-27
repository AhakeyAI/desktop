# 任务卡 WBS-3-LEVER-MACROS：拨杆三档快捷键与宏

计划/WBS：3.1-3.6  
状态：`draft`  
执行 owner：Zcode
基线：WBS 2 accepted 提交  
目标：拨杆每档可配置硬件快捷键/宏，同时继续独立发布 Runtime 状态；硬件动作与自动批准语义正交。

允许修改：统一固件 LeverBinding/InputAction/协议模块与测试。  
禁止：不在固件里编码 Cursor/Kimi/Codex 批准策略；不让 Runtime 开关影响硬件动作。  
完成定义：三档模型；edge/debounce/开机抑制；快捷键/宏/release-all；重入与上传/升级互锁；v4 读写；Runtime 状态通知。  
测试：每档 500 次、快速拨动、休眠唤醒、断连、宏中断、卡键/重复/丢状态为零。  
前置：WBS 2 accepted。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。
