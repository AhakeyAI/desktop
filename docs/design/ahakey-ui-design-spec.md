# AhaKey Studio · 统一 UI 设计规范

> **版本：** 1.0（合并基准版）  
> **适用范围：** AhaKey macOS 客户端全部 UI，含主 App 与 VibeBar 灵动岛  
> **权威来源：**
> - 主 App：`bukeke111/desktop` `my-branch` → `ahakey-design-spec.md` + `AhaKeyDesignSystem.swift`
> - VibeBar：`bukeke111/vibebar1.0` + `mac-vibebar-design-system.md`

---

## 1. 产品界面架构

AhaKey macOS 由两个独立视觉层组成，不得混用 token：

| 层级 | 角色 | 设计关键词 | 用户心智 |
|------|------|-----------|----------|
| **VibeBar** | 能力导航岛 | 黑色胶囊、低打扰、一键跳转 | 「我能从这里进 Voice / 审批 / OLED」 |
| **Studio** | 配置工作台 | 浅色卡片、侧栏导航、Inspector | 「我在这里深度配置和管理」 |

**混合合并规则：**
- VibeBar：以 `vibebar1.0` 设计为准（能力入口命名与布局）
- Studio：保留协作者已有功能，视觉与布局以 `my-branch` 为准
- 状态数据：`VibeBarBridge` 实时绑定保留，以角标/副标题呈现，不取代能力入口主文案

---

## 2. 全局设计原则

| 原则 | 说明 |
|------|------|
| 单一事实来源 | 产品名、试用状态 → 顶栏左侧；设备状态 → 顶栏中部；侧栏只做导航 |
| 层级用色不用阴影 | Studio 主壳用 `bg-card` + 1px `border` 分区 |
| 语义优先于实现 | 文案面向「场景 / 软件 / 批准方式」 |
| 深浅色一等公民 | 所有色来自 token；支持 `light / dark` |
| 能力入口优先于状态监控 | VibeBar 主文案是能力名，状态作次级角标 |
| 低打扰高可见 | 默认收起；悬停、热区、异常、录音时展开 |

---

## 3. VibeBar 灵动岛规范

### 3.1 设计定位

```
Capability Navigation Island（能力导航岛）
≠ Status Monitor HUD（纯状态监控）
```

### 3.2 收起态（Compact）

| 位置 | 内容 | 图标 | 颜色 |
|------|------|------|------|
| 左侧 | `AhaKey`（未连接 `—`） | `keyboard` / `keyboard.fill` | cyan / secondary |
| 右侧 | `Voice` | `mic.fill` / `mic.slash` | green / red / secondary |

- 字号 12pt Semibold，内边距水平 8pt / 垂直 3pt
- 热区：顶部居中 440×58pt

### 3.3 展开态（Expanded）

- 面板宽度 420pt
- 标题：`AhaKey Island`；副标题：动态设备名或 Connected/Disconnected
- 四格：**VoiceAgent / Device / Approve / OLED**（必须可点击跳转）

| Tile | 图标 | 跳转 | 状态角标 |
|------|------|------|----------|
| VoiceAgent | waveform | Studio Voice Agent | Ready |
| Device | battery.75percent | 设备信息 | 电量 % / Off |
| Approve | checkmark.circle | 拨杆设置 | Auto / Ask |
| OLED | rectangle.inset.filled | OLED 管理 | Ready |

### 3.4 VibeBar 颜色 Token

| Token | 色值 |
|-------|------|
| island.black | #000000 |
| island.blackElevated | #050505 |
| text.primary | #FFFFFF |
| text.secondary | rgba(255,255,255,0.64) |
| fill.soft | rgba(255,255,255,0.08) |
| accent.voice | #BF5AF2 |
| accent.success | #30D158 |
| accent.warning | #FFD60A |
| accent.error | #FF453A |

### 3.5 交互状态机

