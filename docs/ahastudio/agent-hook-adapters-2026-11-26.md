# macOS 状态钩子适配与打包

2026-11-26 · 设备信息页「状态钩子」开发和验收清单

状态钩子通过工具自己的会话事件，把进行中、完成和会话结束同步到 AhaKey。安装清单采用三种独立信息：工具已检测到、AhaKey 钩子已配置、收到真实回调。已配置的证据是工具配置引用固定入口，真实回调的证据来自工具进程执行后的本机回执。

在 Studio 展开已安装工具的验证状态，即可查看配置核对、入口自检和真实回调。用要核验的宿主开启新会话。Studio 会在能够识别本机进程来源时分别显示 Orca、LobeHub、T3 Code、原生桌面客户端或终端。配置或固定入口更换后，需要重新收到回调。安装及自检不会发送模型请求。

宿主若在同一台 Mac 上启动原生工具，需让运行时加载 Studio 显示的配置文件。使用独立帐号目录的 Orca 或 T3 Code 实例应先核对 `CODEX_HOME` 或 `CLAUDE_CONFIG_DIR`。LobeHub 远程设备和云沙箱的原生工具由各自运行机器加载配置。[Orca](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/agents/codex.mdx) · [T3 Code](https://github.com/pingdotgg/t3code/blob/main/docs/user/usage.md) · [LobeHub](https://lobehub.com/solutions/manage-claude-code-and-codex)

## 适配范围

| 工具 | 官方接口与配置位置 | Studio 当前能力 |
| --- | --- | --- |
| Claude Code | 用户级 `~/.claude/settings.json`，支持命令生命周期事件。[Claude Code Hooks](https://code.claude.com/docs/en/hooks) | 现有安装器合并 AhaKey 自有条目，保留其他配置。修复、卸载需要保持用户 Hook 与审批状态隔离。 |
| Cursor | 全局 `~/.cursor/hooks.json`，事件名称采用 Cursor 约定。[Cursor Hooks](https://cursor.com/docs/hooks) | 现有安装器合并 AhaKey 自有条目。不同客户端可用的事件需按版本核对。 |
| Codex | 用户配置 `~/.codex/config.toml`，配置和可信状态均受运行时校验。[Codex Hooks](https://learn.chatgpt.com/docs/hooks) | 固定入口已完成真机验证。现有会话可能缓存迁移前的命令，首次迁移后按客户端提示重启所属进程。已验证依据限定为本轮安装的本机真实回执。 |
| Kimi Code | CLI 与 Desktop 共用 `~/.kimi-code/config.toml` 的 `[[hooks]]`。旧 CLI 仍有旧版配置路径。[Kimi Code Desktop 设置与扩展](https://www.kimi.com/code/docs/kimi-code-desktop/settings-and-extensions.html#hooks) | 现有适配涵盖两种路径。配置统一列为 Kimi Code，桌面端和 CLI 的运行时事件仍应分别验收。 |
| WorkBuddy | 腾讯公开的 **WorkBuddy Enterprise / CodeBuddy IDE** 文档列出提交、结束与退出等命令钩子，文档示例采用 `.codebuddy/settings.json`。[腾讯 Hooks 功能使用文档](https://cloud.tencent.com/document/product/1831/134517) | 本地适配使用 `~/.workbuddy/settings.json`，仅转发状态。WorkBuddy 5.3.14 软件包自带引擎已通过真实回调。 |
| GitHub Copilot CLI | 官方支持用户级 `~/.copilot/hooks/` 或 `$COPILOT_HOME/hooks/` 的 JSON 文件。PascalCase 事件使用 `hook_event_name` 和 `session_id`，CLI 支持直接 `exec/args`。[用户级 Hooks](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks) · [事件与格式](https://docs.github.com/en/copilot/reference/hooks-reference) | 已接入逐项安装、卸载和固定入口。官方 CLI 1.0.116 已通过真实回调。 |
| 千问办公 | 公开接口为企业后台配置的 HTTP 回调。桌面端文档给出会话相关事件和企业配置步骤。[千问办公 Hooks](https://docs.qwenwork.cn/desktop/hooks) | 目录保留检测。接入待明确企业授权和回调服务部署方式。 |
| 豆包工作 | 已核对豆包桌面产品说明，未找到公开的会话生命周期 Hook、Runner 或回调配置合同。[豆包桌面版产品说明](https://apps.apple.com/cn/app/%E8%B1%86%E5%8C%85/id6683305962?mt=12) | 目录保留检测，未开放安装。 |
| Gemini CLI / OpenCode | Gemini CLI 有 `BeforeAgent`、`AfterAgent`、`SessionEnd` 等命令钩子。OpenCode 提供本地插件接口，旧版会话事件与新版插件 API 需分开核验。[Gemini CLI Hooks](https://geminicli.com/docs/hooks/reference/) · [OpenCode Plugins](https://opencode.ai/docs/plugins/) | 按实际运行版本推进。可优先做纯状态适配各自的安装、卸载和真实回调。 |
| Cline CLI | 用户级 `~/.cline/hooks`，当前运行库文件名使用 `TaskStart`、`TaskComplete` 等，运行时事件名对应 `agent_start`、`agent_end` 等。[Cline CLI 路径](https://github.com/cline/cline/blob/main/docs/cli/cli-reference.mdx) | 已接入逐项安装和卸载。官方 3.0.75 运行库在隔离 HOME 发现已装脚本，并执行开始、完成和退出回调，固定入口回执已验证。本轮未运行完整 Cline CLI 模型轮次。 |
| Pi | 用户级 `~/.pi/agent/extensions` 或 `PI_CODING_AGENT_DIR`。使用 `agent_settled` 避免自动续跑、重试时误判完成。[Pi 扩展](https://docs.pi.dev/latest/extensions) | Pi 1.6.1 隔离 CLI 用本机模型完成一轮，观察到真实开始和最终完成事件，固定入口回执从等待变为已验证。 |
| OpenClaw | 本机 Gateway 用户级原生插件。使用 metadata 生命周期订阅，只在 `executionSettled` 后标记完成。[OpenClaw SDK](https://github.com/openclaw/openclaw/blob/main/docs/plugins/sdk-runtime.md#settled-agent-lifecycle-events) · [插件路径和允许列表](https://docs.openclaw.ai/gateway/config-extensions) | Studio 放置插件，OpenClaw 保留启用与访问策略。隔离运行 OpenClaw 2026.11.10 Gateway，调用本机模型完成一轮，固定入口生成真实回执。运行时探针看到 `start` 与含 `executionSettled` 的 `end`。 |

## Copilot CLI 适配层

- `AgentManager` 的逐项安装、卸载调用 `CopilotStatusHooks(home:copilotHome:entryPath:)`、`status()`、`install()` 和 `uninstall()`。安装前用 `StudioHookEntryInstaller` 自检并部署固定执行入口。Studio 读取自身进程环境的 `COPILOT_HOME`，如果用户为终端单独设置了该变量，应从相同环境启动 Studio。
- 仅创建 `hooks/ahakey-studio.json`，由 Copilot 自身加载。安装通过同目录原子发布保护外部文件，卸载只删除匹配的自有配置。遇到同名外部文件或符号链接显示路径冲突。
- 提交、轮次结束和会话结束三种事件分别对应进行中、完成和移除。事件名称与会话标识都必须校验。传递的数据只有状态、事件名和必要的会话标识，Hook 不改变审批。
- Copilot CLI 添加后需要开启新的进程。真实回调回执绑定当次配置和固定二进制。使用旧 CLI 或受工具沙箱阻隔时，界面保持「等待回调」。

## 真实回调验收 · 2026-11-26

- **Copilot CLI 1.0.116**。从官方 `@github/copilot@1.0.116` npm 发行包在临时目录启动，以真实适配器生成配置。通过 `COPILOT_OFFLINE=true` 和本机模型执行一次 `copilot --model test/hook-smoke -p 'Return only OK. Do not use tools.'`，回执由等待变为已验证。另用同一官方 CLI 的独立日志探针确认 PascalCase 和 `exec/args` 组合真实触发 `SessionStart`、`UserPromptSubmit`、`Stop`、`SessionEnd` 四项。生产适配订阅后面三项。[Copilot 本地模型与离线模式](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-llm-models#running-in-offline-mode)
- **WorkBuddy 5.3.14**。以 App 内置的 `cli/bin/codebuddy` 运行，用隔离配置加载真实适配器生成的配置。使用本机模型和 `--tools '' --debug hooks --print` 模式，回执由等待变为已验证，内置引擎确认 `UserPromptSubmit`、`Stop` 都确实执行了固定入口并退出为 0。该验证走应用包内置引擎，桌面界面未启动。
- 两项都使用同一份由 SwiftPM 构建的实际 Agent，分别复制到独立临时 HOME 中的标准入口。两轮进程只允许回环请求及各自的临时 Unix 套接字，使用模拟模型和合成输入。验收未使用用户账号凭据、真实工具配置或运行中的 Codex。

## 打包与验收

1. 在工作副本运行适配层测试和 Hook 生命周期回归。覆盖安装、重复安装、单项卸载、保留用户自建 Hook、格式冲突，以及无法收到真实回调时的界面状态。
2. App 构建将 Agent SwiftPM 目标产物放进 `Contents/MacOS/ahakeyconfig-agent`。运行代码已编译进该产物，安装时由 Studio 自检并原子部署至 `~/Library/Application Support/AhaKeyConfig/bin/ahakey-hook`。DMG 脚本会重签 Agent 与 App，并核验签名。参考 [App 构建脚本](../../ahakeyconfig-mac/scripts/build.sh) 和 [DMG 脚本](../../ahakeyconfig-mac/scripts/package_dmg.sh)。
3. 对最终签名且装订公证的 DMG 验证 App 内实际 Agent、签名与目标架构。受控候选的内置 Agent 要能执行 `hook --hook-self-check`。同一次验收需从安装包启动 Studio，确认装入的是该候选的固定入口，再用独立的真实工具进程触发 Hook。
4. WorkBuddy 和 Copilot 的运行时已取得真实回调。最终发布仍需验证 DMG 中包含本轮适配以及已签名的 Agent。千问办公和豆包工作继续在目录中表达各自的公开接口边界。
