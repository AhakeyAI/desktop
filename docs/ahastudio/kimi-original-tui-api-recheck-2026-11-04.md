# Kimi CLI 2.4.0：运行中原版 TUI 权限接口复核

日期：2026-11-04。目标仓库 `connect&talk`。本次仅创建研究文档；没有修改生产实现、用户配置、会话、权限、凭证或固件，没有调用模型、启动 TUI/server、安装软件、启用远控或操控终端窗口。

## 可执行结论

**在锁定的官方 2.4.0 源码中，没有找到由普通原版 TUI 启动、可供外部认证附着并修改其活体会话权限的监听器。当前没有满足全部限制的已验证实现路线。** 这不是“Kimi 没有权限 API”：进程内 SDK、可选 Unix IPC host 和 Web Server 都有能力，但普通 TUI 没有把自己的 core 对外暴露。不能另起 core/server、冷加载相同 session ID，或把配置文件重载当成控制原进程。

此结论严格限定为本次检查的公开源码与已装二进制帮助信息；**不证明已装 Mach-O 与公开 tag 字节一致，不证明未公开接口绝不存在，也没有对真实运行会话做动态验收。** 用户要求的全部已授权原会话 manual↔auto，以及断连恢复原值且保留用户新修改，目前仍不能标为完成。

## 版本与证据固定

