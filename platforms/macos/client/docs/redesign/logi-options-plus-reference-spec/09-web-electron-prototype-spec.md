# Web / Electron 原型交付 Spec

更新时间：2026-05-03
状态：下一轮优先执行草稿

---

## 1. 文档定位

本文档定义下一轮更务实的交付路径：

**优先做 Web 形态的高保真前端原型，必要时再用 Electron 壳包装给合作者体验；不在本轮完整构建桌面应用。**

它替代“直接进入 SwiftUI 原生重构”作为下一轮执行入口。SwiftUI 拆分文档仍保留，但降级为后续原生迁移参考。

---

## 2. 为什么先做 Web / Electron 原型

Logi Options+ 本身是 Electron + React，说明它的前台体验可以用 Web 技术完整承载。

对 AhaKey 当前阶段来说，先做 Web 原型的收益更高：

- 合作者可以直接打开网页或压缩包预览
- 页面、动线、状态表达可以快速迭代
- 不需要先处理 macOS 原生窗口、权限、BLE、后台服务打包
- 可以高保真参考 Logi 的页面壳、布局节奏和组件语气
- 后续如果要包 Electron，只需要加薄壳，不改变前端页面结构

本轮目标不是证明技术集成，而是先把“产品壳长什么样、用户怎么走、状态怎么表达”定下来。

---

## 3. 交付形态

### 3.1 首选交付

一个可运行的 Web 前端原型：

- 本地开发时通过 dev server 预览
- 对外交付时可导出静态构建目录或压缩包
- 合作者不需要安装完整 macOS App

### 3.2 可选包装

如果需要更像桌面应用，可以加一个极薄 Electron wrapper：

- 只负责打开同一套 Web 前端
- 不接入真实 BLE
- 不接入真实后台服务
- 不处理系统级权限
- 不引入自动更新、签名、公证、安装器

Electron 在本阶段只是“演示容器”，不是完整桌面产品。

### 3.3 非目标

本轮不做：

- 完整 macOS 原生客户端
- SwiftUI 页面落地
- BLE 真实连接
- Agent / Voice 后端协议接入
- 系统权限真实申请
- 设备固件写入
- Logitech 资源或代码复制

---

## 4. 推荐技术边界

建议使用：

- React
- TypeScript
- Vite
- CSS Modules 或普通 CSS token 层
- 本地 mock state
- 可选 Electron wrapper

不建议本轮引入：

- 复杂后端
- 数据库
- 跨平台桌面构建流水线
- 真实系统 API
- 大型 UI 组件库

理由：这轮最重要的是页面判断和交互节奏，不是工程平台完备度。

### 4.1 开工基线

截至 2026-05-03，远端状态如下：

- 本地 `desktop/main` 当前仍在 `d1bdb4d`。
- `upstream/main` 已推进到 `42a13be`，比本地多 24 个提交。
- `upstream/main` 已合入 `upstream/dev` 的 VoiceAgent / Feishu / AhaKey 工作台相关改动。
- `upstream/main` 新增了 `platforms/macos/client/docs/prototypes/ahakey-design-spec.md` 和旧 HTML 原型资料。
- `upstream/main` 新增了 SwiftUI 侧的 `AhaKeyDesignSystem.swift`，其中已有浅色 / 深色 appearance mode 与基础 token。

下一轮原型应基于远端最新 `upstream/main` 开干净分支或 worktree，不建议直接在当前 dirty 工作区 `pull`。

推荐做法：

- 先保留当前 spec 文档改动。
- 从 `upstream/main` 开原型分支，例如 `prototype/logi-web-shell`。
- 原型代码放在 macOS client 文档/原型范围内，优先避免碰现有 Swift 源文件。
- 只有需要复用远端设计说明时，读取 `docs/prototypes/ahakey-design-spec.md` 和 `AhaKeyDesignSystem.swift`，不要把旧 HTML 原型当作最终架构。

### 4.2 远端新信息对原型的影响

远端新推送意味着下一轮不是从空白开始：

- VoiceAgent 已成为产品主线之一，原型必须保留 `Agent` / `Voice` 页面入口。
- Feishu 集成已经进入远端，原型的 Agent/Voice 页应预留第三方集成状态，但不要在首版做真实登录。
- 远端已有 AhaKey 自己的设计 token 草案，Web 原型应吸收其角色命名和层级，不只参考 Logi。
- 旧 HTML 原型可作为 AhaKey 自身风格历史参考，但本轮主目标仍是 Logi 式前台壳。

---

## 5. 页面范围

### 5.1 必做页面

#### Home

参考 Logi 首页设备总览：

