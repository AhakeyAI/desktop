# Hero Notes

## 组件职责

首页设备 hero，承载设备身份、主视觉、连接状态与进入工作区入口。

## 视觉结构拆解

- 中央空态插图：键盘、鼠标、收纳盒、蓝牙图标、接收器图标。
- 主 CTA：插图下方的 `连接设备`。
- 周边留白：hero 在页面中央，左侧问候语和右上操作区保持远离。
- 标注图中蓝框标出空态插图主体，橙框标出连接设备入口。

## 状态变化规律

目标状态集合：

- `default`
- `hover`
- `selected`
- `disabled`

已捕获状态：

- `default`：来自 `raw-local/home/2026-05-03-home-window-empty-state@2x.png`

## 与 AhaKey 的映射建议

- 对应 [03-home-overview-spec.md](../../03-home-overview-spec.md) 的设备 hero
- 重点借鉴布局、层级、状态摘要位置
- AhaKey 可把 Logi 的空态插图语义改写为 AhaKey 键盘 hero；未连接时保留中央设备视觉和低权重 CTA。

## 明确不照搬的内容

- Logitech 品牌元素
- Logitech 设备渲染
- Logitech 专有文案

## Capture 缺口

- 缺 hover / selected 差异样本
- 缺 CTA 交互状态
- 缺已连接设备 hero 样本
- 缺多设备 hero 样本

## 当前来源比例

- 真实视觉截图：本组件默认态与标注图来自截图。
- React / CSS / Electron 包：用于确认来源 app、版本、资源存在性，不用于本组件几何标注。
- macOS 窗口信息：用于确认截取窗口标题、坐标和尺寸。
