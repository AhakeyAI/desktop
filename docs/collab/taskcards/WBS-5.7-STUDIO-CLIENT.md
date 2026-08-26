# 任务卡 WBS-5.7-STUDIO-CLIENT：Studio 纯 Runtime 客户端化

计划/WBS：5.7  
状态：`draft`  
执行 owner：Cursor  
基线：HIL-CONFIG-TRANSACTIONS accepted 后冻结  
目标：Studio 仅通过 XPC snapshot/event/operation 管理 Runtime，删除生产直连 BLE/USB。

允许修改：macOS Studio App/Views/ViewModels/Shared XPC client、对应测试；精确清单晋级时冻结。  
禁止：不复制设备状态事实源；不保留隐藏生产直连 fallback；不改 Runtime wire v1.1。  
完成定义：snapshot 首屏；event cursor/断档刷新；operation 进度/取消/错误；诊断按需观察；Studio 退出不影响 Runtime；生产目标无 BLE/USB owner。  
测试：UI reducer、重连/重放/断档、Runtime 离线、取消、进程退出；完整 Swift 测试/Release build。  
前置：5.2、5.6 与配置 HIL accepted。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。

### [2026-08-25 23:46] Codex 预登记 F-HIL2-1

- HIL-RUNTIME-2：Studio 直连 0x99 三次超时进受限模式（`ble-comm.log` ~23:39）；同固件 Agent 路径 v3 正常。本卡删除 Studio 生产直连时一并关闭。不在 5.6 修。
