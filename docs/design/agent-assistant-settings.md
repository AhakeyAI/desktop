# Agent 助手设置（Pet 三分段）

Settings「Agent」Tab = AI 工作流管家（状态、Hook、批准语义、对话管理），**不是**第二套改键台。改键唯一入口在「硬件设备」。侧栏暂不改名。

## IA

```text
Agent
├ 助手（默认）     日常对话下达；顶栏「外观」直达 Agent · 设置（皮肤/图标）
├ 联动             启用主路径常开；高级设置折叠
└ 设置             Pet 皮肤与图标；跳转 / 安全边界折叠
```

| 分段 | title | subtitle |
|------|-------|----------|
| assistant | 助手 | 对话下达 |
| status | 联动 | 启用与蓝牙 |
| general | 设置 | 皮肤与图标 |

视觉：顶部分段 + `AhakeySettingsTheme`；助手为 Chatbot（输入贴底）。

## 高频 / 低频

| 优先级 | 行为 | 入口 |
|--------|------|------|
| 日常 | 查联动、切蓝牙、对话跳转 | 助手 |
| 上手 | 一键启用联动、装 Cursor Hook、蓝牙给 Agent | 联动（常开） |
| 外观 | Pet 皮肤 / 状态图标 | Agent · 设置 |
| 岛侧 | 信息层、尺寸、动画、GIF | 灵动岛 · 组件库 · OLED Pet |
| 低频 | 卸载守护、其它 IDE Hook、Mode/批准、诊断、改键说明 | 联动/设置折叠 |

## 联动页常开

1. **就绪摘要** +「一键启用联动」（未装 `install()`；已装则 `start()` + 蓝牙交给 Agent）
2. **蓝牙占用**
3. **Hook 概览** + Cursor 主按钮；其它 IDE 在高级

折叠「高级设置」：守护细节、Claude/Codex/Kimi Hook、Mode·批准、诊断入口。

## 助手对话（本版）

- 本地自然语言 + 4 芯片：查联动状态、一键启用联动、蓝牙交给 Agent、打开联动页
- 意图 `enableLinkage` 与联动页主按钮同语义
- **不接云端 LLM**

## 边界

| 区域 | 职责 |
|------|------|
| Agent · 助手 | 日常对话 |
| Agent · 联动 | 启用与蓝牙 |
| Agent · 设置 | Pet **皮肤与图标**（主入口）；边界与跳转 |
| 灵动岛 · 组件库 · OLED Pet | 信息层、尺寸、动画、软件岛 GIF；模块显隐/排序 |
| 硬件设备 | 按键映射、Mode |
| 我的设备 | 改名、电量、诊断 |

## 代码

| 概念 | 文件 |
|------|------|
| 分段枚举 | `AhaKeySettingsTypes.swift` |
| 根容器 | `AhaKeyAgentWorkspacePane.swift` |
| 助手 / 联动 / 设置 | `AhaKeyAgentAssistantPane` / `Status` / `General` |
| Pet 皮肤/图标 | `AhaKeyPetAppearanceEditor` |
| 岛侧 Pet | `AhaKeyOledPetIslandSettingsEditor` / `AhaKeyOledPetSettingsPane` |
| 意图与工具 | `AgentAssistantTools.swift` |
