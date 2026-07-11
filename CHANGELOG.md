# 版本更新管理

## v0.5.0 — 2026-07-11

全屏引导之后的功能级一次性气泡 tip、LCD 恢复默认，以及联动 / 我的设备「左状态 · 右操作」卡片一致性。

### 功能级新手指引

- 新增 `FeatureCoachTipStore`：全屏引导完成后，在连接设备、改键写入、Agent 模式、联动、语音空历史、用户中心权限、灵动岛、插件市场等卡点弹出一次性气泡。
- 气泡含「去点 …」目标控件说明与可跳转主按钮；同屏最多一条；点「知道了」后不再出现。
- 「重新打开新手引导」同时重置全屏引导与全部气泡已读状态；修复引导结束后气泡不唤醒的问题。

### 硬件 LCD

- LCD 显示配置增加「清空并恢复默认」：恢复当前 Mode 出厂动图、12 FPS 与默认状态文案（仍需「写入键盘」同步）。

### 卡片操作一致性

- Agent · 联动：「一键启用联动」「安装 Cursor Hook」移到卡片右侧（左状态、右按钮）。
- 我的设备：列表空态与详情「基本设置」的「连接设备」移到卡片右侧。

### 仓库

- 界面开发分支仍为 `ui/develop`；版本说明见 `docs/versioning.md`。

## v0.4.0 — 2026-07-11

Settings 主壳产品化：语音 / Agent 三分段落地，用户中心并入偏好并以弹窗呈现，插件市场升级为独立商店视觉。

### 语音输入

- 三分段：**历史记录 / 词典 / 通用设置**（`AhaKeyVoice*` 系列页）。
- 本机语音状态与词典/历史轻量存储（`VoiceInputStore`）；系统权限入口收拢到用户中心 · 设置。
- 文档：`docs/design/voice-input-settings.md`。

### Agent

- 三分段：**助手 / 联动 / 设置**（含 Pet 外观）；改键仍只在硬件 Studio。
- 助手工具与工作台壳层（`AhaKeyAgent*`、`AgentAssistantTools`）。
- 文档：`docs/design/agent-assistant-settings.md`。

### 用户中心

- 原「偏好配置」整页并入侧栏用户中心；以独立 **sheet 弹窗**呈现，不替换主详情区。
- 弹窗左导航：用户中心 / 设置 / 使用数据 / 关于我们；下方帮助中心 / 版本说明。
- 首页偏社区：身份卡、本机插件/货架摘要、开源市场入口；订阅与额度降为次级。
- 设置含外观语言、权限、Agent API、设备联动；删除独立 `AhakeyGeneralSettingsPane`。
- 顶栏功能入口仅保留插件市场（去掉偏好齿轮）。

### 插件市场

- 静态货架 catalog + 本机已装轻量扫盘；默认「我的插件」，「开源市场」为次级子页。
- 独立商店主题 `AhakeyPluginMarketTheme`（橱窗画布、大圆角瓷砖、Hero 渐变），与 Settings 工具页色板区分。
- 版式：Library 大图标列表；开源 Featured Hero + 货架瓷砖；产品页大图标 + 主 CTA（下载/安装仍占位）。
- 设计规范同步注明商店主题。

### 其他

- Settings 主题 token 与嵌入式 Studio 外观微调；新手引导可从帮助中心再进入。
- 界面开发分支仍为 `ui/develop`；版本说明见 `docs/versioning.md`。

## v0.3.0 — 2026-07-11

硬件设备主页与「我的设备」一轮产品化：Inspector 二级模块、问号帮助、画布对齐，以及设备连接/系统控制从侧栏 Tab 收拢到左下角入口。

### 硬件设备 Studio

- 右侧 Inspector：元件 Tab + 二级模块（`InspectorSection`）；说明文进问号（`InspectorHelpButton`），悬停展开。
- 语音键结构：按键描述 → 按键配置（输入方式）→ 绑定方法 → 更多设置；非语音键绑定在按键配置内。
- Agent Mode 分段下移到画布下方；其下增加硬件组装占位。
- 画布：OLED / 灯条 / 磁吸对齐；去掉灯条上方「灯条」文字标签。
- 顶栏：去掉「AhaKey」字；插件市场（占位）与偏好配置入口。
- 右侧各 Tab 布局收紧（下拉宽度、OLED 按钮行、磁吸档位菜单等），减少溢出功能区。
- 文档：`docs/design/hardware-studio-layout.md`；设计规范 Tab 表同步。

### 我的设备

- 侧栏不再单独放「设备管理」Tab；左下角设备卡上方标注「我的设备」，点击进入详情。
- 详情复用整理后的 `DeviceInfoView`（基本设置 / 蓝牙 / 设备信息 / 系统·Agent / 更多诊断）。
- Agent「设备与系统」、硬件页设备信息入口改为跳转「我的设备」。
- VibeBar Device 导航对齐同一入口。

### 仓库

- 界面开发分支仍为 `ui/develop`；版本说明见 `docs/versioning.md`。

## v0.2.0 — 2026-07-11

VibeBar 灵动岛 Settings 与用户中心一轮产品化更新：信息架构分层、低频选项折叠、账户页视觉升级，以及组件库二级设置。

