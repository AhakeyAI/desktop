# 任务卡 WBS-5.10-WINDOWS-SEAM：Windows Runtime Adapter 与 Studio 对齐

计划/WBS：5.10、4.7  
状态：`draft`  
执行 owner：Cursor  
基线：5.9 accepted 后由 Codex 冻结 Windows 客户端基线  
目标：抽象 macOS interface 的跨平台语义，定义并实现 Windows Adapter/Studio v4 对齐，不复制平台无关业务规则。

允许修改：晋级时指定的 `ahakeyconfig-win*` 主实现、跨平台协议 fixture、文档与测试。  
禁止：未完成基线裁决不得同时修改多个 Windows 历史客户端；不照搬 XPC/libxpc；不改变固件 v4 语义。  
完成定义：选择唯一 Windows 主线；Runtime Adapter 边界；v4 models/UI；Win+H/平台状态/拨杆宏；安装升级；N/N-1 fixture 与 macOS 语义一致。  
测试：Windows 当前/上一支持版本、USB/BLE、Studio 退出纯硬件语音、协议 fixture。  
前置：5.9 accepted；Codex 先裁决唯一 Windows 代码库。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。
