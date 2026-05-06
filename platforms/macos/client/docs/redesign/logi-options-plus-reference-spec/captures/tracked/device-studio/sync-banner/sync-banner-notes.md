# Sync Banner Notes

## 组件职责

工作区内同步与脏状态提示条。

## 视觉结构拆解

- 提示文案
- 状态色
- 次动作

## 状态变化规律

目标状态集合：

- `default`
- `dirty`
- `syncing`
- `success`
- `error`

已捕获状态：

- 暂无，待采集

## 与 AhaKey 的映射建议

- 直接服务于 AhaKey 特有的草稿 / 同步状态机

## 明确不照搬的内容

- Logitech 不具备的状态语义不强行套用

## Capture 缺口

- 缺完整状态样本
