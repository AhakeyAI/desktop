# AhaKey Studio macOS — 重设计文档索引

更新时间：2026-05-02

## 目录定位

本目录存放 AhaKey Studio macOS 客户端的 UI/UX 重设计过程中产生的**决策文档、设计规范和架构思考**。

与 `docs/` 根目录下的文档的区别：
- 根目录文档（`ahakey-native-director-brief.md`、`02-ux-blueprint.md`）是**当前已落地实现的规范**
- 本目录文档是**正在演进中的重设计方向**，经过审批后会合并或替换根目录文档

## 设计参考基准

| 参考产品 | 借鉴维度 | 不借鉴维度 |
|---------|---------|----------|
| Logi Options+ | 首页设备 hero、信息架构分层、Settings 层级、右上角操作区 | 多设备生态复杂度、Flow 跨设备功能 |
| Typeless | 侧栏克制、试用卡样式、权限引导优雅度 | 仪表盘指标、历史记录页 |
| Via / QMK Configurator | 画布点击配置交互、按键映射 UX | 工程师向的信息密度 |

## 文档列表

| 文件 | 内容 | 状态 |
|------|------|------|
| [00-glossary.md](./00-glossary.md) | **概念词汇表（所有文档的用词基准）** | 规范 |
| [01-home-page.md](./01-home-page.md) | 首页（设备 Hero 页）重设计规范 | 草稿 |
| [02-device-studio-page.md](./02-device-studio-page.md) | 设备配置页（Studio）重设计规范 | 草稿 |
| [03-ux-state-machine.md](./03-ux-state-machine.md) | UX 状态机：连接/控制权/草稿同步三层状态 | 草稿 |
| [04-navigation-architecture.md](./04-navigation-architecture.md) | 全局导航架构与页面拆分方案 | 待写 |
| [04-settings-hierarchy.md](./04-settings-hierarchy.md) | Settings 面板层级规范 | 待写 |
| [05-voice-page.md](./05-voice-page.md) | 语音设置页重设计规范 | 待写 |
| [06-agent-page.md](./06-agent-page.md) | Agent 控制台页重设计规范 | 待写 |
| [logi-options-plus-reference-spec/09-web-electron-prototype-spec.md](./logi-options-plus-reference-spec/09-web-electron-prototype-spec.md) | **下一轮 Web / Electron 原型交付 spec** | 草稿 |
| [logi-options-plus-reference-spec/10-inspector-content-spec.md](./logi-options-plus-reference-spec/10-inspector-content-spec.md) | **Inspector 逐部件内容边界与信息披露层次** | 草稿 |

## 专题目录

| 目录 | 内容 | 状态 |
|------|------|------|
| [logi-options-plus-reference-spec/](./logi-options-plus-reference-spec/00-index.md) | 以 Logi Options+ 为高保真参考样本的前台壳重构专题 spec | 草稿 |

## 下一轮执行口径

截至 2026-05-03，下一轮优先做 **Web 前端原型**，必要时再用薄 Electron 壳包装给合作者体验；不在本轮完整构建 macOS 桌面应用。SwiftUI 拆分方案保留为后续原生迁移参考。

## 核心设计判断（持续更新）

1. **首页是设备选择器，不是功能入口。** 用户打开 App 的第一个问题是"我要配置哪个设备"，而不是"我要用哪个功能"。即使当前只有一个设备，首页也应该以设备 hero 为中心，为生态扩展预留结构。

2. **三条产品主线必须分离。** 配置主线（键盘编辑）、状态反馈主线（Agent/Hook/灯效）、控制权主线（App vs Agent 蓝牙占用）不能混在同一个页面。每个导航目的地只回答一个问题。

3. **Inspector 只做属性编辑。** 语音配置、Agent 状态、权限管理不属于 Inspector 的职责范围，应该迁移到独立页面。Inspector 的职责是：当前选中硬件部件的属性编辑面板。

4. **Settings 是元操作的容器。** 只有"不属于任何具体功能页面、但影响全局行为"的操作才进 Settings。具体功能的配置（语音预设、Agent 选择）留在对应功能页面。