- 官方仓库是 [MoonshotAI/kimi-code](https://github.com/MoonshotAI/kimi-code)。annotated tag `@moonshot-ai/kimi-code@2.4.0` 对象为 `b8f43387e0b4af152fbdcb3c6f78c432f15fb649`，peeled commit 为 `f26e4d91ef8d5d233f6c20b42a150f96924d4f5e`，提交时间 `2026-10-28T19:39:17+08:00`。[CLI package metadata](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/apps/kimi-code/package.json) 明确 version `2.4.0`。下列源码链接全部固定此 commit，不使用旧 Python kimi-cli 文档作新版依据。
- 本机 `/Users/heartline/.kimi-code/bin/kimi`：`file` 输出 `Mach-O 64-bit executable arm64`；`--version` 输出 `2.4.0`；SHA-256 `39ebd6b434447574876bc66b05ae409c8e99b239494b3fef62b3a34ecceb9fd8`。这是本机观察，不是官方构建溯源证明。
- 已读前次 [2026-10-25 调研](kimi-runtime-permission-api-research-2026-10-25.md)及 [当前权限同步说明](../kimi-permission-sync.md)，本次对新 tag 独立核验。现有 Code Desktop 整合与未来 CLI 会话默认配置是不同能力，本次不改动它们。

## 各条候选通路

| 通路 | 2.4.0 官方证据 | 对运行中原版 TUI 的判断 |
| --- | --- | --- |
| 普通 `kimi` TUI | [run-shell.ts](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/apps/kimi-code/src/cli/run-shell.ts) 创建 `createKimiHarness` 并传入 `KimiTUI`；[SDKRpcClientV2](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/node-sdk/src/sdk-rpc-client-v2.ts) 自行 bootstrap core，使用 `@moonshot-ai/klient/memory` 和 `createKlient({ scope: app })` | 进程内 core；该启动链没有启动外部 permission listener |
| Node SDK | [SDKRpcClientV2](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/node-sdk/src/sdk-rpc-client-v2.ts) 的 `setPermission` 对本 core 的 main agent 调用 `setPermission(input.mode)` | 可控制自己持有的 session，不是现有 TUI 的连接器 |
| Unix IPC | [IPC host](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/klient/src/transports/ipc/host.ts) 确有 `serveKlientIpc({scope,socketPath,token?})`，通过 hello 可校验 token；[klient README](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/klient/README.md) 明确 memory／ipc 为创建时选择的 transport | 必须由持有 core scope 的进程主动启动 host；全树非测试搜索仅见定义、导出、README，无 TUI／SDK 启动调用。不能把“有 IPC 库”宣称为“原 TUI 已监听” |
| Web REST／WS | [Server API（固定版本）](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/docs/en/reference/server-api.md) 有 Bearer 认证、实例登记、GET/POST session profile；`agent_config.permission_mode` 支持 manual/yolo/auto；接口标记 experimental | [applySessionAgentConfig](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/kap-server/src/routes/sessionAgentConfig.ts) 对传入的本 core `resumeSessionById` 后调用 broadcast。没有转发到另一 TUI 的步骤；同 ID 不等于同活体对象 |
| TUI `/web` | [TUI web／remote handoff](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/apps/kimi-code/src/tui/commands/web.ts) 明确 `startNewServerAfterExit`、`await host.stop()`，退出后 `startServerForeground` | 原 TUI 停止，进程转为前台服务；违反保持原 TUI 的限制 |
| TUI `/remote-control` | 同一 [TUI web／remote handoff](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/apps/kimi-code/src/tui/commands/web.ts) 注册退出任务并停止 TUI，再启动 server／远控 | 同时违反不停止 TUI、不启用远控的限制 |
| ACP | [ACP reference](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/docs/en/reference/kimi-acp.md) 与本机 `acp --help` 定义 stdio server | `kimi acp` 是新的宿主进程通路，未定义附着到已运行 TUI |
| Hooks | [Hooks reference](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/docs/en/customization/hooks.md) 将 PermissionRequest／PermissionResult 定义为 observation-only；PreToolUse 的允许仅继续进入原权限检查 | 不提供 session mode setter；不能以返回 allow 绕过原生审批，也不能用 deny 冒充手动模式 |
| CLI 子命令 | 本机 `session --help` 只有 `list`；根帮助的 `--auto`、`--yolo` 是启动模式 | 没有暴露对既有 TUI 的 permission/attach 子命令 |

“没有 listener”的证据是**被检查源码的调用链与全树搜索**，不是简单根据文档没有提到而下结论；IPC 源码存在也已明确记载。搜索范围覆盖 `apps`、`packages`，排除测试做生产调用检索，并另外读了 transport 实现；没有尝试连接任何用户端点或读取 server token。

## 配置重载为什么不能补上这个接口

[ConfigService](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/agent-core-v2/src/app/config/configService.ts) 确实 watch config 文件并 debounce 调用 reload。因此不能沿用“新 CLI 完全不监听配置变更”的说法。但配置重载与当前 agent 权限更新是两个步骤：

1. [AgentLifecycleService](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/agent-core-v2/src/session/agentLifecycle/agentLifecycleService.ts) 的 `bindBootstrap` 读取 default permission，只有 `permissionModeConfiguredKey` 为 false 才应用；已有恢复权限时不会覆盖。
2. [permissionModeOps](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/agent-core-v2/src/agent/permissionMode/permissionModeOps.ts) 将 PermissionSetMode 标记 durable，`permissionMode` 和 configured 状态可 replay。[AgentPermissionModeService](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/agent-core-v2/src/agent/permissionMode/permissionModeService.ts) 的 `setMode` 直接改 agent 状态并发事件，不订阅 config default 变更。
3. [KimiTUI](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/apps/kimi-code/src/tui/kimi-tui.ts) 的 `hydrateLazyConfigDefaults` 用于无 session 的 lazy defaults；实际 create path 显式传 UI 内存中的 permission。已有 TUI 内 `/new` 也不能仅凭磁盘写入就保证使用新默认。
4. [TUI reload command](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/apps/kimi-code/src/tui/commands/reload.ts) 的 `/reload` 走 `reloadSession`；[SDKRpcClientV2](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/node-sdk/src/sdk-rpc-client-v2.ts) 明确拒绝 turn／compaction 进行中的 reload，然后重读配置、关闭并从磁盘恢复 session。这是 TUI 内部命令，不是外部附着 API，也不是活体权限热切换合同。

所以保留现有默认同步，但其成功不能映射为“所有已打开原会话已切换”。

## 会话归属与恢复要求

[Server API（固定版本）](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/docs/en/reference/server-api.md) 明确 live busy/pending 等事实只来自该 server 已加载的 session；cold session 显示 not-busy。它还记录 `40931` session occupied 和 `40932` session updated by another client，证明共享持久化不等于统一活体控制。[SessionLockService](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/agent-core-v2/src/persistence/backends/node-fs/sessionLockService.ts) 的锁实现以 PID／hostname／token 判断写入占用，另有 takeover；这些是写入协调，不是发现原 TUI 的权限 RPC。锁的存在也不意味着空闲原 session 永远无法被第二进程读取，不能夸大为永久独占。

[AgentLifecycleService](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/agent-core-v2/src/session/agentLifecycle/agentLifecycleService.ts) 的 `broadcastPermissionMode` 遍历活动 agent，跳过 closing／inactive 和 pinned permission profile；不能承诺所有子 agent 无条件统一。[AgentPermissionModeService](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/agent-core-v2/src/agent/permissionMode/permissionModeService.ts) 的 setter 更新模式与状态事件，没有停止既有工具的逻辑；本次没有动态验证待审批请求、正在执行的工具及子 agent 的转换时机。

当前 profile setter／SDK setter 接收的是 mode；[permissionModeOps](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/agent-core-v2/src/agent/permissionMode/permissionModeOps.ts) 的 PermissionSetMode 只含 agentId、mode，[AgentPermissionModeService](https://github.com/MoonshotAI/kimi-code/blob/f26e4d91ef8d5d233f6c20b42a150f96924d4f5e/packages/agent-core-v2/src/agent/permissionMode/permissionModeService.ts) 的变更上下文为 mode／previousMode。被检查的这些接口没有提供“本次写入者／托管租约／期望 revision”合同。即使将来原 TUI 暴露 socket，单靠断连时“值仍等于最后托管值”也不足以证明用户没主动选回同一值，存在同值与竞态问题。用户要求保留主动修改，需要实际 owner 提供来源／revision／条件写入或等价可靠机制，并验证退出、异常重启和失联时恢复。此处是接口设计推论，不是声称整套上游没有任何 revision 字段。

## 后续安全路线

- **当前产品实现**：继续保留已实现的未来会话默认同步及其原值恢复，明确原 TUI 实时控制未接通；不新增猜端口、写私有 session 文件、takeover、模拟按键或自动开启远控的方案。
- **上游可行方向**：由原 TUI 自己 opt-in 暴露经认证的 owner endpoint（可复用现有 IPC 库），支持目标身份／当前权限独立读回、授权范围、变更来源与条件恢复。这需要上游能力或另行允许的客户端改造；不能从外部给已经运行且未监听的原版进程补上 host。
- **验收前提**：取得这种真实 owner endpoint 后，先隔离空白 session 验证 manual→auto→manual、全部授权对象、用户改值及改回同值、busy／pending／子 agent、断连／退出／崩溃恢复，再判断可交付。当前没有开展这些写入或模型试验。

## 复现命令与检查记录

以下为本次实际执行的核心只读命令；临时源码位于 `/tmp/kimi-240-recheck.3hJZrk/source`，没有安装依赖或运行仓库代码。

```sh
file /Users/heartline/.kimi-code/bin/kimi
/Users/heartline/.kimi-code/bin/kimi --version
/Users/heartline/.kimi-code/bin/kimi --help
/Users/heartline/.kimi-code/bin/kimi session --help
/Users/heartline/.kimi-code/bin/kimi web --help
/Users/heartline/.kimi-code/bin/kimi acp --help
shasum -a 256 /Users/heartline/.kimi-code/bin/kimi
git ls-remote --tags https://github.com/MoonshotAI/kimi-code.git '*2.4.0*'
git clone --depth 1 --branch '@moonshot-ai/kimi-code@2.4.0' https://github.com/MoonshotAI/kimi-code.git /tmp/kimi-240-recheck.3hJZrk/source
# 以下在临时源码目录执行
git show -s --format='%H%n%cI%n%s'
rg -n 'serveKlientIpc|@moonshot-ai/klient/ipc|transports/ipc|socketPath|KIMI.*IPC|KIMI.*SOCKET' apps packages --glob '!**/test/**'
rg -n 'listen\(|createServer|serveKlientIpc' apps/kimi-code/src packages/node-sdk/src --glob '!**/test/**'
rg -n 'DEFAULT_PERMISSION_MODE_SECTION|permissionModeConfiguredKey|defaultPermissionMode' packages/agent-core-v2/src
```

关键搜索输出：`serveKlientIpc` 仅见 klient transport 定义／导出及 README；普通 CLI 区域 `createServer` 命中的是 `cli/sub/web/run.ts` 的 `createServerLogger/startServer` 导入，未命中 TUI listener。config 搜索进一步沿 bindBootstrap／durable permission state 读取上述源码，避免把无搜索结果当作唯一证据。未读取用户聊天、会话数据库、令牌或凭证。
