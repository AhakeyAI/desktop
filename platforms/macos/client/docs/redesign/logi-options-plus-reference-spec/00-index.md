# AhaKey Studio macOS - Logi Options+ Reference Spec

更新时间：2026-05-02
状态：专题参考 spec（高保真重构工作底稿）

---

## 1. 目录目的

本目录用于沉淀一套**以 Logi Options+ 为高保真参考，对 AhaKey Studio 前台壳做高保真重构**的详细 spec。

这不是一套“直接替换现有正式规范”的文档，而是一组为下一轮重构服务的**专题参考文档**。它回答的问题不是“当前代码已经是什么”，而是：

- Logi Options+ 的前台产品壳到底有哪些值得借鉴的结构
- 哪些借鉴适合 AhaKey，哪些不适合
- AhaKey 特有的 BLE / Agent / 草稿同步复杂度，应该如何嫁接到 Logi 式 UI/UX 语言里
- 后续 Web / Electron 原型与 SwiftUI 原生重构时，页面、组件、导航和状态层应该怎样拆

---

## 2. 与现有文档的关系

本目录与以下文档并行存在：

- [00-redesign-index.md](../00-redesign-index.md)：`redesign/` 的总索引
- [00-glossary.md](../00-glossary.md)：所有重设计文档的用词基准
- [02-ux-blueprint.md](../../02-ux-blueprint.md)：当前已落地原生实现的首版蓝图

关系说明：

1. [02-ux-blueprint.md](../../02-ux-blueprint.md) 记录的是**当前首版已落地实现**。
2. `redesign/` 目录下原有草稿，记录的是**AhaKey 自身正在演进中的重设计方向**。
3. 本目录记录的是**“以 Logi Options+ 为高保真参考样本”这条专题线**，重点是把参考对象、迁移原则和实现拆分写清楚。

因此，本目录的文档默认都属于：

- 正在演进中的参考 spec
- 可以指导实现
- 但不会自动替代根级正式规范

只有在后续重构真正落地并经过审批后，才会把其中稳定的部分提升为正式规范，或并入根级文档。

---

## 3. 阅读顺序

建议按以下顺序阅读：

1. [01-reference-baseline.md](./01-reference-baseline.md)
2. [02-information-architecture.md](./02-information-architecture.md)
3. [03-home-overview-spec.md](./03-home-overview-spec.md)
4. [04-device-studio-spec.md](./04-device-studio-spec.md)
5. [05-secondary-pages-spec.md](./05-secondary-pages-spec.md)
6. [06-state-machine-spec.md](./06-state-machine-spec.md)
7. [07-visual-system-spec.md](./07-visual-system-spec.md)
8. [09-web-electron-prototype-spec.md](./09-web-electron-prototype-spec.md)
9. [08-swiftui-implementation-spec.md](./08-swiftui-implementation-spec.md)

阅读逻辑：

- `01` 先界定“参考对象是什么、我们看到了什么、哪些不能照搬”
- `02~05` 给出前台产品壳与各页面 spec
- `06` 单独处理 AhaKey 最复杂的状态问题
- `07` 把“像 Logi”收敛成可执行的视觉与组件规则
- `09` 定义下一轮优先执行的 Web / Electron 原型交付边界
- `08` 保留为后续 SwiftUI 原生迁移参考

---

## 4. 文档列表

| 文件 | 作用 | 状态 |
|------|------|------|
| [01-reference-baseline.md](./01-reference-baseline.md) | Logi 参考样本基线、可观察证据、借鉴边界 | 草稿 |
| [02-information-architecture.md](./02-information-architecture.md) | AhaKey 前台信息架构与导航骨架 | 草稿 |
| [03-home-overview-spec.md](./03-home-overview-spec.md) | 首页设备总览页详细 spec | 草稿 |
| [04-device-studio-spec.md](./04-device-studio-spec.md) | 设备工作区详细 spec | 草稿 |
| [05-secondary-pages-spec.md](./05-secondary-pages-spec.md) | Agent / 语音 / Settings / 设备信息等次级页面 spec | 草稿 |
| [06-state-machine-spec.md](./06-state-machine-spec.md) | BLE / 控制权 / 草稿同步三层状态机 | 草稿 |
| [07-visual-system-spec.md](./07-visual-system-spec.md) | 视觉系统、token 与组件语气 | 草稿 |
| [09-web-electron-prototype-spec.md](./09-web-electron-prototype-spec.md) | 下一轮 Web / Electron 原型交付 spec | 草稿 |
| [10-inspector-content-spec.md](./10-inspector-content-spec.md) | Inspector 逐部件内容边界与信息披露层次 | 草稿 |
| [08-swiftui-implementation-spec.md](./08-swiftui-implementation-spec.md) | SwiftUI 重构拆分与实现约束，现作为后续原生迁移参考 | 草稿 |

附属目录：

- [captures](./captures/)：后续存放截图、标注图、页面比对图，仅做内部参考

---

## 5. 本目录的适用边界

本目录默认采用以下边界：

### 5.1 借鉴对象

借鉴的是 Logi Options+ 的：

- 信息架构
- 页面骨架
- 导航层次
- 工作区组织方式
- 组件语气
- 视觉节奏
- 设置层级

不是借鉴它的：

- 设备生态规模
- Flow 自动化能力
- Logitech 品牌表达
- 云服务 / 账户体系
- 具体后端协议和业务能力

### 5.2 实现目标

目标是让 AhaKey 的前台壳达到：

- 用户第一次打开时更像成熟桌面产品
- 页面职责更清晰
- AhaKey 的复杂状态被表达清楚
- 后续拆 Web / Electron 或 SwiftUI 组件和页面时有明确边界

不是目标：

- 做一份法律意义上的逐像素复制
- 在本阶段改变 BLE / Agent / Voice 后端协议
- 直接从 Logi 包里搬资源进正式产物

### 5.3 下一轮交付口径

截至 2026-05-03，下一轮优先交付不再是完整 macOS 原生应用，而是：

- 先做浏览器可运行的 Web 前端原型
- 必要时用极薄 Electron 壳包装给合作者体验
- 不在本轮接入真实 BLE、系统权限、后台协议或完整桌面发布链路

详见 [09-web-electron-prototype-spec.md](./09-web-electron-prototype-spec.md)。

---

## 6. 输出标准

本目录下的每份文档都应该做到：

1. 另一个工程师读完后可以直接开始拆页面、建组件、重构导航
2. 不需要再追问“这个页面回答什么问题”
3. 不需要再追问“这个状态到底显示在哪里”
4. 不需要再追问“哪些行为是 Logi 式参考，哪些是 AhaKey 特有补丁”

如果后续阅读时发现某份文档仍需要大量口头补充，说明那份 spec 仍未完成。
