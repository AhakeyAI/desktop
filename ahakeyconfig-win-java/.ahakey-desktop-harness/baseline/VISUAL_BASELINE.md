# 真实 UI / Design System 基线

状态：SOURCE_INFERRED_ONLY。当前没有运行截图或录屏，以下仅为源码结构推断，不是视觉验收。

| 页面/入口 | 当前截图/窗口条件 | Java/FXML/CSS 位置 | 已确认结构事实 | Preserve/统一候选 | 缺口 |
|---|---|---|---|---|---|
| 主窗口 | 无截图；源码默认 1280x820，最小 800x600 | `App.java`、`style.css` | `BorderPane`：TopBar / ScrollPane(HBox Canvas+Inspector) / StatusBar；窗口标题 `AhaKey Studio` | 保留单窗口工作台和顶部主状态 | 需运行截图确认视觉、拥挤、高 DPI、文本溢出 |
| TopBar | 无截图 | `TopBar.java`、`style.css`、messages | 标题、连接状态 pill、电量、拨杆、连接/断开、BLE driver、AhaType、语音、配置保存、More 菜单 | 普通用户主操作集中在顶部；诊断入口收在 More 或支持弹窗 | 当前 TopBar 横向内容较多，需截图判断是否拥挤 |
| CanvasPane | 无截图 | `CanvasPane.java`、`CanvasLayout.fxml`、`CanvasController.java` | 模式切换 + 键盘布局预览，热点驱动 Inspector | 保留“先选模式/部件，再右侧配置”的心智模型 | 真实键盘图、热点命中、缩放未验证 |
| InspectorPane | 无截图 | `InspectorPane.java` | 根据选中部件重建配置区；非编辑模式 body 禁用；支持按键、宏、灯效、OLED、拨杆等 | 保留右侧局部配置，不把全局诊断塞入 Inspector | 具体控件密度、文字、禁用态可读性未验证 |
| 设备信息/Hook 对话框 | 无截图 | `TopBar.showDeviceInfoDialog()` | 当前包含设备摘要、Claude/Cursor/Codex/Kimi Hook 卡、日志、连接/断开/清日志/关闭 | 作为支持/诊断入口候选 | 旧调查中的固件维护、配对指南、支持服务等当前源码未确认 |
| 语音浮窗/VoiceInputPanel | 无截图 | `FloatingVoiceNotification.java`、`VoiceInputPanel.fxml` | 语音相关 UI 存在；`VoiceInputPanel.fxml` 是否在主流程使用仍未确认 | 保留语音失败不阻塞主 UI | 需运行和路径确认 |

## 当前 Design System 观察

- 样式集中在 `style.css`，国际化文本在 `messages_zh.properties` / `messages_en.properties`。
- UI 多由 Java 代码创建，局部使用 FXML：`CanvasLayout.fxml`、`VoiceInputPanel.fxml`。
- 图标由 `Icons.java` 生成，尚未确认实际视觉一致性。

## 截图/预览规则

没有当前截图时，不能生成“当前 UI”假图。未来任何新增或改变可见入口的 Contract，必须先基于真实界面制作局部预览，并记录窗口尺寸、缩放、连接状态、模型状态和设备状态。