- 悬停紧凑条 → 展开
- 鼠标离开展开区 → 450ms 后收起
- 点击 chevron.up → 立即收起

---

## 4. AhaKey Studio 主 App 规范

详见 `my-branch` 的 `ahakey-design-spec.md` 与 `AhaKeyDesignSystem.swift`。

### 4.1 页面骨架

Settings 导航壳（侧栏：硬件 / 语音 / Agent / 灵动岛）+ 各 Tab 详情区；**深浅色一等公民**——偏好外观切换驱动整窗（侧栏、内容区、卡片、嵌入硬件 Studio），而非仅系统控件。默认 **深色**；可选浅色 / 跟随系统。硬件 Tab 内嵌 Gen2 嵌入式 Studio（画布 + Inspector）。左下角「我的设备」进入连接、改名与系统控制。

详情区顶栏右侧为功能入口（无品牌字）：**仅插件市场**（购物袋）。插件市场使用独立商店主题（`AhakeyPluginMarketTheme`：橱窗画布、大圆角瓷砖、Hero 渐变），与 Settings 工具页色板刻意区分。信息架构仍以「我的插件」为主（Library 大图标列表 + 可折叠安装教程）；「开源市场」为页头次级入口子页（Featured Hero + 货架瓷砖 + 页脚贡献）；点进产品页再看路径/权限与主 CTA。下载、安装、卸载与社区上传即将开放。

原「偏好配置」已并入侧栏 **用户中心**（以独立弹窗呈现，不替换主详情区；弹窗内左导航：用户中心 / 设置 / 使用数据 / 关于我们；下方帮助中心 / 版本说明）。首页为社区成员主页：身份卡、本机插件/货架摘要、开源市场与贡献入口；订阅与额度降为次级。设置含外观与语言、权限与隐私、接入与服务、设备联动；使用数据含隐私说明与额度摘要；关于我们含品牌简介；帮助中心含新手引导与帮助文档占位。全屏新手引导完成后，主路径关键节点会弹出一次性功能 tip（连接设备、改键写入、Agent 模式 vs 联动、语音空历史等；灵动岛 / 插件市场等为防误判提示），点「知道了」后不再出现。

**不在本壳切换范围内：** VibeBar 灵动岛浮层仍保持黑色胶囊定位。

### 4.2 主窗口 Tab

| Tab | 标识 | 用途 |
|------|------|------|
| 硬件设备 | hardware | 嵌入式 AhaKeyStudioView（Gen2 画布 + 磁吸/OceanLight）；职责为按键/部件映射 |
| 语音输入 | voiceInput | 三分段：历史记录 / 词典 / 通用设置；系统权限在用户中心 · 设置 |
| Agent | agent | 三分段：助手 / 联动 / 设置（含 Pet 外观）；改键仅在硬件；见 `agent-assistant-settings.md` |
| 灵动岛 | dynamicIsland | VibeBar 外观与行为设置 |

侧栏底部另有 **我的设备**（非 Tab）：设备卡上方标注「我的设备」，点击进入当前设备详情（改名、蓝牙占用、设备信息、Agent 系统）。

### 4.3 Settings 壳 Token（`AhakeySettingsTheme`）

色值随窗口 `NSAppearance` / `preferredColorScheme` 自适应；嵌入 Studio 复用同一套（`AhaKeyStudioEmbeddedTheme`）。

| Token | Dark | Light |
|-------|------|-------|
| window / content | `#1C1C1E` | `#F4F4F6` |
| sidebar | `#171718` | `#ECECEF` |
| card | `#29292B` | `#FFFFFF` |
| cardHover | `#303032` | `#F0F0F2` |
| primaryText | white 95% | black 88% |
| secondaryText | white 45% | black 48% |
| tertiaryText | white 32% | black 32% |
| controlFill | white 10% | black 6% |
| divider / selection | white 6–8% | black 6–8% |
| accentBlue | `#0A85FF` | `#007AFF` |