- 顶部问候 / 品牌区
- 右上角操作区
- 无设备空态
- 单设备已连接态
- 多设备布局预留
- 添加设备入口
- Smart Actions / 快捷操作入口
- Settings 入口

AhaKey 映射：

- 首页是设备选择器
- 主视觉从 Logi 的鼠标 / 键盘 hero 改为 AhaKey 设备 hero
- 不展示 Logitech 品牌、生态文案、原始插图

#### Add Device Flow

参考已观察到的“选择连接类型”页面：

- 返回按钮
- 居中标题
- 单个或多个连接方式卡片
- 底部辅助说明

AhaKey 映射：

- 首版可以只保留 `Bluetooth`
- 文案改为 AhaKey 语气
- 权限和扫描结果用 mock 状态表达

#### Device Studio

参考 Logi 设备详情 / 自定义工作区：

- 返回首页
- 平台 / 应用上下文切换器
- 中央设备画布
- 可点击热点
- 右侧 inspector
- 状态 pill / 同步状态

AhaKey 映射：

- 平台切换器固定为 `Claude Code / Cursor / Codex`
- 中央画布使用 AhaKey 键盘示意，不使用 Logi 设备图
- inspector 编辑 AhaKey 的按键、OLED、灯条、拨杆
- 明确显示草稿 / 同步 / 控制权状态

### 5.2 应做页面

#### Settings

用于承载全局元操作：

- 启动项
- 后台服务
- 权限
- 诊断
- 关于

#### Agent

作为设备工作区内的软件功能页：

- 后台服务状态
- 当前运行模式
- 控制权说明
- mock 启停操作

#### Voice

作为设备工作区内的软件功能页：

- 麦克风权限态
- 语音输入启用态
- 当前语音目标或 provider mock

---

## 6. 原型状态模型

Web 原型不接真实服务，但必须模拟 AhaKey 的核心状态复杂度。

### 6.1 设备状态

至少支持：

- `noDevice`
- `scanning`
- `connected`
- `disconnected`
- `permissionRequired`

### 6.2 控制权状态

至少支持：

- `runtimeOwnerAgent`：运行中，后台持有连接
- `configOwnerStudio`：配置中，Studio 持有连接
- `handoffPending`：控制权切换中
- `handoffFailed`：控制权切换失败

### 6.3 草稿同步状态

至少支持：

- `clean`
- `dirty`
- `syncing`
- `synced`
- `syncFailed`

这些状态要在页面里可切换，方便合作者评审所有状态，而不是只看一张静态默认态。

---

## 7. 组件拆分建议

建议第一版拆成以下组件边界：

- `AppShell`
- `HomePage`
- `TopActionBar`
- `DeviceHero`
- `DeviceStatusPill`
- `AddDevicePage`
- `DeviceStudioPage`
- `PlatformSwitcher`
- `StudioCanvas`
- `HotspotCallout`
- `StudioInspector`
- `SyncStatusBanner`
- `SettingsPage`
- `AgentPage`
- `VoicePage`
- `MockStatePanel`

`MockStatePanel` 只在原型评审版本里显示，用于切换状态矩阵；未来正式 UI 可移除。

---

## 8. 视觉执行原则

从当前截图与 React / CSS 逆向可以确定的方向：

- 大面积浅背景
- 极少边框
- 顶部操作区右对齐
- 主设备 hero 居中偏视觉重心
- 文字层级克制
- icon + text 组合用于主要动作
- 右侧 inspector 使用独立浅表面
- 状态 pill 小而明确
- 紫色只作为选中 / 强调色，不作为整页主色
- 明暗主题都必须是一等公民
- 深色 Settings 使用近黑背景、白色文本层级和青绿色 accent

需要 AhaKey 化的地方：

- 不使用 Logi 插图和设备图
- 不使用 Logitech 品牌色和品牌文案
- 不照搬鼠标滚轮、Flow、Easy-Switch 等专属能力
- AhaKey 的状态语言要比 Logi 更显式，因为它有控制权和草稿同步问题

### 8.1 原型主题 token

已确认 Logi React/CSS 包提供 `body.light` / `body.dark` 两套主题变量。Web 原型必须建立自己的 `:root[data-theme="light"]` / `:root[data-theme="dark"]` token。

最低 token 集：

```css
:root[data-theme="light"] {
  --ak-bg-app: #fff;
  --ak-bg-page: #fbfbfb;
  --ak-bg-panel: #f5f5f5;
  --ak-bg-control: #f0f0f0;
  --ak-text-primary: #222425;
  --ak-text-secondary: #888;
  --ak-accent: #814efa;
  --ak-accent-hover: #673ec8;
  --ak-accent-soft: rgba(129, 78, 250, 0.1);
  --ak-border: #d8d8d8;
}

:root[data-theme="dark"] {
  --ak-bg-app: #000;
  --ak-bg-page: #191919;
  --ak-bg-panel: #222425;
  --ak-bg-control: #333;
  --ak-text-primary: #fbfbfb;
  --ak-text-secondary: #ccc;
  --ak-accent: #00ead0;
  --ak-accent-hover: #03dbc3;
  --ak-accent-soft: rgba(0, 234, 208, 0.1);
  --ak-border: #666;
}
```

