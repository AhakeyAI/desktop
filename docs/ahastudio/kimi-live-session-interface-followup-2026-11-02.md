# Kimi 三端原会话权限接口复查 — 2026-11-02

## 结论与范围

**本轮没有发现能解除“普通Kimi/Work＋官方原版TUI原会话权限控制”依赖的新公开合同。** 已有Kimi Code Desktop适配应保留；官方Desktop发布文档出现新版本，值得单独核验兼容性，但不能用通用Code Server或新版本号证明三端均已接通。

目标保持不变：全部明确授权的原会话，实体自动档使用官方完全自动 `auto`，手动档请求批准；失连／暂停／退出恢复接管前值并保留用户后续修改。可以由原官方Code Desktop加载明确授权的原会话；不创建替代server接管原TUI，不换成Studio管理的TUI。没有接口或未授权时继续原审批链路，不能返回拒绝或伪称自动批准。

本轮只读取公开源码、官方文档及本机应用Info.plist。不启动应用、模型或server，不读取账号、凭据、会话正文或权限记录，不调用实际权限接口，不安装、更新或修改任何应用／配置。新增本文件，不修改生产代码。

## 固定版本及完整差异入口

- 官方main固定 `a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55`，提交日期2026-10-30。对照此前 `bd0d4de3f895446680bb7d46dcd7f0f299889735`，Git对象比较为8个提交、266个变化路径。路径清单取自完整Git差异，不使用截断的GitHub compare API文件列表。[固定比较](https://github.com/MoonshotAI/kimi-code/compare/bd0d4de3f895446680bb7d46dcd7f0f299889735...a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55)
- CLI公开变更记录最新为2.4.1；本轮变化主要为读取预算、提示词、工作区技能、目录git状态、归档索引及ACP启动竞态，不能由版本升级推导出原TUI控制通路。[固定变更记录](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/apps/kimi-code/CHANGELOG.md)
- 官方Code Desktop发布页最新为1.2.1（2026-10-30）；列出的改动为阅读长中文文件与内置提示词等。本机只读Info.plist仍为1.1.3，bundle `com.kimi.code.desktop`；没有将官网新版本当成本机已安装版本。[官方发布页](https://www.kimi.com/code/docs/en/kimi-code-desktop/changelog.html)
- 普通Kimi本机Info.plist现为3.2.22，bundle `com.moonshot.kimichat`；官方Work发布页同为3.2.22（2026-10-29）。该版本的公开条目包括任务中心、提问和交互修复，没有公布第三方原会话权限setter。[官方Work发布页](https://www.kimi.com/help/kimi-work/release-notes)

本轮重点检查CLI/TUI入口、权限选择、`/web`／`/remote-control`、ACP、SDK setter、Server profile/schema、权限Hook及这些路径的差异；不是对全部266个路径做完整代码审计，也不据有限范围证明所有私有接口绝对不存在。

## 三端能力矩阵

| 对象 | 当前证据 | 本轮判定 |
| --- | --- | --- |
| 官方CLI TUI | `/permission`调用当前进程持有的Session setter；没有本轮核实到的外部附着端点 | 仍是外部接口依赖；不能靠新SDK Session或新server冒充原TUI控制 |
| Kimi Code Desktop | 现有原应用Server的profile写入／status读回路径继续存在；本机仍是已核验的1.1.3 | 保留现有接线与已获授权范围；1.2.1须先独立核验实际bundle／server合同，不直接扩白名单 |
| 普通Kimi／Work | 本机3.2.22；官方文档说明插件、Hooks及远程产品能力 | 未获得可由外部Studio枚举、授权并修改其原任务权限的公开合同，不能套用Code Server协议 |

### 原TUI内部setter与外部控制的区别

TUI的权限选择最终调用 `host.session.setPermission(mode)`；SDK的 `Session.setPermission`转发给该SDK持有的RPC实例。这证明原应用能控制自己持有的会话，并不提供发现其他既有TUI PID、认证和附着其Session的方法。本次对应TUI picker未发生新变化。[TUI权限选择](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/apps/kimi-code/src/tui/commands/config.ts)、[SDK Session](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/packages/node-sdk/src/session.ts)

`/web`仍调用 `host.stop()`，并在TUI退出后启动前台Server；`/remote-control`同样注册退出交接再停止TUI。它们是原会话交接到另一界面，不是保留当前官方TUI、从外部修改其正在持有的原会话。官方远程文档也把该命令描述为交接到远程界面。本轮没有启用远控。[固定实现](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/apps/kimi-code/src/tui/commands/web.ts)、[官方远控说明](https://www.kimi.com/code/docs/en/kimi-code-cli/guides/remote-control.html)

ACP新增变化是等待环境provider／server初始化完成后再派发请求。`kimi acp`明确启动stdio ACP server；`session/setMode`等处理器属于该server持有的实例，不是新增的任意现有TUI附着端口。不能为了利用这一能力更换用户官方TUI。[ACP启动入口](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/apps/kimi-code/src/cli/sub/acp.ts)、[启动队列修复](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/packages/acp-server/src/start.ts)、[处理器](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/packages/acp-server/src/server.ts)

### Server路径可用，但严格恢复合同没有新增

`POST /api/v1/sessions/{id}/profile`的 `agent_config.permission_mode`仍支持 `manual/yolo/auto`；实际实现先 `resumeSessionById`，再广播权限。对已验证、已授权、原Code Desktop持有的会话可继续复用；原应用加载已授权原会话的用户许可保持有效。这仍不能控制没有被该Server持有的原TUI。[固定profile路由](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/packages/kap-server/src/routes/sessions.ts)、[实际设置实现](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/packages/kap-server/src/routes/sessionAgentConfig.ts)

写入schema没有增加expected-revision、原子live-only条件或修改来源字段。本轮不能把“先读后写＋当前值相同才恢复”扩大成对任意并发用户修改的严格保证：用户在两步之间修改，或主动选回与托管相同的值，仍缺原子区分依据。广播还可能影响符合上游传播规则的子Agent，应继续保留此边界的完整验收。[固定schema](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/packages/agent-core-v2/src/app/sessionLegacy/sessionProtocol.ts)、[权限服务](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/packages/agent-core-v2/src/agent/permissionMode/permissionModeService.ts)

官方Server API自称实验接口并要求以目标版本实际OpenAPI／AsyncAPI为准。因此公开2.4.1源路径相近，不足以直接放宽Studio当前已核验Desktop server2.3.2的版本／元数据门控。[官方Server API](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/server-api.html)

### PermissionRequest仍不能代替批准接口

实际 `PermissionApprovalRequested`订阅仍 `fireAndForget('PermissionRequest',...)`；官方Hooks表将其列为只观察事件。返回stdout allow／exit0只能继续原流程，不能替代原权限批准。不能用它宣称已做到“自动档不再询问”。[固定Hook实现](https://github.com/MoonshotAI/kimi-code/blob/a2afdbc7d1fa0737d45d5780cc6c2bd38e477b55/packages/agent-core-v2/src/features/externalHooks/agent/agentExternalHooksService.ts)、[官方Hooks文档](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/hooks.html)

### 普通Work仍需自己的外部合同

Work文档确认支持Kimi Code式插件组件，包括Hooks；插件方向是让Kimi调用外部能力。该说明没有定义Studio反向发现／鉴权／设置Work原任务权限的端点。不能因普通Work与Code共用插件定义，就复用Code的home、Bearer或profile API；也不能把全局UI设置当作全部原任务权限已变更。[官方插件定义](https://www.kimi.com/help/plugins-and-skills/overview)

## 精确可推进事项与依赖

1. **现在可独立推进的兼容开发前置**：从官方入口取得Code Desktop1.2.1测试产物，只做签名、Info.plist、内嵌Server、路由/schema、实例登记／监听归属及meta能力形状的静态对照；确认实际差异后新增明确版本合同和隔离fixture。不能先把2.3.2白名单改成任意2.x，也不能仅凭本次公共源研究宣称bundle等价。官方稳定下载入口可沿用此前已验证的 `https://code.kimi.com/kimi-code/desktop/download/KimiCode-mac-arm64.dmg`，仍须核验实际下载字节和版本，不能只相信文件名。本轮未下载或安装该新版本。
2. **现有Code Desktop可以继续做无需模型请求的边界验收**：对现有明确授权目标，补owner退出／重启、HTTP成功但读回不一致、用户外部修改、恢复失败后的补偿与提示。须按既有授权范围、隔离记录及实际操作风险执行；本轮研究不另授予真实权限写入许可，也不把旧HIL证明扩展到新版本。
3. **原版TUI尚不能完成的接线**：需由官方原进程提供可发现且经授权的控制端点，能证明owner PID＋启动身份＋session归属，读／写manual/auto，并提供revision／CAS或明确修改来源来处理恢复冲突。只提供内部SDK setter、stdio ACP新实例或退出后Web交接，均不满足用户选择的原TUI范围。
4. **普通Work尚不能完成的接线**：需独立确认其原任务枚举、授权／鉴权、permission getter/setter、会话与全局的作用域、失连恢复及用户修改语义。发布日志与插件定义不能替代该合同。

截至本轮，不应新增未经证实的Work/TUI权限写入实现；不应减少三端目标或标整个H02-KIMI2完成。可推进Desktop新版本静态合同核验和既有实现的边界验收；Work/TUI依赖继续保留。本报告不改变此前已验证的Code Desktop功能、main默认权限同步或原生任务状态联动。
