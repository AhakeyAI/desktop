# Permission Card Notes

## 组件职责

语音页中的权限状态卡或引导卡。

## 视觉结构拆解

- 权限名称
- 当前状态
- 下一步动作
- 辅助说明

## 状态变化规律

目标状态集合：

- `default`
- `active`
- `disabled`
- `success`
- `error`

已捕获状态：

- 暂无，待采集

## 与 AhaKey 的映射建议

- 用于输入监控、辅助功能、麦克风、语音识别等权限表达

## 明确不照搬的内容

- Logitech 不相关的权限语义

## Capture 缺口

- 缺缺权限 / 已授权 / 错误态样本
