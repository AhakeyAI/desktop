# Inspector Notes

## 组件职责

设备工作区右侧属性面板。

## 视觉结构拆解

- 标题区
- 主配置区
- 辅助说明
- 高级区
- 状态提示区

## 状态变化规律

目标状态集合：

- `default`
- `active`
- `selected`
- `disabled`
- `error`

已捕获状态：

- 暂无，待采集

## 与 AhaKey 的映射建议

- 对应工作区的 `StudioInspector`
- 重点借鉴结构化布局与密度，不继续把跨硬件功能塞进去

## 明确不照搬的内容

- Logitech 专有字段
- Logitech 业务流程

## Capture 缺口

- 缺默认态、选中态、错误态样本
- 缺字段组间距与状态提示样本