这些值来自 Logi CSS token 的参考抽取，不作为 AhaKey 最终品牌色承诺。实现时应通过角色 token 使用，不允许在组件里散落硬编码色值。

### 8.2 深色 Settings 页面规则

根据新截图，Settings 原型至少覆盖：

- `General`
- `Notifications`
- `Feedback & Support`

页面规则：

- 左侧固定导航，当前项用 accent 竖条 + accent 文本。
- 内容列最大宽度控制在可读范围内，不铺满整屏。
- 每页使用大标题、分组标题、正文 / 链接 / 控件的层级。
- `General` 必须包含版本信息、检查更新、自动更新 toggle、语言下拉、主题卡片。
- `Notifications` 必须包含通用通知 toggle 与叠加通知分组。
- `Feedback & Support` 必须包含反馈链接、评分链接、故障排除链接、蓝牙问题 checkbox 组。
- 深色截图只作为结构与语气参考，文案必须改为 AhaKey。

---

## 9. 当前证据来源

截至 2026-05-03，本专题的 UI 判断来自三类来源：

| 来源 | 当前贡献 | 适合决定什么 | 不适合决定什么 |
|------|----------|--------------|----------------|
| React / CSS / assets 逆向 | 高 | 页面家族、组件名称、样式 token、文案、状态信号 | 最终运行时像素表现 |
| 用户提供截图 | 中 | 首页、添加设备、设备详情、inspector、深色 Settings 的真实视觉节奏 | 全状态覆盖、交互逻辑完整性 |
| AhaKey 产品约束 | 高 | BLE 控制权、草稿同步、平台语义 | Logi 原组件真实细节 |
| 远端 AhaKey 新推送 | 中 | VoiceAgent/Feishu 已进入产品主线、AhaKey 自有 token 草案、旧原型资料 | Logi 原组件真实细节 |

粗略判断：

- 信息架构：React / CSS 已足够覆盖约 80%
- 组件清单：React / CSS 加截图可覆盖约 75%
- 视觉方向：当前截图可覆盖约 60%，还需要 AhaKey 设备工作区细节补图
- 明暗主题 token：React / CSS 已确认可覆盖约 80%，截图用于校验运行时观感
- 交互状态：React / CSS 可辅助推断约 60%，但关键状态仍需 mock 验证
- 像素级复刻：不追求法律意义上的逐像素复制，目标是 85% 左右的产品体验相似度

---

## 10. 还需要的截图资产

因为下一轮改为 Web 原型，截图不再追求穷尽采集，而是只补关键决策缺口。

优先需要：

1. 设备详情页完整正视角截图
2. 右侧 inspector 的默认态、选中态、编辑态
3. 平台 / 应用切换器的 hover、selected、添加应用态
4. Settings 首页与一个二级设置页
5. 权限态或错误态页面

可选需要：

- 首页设备 hover 态
- 设备断开态
- 同步中 / 成功 / 失败状态
- popover 或 sheet 打开态
- 短录屏，用于观察页面切换和 hover 动效

截图只进入 `captures/raw-local/`，由后续整理动作筛选为 `tracked/` 精选资产。

---

## 11. 验收标准

下一轮原型完成后，应满足：

1. 合作者能在浏览器里完整走通 Home -> Add Device -> Device Studio -> Settings。
2. 主要页面不依赖真实后端，也能展示关键状态。
3. Device Studio 能表达平台切换、热点选中、右侧 inspector、草稿同步。
4. 视觉上能明显看出参考了 Logi 的成熟桌面软件壳层。
5. 内容、品牌、设备图、文案都已经 AhaKey 化。
6. 代码结构允许后续升级为 Electron 包装或迁移到 SwiftUI。

---

## 12. 与 SwiftUI 文档的关系

[08-swiftui-implementation-spec.md](./08-swiftui-implementation-spec.md) 仍然有效，但它不再是下一轮的直接执行入口。

新的顺序是：

1. 先用 Web 原型验证 UI/UX 和状态模型
2. 必要时用 Electron 壳交付给合作者
3. 等页面边界和状态表达稳定后，再决定是否迁移到 SwiftUI 原生客户端

这样可以避免在产品壳还没定型时，就提前承担完整桌面工程成本。
