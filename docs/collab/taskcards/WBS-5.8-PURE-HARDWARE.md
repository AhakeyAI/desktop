# 任务卡 WBS-5.8-PURE-HARDWARE：纯硬件语音零 Runtime

计划/WBS：5.8  
状态：`draft`  
执行 owner：Cursor  
基线：5.4、4.3、5.7 accepted 后冻结  
目标：删除 Studio 无条件语音启动，确认系统听写/Typeless 等纯硬件路径不启动、不监听 Runtime；仅 AhaType 需要 Runtime。

允许修改：macOS 启动策略、语音配置 UI/迁移、生命周期测试。  
禁止：不改固件平台动作，不把系统听写称为 AhaType，不削弱已启用后台 AI/防休眠持续性。  
完成定义：系统/第三方语音零 Runtime；AhaType 正确启停；配置迁移明确；Studio 退出行为符合策略；进程/麦克风/CPU 证据通过。  
前置：5.4、4.3、5.7 accepted。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。
