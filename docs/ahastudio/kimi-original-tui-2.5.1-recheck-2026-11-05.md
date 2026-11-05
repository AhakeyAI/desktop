# Kimi CLI 2.5.1 原进程权限控制复核

2026-11-05。承接[2.5.0复核](kimi-original-tui-2.5.0-recheck-2026-11-05.md)，只获取并静态读取官方源码、发布页，未安装或执行Kimi，未启动TUI/server，未读取用户配置、token或会话，未写权限，未调用模型。没有修改客户端权限逻辑。

## 结论

**2.5.1没有为本次核验的普通官方CLI TUI补齐外部原实例权限接管通路。** 普通启动仍创建进程内core；SDK `setPermission`、服务器权限设置、Klient IPC传输均确实存在，但不能据此证明Studio可以发现并授权连接“正在运行的这个原TUI实例”，读取其状态、修改其权限、收到用户后续修改并在断连时条件恢复。此结论限于下面检查的官方提交及启动路径，不是断言所有隐藏接口都不存在，也没有经过动态联调。[普通入口](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/apps/kimi-code/src/cli/main.ts#L67-L101)、[TUI装配](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/apps/kimi-code/src/cli/run-shell.ts#L67-L149)、[SDK装配](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/packages/node-sdk/src/sdk-rpc-client-v2.ts#L499-L552)。

因此，本轮没有可直接落地且满足“原版官方TUI、无包装/分叉、全部显式授权会话、自动时完全自动/手动时请求审批、断连恢复原值且保留用户后续修改”的新增客户端集成路径。继续保留CLI默认权限同步及运行中原TUI不跟随的提示；不能用第二个core恢复同一磁盘会话作为接管原实例的验收证据。

## 版本与完整差异范围

官方[2.5.1发布页](https://github.com/MoonshotAI/kimi-code/releases/tag/%40moonshot-ai%2Fkimi-code%402.5.1)显示05 Nov 09:53；官方发布API本轮读回的精确发布时间为2026-11-05T09:53:44Z（[按标签查询](https://api.github.com/repos/MoonshotAI/kimi-code/releases/tags/%40moonshot-ai%2Fkimi-code%402.5.1)）。通过官方origin获取标签`@moonshot-ai/kimi-code@2.5.1`，标签对象为`232e42606210d4f1674f104abfa133043408b925`，`^{}`剥离为源码提交[`1b02030d8c2c6b00131b23ebb67a231614877827`](https://github.com/MoonshotAI/kimi-code/commit/1b02030d8c2c6b00131b23ebb67a231614877827)。对比基线为2.5.0的`41c341434ae24e45bfe0f2232ec11b80531ac717`；以下源码链接全部固定在2.5.1提交。

[官方不可变版本日志](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/apps/kimi-code/CHANGELOG.md#L3-L21)列出的补丁涉及：动态工具schema空system消息引起的HTTP 400；新会话标题；带空格本地图片路径；工具结果图片/视频预览；窄布局面板；已删除workspace的会话列表；过时空隐式workspace；流式工具摘要折叠抖动。

完整`git diff`共89个路径（含web构建产物重命名），逐项读取所有非web构建产物的变化，并复查保留的相关代码。源码变化集中在Kimi协议空content处理、kap-server会话列表workspace可见性、媒体结果投影、transcript分组及对应测试；web构建产物和版本/日志同时更新。对以下路径的`git diff --quiet`结果为相同：`apps/kimi-code/src`、`packages/node-sdk`、`packages/klient`、core的`agent/permissionMode`和`session/agentLifecycle`、`kap-server/src/routes/sessionAgentConfig.ts`。可复核[完整提交对比](https://github.com/MoonshotAI/kimi-code/compare/41c341434ae24e45bfe0f2232ec11b80531ac717...1b02030d8c2c6b00131b23ebb67a231614877827)。workspace列表过滤是磁盘索引展示行为变化，不能推导为运行中TUI owner发现能力。[可见性实现](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/packages/kap-server/src/services/workspaceVisibility.ts#L1-L22)。

## 保留路径的逐层证据

| 检查环节 | 2.5.1证据与含义 |
| --- | --- |
| 普通CLI → TUI | `handleMainCommand`非print分支调用`runShell`；后者`createKimiHarness(harnessOptions)`再将harness传入`KimiTUI`。[main](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/apps/kimi-code/src/cli/main.ts#L93-L100)、[run-shell](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/apps/kimi-code/src/cli/run-shell.ts#L94-L149) |
| harness → owner | `createKimiHarness`新建`SDKRpcClientV2`；其构造函数bootstrap app scope，使用`createKlient({ scope: app })`，即当前进程内实例。[harness](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/packages/node-sdk/src/sdk-rpc-client-v2.ts#L3197-L3214)、[scope](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/packages/node-sdk/src/sdk-rpc-client-v2.ts#L517-L552) |
| SDK权限设置 | `setPermission`转发给此SDK实例的`agentFacade(sessionId)`，没有在该方法中发现外部原TUI owner连接。[实现](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/packages/node-sdk/src/sdk-rpc-client-v2.ts#L2139-L2142) |
| IPC能力与接线 | `serveKlientIpc`接受已有scope、socketPath及可选token，使用memory dispatcher并校验hello token。因此IPC不是不存在；但在该提交全库非测试源码对`serveKlientIpc`及`klient/ipc`的检索中，查到定义/导出/说明，未找到普通TUI创建链启动它的调用，更未建立该TUI的授权端点发布/发现协议。[IPC host](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/packages/klient/src/transports/ipc/host.ts#L19-L52)、[认证](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/packages/klient/src/transports/ipc/host.ts#L100-L110) |
| CLI session发现 | `session`注册的是`list`；默认依赖创建自己的harness并调用`listSessions`。列表不是正在运行的TUI owner控制入口。[子命令](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/apps/kimi-code/src/cli/sub/session.ts#L65-L123) |
| HTTP服务器权限 | `applySessionAgentConfig(core, …)`在传入的服务器core上`resumeSessionById`，之后广播permission到该生命周期服务的roster。没有在此路径建立跨进程原TUI转发。[route helper](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/packages/kap-server/src/routes/sessionAgentConfig.ts#L19-L41)、[roster广播](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/packages/agent-core-v2/src/session/agentLifecycle/agentLifecycleService.ts#L494-L502) |
| `/web`和Remote Control | `/web`先设置exit task再`host.stop()`，退出后启动新前台server；Remote Control同样先注册exit task并停止TUI。即使OS PID可能保留，也不是保留正在交互的原TUI及其core控制。[web](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/apps/kimi-code/src/tui/commands/web.ts#L30-L60)、[退出与server启动](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/apps/kimi-code/src/tui/commands/web.ts#L125-L157) |
| 默认配置与恢复 | bootstrap仅在未恢复`permissionModeConfiguredKey`时应用默认模式。`setMode`为mode写入及mode-change事件；本次检查的设置接口没有expected revision/owner lease参数。已有内存事件并不自动提供Studio对原TUI的订阅和有条件恢复能力。[bootstrap](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/packages/agent-core-v2/src/session/agentLifecycle/agentLifecycleService.ts#L414-L427)、[mode service](https://github.com/MoonshotAI/kimi-code/blob/1b02030d8c2c6b00131b23ebb67a231614877827/packages/agent-core-v2/src/agent/permissionMode/permissionModeService.ts#L51-L81) |

## 客户端决策及后续验收门槛

本轮范围是独立发布的`@moonshot-ai/kimi-code@2.5.1` CLI，不能将其版本等同于Kimi Code Desktop随包server版本。本报告不构成扩大Code Desktop已验证版本门禁的依据，也不提出因此修改Desktop版本门禁。

本轮保持此前依赖判断。未来需要官方原TUI实际暴露并发布授权端点，能绑定明确的owner及全部用户授权会话，在该owner上读取/修改/观察权限，并对用户并发修改和断连恢复提供可验证的策略。仅保存旧值后无条件写回会覆盖用户后续选择；仅比较当前mode也不足以区分用户先改走再改回的情形。这里是客户端验收条件和并发推理，不是声称上游承诺了某种具体API。

实际接通后仍需验证自动/手动的行为映射、会话切换、原TUI持续运行、用户中途修改、断连及重连；本轮没有运行这些实验，因此不能宣布集成已完成。现有官方SDK/IPC可作为将来上游接线的技术线索，但客户端自行包装或修改TUI以打开它不符合本任务的产品约束。
