# Platform Switcher Notes

## 组件职责

设备工作区高层上下文切换器，对应不同平台 / 应用上下文。

## 视觉结构拆解

- 图标 / 标签区
- 当前选中指示
- 未选中项弱化方式

## 状态变化规律

目标状态集合：

- `default`
- `hover`
- `pressed`
- `selected`
- `disabled`

已捕获状态：

- 暂无，待采集

## 与 AhaKey 的映射建议

- 对应 `Claude Code / Cursor / Codex` 平台切换器
- 重点参考它作为“上下文切换器”而非传统 segmented control 的语气

## 明确不照搬的内容

- Logitech 应用图标
- Logitech 应用列表语义

## Capture 缺口

- 缺默认态、hover、selected 对照
- 缺禁用 / 不可切换样本
