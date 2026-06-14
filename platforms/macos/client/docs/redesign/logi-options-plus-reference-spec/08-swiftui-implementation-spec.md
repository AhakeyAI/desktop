# SwiftUI 实现映射 Spec

更新时间：2026-05-02
状态：草稿，现作为后续原生迁移参考

---

## 1. 文档定位

本文档把前面的产品 spec 直接翻译成 SwiftUI 实现层的拆分约束。

2026-05-03 更新：

下一轮优先执行路径已调整为 [Web / Electron 原型交付](./09-web-electron-prototype-spec.md)。本文档暂不作为下一轮直接实施计划，而是保留为页面边界稳定后迁移到 SwiftUI 原生客户端时的参考。

它回答的问题是：

- 页面应该怎样拆
- 共享样式层应该怎样落
- 当前 `AhaKeyStudioView` 应怎样被拆解
- 哪些状态模型要上升为页面级导航状态
- 哪些底层服务保持不动

---

## 2. 实现目标

本轮实现不是“给现有视图补几个 panel”，而是做一次**前台壳层重构**。

目标：

1. `ContentView` 不再直接承载当前 studio
2. 首页与设备工作区分层
3. 工作区与次级页面分层
4. Inspector 职责收敛
5. 样式系统抽离

非目标：

- 改 BLE 协议
- 改 `AgentManager` / `VoiceRelayService` 的核心逻辑
- 改固件命令结构

---

## 3. 建议的视图拆分

### 3.1 顶层

建议新增：

- `AppRootView`
- `HomeView`
- `StudioView`
- `Settings` scene

当前：

- `ContentView` 直接包 `AhaKeyStudioView`

目标：

- `ContentView` 或 `AppRootView` 只负责顶层导航分发

### 3.2 设备工作区

建议把当前 `AhaKeyStudioView` 拆成至少以下几个部分：

- `StudioToolbar`
- `StudioSidebar`
- `PlatformSwitcher`
- `StudioCanvasHost`
- `StudioInspectorHost`
- `StudioStatusBanner`
- `StudioBottomStatus`

### 3.3 次级页面

建议新增：

- `AgentPageView`
- `VoicePageView`
- `DeviceInfoPageView`

这些页面作为 `StudioView` 中央区域的替代内容，而不是 sheet 拼凑物。

### 3.4 首页

建议新增：

- `DeviceHeroCard`
- `QuickActionsPopover`
- `AddDeviceSheet`

---

## 4. 建议的状态模型拆分

### 4.1 顶层导航状态

需要新增一个顶层导航状态模型，至少包含：

- 当前顶层页面
- 当前设备 id / 当前设备引用
- 当前是否显示设置

### 4.2 Studio 页面状态

设备工作区需要独立页面状态模型，至少包含：

- 当前平台
- 当前页面级导航项
- 当前选中部件
- 当前是否显示 inspector

### 4.3 运行状态模型

在不改服务层的前提下，需要增加一个**面向页面的聚合状态层**，把底层服务翻译成 UI 能直接消费的状态。

例如聚合出：

- `connectionState`
- `controlState`
- `syncState`

而不是让页面到处自己拼：

- `bleManager.isConnected`
- `agentManager.bluetoothConnectionOwner`
- `isSyncing`
- `studioDraft != lastSyncedDraft`

### 4.4 视图状态 vs 服务状态

必须明确区分：

- 服务状态：来自 BLE / Agent / Voice 单例
- 页面状态：当前用户正在看哪里、选中了什么

这两层不能继续混在同一个巨型 view 里。

---

## 5. 样式系统建议

### 5.1 新建共享 UI 样式层

建议新增独立样式文件或目录，承载：

- 色彩 token
- 字体角色
- 圆角等级
- 面板样式
- 状态 pill 样式
- banner 样式

### 5.2 避免继续在页面内散落样式

当前 `AhaKeyStudioView` 已经包含大量局部渐变、描边、圆角、阴影逻辑。

重构时应把这些收口到共享样式层，避免：

- 首页一套风格
- 工作区一套风格
- 次级页面再一套风格

---

## 6. 现有 `AhaKeyStudioView` 迁移策略

### 6.1 保留的部分

当前可直接复用或局部重包的部分：

- 键盘画布逻辑
- 热区选中逻辑
- OLED 预览相关视图
- 同步命令拼装逻辑

### 6.2 需要拆出的部分

必须从 `AhaKeyStudioView` 中拆出的部分：

- 顶栏
- 左侧导航
- 页面级状态表达
- 后台服务 / 语音 / 设备信息的入口与承载
- 全局状态提示

### 6.3 需要降级职责的部分

Inspector 应降级为：

- 只处理当前部件属性编辑

不再承载：

- 全局语音页职责
- 后台服务页职责
- 设备信息整页职责

---

## 7. 数据流建议

### 7.1 自上而下的导航分发

顶层页面切换从 root state 下发。

### 7.2 服务状态聚合

建议增加一层 UI-facing adapter / store，把：

- `AhaKeyBLEManager`
- `AgentManager`
- `VoiceRelayService`

聚合成页面可直接消费的状态对象。

### 7.3 草稿编辑流

建议保留草稿在本地编辑、显式同步的模型，但把“脏状态判断”和“同步状态文案”统一封到页面状态层。

---

## 8. 页面级实现顺序

建议的实现顺序：

1. 建立 root navigation 与 `HomeView`
2. 拆出 `StudioView` 框架（顶栏 / 左栏 / 中央 / 右栏）
3. 把现有 `AhaKeyStudioView` 内容迁入 `StudioCanvasHost + StudioInspectorHost`
4. 实现 `AgentPageView / VoicePageView / DeviceInfoPageView`
5. 新建共享样式层
6. 再做视觉统一与交互精修

理由：

- 先把信息架构站稳
- 再把功能从单视图里搬出来
- 最后做视觉收口

---

## 9. 回归边界

本轮重构必须确保不破坏以下能力：

- BLE 自动连接与手动连接
- BLE 抑制逻辑（交给后台守护进程时本 App 不抢连）
- 现有同步命令链路
- OLED 上传链路
- Voice Relay 路由更新
- 后台守护进程安装与状态检测

如果某次页面重构导致上述能力异常，应视为阻断问题，而不是“后面再看”的视觉问题。

---

## 10. 验收标准

### 10.1 工程结构验收

另一个工程师应能根据本文，直接开始建立：

- 顶层导航
- 首页
- Studio 页面壳
- 次级页面
- 样式系统

### 10.2 代码边界验收

应能明确判断：

- 哪些逻辑还留在服务层
- 哪些逻辑属于页面状态聚合层
- 哪些视图只负责渲染

### 10.3 产品一致性验收

应能确保：

- 页面结构符合前面的信息架构 spec
- 状态表达符合状态机 spec
- 视觉语气符合视觉系统 spec

如果实现时仍要频繁重新决定“这个页面到底归谁管”，说明这份实现 spec 还不够完整。
