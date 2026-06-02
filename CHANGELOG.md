# Changelog

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
