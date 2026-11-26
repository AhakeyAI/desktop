# 状态钩子适配优先级

数据核对日期为 2026-11-26。公开来源没有覆盖全部候选、口径一致的全球活跃用户排名。适配优先级使用同一调查题目的使用率作为主序列，用公开的 CLI 下载量补足调查缺口。下载次数包含更新、CI 与重复安装，不能换算为人数或与调查比例合并排序。桌面产品和 CLI 分开记录。状态钩子仅观察生命周期，新增适配沿用工具本身的权限设置。

## 同口径调查

Stack Overflow 2026 调查的过去一年使用，多选，作答人数 12,255。只列本清单中的工具及需区分的产品名。来源 [2026 AI coding agents](https://survey.stackoverflow.co/2026/ai/data#ai-coding-agents)。

| 调查顺序 | 工具 | 使用率 | 适配状态 |
| ---: | --- | ---: | --- |
| 1 | Claude Code | 65.5% | 有用户级 Hook 安装和单项卸载 |
| 2 | GitHub Copilot | 58.7% | 调查包含 Copilot 家族。Studio 的 CLI 适配已通过真实回调 |
| 3 | OpenAI Codex | 29.5% | 固定入口和真实回执已验 |
| 4 | Cursor | 25.5% | 有用户级 Hook 安装和单项卸载 |
| 5 | Google Antigravity | 16.0% | 本轮接入全局命名 Hook。App、CLI 和 IDE 使用同一官方配置路径，运行时分别待验 |
| 6 | Gemini Code Assist | 14.6% | 与 Gemini CLI 的用户量及接口分开计算 |
| 7 | OpenCode | 13.6% | 本轮接入 V1 全局插件。OpenCode 2 使用独立插件接口 |
| 8 | Cline | 4.5% | 已接入 Cline CLI 全局脚本，官方运行库验证回调。完整 CLI 轮次和 IDE 扩展另验 |
| 9 | Pi | 4.4% | Pi 1.6.1 CLI 本机模型轮次已验证。另列的 Pipi 先核对产品身份 |
| 10 | Amazon Q Developer | 3.9% | 调查产品与清单中的 Kiro 分开记录，不继承使用率 |
| 11 | Continue | 3.8% | 待核对扩展和 CLI 的生命周期接口 |
| 12 | Mistral Vibe | 3.2% | 待核对用户级 Hook 与无交互实测方式 |
| 12 | Kilo Code | 3.2% | 扩展与 CLI 分开验收 |
| 14 | Devin | 2.9% | 需区分本机 CLI 生命周期和云端会话接口 |
| 15 | Aider | 2.1% | 待核对可支持的生命周期入口 |
| 16 | TRAE | 1.3% | 国际版与中国版分别核对 |
| 17 | Augment Code | 1.2% | 单独核对 Auggie CLI 接口，不继承整个产品使用率 |

Antigravity Hook 接入用户级命名配置，观察调用开始及全部工作结束。OpenCode V1 观察会话状态和删除事件。产品发布或安装数字不直接证明回调在所有运行版本可用。
[Antigravity Hooks](https://antigravity.google/docs/hooks) · [OpenCode V1 插件](https://github.com/anomalyco/opencode/blob/dev/packages/web/src/content/docs/plugins.mdx) · [OpenCode V2 迁移说明](https://opencode.ai/v2/docs/build/plugins/migrate-v1/)

## 下载量参考

npm 公开 API，2026-10-27 至 2026-11-25，查询入口 [npm downloads API](https://github.com/npm/registry/blob/main/docs/download-counts.md)。仅统计安装入口包，不叠加平台二进制包。

| CLI 或工具 | 包名 | 30 天下载 |
| --- | --- | ---: |
| Codex | `@openai/codex` | 112,445,717 |
| Claude Code | `@anthropic-ai/claude-code` | 68,840,544 |
| Pi Coding Agent（当前包） | `@earendil-works/pi-coding-agent` | 27,105,160 |
| OpenCode | `opencode-ai` | 16,409,176 |
| OpenClaw | `openclaw` | 11,839,053 |
| GitHub Copilot CLI | `@github/copilot` | 7,262,137 |
| Gemini CLI | `@google/gemini-cli` | 2,084,642 |
| Pi Coding Agent（旧包） | `@mariozechner/pi-coding-agent` | 1,785,803 |
| CodeBuddy Code | `@tencent-ai/codebuddy-code` | 800,052 |
| Qwen Code | `@qwen-code/qwen-code` | 630,641 |
| Kilo CLI | `@kilocode/cli` | 232,847 |

优先补足调查前列的 Antigravity 和 OpenCode。下一组重点核对 Cline、Pi 和 OpenClaw，其中 Pi 当前包的下载量显著高于旧包，两个包分列以免重复计算。Gemini CLI 和 Qwen Code 已找到明确的原厂生命周期入口。GitHub Copilot CLI 和 WorkBuddy 内置引擎已完成真实回调验证，WorkBuddy 本轮验证覆盖提交和完成。CLI 数字只使用各自的包名作为归属，Gemini Code Assist 与 Gemini CLI、千问办公与 Qwen Code、WorkBuddy 与 CodeBuddy 各自保留独立记录。

## 清单中其他产品

| 工具 | 可核实的入口或待补证据 |
| --- | --- |
| Kimi Code／Kimi CLI | 现有 Hooks 适配。CLI、Desktop 实际运行边界分别记录 |
| WorkBuddy | 5.3.14 安装包内置引擎已验证提交和完成回调。桌面版与 Enterprise 的配置路径分开 |
| 千问办公（千问工作） | 文档公开企业后台 HTTP Hook，接入依赖企业授权和回调部署 |
| 豆包工作 | 已确认产品。尚未核实公开的本机会话 Hook |
| Claude Agent Teams | 需确认 Orca 启动方式下主会话与队员事件去重，保留 Claude Code 配置 |
| DeepSeek Harness | 核对 `dsh-tui` 的事件格式、真实进程及支持版本 |
| ZCode | 核对 Orca 描述与 ZCode 原生事件合同 |
| OpenClaude | 核对产品、配置路径及 Claude 兼容性 |
| Grok | 核对实际 CLI 安装来源和用户级事件接口 |
| OpenCode 2 | 使用 V2 插件接口，分别验收 |
| MiMo Code | 核对 CLI 生命周期事件和用户级扩展路径 |
| Ante | 核对本机发布渠道和状态接口 |
| Muse | 核对当前 CLI 版本的原生接口 |
| Qoder CLI | 核对国际版 Hook 格式和路径 |
| Qoder CLI 中国版 | 单独核对中国版二进制和用户级配置 |
| Pipi | 核实与 Pi 是否同一工具，避免误装 |
| OMP | 核对插件合同及后台任务事件 |
| Prime Agent | 核对会话事件和本机安装渠道 |
| Gemini CLI | 有公开用户级命令 Hook，可按 BeforeAgent / AfterAgent / SessionEnd 开发 |
| Goose | 核对本机状态扩展接口与不同安装路径 |
| Amp | 核对本机扩展可观察的事件 |
| Kiro | 核对独立 CLI 版本、全局路径及会话事件 |
| Charm Crush | 核对生命周期的公开扩展方式 |
| Autohand Code | 核对官方配置路径和开始／结束回调 |
| Codebuff | 核对生命周期和本机扩展入口 |
| Freebuff | 区分 Codebuff 与 Freebuff 的程序入口及生命周期 |
| Command Code | 核对 CLI 状态合同 |
| Droid | 核对官方 Hooks 合同及版本 |
| Qwen Code | 保留 CLI 独立条目，核对官方 Hooks 与发布版本 |
| Rovo Dev | 检测仅看到 ACLI 时需进一步确认实际可用 Rovo Dev，单独核对事件接口 |
| Hermes | 核对本地 Agent Hook 与 CLI、网关差异 |
| OpenClaw | 已接入本机 Gateway 的状态元数据插件，插件启用由 OpenClaw 管理 |
| CodeBuddy | 企业 IDE、CLI、WorkBuddy 分版本核对 |
| Jcode | 核对同名产品和命令，再验证生命周期 |

下一组的接口证据：

- Cline 的扩展文档有全局单事件文件，SDK 又提供另一套文件与插件入口。适配需先锁定 CLI / 桌面端所用运行时，现有用户脚本必须保留。[Cline 全局 Hook](https://github.com/cline/cline/blob/main/.clinerules/hooks/README.md) · [Cline SDK 插件示例](https://github.com/cline/cline/blob/main/sdk/examples/plugins/README.md)
- Pi 当前扩展接口区分 `agent_end` 和最终稳定的 `agent_settled`，完成态须采用后者或按老版本能力降级。[Pi 扩展文档](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md)
- OpenClaw 的内部 Gateway Hook 和类型化插件 Hook 是两条入口。应优先验证仅携带会话标识和状态的观察事件，保持默认隐私设置。[OpenClaw 插件 Hook](https://docs.openclaw.ai/plugins/hooks)
- Qwen Code CLI 提供用户级配置中的命令 Hook；千问办公继续按独立企业 HTTP 方案评估。[Qwen Code Hooks](https://qwenlm.github.io/qwen-code-docs/en/users/features/hooks/)

相关来源 [Orca 工具目录](https://orca.dev/docs/agents/supported) · [Gemini CLI Hooks](https://geminicli.com/docs/hooks/reference/) · [Kimi Code 桌面 Hooks](https://www.kimi.com/code/docs/kimi-code-desktop/settings-and-extensions.html#hooks) · [千问办公 Hooks](https://docs.qwenwork.cn/desktop/hooks)。原厂合同、可用测试运行时和本轮打包验收见 [状态钩子适配与打包](./agent-hook-adapters-2026-11-26.md)。