### 用户中心

- 侧栏用户卡进入整页用户中心（登录 / 资料 / 额度 / 充值 / 兑换），与通用设置解耦。
- Profile Hero：头像、欢迎/脱敏手机号、已登录状态点。
- 登录卡：深色输入框、主次按钮层级；账户卡：资料分行、日/周/月三列额度、退出弱化危险样式。
- 订阅套餐卡片化、支付二维码区统一容器；AhaType 收成附属卡。
- 文档：`docs/user-center.md`。

### 灵动岛 Settings IA

- 三分段：**常驻岛 | 展开岛 | 通用**；系统级选项迁入通用。
- 常驻岛：预览内状态切换、布局（左/右槽）、灯条与尺寸。
- 展开岛：组件库入口、交互、个性化（焕肤入口常开）。
- **低频选项默认折叠**：常驻岛「更多外观」、展开岛「交互与更多」、通用「更多通用」；焕肤不折叠。
- 侧栏品牌头去掉 logo，仅保留「AhaKey Studio」文案。

### 组件库与模块设置

- 组件库管理展开岛模块显隐与顺序。
- 四键键帽 / OLED Pet 二级设置页（外观、映射、皮肤、动画、状态覆盖等）。
- 展开岛命令中心按启用模块渲染。

### 稳定性

- 修复主窗口关闭后 VibeBar「设置」无法再打开主窗：`openWindow` 注册到 `AppDelegate`。

### 仓库

- 界面开发分支：`ui/develop`（由原 `integrate/keke-vibebar-ui` 改名）。
- 版本说明：`docs/versioning.md`。

## v0.1.1-alpha — 2026-05-03

macOS 客户端从 baseline 迁入阶段进入活跃功能开发期。本版本主要新增 Voice Agent 体系、飞书集成与 Agent 工作台。

### macOS — Voice Agent 体系

- 新增 `VoiceAgent` Swift 模块，分 `Core` / `Agents` / `Networking` / `Runner` / `Integrations` 五个子模块。
- Supervisor + sub-agent 编排：`VoiceAgentOrchestrator`、`VoiceSubAgent`、`VoiceAgentRunner`、`VoiceAgentRunState`。
- 结构化工具调用与独立记忆：`VoiceAgentTool`、`VoiceAgentMemory`、`VoiceAgentMessage`、`JSONValue`。
- 并发与生命周期：`ConcurrencyLimiter`、`VoiceAgentLiveSession` 可执行目标。
- OpenAI 协议兼容客户端：`LLMClient` + `OpenAIProtocol`，新增 `LLMConfigView`（模型 / endpoint / key 配置）。
- 跨次启动会话保留：`VoiceAgentSessionStore`、`VoiceAssistantModel`。

### macOS — 飞书 / Lark 集成

- 新增 `FeishuClient`、`FeishuTools`、`FeishuSubAgentFactory`：通过 `lark-cli` 以用户自己的身份发消息和查联系人，App 不存储飞书凭证。
- 联系人本地别名解析（`FeishuContactBook`）：sub-agent 可把"智能助手"等名字解析成 `open_id` / `user_id` / `chat_id` / `email`。
- 新增配置入口 `FeishuSetupView` 与 `FeishuContactsConfigView`。
- 修复飞书登录错误。

### macOS — 工作台与 UI

- 双工作台：`AhaKeyRootWorkspaceView` 在 **IDE 工作台**（经典键位配置）与 **Agent 工作台**之间切换。
- 重写 `AhaKeyStudioView`；新增 `AhaKeyWorkbenchView`、`AhaKeyKeyConfigPageView`、`VoiceAgentWorkspaceView`。
- 新增浮动语音输入 `VoiceInputFloatingHUD`；`NativeSpeechTranscriptionService` 增强 push-to-talk 中继路由（修复 View 重建时按住状态丢失）。
- 统一引导 `UnifiedTypelessOnboardingView` + Onboarding 资源图。
- 设计系统：新增 `AhaKeyConfigUI` target 与 `AhaKeyDesignSystem`。
- 移除独立 `DeviceInfoView`（合并入工作台）。

### macOS — 构建与发布

- `Package.swift` 新增 `AhaKeyConfigUI`、`VoiceAgent`、`VoiceAgentLiveSession` target。
- 调整 `scripts/build.sh` / `scripts/build-debug.sh`，新增 `build.local.env.example`、`ensure-dev-signing.sh`、`open-xcode-preview.sh`、`package_dmg.sh`、`release_dmg.sh`。
- 新增设计原型与 UX review 文档（`docs/prototypes/ahakey-design-spec.md` 等）。

### 仓库

- 根 README 重写为产品 + 仓库混合型，新增 macOS Highlights 段。
- `platforms/macos/README.md` 同步更新当前状态。
- 新增 `.github/workflows/release.yml` 发布流程。

## v0.1.0 — 初始化 baseline

- 初始化 `AhakeyAI/desktop` 仓库结构。
- 导入 Windows 主客户端、BLE bridge、hook installer、speech 源码。
- 导入 macOS baseline 客户端到 `platforms/macos/client/`。
- 补充仓库级与平台级说明文档。
- 排除安装包、构建产物、预编译 DLL、本地配置与私钥文件。
