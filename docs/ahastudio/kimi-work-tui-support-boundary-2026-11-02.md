# 普通 Kimi／Work 与官方 TUI 支持边界 — 2026-11-02

> 2026-11-02补查：已通过认证GitHub API取得当前main `fc3b521b8b68468268bb4cfe7f45008ce08b2b99`（09:11:48Z）。下文五处关键实现：TUI config/web、ACP入口、SDK session、externalHooks service，与既有审计提交逐文件SHA256完全相同。原匿名限流记录是历史状态；本次只证明这五处未变，不声称整个仓库无新入口或私有接口不存在。[刷新回执](../validation/connect-talk-hil-2026-10-22/wbs-external-dependency-refresh-2026-11-02.json)。

结论：**目前没有核实到让 Studio 从外部切换普通 Kimi／Work 原任务、或保持官方 TUI 运行并切换其原会话权限的公开接口合同。** 原会话控制未完成的缺口是目标进程的发现、鉴权、权限读写和恢复语义；不是把 Hook 返回值改成 allow 就能补齐。

本轮只读官方网页、公开源码和项目证据；没有读取凭据、发送模型请求、修改应用／配置、安装软件或发送外部消息。官方 Work 发布页当前首条为 **3.2.22（2026-10-29）**；CLI main 变更记录首条为 **2.4.1**。实现核查固定于既有审计提交 `a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55`，不声称完整审计今日全部 main；GitHub API 查询当前 main SHA 遇到匿名限流。[Work 发布日志](https://www.kimi.com/help/kimi-work/release-notes)、[CLI 变更记录](https://raw.githubusercontent.com/MoonshotAI/kimi-code/main/apps/kimi-code/CHANGELOG.md)

## 能做什么，缺什么

| 对象／入口 | 已核实能力 | 对原会话接管的意义 |
| --- | --- | --- |
| 普通 Kimi／Work | 插件可让 Kimi 调用外部服务；Work 支持包含 Hooks 的完整插件组件组合，Web 当前支持 MCP 和 Skills | 文档没有给出第三方反向枚举、鉴权和修改其原任务权限的端点，不能据此套用 Code Server 协议 |
| 官方 TUI `/permission` | 选择器调用当前 `host.session.setPermission(mode)`；未建会话时把选择存入当前 TUI 的 appState | 是当前进程内部能力；没有因此获得附着另一既有 TUI 的端点 |
| `/web`、`/remote-control` | 停止 TUI，再交接到前台 Server；远控支持在远程界面处理审批 | 可交接原会话，但不满足保持原 TUI 运行的接管要求 |
| `kimi acp`／SDK | ACP 启动自己的 stdio Server／engine；SDK setter 使用该 Session 已持有的 RPC | 可驱动其管理的实例，不能把新实例当作原 TUI 已被控制 |
| `PermissionRequest`／`PermissionResult` | 官方列为观察事件，源码以 `fireAndForget` 派发 | 可观察审批状态；返回 exit 0／allow 不能完成审批或切换权限 |

证据：[插件官方定义](https://www.kimi.com/help/plugins-and-skills/overview)、[TUI 权限选择实现](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/apps/kimi-code/src/tui/commands/config.ts#L857-L878)、[TUI Web／远控交接实现](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/apps/kimi-code/src/tui/commands/web.ts#L23-L121)、[官方远控文档](https://www.kimi.com/code/docs/en/kimi-code-cli/guides/remote-control.html)、[ACP 入口](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/apps/kimi-code/src/cli/sub/acp.ts)、[SDK Session](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/packages/node-sdk/src/session.ts)、[Hooks 官方事件表与返回规则](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/hooks.html)、[权限 Hook 实现](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/packages/agent-core-v2/src/features/externalHooks/agent/agentExternalHooksService.ts#L188-L201)。

## 与已完成部分的区别

**Kimi Code Desktop 1.2.1／内嵌 Server 2.4.0 已接入，并已实际通过同一授权原会话 manual→auto 双向切换与正常停止恢复验收。** 不能沿用早期调查中“1.2.1 仍待接入／真实 HIL”的旧状态。此事实来自项目实现及实际验收记录，不由公共 API 文档推导；并发用户修改、崩溃／断网等完整异常矩阵仍不能据此判定全部通过。[接入与后续真实验收](kimi-code-desktop-1-2-1-adaptation-2026-11-02.md)、[实际验收记录](../validation/connect-talk-hil-2026-10-22/kimi121-and-k1-followup-hil-2026-11-02.json)

**当前生产已管理 nativeV2 的未来会话默认权限：自动档写 `auto`，手动档写 `manual`。** 实际调用链为 `AhaKeyAgent.finishApproval` → `KimiConfigLeverSync.synchronizeManaged` → `KimiManagedPermissionDefaults.synchronize`；有托管 Hooks 且 Kimi 自动化控制启用时才接管，使用日志保存原值，状态为 nil／撤销管理时尝试恢复。检测到用户外部改值后同档位让出管理；下一次实体拨杆变化可重新接管，并以用户新值作为恢复基线。这是默认配置标量管理，不能据此认定已运行的原 TUI 会话权限随拨杆改变；也未据此证明任意并发修改的原子保证。[实际 Agent 接线](../../ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift)、[默认值同步入口与 Hooks 条件](../../ahakeyconfig-mac/Sources/Agent/KimiConfigLeverSync.swift)、[native auto/manual 与恢复日志](../../ahakeyconfig-mac/Sources/Shared/KimiManagedPermissionDefaults.swift)

旧 `KimiConfigPolicySync.apply` 的 legacyPython 限制不是这条实际生产调用链，不能用它判定 nativeV2 默认同步禁用。legacyPython 的 `default_yolo` 默认值同步也仍在托管实现中保留。

## 为什么仍不能标为三端完成

普通 Work 尚需自己的原任务枚举、授权、权限 getter／setter 与作用域合同；官方 TUI 尚需由原进程暴露可发现、可鉴权且能证明会话归属的外部控制入口。两者还需确认失连恢复及用户并发修改语义。Code Server 官方明确把 API 标为实验接口，以目标版本自身 OpenAPI／AsyncAPI 为准，因此已验证 Desktop 通路也不能自动扩展到 Work 或另一 TUI 进程。[Server API 官方说明](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/server-api.html)

这里的“未核实到”限于上述公开文档及固定源码路径，不是证明所有私有接口不存在。后续获得官方外部合同后仍需针对目标应用版本做接线和原会话验收；仅共享插件格式、看到内部 setter、启动替代 Server 或观察到审批请求，均不足以宣称完成。

## 本轮提测应覆盖的现有能力

新版官方CLI TUI并非完全未适配：已安装托管Hooks的进程可发送任务生命周期／审批观察事件；Agent已接入新会话默认权限auto/manual的同步与原值恢复。测试应覆盖这两项，不能因为原会话控制缺口就从本轮测试范围移除。示例：自动档创建会话A时可采用auto；随后拨回手动，默认配置变manual，但已打开或恢复的A不因该文件改变而保证撤回权限，需用户在原TUI通过官方权限选择修改。具体新建／恢复／显式启动参数的优先级仍需实际版本回归。

普通Kimi/Work不能据插件文档承诺已完成同等状态与权限集成；没有核实专用适配及验收时，保持其自身行为。通用键盘快捷键和系统听写不依赖Work权限接口，但不等于Work任务权限已被拨杆接管。旧Python CLI兼容代码还保留条件式本机安装补丁，不能推广成新版原TUI支持证明。

