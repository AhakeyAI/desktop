# Kimi Desktop／原版 TUI 权限控制接口调研

日期：2026-10-25。只读调研；本次不安装软件、不修改用户权限／配置／会话、不发模型请求。官方公开源码锁定 `MoonshotAI/kimi-code@7ccac2b45b8a3481c76f771bb99c043b562de2c5`；本机 CLI `2.3.0`；待整合客户端 main 为 `0ddab17`。

## 结论

**Kimi 已经有会话权限设置能力，不能笼统写成“没有接口，只能同步状态”。** 必须区分：原会话所属进程内的设置、可鉴权连接的服务器、外部附着到独立 TUI、只影响未来会话的配置。

用户要求保留 main 已有能力并在其基础上完善。main 的新版配置路径、默认权限同步、托管配置恢复和准确提示均应保留为整合输入；不能因为原版 TUI 的实时附着尚未证明，就把现有能力整体删掉。保留实现不等于未经最终方案确认就立即改写用户默认权限。

| 产品／通路 | 已证实能力 | 对 AhaKey 的准确结论 |
| --- | --- | --- |
| Kimi Code Desktop | Composer 可随时切 Always Ask／Ask When Needed／Never Ask；有正式 Remote Control 可处理已有会话审批 | 有产品内权限控制，但本机尚无已验证 Code Desktop 实例；外部本地接口、认证与原会话归属仍需确认 |
| 官方 CLI TUI | `/permission` 可在运行期间打开权限列表，`/yolo`、`/auto` 可预选模式 | 原版 TUI 内有控制入口；这不是 Studio 可直接调用的外部 API |
| Node SDK | `Session.setPermission(mode)`，支持 manual／yolo／auto | 对自己持有的会话可调用；当前 v2 SDK 本进程启动 core、走内存传输，不可假设能接管另一个 TUI 进程 |
| Kimi local Web Server | 会话 profile 的 agent_config.permission_mode 可更新 | 有实际 REST 设置接口；需连接真正持有目标会话的实例，不能自行启动服务器后冷恢复同名会话冒充实时接管 |
| TUI `/web`／`/remote-control` | 可把当前会话移交服务器／网页 | 当前公开源码会先停止 TUI，再让进程转为前台 server，不是 TUI 保持原样的无侵入附着 |
| main 默认配置同步 | 原生路径及 default_permission_mode 已实现，旧 Python 路径兼容保留 | 应保留并补测试、所有权与提示；与现有会话实时收权分开验收 |

## Desktop：产品与本机实例不能混淆

