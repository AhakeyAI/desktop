# Canvas Hotspot Notes

## 组件职责

工作区中央设备画布上的可交互热区。

## 视觉结构拆解

- 热区边界
- 选中高亮
- hover 反馈
- 焦点与禁用表达

## 状态变化规律

目标状态集合：

- `default`
- `hover`
- `selected`
- `focused`
- `disabled`

已捕获状态：

- 暂无，待采集

## 与 AhaKey 的映射建议

- 对应当前 `AhaKeyKeyboardCanvasView` 中的热区交互

## 明确不照搬的内容

- Logitech 设备外形
- Logitech 功能标签

## Capture 缺口

- 缺热区 hover / selected / focused 样本
