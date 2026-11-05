# Kimi CLI 2.5.0 原进程权限控制复核

2026-11-05，针对上一轮2.4.0之后新发布的官方版本补查。仅取得官方源码并静态读取，没有安装或执行该版本、启动TUI/server、读取用户会话/token、修改权限或调用模型。当前客户端对已授权Code Desktop会话的既有接管不变。

## 结论与适用边界

2.5.0含SDK/服务器权限设置能力，但本次核验的普通官方CLI TUI仍使用进程内core。尚未建立Studio经用户授权接入“这个正在运行的原TUI实例”的发现、读取、条件修改及恢复通路。因此继续保留CLI默认权限同步及运行中TUI不跟随的提醒，不用第二个core恢复同一磁盘会话冒充接管原进程。

这不是断言Kimi没有权限API，也不穷尽所有未公开接口。解除依赖需要原实例可用的授权控制接口及真实联调，不能仅凭SDK的`setPermission`方法名。

## 精确来源与路径

官方[2.5.0发布](https://github.com/MoonshotAI/kimi-code/releases/tag/%40moonshot-ai%2Fkimi-code%402.5.0)，发布于2026-11-04T11:52:02Z。标签对象ce342530baf90c89ecc4da254fceb8a299535d8c，剥离后源码提交41c341434ae24e45bfe0f2232ec11b80531ac717。下面路径均固定在该提交：

- [run-shell.ts](https://github.com/MoonshotAI/kimi-code/blob/41c341434ae24e45bfe0f2232ec11b80531ac717/apps/kimi-code/src/cli/run-shell.ts#L96)：普通TUI创建自己的`createKimiHarness`。
- [sdk-rpc-client-v2.ts](https://github.com/MoonshotAI/kimi-code/blob/41c341434ae24e45bfe0f2232ec11b80531ac717/packages/node-sdk/src/sdk-rpc-client-v2.ts#L551)：`createKlient({scope: app})`使用当前实例；同文件2139行的`setPermission`转给该实例的agent。不是对外发现原TUI的授权入口。
- [sessionAgentConfig.ts](https://github.com/MoonshotAI/kimi-code/blob/41c341434ae24e45bfe0f2232ec11b80531ac717/packages/kap-server/src/routes/sessionAgentConfig.ts#L24)：服务器按自己的core恢复会话并广播权限变化，不能由此证明另一个正在运行的TUI被修改。
- [agentLifecycleService.ts](https://github.com/MoonshotAI/kimi-code/blob/41c341434ae24e45bfe0f2232ec11b80531ac717/packages/agent-core-v2/src/session/agentLifecycle/agentLifecycleService.ts#L414)：bootstrap检查已恢复的permissionModeConfiguredKey；默认配置不是既有原会话的实时控制。

另外检查CLI session子命令及非测试源码的`serveKlientIpc/socketPath`调用：查到传输定义，但未在正常TUI创建链找到开放该服务的调用。`/web`路径先退出TUI后启动前台服务器，不能作为不打断原TUI的原实例控制证据。发布中的模型/effort下一轮更新也不能直接推导权限接口已对外开放。

普通Kimi Work公开latest下载入口本轮仍302指向kimi_3.2.24.dmg；未重新下载，也不声称字节未变。上一轮[3.2.24限定静态审计](kimi-work-3.2.24-control-recheck-2026-11-04.md)继续有效，未新增动态控制结论。
