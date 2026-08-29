# 任务卡 WBS-4-STUDIO-V4：Studio v4 模型、配置与界面

计划/WBS：4.1-4.8  
状态：`draft`  
执行 owner：Cursor  
目标版本：v0.4（4.1-4.4）、v0.5（4.5）、v1.0（4.6-4.8）
基线：每个版本 slice 晋级时由 Codex 分别冻结；4.1-4.4 不等待 WBS 3
目标：让 Studio 配置统一固件的平台、语音与拨杆宏，支持能力降级、事务保存和旧配置迁移。

允许修改：晋级时列出的 `ahakeyconfig-mac/Sources/Models|Shared|Views/**`、对应测试；Windows 客户端另在 5.10 卡处理。  
禁止：不直接接管 Runtime 设备 ownership；不把旧固件显示成支持 v4；不复制协议常量到多处。  
完成定义：v4 模型/编解码；VoicePreset 迁移；系统/Typeless/AhaType UI；平台来源/覆盖；拨杆三档快捷键/宏 UI；事务保存/回滚；旧配置提示与能力 `0x99` 降级。  
测试：模型 round-trip、迁移 fixture、能力矩阵、保存失败回滚、UI state；完整 Swift 测试/Release build。  
前置按切片：4.1-4.4 依赖 WBS 2；4.5 依赖 WBS 3；4.6-4.8 在 1.0 收口。任何切片不得恢复 Studio 生产直连长期架构，也不得阻塞更早版本。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。

### [2026-08-25 23:57] Codex：4.1 模型冻结改由 5.6 第 0 刀承担

- 用户批准 waive 整张本卡对 5.6 的前置。4.2–4.8 UI 仍本卡、仍 draft。禁止 Studio 另立 JSON schema。
