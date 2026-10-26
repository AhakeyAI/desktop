# Kimi Code Desktop 官方安装包静态接口核验

日期：2026-10-26。只读安装包研究；没有安装或启动App及其内嵌可执行程序，没有连接实际权限API、启用远控、调用模型，亦未读取用户聊天／凭据。普通`/Applications/Kimi.app`保持原状。仓库只新增本文件，未提交。

## 来源与版本锚点

下载入口为官方[Code Desktop快速入门](https://www.kimi.com/code/docs/en/kimi-code-desktop/getting-started.html)链接的[FAQ Apple Silicon按钮](https://www.kimi.com/code/docs/en/kimi-code-desktop/help.html)。按钮实际指向：

- 请求URL：[code.kimi.com Apple Silicon DMG](https://code.kimi.com/kimi-code/desktop/download/KimiCode-mac-arm64.dmg)
- 302后的官方地址：[cdn.kimi.com同名DMG](https://cdn.kimi.com/kimi-code/desktop/download/KimiCode-mac-arm64.dmg)
- 本次下载大小：142,183,280字节；服务器Last-Modified为2026-10-25 10:33:08 GMT。
- SHA256：`b12328d3933e2fc2c0f8add452ac8546f1d3663dbeee03f01f97b168a06e4874`。
- App实际版本：**1.1.3**，bundle ID：`com.kimi.code.desktop`，主程序arm64。ASAR内package.json亦为kimi-code-app 1.1.3；内嵌server启动标注 **2.3.2**。
- Developer ID：Beijing Moonshot Technology Co., Ltd，Team ID `2J9472RW75`；签名时间2026-10-25 17:53:17（本机显示时区）。`codesign --verify --deep --strict`退出0，签名详情显示stapled notarization ticket。此处未另做在线公证查询。

**官方滚动下载已到1.1.3，而先前文档Changelog仅列到1.1.1。** 集成不能把文档版本号直接当安装包最新版，也不能把1.1.3静态证据追溯成旧版已验收。滚动URL可能更新，复现必须核对上面的哈希。

## 静态提取与复现证据

DMG仅以readonly、nobrowse、noautoopen挂载到任务临时目录。读取Info.plist与签名后，用标准Python读取ASAR目录与条目偏移、复制非node_modules的JavaScript文本到临时目录；未执行任何包内JavaScript。磁盘映像完成检查后已卸载。

临时证据根：`/tmp/ahakey-kimi-code-desktop-static-20261026/`。保存DMG、`asar-header.json`、`static-evidence.json`、`static-symbol-evidence.json`和提取的`extracted/out/*.cjs`；均来自公开安装包，不含用户数据。关键实现文件为ASAR条目`out/screenshot-ndJSkzLM.cjs`，其提取内容SHA256：`4987ed8984e7d52d2bc2526a5d4ddc3a05a263da9237d764e5ae562e9111c9a7`。文件名虽叫screenshot，实际上捆绑了主进程、core、server等实现，不能按文件名断定仅截图代码。

以下偏移为该UTF-8文本解码后的字符偏移（从0计），方便复核，不冒充上游源文件行号：

| 证据位置 | 字符偏移 | 含义 |
| --- | ---: | --- |
| `Sy` | 1858566 | home解析：显式home、KIMI_CODE_HOME、用户目录/.kimi-code依次回退 |
| `hon` | 4913700 | 实例登记序列化server_id、PID、host／port、启动／心跳／版本 |
| `_xn` | 5365041 | 通用server启动、实例登记、路由和鉴权装配 |
| `Sxn` | 5375516 | Desktop认证服务：内存token及私密home token兼容 |
| `HPn` | 5726809 | Desktop内嵌server引导与127.0.0.1随机端口 |
| GET／POST profile | 5202618／5203227 | 权限profile通路存在 |
| GET status | 5207050 | 实时权限读回通路存在 |
| PermissionRequest观察调用 | 2980148 | 仍fireAndForget，不接收审批决策 |

## 已证实：Desktop可以是原会话server owner的适配目标

### 1. 内嵌server及实例发现不是推测

`HPn`读取`Sy()`得到home，调用同bundle的`_xn`，参数含`host=127.0.0.1`、`port=0`、`serverVersion=2.3.2`、Desktop hostIdentity和自定义authTokenService。`_xn`在所解析home的`server/instances`登记PID与server ID，成功监听后用真实端口更新登记。默认home即`~/.kimi-code`；若App进程继承KIMI_CODE_HOME则不同，不能固定只扫描一个目录。

这次静态证据将上一轮“Desktop是否兼容通用实例登记尚未确认”推进为：**官方1.1.3内嵌server确实使用这套登记实现。** 尚未运行App，因此未实际观察登记文件、PID或监听端口；不能将静态分支当成现有机器已经运行此实例。

### 2. 鉴权同时支持内存token和共享home token

`Sxn(home)`创建认证服务，先生成只存在于主进程内存的随机token，Renderer请求由Electron网络拦截器添加该Bearer。除此之外，`isValid`还接受同home的`server.token`内容；该文件读取会检查Unix私密权限，并随mtime/inode变化重读。初始化另异步调用`hxn(home)`，文件不存在时生成并私密写入。

因此**不能再说Code Desktop只能通过不可访问的内存token认证**；1.1.3有共享home token兼容分支。也不能在本次未启动App的情况下声称其文件现已存在或可用。本次从未读取用户home的token，只分析安装包的路径和验证逻辑。

私有内存token、Electron的`serverCredential` IPC及Renderer请求注入不是第三方稳定API，不应提取进程内存、注入Renderer或调用私有IPC来规避公开认证。后续集成可在用户明确授权后评估使用同home官方Bearer合同，且不得输出token。

### 3. 权限读写接口属于同一个core实例

安装包内含`POST /sessions/{session_id}/profile`的`agent_config.permission_mode`处理，调用目标core的resume及broadcast；`GET /sessions/{session_id}/status`读取该core内Agent的permission，另有session目录、connections、WebSocket更新等通路。与官方[Server API参考](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/server-api.html)的接口架构一致，适配仍应以实际目标OpenAPI／AsyncAPI验证版本。

这个证据证明**已存在Desktop内嵌server上的权限适配是可实现候选**，不需要另开托管TUI或新的server来替代Desktop会话。

## 仍不能消除的原会话边界

- 实例登记说明哪个PID提供server，不证明任意已存session属于这个实例。需要PID／进程启动身份、server_id、版本和明确授权session共同核对，不能只拿home共享token就控制目录所有会话。
- profile写、status读仍可能调用resume，冷会话可以被加载；另一个TUI占用可能触发occupied。不能自动takeover、关锁或把冷恢复标成原实例live控制。
- 同bundle的目录live事实与connections订阅可作归属线索，但检查后到POST之间会有关闭／迁移竞态。本轮未确认公开写API支持live-only、owner generation或CAS前置条件。
- broadcast会覆盖活动且未固定profile的Agent，可能包含子Agent。只保存main原值不足以保证恢复每个子Agent的不同原权限。
- 仅比较当前值与最后托管值，不能辨别用户后来主动选择了同一个值。严格保留用户新修改需要事件来源／revision或对应上游合同；请求成功也不能代表所有待审批与在执行工具都已按新模式处理。
- `PermissionRequest`仍是观察事件，不能输出allow来批准。原链路有审批时要保留原行为。
- `out/app-CSJ4pYxR.cjs`中的kimi-code深链用于open工作目录／新会话和auth成功；未发现经该深链选择既有会话并切权限的已支持合同，不能用私有参数猜测。

普通Kimi／Work `com.moonshot.kimichat`与本包不同；上述结论不能套给普通Work。原版TUI也没有因Desktop包含server便自动拥有监听。

## 生产接入的具体下一步

1. 将Desktop **1.1.3／server2.3.2**列为已静态确认的协议候选；先做真实已运行实例的只读发现与签名／进程身份核对，不安装或自动启动替代实例。
2. 在明确授权后，按对应home取得官方Bearer，通过meta和runtime schema确认身份及合同；不调用聊天／历史接口，不输出凭据，认证失败保持原审批。
3. 在原server的受控空白会话上独立验证原权限读取、auto→manual及恢复，覆盖用户修改、会话关闭、owner改变、断连和暂停；不得用启动第二server并恢复同名ID替代该验证。
4. live-only写、CAS、子Agent原值恢复仍是交付缺口。若当前合同不足，应向上游寻求小型接口增强或明确限制，不用“POST成功”吞掉这些问题。
5. 客户端将默认配置同步和已确认原会话切档分别展示。此次静态核验可推进Desktop适配开发，但不能将三端live验收整体标为完成。

结论：Code Desktop公开官方安装包提供了此前缺失的发现与认证实现证据，**本地原Desktop会话接入值得继续做**；下一步是经授权的原实例只读识别与受控验收。本轮没有生产接入、实际权限写入或安装行为。


## 原会话原子边界补查

日期同上；仅补读已缓存官方`1011d8b63fcc150998a4710641563cd0f73369c9`源码及同一SHA256的Desktop1.1.3提取文本，未重新下载、运行App或调用实际API。**此次发现公开源码和Desktop bundle虽都标server2.3.2，局部实现并不相同，不能用版本字符串代替逐项能力核验。**

### Loaded map证据：目录非空model意味着取样时已加载

公开[v2目录实现](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/routes/v2/sessions.ts)的`factsOf`调用[resolveSessionFacts](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/routes/sessions.ts)，再经`getLiveSessionById`到[SessionManager.get](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/app/sessionManager/sessionManagerService.ts)的`this.sessions.get(id)`。`activity.model`只来自该live handle的main Agent；没有从持久化model填回。故非null是“该server取样时确实有loaded main”的证据，null可能是冷会话、缺main或未绑定model，不是完整否定。该目录读路径没有为取样而resume目标。

Desktop提取文本的`CH(accessor,id)`同样直接调用manager.get；`createSessionState`也在异步打开事件journal前后比较相同handle。这确认其内部认识loaded身份，但公开profile setter未接收该handle作为前置条件，外部仍不能把目录取样变成写时保证。

### WebSocket订阅不提供统一保活或原子写保证

公开[SessionEventBroadcaster.subscribe](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/transport/ws/v1/sessionEventBroadcaster.ts)先`resumeSessionById`，再登记subscriber；所以对冷会话subscribe不是无副作用的live探测。公开[IdleReaper](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/services/sessionIdleReaper.ts)默认30分钟、每分钟扫描，`closeIfIdle`只保留cron／busy／pending interaction，没有检查WebSocket订阅数量。其lease用于会话锁并在检查后释放，不是第三方可持有的“阻止卸载”租约。关闭事件会使broadcaster detach；订阅不能冻结生命周期。

**Desktop1.1.3 bundle不同：**同一提取文件中的`async subscribe(e,t,n,r,i)`直接`ensureState`，没有先resume；其`createSessionState`仅获取live map并比较对象。对该已下载包，订阅实现是loaded候选探测通路，而不是公开1011d8b的cold-resume通路。完整提取文本中未检索到`closeIfIdle`／`KIMI_CODE_SESSION_IDLE_RECLAIM_MS`或reaper的识别文本，不能宣称该包一定有公开源码的30分钟回收，也不能据此保证无其他关闭路径。**两者订阅均没有给后续权限POST携带可校验handle／generation；无原子保证。**

### 确有不cold-resume session的generic RPC，但属于显式调试端点

[dispatcher.resolveScope](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/transport/dispatcher.ts)对session／agent scope先`getLiveSessionById`，找不到即报错而不resume会话。由[serviceDispatcherRoutes](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/transport/serviceDispatcherRoutes.ts)及[permissionMode服务标识](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/agent/permissionMode/permissionMode.ts)可推导出如下调试路由形态：

- `/api/v1/debug/session/{sid}/agent/{aid}/agentPermissionModeService/mode`
- 同路径尾段`setMode`或`setModeAndBroadcast`，参数为模式。
- `/api/v1/debug/channels`可反射服务描述。

这是真实存在的内部generic分发能力，不能漏报成完全没有loaded-only实现；但[registerDebugRoutes](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/transport/registerDebugRoutes.ts)和[路由挂载条件](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/kap-server/src/routes/registerApiV1Routes.ts)证明它仅在`debugEndpoints=true`时注册，启动再限定loopback。Desktop bundle也保留相同开关，普通引导只传`debugEndpoints===true`，不是默认开启。

此调试通路不cold-resume session，仍可能`ensureMainAgent`或`getOrRestoreAgent`恢复Agent，且getter到setter有异步分发、生命周期释放竞态，没有CAS／expected owner generation。它不是普通发行可默认依赖的公开稳定合同。**不应为交付拨杆功能打开调试端点或调用任意服务反射。** 更合理的上游增强是把所需loaded-only条件做成窄的、鉴权且正式支持的权限端点。

### POST无已证实CAS；固定profile的子Agent不跟随广播

公开`updateSessionProfileRequestSchema`及对应处理器未包含expected owner、if_loaded、permission revision或If-Match校验；已下载bundle的profile路径也仅对permission_mode broadcast，未发现这些前置条件。接口外先检查目录或保持订阅不能补成服务端原子条件。这里结论限于已核查路径，不断言其他未来接口不存在。

[hasPinnedPermissionMode](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/features/tower/tower.ts)在当前版本具体为`profileName == tower-worker`；[broadcast](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/session/agentLifecycle/agentLifecycleService.ts)跳过这类profile、closing及非active的Agent。Desktop bundle的`jR`同样只识别tower-worker。因此main切auto并不等于所有子Agent都切auto；不应绕过固定profile逐个强改。

普通子Agent重建时，[AgentTool](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/agent/tools/agent/agentTool.ts)及[swarm重建路径](https://github.com/MoonshotAI/kimi-code/blob/1011d8b63fcc150998a4710641563cd0f73369c9/packages/agent-core-v2/src/features/swarm/session/sessionSwarmService.ts)会继承caller当前模式，tower-worker例外。这意味着托管期间新建／重建的子Agent与先前已活动子Agent的恢复基线并不相同；只有main原值不能完整恢复各Agent历史状态。

补查结论：**公开正常REST写路径尚无已证明满足原会话loaded-only＋CAS的能力；调试RPC存在可复用的内部实现思路，但不宜以开启debug的方式投入正常产品。** 可先继续实例解析和身份核验，保留权限写关闭；Desktop1.1.3可在明确授权后做原实例受控接口验收，但依旧不能把subscribe或目录结果当成原子写许可。向上游建议正式提供以server/owner generation、session/agent incarnation和expected revision为前置条件的读写接口，以及来源可区分的权限变更事件。


## 上游公开问题交叉核对（2026-10-26）

[Issue #914](https://github.com/MoonshotAI/kimi-code/issues/914)讨论的是运行中`/permission`等修改未同步为新会话默认值，方向不等于“写默认值能控制现有会话”。[Issue #2828](https://github.com/MoonshotAI/kimi-code/issues/2828)记录ACP呈现的mode可能与引擎实际permission不同；应据此设计真实状态读回，不能仅看UI/default标签。此次两项查询均为只读；问题报告不证明所有当前版本仍有同一缺陷，也没有发布新问题或评论。

## 客户端发现模块检查点

已实现KimiDesktopInstanceDiscovery和现有设备信息/Kimi诊断中的显式只读入口。读取范围限默认/显式KIMI_CODE_HOME的server/instances，不扫描用户其他目录，不读取token或对话、不建立HTTP连接、不恢复/写会话、不启用调试接口。登记需匹配规范server ID文件名、精确整数、仅loopback、有效端口和45秒内心跳；目录/文件所有者及写权限、软链接、读取时变化均核对。

生产核验使用同用户进程起始身份、官方bundle ID、Apple运行代码签名Team 2J9472RW75及内核FD信息证明PID实际拥有登记的loopback TCP监听，并再次核对进程未复用。输出关联原配置目录，但不是任意session的owner证明或权限写入授权。安装版本与serverVersion也不被当成逐字协议等价证明。

最终856项Swift测试通过，含8项发现/文件约束/真实IPv4和IPv6自有监听测试；没有生产token读取、HTTP或权限操作。此模块只完成接入前置发现与身份核验，不将三端原会话控制标为完成。是否允许官方REST在原Desktop中恢复已授权会话的产品范围已向用户确认；该选择到来前不启用依赖它的权限写。