[Kimi Code Desktop 快速入门](https://www.kimi.com/code/docs/en/kimi-code-desktop/getting-started.html)说明它是管理本地项目和Agent工作的桌面产品。`kimi app` 是新聊天入口。

本机 `/Applications/Kimi.app` 元数据为 `com.moonshot.kimichat`、3.2.18／build3.2.18.6；这不能当作 Kimi Code Desktop 真机。官方 [Code Desktop 版本记录](https://www.kimi.com/code/docs/en/kimi-code-desktop/changelog.html)当前最新为1.1.1（2026-10-21）；其中记载会话重新加载、跨客户端占用处理，早期也有内嵌服务器修复。这些事实不能替代外部可连接接口的证据。

[Desktop 权限文档](https://www.kimi.com/code/docs/en/kimi-code-desktop/task-execution-and-review.html)确认三档权限及Composer即时选择。当前没有从这些公开页面找到供第三方直接连接现有Desktop会话、改权限并读回的本地协议合同；结论是“尚未验证”，不是断言它不存在。

[Desktop 配置文档](https://www.kimi.com/code/docs/en/kimi-code-desktop/settings-and-extensions.html)明确CLI与Desktop共享部分配置、会话和日志；`~/.kimi-code/config.toml` 中的Hooks也适用于Desktop，UI数据另在 `~/Library/Application Support/kimi-code-app/`。它未保证每个权限默认字段都按同一时点应用，因此不能仅凭共享路径就声称main默认同步在Desktop也已实测成功。

[Desktop Remote Control](https://www.kimi.com/code/docs/en/kimi-code-desktop/remote-control.html)能打开已有会话、处理审批和继续任务；需要设置中明确开启、相同Kimi账号及相应会员权益。它是经Kimi网络的远控能力，不应为本地拨杆功能自动开启，也不能把单次审批与权限模式切换混作一项能力。

公开源码的 [app 命令](https://github.com/MoonshotAI/kimi-code/blob/7ccac2b45b8a3481c76f771bb99c043b562de2c5/apps/kimi-code/src/cli/sub/app.ts)只构造打开工作目录并新建聊天的 `kimi-code` 深链，没有权限设置参数。本次公开树中没有Code Desktop主程序源码；名为desktop的Web语法资源并不是Desktop IPC实现。

## TUI、SDK 和 Server 的实际边界

[官方 slash 命令](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/slash-commands.html)把 `/permission` 标为运行期间也可使用，`/yolo`、`/auto` 打开同一选择器；`/reload` 仍是空闲状态命令。不能把TUI内部操作不存在误说成没有权限能力。

SDK的 [Session.setPermission](https://github.com/MoonshotAI/kimi-code/blob/7ccac2b45b8a3481c76f771bb99c043b562de2c5/packages/node-sdk/src/session.ts)提供明确方法。其 [SDKRpcClientV2](https://github.com/MoonshotAI/kimi-code/blob/7ccac2b45b8a3481c76f771bb99c043b562de2c5/packages/node-sdk/src/sdk-rpc-client-v2.ts)会启动自己进程内的core并用内存传输。名字包含RPC不等于有现成跨进程接入点。

[Server API](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/server-api.html)定义 `POST /api/v1/sessions/{session_id}/profile` 的 `agent_config.permission_mode`，可传manual／yolo／auto。需要Bearer认证；接口实验性，以实际实例OpenAPI为准；实时事实仅针对该进程加载的会话。这里证明“有设置API”，不证明“任意服务器能更改另一个TUI”。

实际 [sessionAgentConfig 处理器](https://github.com/MoonshotAI/kimi-code/blob/7ccac2b45b8a3481c76f771bb99c043b562de2c5/packages/kap-server/src/routes/sessionAgentConfig.ts)在本core中恢复／取得会话，再调用广播模式设置。[广播实现](https://github.com/MoonshotAI/kimi-code/blob/7ccac2b45b8a3481c76f771bb99c043b562de2c5/packages/agent-core-v2/src/session/agentLifecycle/agentLifecycleService.ts)遍历仍活动、未固定权限profile的Agent。因此需验证主Agent与子Agent作用范围，不能只看HTTP成功。已批准并运行中的工具不会因“模式字段已变”就被证明停止；待审批请求能否立即转自动也未在本次做动态验证。

TUI [web命令源码](https://github.com/MoonshotAI/kimi-code/blob/7ccac2b45b8a3481c76f771bb99c043b562de2c5/apps/kimi-code/src/tui/commands/web.ts)先退出TUI再启动前台服务。官方 [CLI Remote Control](https://www.kimi.com/code/docs/en/kimi-code-cli/guides/remote-control.html)也说明从现有CLI移交会话，并使用Kimi中继；不能自动启用或描述为保持原TUI运行的直接附着。

[ACP参考](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-acp.html)是启动 `kimi acp` 后的stdio JSON-RPC宿主通路。它可驱动自己连接的会话，但不是已经打开的独立TUI所暴露的监听端点。

## 对 main 现有功能的保留清单

源代码基线：[KimiPermissionModeSync](https://github.com/AhakeyAI/desktop/blob/0ddab17fc8128d4090a5f1963354be666771f6f3/ahakeyconfig-mac/Sources/Shared/KimiPermissionModeSync.swift)、[KimiConfigLeverSync](https://github.com/AhakeyAI/desktop/blob/0ddab17fc8128d4090a5f1963354be666771f6f3/ahakeyconfig-mac/Sources/Agent/KimiConfigLeverSync.swift)。

- 保留Kimi Code原生目录、显式KIMI_CODE_HOME与旧Python版区分。
- 保留manual／yolo默认同步及main对用户已有auto值的处理，不把它误写成当前运行会话已改。
- 保留已托管配置在启动／断连／未知状态时的恢复、字节保真和私密文件权限保护，并与当前更严格的真实档位／出厂绑定／暂停授权核对接线。
- 保留提示“新建会话”与“已打开/恢复会话”之间的区别；旧版reload语义不能套到新版TUI。
- 与当前9项原生状态/审批观察事件整合，不能恢复“所有PreToolUse都等于等待审批”。

## 可验证的接续路线

1. 在隔离home、无真实凭证和模型请求下保留main默认同步回归，逐项验证用户自选auto、断连、暂停及重新安装时的所有权；这不是实时原会话验收。
2. 若有真正Code Desktop安装，先只读核对bundle/内嵌服务版本、同用户实例登记、服务身份、认证和目标会话归属；禁止用普通Kimi聊天客户端替代。
3. 只在可证实的目标持有者上，针对自建空白会话测试manual→yolo→manual及独立读回；不新建第二份正在使用的TUI会话，不把冷状态回写当活体控制。
4. 单独测试空闲、进行中、待审批、子Agent、断线/退出时的生效和撤权，标清下一次权限判断与当前已运行工具的边界。
5. 若原版TUI不提供外部附着，保留main的新会话默认能力，并如实显示作用范围；实时能力继续研究，不能以此为由删掉既有默认同步。Desktop若有可用本地通路则独立接入，不与TUI统一假设。

版本边界：CLI版本号2.3.0不能证明本机二进制与公开源码7ccac2b逐字节对应。slash文档对/web描述包含选择现有服务，而锁定源码实际是退出TUI后启动新服务；集成必须按目标安装版本实测，不能混用描述。

以上只形成研究结论，不修改生产实现；后续仍按用户要求逐项grill确认产品行为后执行整合。

## 补充核验：main默认同步的具体语义

main在自动档遇到用户已有`auto`时不会降为`yolo`；但手动、启动或断连同步会对检测到AhaKey Hooks的配置写`manual`。这不等于已具备独立授权、原值恢复或用户修改保护，整合时要完善这些边界，不能把“有Hooks”直接解释成无限期控制许可。

本次公开源码的[TUI创建会话路径](https://github.com/MoonshotAI/kimi-code/blob/7ccac2b45b8a3481c76f771bb99c043b562de2c5/apps/kimi-code/src/tui/kimi-tui.ts#L2752)把当前UI的`permissionMode`显式传给`harness.createSession`。因此修改磁盘默认值不应描述成能控制运行中TUI里的`/new`；至少要区分重新启动CLI、新进程建会话、恢复旧会话、同一TUI内新建和Desktop新建这几种入口。当前TUI已捕获的模式可能被继承，不能仅凭配置写入就显示该会话已切换。

核验方式为官方源码、官方文档、已装CLI `--version`及`--help`、本机应用Info.plist；没有对真实或临时会话发权限写入，没有启用Remote Control，没有启动模型调用。官网前端资源也未提供可直接用作Desktop会话权限调用的已验证深链。静态线索不作为外部控制已验收证据。


## 普通Kimi桌面版补充

本节补足用户指定的第三类产品：普通 Kimi 桌面版中的 Work／Chat；与上文 Kimi Code Desktop、官方 CLI TUI 分开判断。本节只查公开官方说明，没有查看用户聊天、凭证或任务记录，也没有启用远控。

### 已证实：Work也有真正的任务执行权限

不能把普通桌面版概括成“只有插件授权或macOS系统权限”。官方 [Work FAQ](https://www.kimi.ai/help/kimi-work/kimi-work-faq)明确三档：默认（常规操作自动，敏感操作询问）、手动允许（执行前询问）、全部／完全自动（不询问直接执行）。这些是本地 Agent 的任务执行策略，与挂载文件夹授权、插件账户授权不是同一层。

[Work版本记录](https://www.kimi.com/help/kimi-work/release-notes)在3.2.2（2026-08-26）明确新增“默认”并称**全局**支持三档；3.2.5（2026-09-04）加入手机远程控制Work。截至本次查询，页面最新条目为3.2.19（2026-10-22），本机3.2.18对应10月21日版本线。因此，当前本机普通Kimi应用与Work发布线吻合，但不能直接把权限描述为“每个会话独立”，也不能仅凭有远控就推断第三方可调用切档接口。全局默认、项目权限、已有任务快照的实际关系仍需核验。

官方[产品区分](https://www.kimi.com/help/others/product-comparison)说明普通桌面版有Work和Chat两种模式；Work是本地Agent，Kimi Code是开发者产品。[下载页](https://www.kimi.com/products/download)进一步说明Chat记录跨端同步、Work任务留在创建它的电脑，且Intel Mac普通桌面版仅有Chat；本地文件夹需挂载授权。这些是产品与数据归属证据，不能据此推导内部配置或API兼容。

### 公开扩展能力与外部控制之间的证据缺口

[官方插件定义说明](https://www.kimi.ai/help/plugins-and-skills/overview)确认Work和Code支持包含Skills、MCP、Agents、Hooks、Commands等组件的插件，部分插件还需OAuth授权。由此可以把Work插件／Hooks列为后续核验入口，但文档没有证明普通Work复用CLI的`~/.kimi-code/config.toml [[hooks]]`、事件格式、权限默认字段，或允许Hooks修改任务执行权限。不能把“支持Hooks”写成“已经能自动批准”。

本次检查的普通Work产品介绍、FAQ、插件说明与发布记录中，**尚未验证到**供第三方连接正在运行的Work、选择已有任务、设置权限并独立读回的公开本地协议；也没有可确认的权限设置深链、认证合同、配置重载时机或撤权保证。这是当前证据缺口，不是证明内部接口不存在。Code Server的profile接口不能直接宣称适用于普通Work；其“内核由Code提供”的产品描述也不能替代接口版本与进程归属验证。

| 需要区分的对象 | 已证实内容 | 尚需核验的控制范围 |
| --- | --- | --- |
| Work运行权限 | 默认／手动允许／全部三档；版本记录称全局支持 | 已有任务是否即时改变、下一次工具判断或仅未来任务；子Agent和待审批请求如何处理 |
| 普通桌面Chat | 跨端同步的在线聊天；与本地Work分开 | 是否存在需要本地拨杆控制的工具审批，以及具体可控接口；不能套用Work或Code合同 |
| 文件夹访问 | 用户挂载后允许访问本地文件 | 不能因切到自动档便扩大挂载范围 |
| 插件／MCP账号授权 | 插件可接外部服务，部分需OAuth | 不能以修改任务模式代替用户登录或增加服务权限 |
| macOS系统权限 | 与应用的本地Agent执行策略属于不同权限层 | 不自动开关辅助功能、麦克风等系统授权；没有把这些当作已验证的会话模式API |
| 手机远控 | 官方产品已提供Work远控 | 第三方接入、身份认证、会话归属、模式切换API未确认；本轮不启用 |

### 对整合方案的影响与下一步

1. **保留main已有Kimi Code默认同步能力。** 普通Work接口未核验，不应反过来成为删除CLI已实现能力的理由。界面与诊断应分别标识普通Kimi／Work、Code Desktop、CLI，避免显示一个笼统的“Kimi已切换”。
2. 对普通Work先只读核对安装包公开资源、运行进程及其本地服务身份，不读取用户对话／令牌，不猜端口调用写接口，不修改私有数据库；发现静态IPC／本地服务线索也只能作为下一步证据，不能标记已验收。
3. 若找到可支持的实例接口，先用空白受控任务验证目标身份、权限读回和manual→自动→manual，并分别覆盖已有任务、待审批、子Agent、断线及退出；全局设置要明确影响范围，不能伪装成只控制当前会话。
4. 若只有产品UI可切换，向用户明确它与稳定公开API不同；是否接受桌面UI适配、版本约束及失败回退，需要另行grill确认，不能在本次调研中替用户决定。拿不到控制权时继续原审批链路，不能将普通操作直接拒绝。

本节不改变上文结论：三类产品均存在产品内权限选择；AhaKey能否从外部控制用户原实例，以及何时生效，必须按产品、版本和会话归属分别验证。


### 本机普通 Kimi 安装包静态补证（2026-10-25）

只读检查 `/Applications/Kimi.app`：bundle `com.moonshot.kimichat`，版本 3.2.18 / build 3.2.18.6。打包主程序 `app.asar/out/main/index.js` 及 `out/main/chunks/ipc-channels-BkfOrbOL.mjs` 含内部通道 `kimi-agent:set-default-permission-mode`。主程序亦包含消息提交参数 `permissionMode` 与请求校验逻辑。这证明普通桌面 Work 有内部权限设置实现，但**不能证明第三方程序可通过稳定、已认证的外部接口控制正在运行的任务**，更不能直接套用 Kimi Code 的 REST 协议。尚未调用该内部通道、变更设置或读取用户会话/凭据。

用户已确认普通 Kimi 桌面版（含 Work）、Kimi Code Desktop、官方 CLI TUI 均在适配范围；三者需分别记录原会话接入、默认设置及撤权生效边界。main 既有 CLI 默认权限同步功能保留。


### 第2项已确认：自动档为完全自动（2026-10-25）

用户明确选择“改为完全自动：不再询问”。Kimi Code 的目标为 `auto`（Never Ask），不再沿用 main 自动档写 `yolo` 的产品映射；普通 Work 的实际等价档位与可控制范围需分别核实。保留 main 的功能与兼容路径，不代表保留其旧档位映射。不能通过捕获失败后返回 deny 模拟手动档，仍须保持原生审批链路。

main 固定基线 `0ddab17fc8128d4090a5f1963354be666771f6f3` 的原始 `KimiPermissionModeSync` 与 `TomlPolicyLocator` 已在独立临时目录运行往返探针（未读写用户配置）：初始 auto → 自动档 alreadyDesired/auto → 手动档 replaced/manual → 自动档 replaced/yolo。这证明“遇到auto不降级”只适用于当次自动档检查，不能保证往返后保留原完全自动语义。整合应以新确认的auto目标替换映射，并补往返与生命周期用例。

下一待确认：拨杆管理所有已授权会话，还是仅当前聚焦会话；三端接口可达范围、未接管会话与失联时的提示须据实显示，不能以默认配置成功代替活跃会话确认。仍处讨论阶段，未修改生产实现或安装客户端。


### 第2项已确认：全部已授权会话（2026-10-25）

用户选择拨杆管理全部已明确授权接管的Kimi会话，包含后台会话；未授权对象保持原设置。当前聚焦窗口不是唯一作用范围。三端分别识别实际会话持有者与控制结果，不可连接或读回失败的会话单独显示未同步，不能因默认配置写入成功而标整体成功。该选择是产品范围，尚不代表三端原会话接口均已验证可用。

下一待确认：设备断连、暂停后台或退出Studio时，恢复接管前权限还是切到手动；必须考虑用户在接管期间主动改权限的情况，防止退出覆盖用户新选择。


### 第2项已确认：恢复原设置并保留用户新修改（2026-10-25）

用户确认设备断连、暂停后台或退出Studio后，恢复接管前的权限，并保留用户在接管期间主动做的新修改。原本完全自动的会话恢复后可以仍是完全自动；不得机械写manual。必须按目标分别保存原值/最后一次确认的托管值，并在恢复前重新核验，无法区分来源或发生冲突时不能覆盖用户新值。异常退出后的恢复日志、目标持有者验证、恢复失败可见提示及重启恢复亦需实现与验证。三端原会话接口未确证不记为完成。

源码补证：固定上游SHA的 `AgentPermissionModeService.setMode` 更新状态并发事件，未在该方法中停止既有工具；permissionGate在执行前裁决，toolApproval通过独立interaction等待用户回答。不能声称手动切档会取消已经执行的操作，现有等待请求的转换行为仍须动态验证。`auto-mode-ask-user-question-deny`禁用AskUserQuestion，用户显式deny规则亦优先于auto放行；这些是Kimi原生政策，不应由Studio补丁绕过。完全自动是选择官方auto档，不能承诺覆盖上游所有禁用规则或系统权限。
