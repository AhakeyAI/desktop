# Kimi 三端原会话权限接口第二轮调查

日期：2026-10-26。范围：普通 Kimi／Work Desktop、Kimi Code Desktop、官方 CLI TUI。用户目标为明确授权的会话随拨杆进入官方完全自动模式，断连／暂停／退出恢复原权限并保留用户后续修改。本报告只调查接口，不把默认配置写入当作原会话控制成功。

## 本轮锁定版本与调查方式

官方公开仓库 [MoonshotAI/kimi-code](https://github.com/MoonshotAI/kimi-code) 在公共临时副本中 fetch 后锁定 **1011d8b63fcc150998a4710641563cd0f73369c9**。此前研究为7ccac2b45b8a3481c76f771bb99c043b562de2c5；其后是2.3.2发布同步与文档同步。关键TUI、SDK、server、Hooks接口源码未因这次差异新增外部附着通路。固定[CLI变更记录](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/apps/kimi-code/CHANGELOG.md)的最新条目为2.3.2，改动集中于Agent委派／swarm启用约束；2.3.1另记录会话锁占用与崩溃恢复改进。不能用最新版源码声明本机旧二进制已拥有相同实现。

本轮只执行公开源码读取、官方网页检索和安装包元数据／文件名检查。未读取用户聊天、会话正文、账号凭据、server token；未调用模型、启用远控、安装或启动新应用、调用实际会话读写API；未改客户端生产代码／配置、未提交。普通本机安装元数据仍为`/Applications/Kimi.app`、`com.moonshot.kimichat`、3.2.18，不能算Code Desktop真机实例。

## 结论与可接入能力

| 对象 | 确认存在的权限能力 | 原会话外部控制状态 |
| --- | --- | --- |
| 官方原版TUI | 本进程持有Session，`/permission`最终调用`Session.setPermission` | 最新公开TUI启动路径仍未发现常驻控制server/socket；`/web`退出TUI后转前台server，不是保留TUI的live attach |
| 已由官方Code Server持有的会话 | 实例发现、Bearer认证、profile写权限、status读权限、WebSocket事件、审批应答均有实际实现 | 可实施适配候选，但必须证明连接的是原owner且会话已在该实例加载；不能创建server再cold resume冒充接管 |
| Kimi Code Desktop | 官方UI三档及内嵌server产品能力存在 | 尚无本机实际Code Desktop安装证据；公开CLI server合同不能无条件套用Desktop的发现／认证／进程归属 |
| 普通Kimi Work | 官方确认默认／手动允许／全部，版本记录称全局支持 | 未证实公开的第三方原任务权限读写协议；插件Hooks、私有IPC、远控均不能直接等同外部setter |
| `PermissionRequest` Hook | 新版提供真实等待审批事件通知 | 当前仍观察事件，不能以stdout allow代替原审批；不支持的返回应继续原链路 |

**能开发的是已存在目标server的适配、能力与归属探测、授权／恢复状态机、准确未接管提示。目前证据不足以认定三端原实例完全自动切档均已打通。** main已有新进程默认同步继续保留，但需要与live结果分开展示。

## CLI TUI：内部setter不等于外部附着

最新[TUI权限命令](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/apps/kimi-code/src/tui/commands/config.ts)调用当前`host.session.setPermission(mode)`。这是官方原版TUI有能力切当前会话的直接证据。

[Node SDK](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/node-sdk/src/session.ts)公开`Session.setPermission`；[v2客户端](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/node-sdk/src/sdk-rpc-client-v2.ts)持有本进程core，不是任意PID的控制客户端。本轮针对TUI／CLI／SDK源码的server启动、监听、实例注册与socket搜索，仅找到web/远控显式入口，未确认普通TUI启动会附带可被Studio连接的控制监听。

[/web源码](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/apps/kimi-code/src/tui/commands/web.ts)明确当前TUI关闭、原进程改以前台server运行。它是同一会话的显式移交途径，但用户已要求原版TUI；不能悄悄迁走界面、开托管副本或启用远控来充当完成验收。

[会话锁合同](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/persistence/interface/sessionLock.ts)包含PID、hostname、启动时间、clientIdentity／显示名，并返回occupied冲突。**占用信息是owner线索，不是IPC地址**。不能自动takeover或关闭锁来绕过原进程。

## Code Server：真实现有接口与冷恢复陷阱

### 实例发现与认证

[官方Server API](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/server-api.html)说明多实例登记在`~/.kimi-code/server/instances/`、默认loopback、Bearer认证、实验性版本接口。`GET /meta`提供`server_id`、版本、启动时间；实时OpenAPI／AsyncAPI才是目标版本合同。

固定[instanceRegistry源码](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/instanceRegistry.ts)登记server ID、PID、host／port、启动／心跳时间；`listLive`主要检验PID存活，且可能清死文件，因此生产只读发现不应直接照搬会写目录的helper，也不能仅信同PID或旧心跳。需核对同用户、PID启动身份、loopback与`/meta`匹配。登记不含会话owner列表，也不含令牌。

[官方命令文档](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command)说明`server.token`按home共享，轮换被同home所有实例采纳。本轮只读公开实现，没有读取本机token；不能把共享认证当作“用户授权所有会话”。Desktop若使用不同home、`rpcToken`或自有token service，需独立验证，不能扫描或输出凭证。

### 会话识别、权限读回与写入

1. `GET /api/v2/sessions`用于目录发现；[v2源码](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/routes/v2/sessions.ts)的`activity.model`来自live事实，冷会话为null。非null可作为“该server已加载”候选线索；null不能反证无人持有，也不能证明该会话是目标用户窗口。
2. [GET /connections](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/routes/connections.ts)列WebSocket客户端、时间、user agent及订阅session ID，可辅助目标绑定，但订阅者不是执行owner的完备证明。
3. [profile POST](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/routes/sessions.ts)接受`agent_config.permission_mode`；实际[applySessionAgentConfig](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/routes/sessionAgentConfig.ts)先`resumeSessionById`，再broadcast。它会对未加载会话尝试冷恢复，因此HTTP成功不是live attach证明。
4. 同文件的GET profile／session最终序列化`agent_config`时只有model，不能将其当成权限读回。实际`GET /sessions/{id}/status`通过[legacy.status](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/app/sessionLegacy/sessionLegacyService.ts)返回`permission`，**但status也会resume**。
5. [GET runtime](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/routes/runtime.ts)同样会resume；runtime_id表示执行后端绑定，不是原UI owner。不能用它做无副作用owner探测。

[sessionLookup](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/app/sessionManager/sessionLookup.ts)明确区分`getLiveSessionById`与`resumeSessionById`。现有公开写API没有在本轮确认到“仅已加载、owner generation匹配才写”的原子前置条件。目录检查与POST之间仍有会话关闭／迁移竞态；生产应把这一项列为接口缺口，不能声称先列目录即可完全消除冷恢复。

### 生效范围与恢复

[broadcast实现](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/session/agentLifecycle/agentLifecycleService.ts)影响活动且未固定权限profile的Agent，包含可能的子Agent。[Mode服务](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/agent/permissionMode/permissionModeService.ts)广播状态更新；不能据此保证已经执行的工具停止、待审批请求自动重算或所有子Agent原值完全一致。

[审批REST](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/routes/approvals.ts)能列出并应答该server的pending approval，这与切换permission mode不同；它也使用resume，不能拿它接管另一TUI。不要把授权“管理模式”解释成可以回复所有历史审批。

用户选择的完全自动应映射官方`auto`而不是`yolo`。但[permissionPolicy顺序](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/agent/permissionPolicy/permissionPolicyService.ts)在auto策略之前仍有用户deny及危险命令guard；模式名不是无条件越过所有保护。本轮没有关闭这些保护。

断连恢复应按owner实例、session及可能子Agent记录原值与最后托管值，重新读到当前值仍等于最后托管值时才恢复，避免覆盖用户新选择。但仅值相等也无法辨别用户后来主动选了相同值；若要严格保留每次用户新修改，还需完整事件来源／修订号或上游CAS合同。server离线／权限读回失败应保留待恢复记录和明确状态，不能显示恢复成功。进程退出后仅靠Agent退出回调也无法保证立即远端恢复，需要独立存活的恢复执行者或下次启动补偿，二者语义不能混淆。

## 新PermissionRequest Hook：不能返回allow接管审批

[官方Hooks文档](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/hooks.html)把PermissionRequest标为观察事件；只有PreToolUse、Stop、UserPromptSubmit可阻断。说明中的exit0“allow”指继续原流程，不等于批准工具。

最新[agentExternalHooksService](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/features/externalHooks/agent/agentExternalHooksService.ts)对PermissionApprovalRequested仍调用`fireAndForget('PermissionRequest', …)`，不等待脚本决策；[runHook](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/features/externalHooks/internal/runHook.ts)只把`permissionDecision == deny`解析为block。返回allow没有实现覆盖审批的通路。可用它准确显示“等待审批”和观察结果，不能伪装拨杆自动批准。

## Code Desktop与普通Work的分别结论

[Code Desktop执行说明](https://www.kimi.com/code/docs/en/kimi-code-desktop/task-execution-and-review.html)确认Composer中的三档可切；[设置说明](https://www.kimi.com/code/docs/en/kimi-code-desktop/settings-and-extensions.html)确认部分CLI配置与Hooks共享；[版本记录](https://www.kimi.com/code/docs/en/kimi-code-desktop/changelog.html)本次最新条目仍1.1.1，历史修复提及内嵌server。**这些没有给出Desktop使用哪个实例登记、local bearer/rpc认证、server持有会话枚举的完整外部合同。** 本机只定位普通Kimi安装包，未安装／启动Code Desktop；因此Code Desktop应先完成实际安装版本与静态bundle的存在性核验，再判定可否复用上述server适配器。

普通[Work FAQ](https://www.kimi.ai/help/kimi-work/kimi-work-faq)确认默认／手动／完全自动；[Work版本记录](https://www.kimi.com/help/kimi-work/release-notes)最新条目仍3.2.19，3.2.2称三档为全局支持。它不等同每会话setter。[插件说明](https://www.kimi.com/help/plugins-and-skills/overview)确认Work可用Hooks等组件，并未确认沿用Code CLI的协议、配置目录和权限事件响应。官方产品页／FAQ／插件／日志中本轮仍未证实普通Work对外原任务权限读写API。产品内部IPC或自然语言能调用外部MCP的事实，不是让外部Studio反过来改Work权限的稳定合同。

## 建议实施顺序与明确缺口

1. 可先实现不改权限的产品／版本／实例发现及能力结果模型，区分`default-only`、`original-runtime-verified`、`unverified`，禁止仅写磁盘就点亮“会话完全自动”。保留main默认同步的独立状态。
2. 对已存在且真实持有目标会话的Code Server实现版本适配器：身份核对→授权范围匹配→读原值→POST auto/manual→独立status／事件确认→记录最后托管值；不自动启动server或冷恢复。
3. 在隔离、无模型请求的受控测试中验证owner消失、会话迁移、用户更改、server重启、HTTP成功但读回不符、断连及恢复重试。原子live-only写、修改来源／revision、子Agent保留原值都是需补强合同，不应省略。
4. Code Desktop先只读证明bundle/内嵌server与会话owner合同；普通Work另查官方支持的外部接口。原版TUI若没有随进程监听，就向上游提出本进程授权控制端点，不以更换TUI或冷恢复达成。
5. 没有接口／未获管理权时继续用户原审批链路。保留任务状态与等待审批观察，不能新增拒绝或宣称已撤权。

本报告保存调查结果；尚未开始生产live权限实现，也没有提交或推送。
