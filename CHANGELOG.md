# Changelog

## v0.2.3 — 2026-10-15

### macOS — AhaType 与 Claude Code

- 修复 AhaType 将带毫秒和时区的云端令牌有效期误判为过期，导致语音结果跳过云端整理的问题。
- Claude Code 自动批准提前在 `PreToolUse` 阶段读取实体拨杆；桌面 Code 本地会话与 CLI TUI 均可使用，`PermissionRequest` 保留为兜底。
- Claude 两条审批路径仅在本次 BLE 查询确认实体拨杆为自动档时批准；查询超时、断连或缺少验证信息时交还原生确认，不使用旧缓存。
- macOS 安装包内含 `ahakeyconfig-agent`；安装后可在「设备信息 · Agent」中安装并启用 Claude、Cursor、Codex、Kimi Hooks。
- “更多”菜单新增“关闭灵动岛 / 开启灵动岛”，开关状态在重启后保留。
- 修复图形界面遗漏 Homebrew 和 ChatGPT.app 内 Codex CLI 时的安装误报。
- 修复 Cursor 桌面端 Hook 已返回允许但仍被命令白名单拦截的问题；自动档临时加入通配项，手动档恢复原配置并交还原生确认。
- 新增 macOS 客户端自动及手动检查 GitHub 最新正式版，发现更新后弹窗提示，下载并校验安装包后打开。
- 整理“更多”菜单：清空剪贴板移入菜单，更新检查与固件升级集中显示，移除冗余英文附注和 AhaType 刷新项。
- 顶栏键盘控制状态改为打开设备信息，AhaType 状态改为打开云端账号；精简“更多”菜单文案与排序。
- 恢复客户端中英文切换与系统语言初始化；AhaType 顶栏开关保留，状态文字可打开云端账号。
- 更新帮助中的 OTA 说明；软件更新弹窗可前往 GitHub Release 列表；设置、帮助与权限诊断弹窗统一使用文字“关闭”。
- 灵动岛展开态左下角新增“Exit island”电源按钮，可持久关闭灵动岛。
- 将语言切换移到顶栏“更多”左侧，提供“跟随系统 / 简体中文 / English”下拉选项；默认读取 macOS 全局语言设置。
- 修复英文界面下旧中文按键配置跳过迁移的问题；历史描述按固定值识别，保留用户自定义配置，并加入旧配置迁移回归测试。

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