其它 Studio 尺寸：圆角 sm 8 / md 10 / lg 12 / pill 999；间距 shell 5 / page 24 / panel 14。

---

## 5. VibeBar ↔ Studio 导航映射

| VibeBar 入口 | Studio 目标 | 说明 |
|-------------|-------------|------|
| VoiceAgent | Agent · 助手分段 | Pet 对话管家（本地意图） |
| Device | 左下角「我的设备」→ 当前设备详情 | 我的设备 |
| Approve | 硬件设备 · Key 2（批准键） | 改键唯一入口在硬件 |
| OLED | 硬件设备 · OLED | Inspector LCD |
| Voice（紧凑右） | 硬件设备 · Key 1（语音键） | 改键唯一入口在硬件 |

---

## 6. 代码映射

| 概念 | 文件 |
|------|------|
| VibeBar 视图 | `vibebar/Sources/VibeBar/VibeBarViews.swift` |
| VibeBar Token | `vibebar/Sources/VibeBar/VibeBarDesignTokens.swift` |
| VibeBar 状态 | `vibebar/Sources/VibeBar/VibeBarState.swift` |
| BLE 绑定 | `ahakeyconfig-mac/Sources/Utilities/VibeBarBridge.swift` |
| Studio 导航 | `ahakeyconfig-mac/Sources/Utilities/StudioNavigationRouter.swift` |
| 设计系统 | `ahakeyconfig-mac/Sources/Views/Settings/AhakeySettingsTheme.swift` |
| Settings 主壳 | `ahakeyconfig-mac/Sources/Views/Settings/AhaKeySettingsRootView.swift` |
| Agent 三分段壳 | `ahakeyconfig-mac/Sources/Views/Settings/AhaKeyAgentWorkspacePane.swift` |
| Agent 助手工具 | `ahakeyconfig-mac/Sources/Utilities/AgentAssistantTools.swift` |
| 旧工作台（独立窗口可留） | `ahakeyconfig-mac/Sources/Views/AhaKeyWorkbenchView.swift` |
| 按键配置页（硬件路径） | `ahakeyconfig-mac/Sources/Views/AhaKeyKeyConfigPageView.swift` |
| 浮动语音 HUD | `ahakeyconfig-mac/Sources/Views/VoiceInputFloatingHUD.swift` |
| 磁吸 Inspector | `ahakeyconfig-mac/Sources/Views/IslandKeyboard/MagneticModuleInspectorView.swift` |

---

## 7. 合并验收清单

**VibeBar：**
- [x] 收起左：AhaKey（非电量）
- [x] 收起右：Voice（非 Auto/Ask）
- [x] 展开四格：VoiceAgent / Device / Approve / OLED
- [x] 每格可点击并跳转 Studio
- [x] Device/Approve 角标显示实时状态

**Studio：**
- [x] Settings 壳深浅色一等公民；默认深色；切换浅色整窗同步（侧栏/卡片/嵌入 Studio）
- [x] 侧栏 4 Tab 可切换
- [x] 硬件 Tab：Gen2 画布 + 磁吸 Inspector + OceanLight
- [x] 语音 Tab：历史 / 词典 / 通用三分段；系统权限在用户中心 · 设置
- [x] Agent Tab：助手 / 联动 / 设置三分段；Pet 外观在设置页；高频常开、高级折叠；无嵌入按键配置整页
- [x] VibeBar 跳转自动切换对应 Settings Tab（Approve/Voice → 硬件元件）
- [ ] VibeBar 灵动岛浮层保持深色胶囊（有意不跟 Settings 外观）

---

## 8. 相关文档

- `mac-vibebar-design-system.md` — VibeBar 细节补充
- `ahakey-design-spec.md` — Studio 组件与 HTML 原型对照
- `agent-assistant-settings.md` — Agent Pet 助手 IA 与工具边界
- `voice-input-settings.md` — 语音输入三分段与高频/低频
- `hardware-studio-layout.md` — 硬件设备主页布局
