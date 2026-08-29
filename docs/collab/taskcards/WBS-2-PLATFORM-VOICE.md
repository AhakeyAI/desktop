# 任务卡 WBS-2-PLATFORM-VOICE：跨平台纯硬件语音

计划/WBS：2.1-2.8  
状态：`draft`  
执行 owner：Zcode
目标版本：v0.4
基线：WBS 1 accepted 提交  
目标：设备连接电脑后学习/识别 Mac 与 Windows，无 Studio/Runtime 时发送 macOS F5、Windows Win+H 或用户选择的第三方语音模板。

允许修改：统一固件 HostPlatform/InputAction/协议模块与测试；不得修改客户端 UI。  
禁止：Unknown 平台不得猜测并误发；不得把 AhaType 当固件内转写；不硬编码 Fn 等价于 F5。  
完成定义：HostPlatform FSM；USB probe；host hint/用户覆盖/bond cache；InputAction；系统语音；Fn/Globe 或 F19 fallback；OLED Unknown 选择；v4 capabilities/platform/action。  
测试：Mac/Windows × USB/BLE、平台切换/缓存/覆盖、release-all、Studio 完全退出；Unknown 不误发。  
前置：v0.3/WBS 1 accepted，WBS-0.3/WBS-0.6 结论可用；不阻塞 v0.2/v0.3。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。
