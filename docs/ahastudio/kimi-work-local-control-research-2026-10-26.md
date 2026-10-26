# 普通 Kimi／Work 3.2.18 本地控制静态调查

日期：2026-10-26。仅调查本机官方安装程序资源；不安装或启动任何App／内嵌程序，不连接socket、HTTP、WebSocket、IPC或生产API，不调用模型，不读取用户Library、聊天、运行会话、账号或凭据，不改生产代码／配置，未提交。

## 结论

**普通Work实际包含本地WebSocket控制面，不是只有Renderer私有IPC。** 但“有控制传输”“可改默认值”“内核内部有setPermission”三件事不能直接拼成第三方已经可以实时切换所有原任务权限。

当前确认的三层能力：

| 层 | 静态确认 | 对原任务切档的意义 |
| --- | --- | --- |
| App本地方法`app.askMode.get/set` | 默认值、按conversation覆盖、读取effectiveMode、广播changed | 有完整App设置层；setter本身只改存储和广播，不直接改内核运行中权限 |
| 内嵌Daimon控制服务器 | loopback WebSocket＋Bearer；备用继承fd RPC；App从子进程ready行取得URL/token | 外部传输真实存在；尚缺可支持的第三方发现／授权合同及原任务权限setter接线证据 |
| 内核权限能力 | core有setPermission；Daimon在创建／恢复／每轮apply状态及临时恢复时调用 | 内部会话控制有实现；未证明通用控制路由直接暴露它，某外层adapter的同名方法明确unsupported |

因此值得继续核验已有Daimon控制协议及命令目录；不能采用写私有ask-mode.json、调用Renderer IPC或给下一轮send塞模式来冒充拨杆对原任务即时生效。

## 版本、签名与复现锚点

程序：`/Applications/Kimi.app`，bundle ID `com.moonshot.kimichat`，3.2.18／build3.2.18.6；Developer ID为Beijing Moonshot Technology Co., Ltd，Team ID `2J9472RW75`；签名详情显示2026-10-20签名与stapled ticket。本轮只读签名详情，未额外在线公证验证。

ASAR：`Contents/Resources/app.asar`，SHA256 `6eb027db9d23b1c7f5246c1cc8f15bd92340febb422bc09e5d7309449469d6d0`。主入口条目`out/main/index.js`的SHA256 `4b20660fdc04d6c9de50bf252ccadb3fb9502f5be3065126529a83dcd5f98408`。

官方安装资源`Contents/Resources/resources/daimon-bundle/bundle.json`记载Daimon **0.6.8**、kernelCommit **fdc02718d**、darwin-arm64、构建于2026-10-20。不能套用另一个产品Kimi Code Desktop1.1.3／公开1011d8b的接口行为。

临时证据：`/tmp/ahakey-kimi-work-static-20261026/`，含ASAR目录、定点提取的main／preload程序文本、程序哈希和符号偏移`evidence.json`。主入口有字符串表混淆，研究使用Python静态读取字符串数组、计算数组轮转与文本替换来辅助阅读，**未执行包内JavaScript**；辅助解码可能有同形函数误替换，关键行为均对照原始符号／调用结构确认，未将辅助文本当发布源码。

原主入口字符偏移（从0计）：

| 原符号 | 偏移 | 用途 |
| --- | ---: | --- |
| `_0x493b98` | 5261131 | ask-mode存储更新 |
| `_0x5bdbc7` | 5262317 | app.askMode方法表 |
| `_0xcfe4ed` | 6094879 | 内存默认模式setter |
| `_0x32cfec` | 4862911 | 按accepted turn处理auto审批fallback |
| `_0x14d226` | 5863279 | 子进程control-ready解析 |
| `_0x4e6735` | 7979445 | App context socket方法验证 |
| `_0xcce79c` | 7985022 | context.sock传输 |

## App设置层：全局默认与会话覆盖确实分开

`app.askMode.get`读取`initialized/defaultMode/effectiveMode/byConversation`；有效值先取conversationKey对应覆盖，没有覆盖才取默认。`app.askMode.set`接收mode和可选conversationKey，验证模式为`ask-before-acting`、`act-without-asking`、`auto`，写入以ask-mode.json为文件名的store并持久化，然后广播`app.askMode.changed`及读回快照。未传conversationKey修改的是`$default`，不会删除所有会话覆盖。

这不是“全局三档意味着每个既有任务必然跟着一起变”。setter本身没有调用core.setPermission，没有遍历内核运行任务；广播可更新界面／未来取值，当前执行轮次是否消费该广播不能仅凭广播存在确认。

另一个`kimi-agent:set-default-permission-mode`由Renderer通过Electron IPC调用，只验证manual／yolo／auto后写主进程模块变量`_0x41560a`，读取者包括launcher。它既不是持久化ask-mode store，也不是直接的现有会话setter。IPC handler还验证sender／注册WebContents，并非外部HTTP地址。

## 实际Daimon外部传输与认证

安装资源`daimon-bundle/README.md`明确描述：`bin/daimon`最终启动前台daemon及control；ready行提供`ws://127.0.0.1:<port>/control`和Bearer认证信息，WebSocket受阻时可用继承fd3/4的fd-rpc。**这里是读取安装资源说明，未运行这些命令。**

主程序`_0x14d226`确实从子进程输出解析URL、token、auth并缓存endpoint；DaimonHost维护runtimeGeneration、已连接URL、重连及通知处理。说明普通Work本地控制server不是文档猜测。fd是父子进程继承通路，不是第三方可直接附着的稳定地址。

本轮没有找到可供第三方无需读取日志／凭据便取得既有Daimon endpoint和授权token的完整外部发现合同；没有读取ready行日志或用户状态来补这个空白。也没有验证该WS允许调用App命名空间的方法。App自己的control-plane dispatcher注册`app.askMode`等本地方法，接受受验证Electron IPC及产品远控连接；**Daimon进程的WS不是自动等于App主进程dispatcher**，不能把同名“control”混在一起。

主程序列有`capabilities.get`、`control.commands.list`、`control.command`、`sessions.list`、`conversations.send/setModel/setThinking`等Daimon方法。这里没有明确的conversations.setPermission条目；但命令目录及generic command可能另有能力，尚未完成其参数和命令白名单的静态穷尽，不能以缺少直观名字证明不存在权限通路。

## 当前轮次权限：有内部实现，不能当已开放setter

App `_0x32cfec.rememberAcceptedTurn`在send／goal接受后，把accountId、conversationKey、requestId、kernelSessionId、当时的permissionMode存入Map。审批事件到来时，依据匹配到的accepted turn记录是否为auto来决定fallback自动应答。它不会在每个审批点重新读取ask-mode默认store；后续设置变更不等于旧accepted-turn记录已改变。失败路径还能重新展示tool approval，因此不能复制其部分逻辑就宣布恢复／撤权已完成。

安装包内Daimon的`dist/_internal/c-XCTHSDSV.js`（SHA256 `a8ccd30734ba1b371cd7372c85ff733c55d8c321b0a1e2037f80f51aef4efaf1`）含内部kernel adapter。静态读到：

- `forkKimiCodeSession`、`resumeKimiCodeSession`设置指定mode；`applyTurnRuntimeState`在每轮应用permissionMode并更新session cache。
- `runKimiCodeTurn`含临时权限覆盖后恢复originalPermissionMode的路径，属于该轮执行控制，不是AhaKey断连恢复合同。
- 某外层adapter的`setPermission(request)`返回unsupportedOperation；内核底层仍可通过core.setPermission执行。须明确具体adapter／sessionKind，不能“搜到setPermission”就声称对外可用。
- `@moonshot-ai/agent-core/dist/index.mjs`确实含setPermission和manual／yolo／auto，但它是Daimon内部持有的core通路，不是本机公开监听地址。

当前证据不能证明改变全局默认会广播到全部既有内核运行任务，也不能证明改变某会话覆盖会更新正在执行这一轮。要继续沿Daimoncontrol.command／命令表及adapter可用性验证，且需要原任务owner与独立permission读回；只返回askMode effectiveMode不够。

## 其他本地入口排除与边界

App有随机临时目录下的Unix `context.sock`，目录0700、socket0600、校验同UID／dev／inode，Windows对应named pipe。其服务请求严格限定op字段，支持get_app_info、get_user_info、get_access_token、flush_slides_decks。**不含权限设置；本轮没有连接它或读取任何token。** 这个入口也不能作为任意RPC转发器。

Info.plist登记kimi与kimi-work scheme；已核查的kimi-work路径处理插件等入口，没有确认既有任务权限setter。HTTP监听位置还包含OAuth callback、自动更新代理、文件／资源服务等，不能因“有本地端口”就当成会话控制API。

本轮只对App及Daimon定点程序路径做静态调查，未穷尽所有混淆模块、native Mach/XPC实现或远端网页资源，故不写“所有外部接口都不存在”。发现的明确入口是DaimonWS，而关键未证实处是第三方发现／鉴权、权限命令与对当前任务的生效合同。

## 下一步可实施调查与生产限制

1. 继续定点阅读`control.commands.list`／`control.command`实际方法表，确认是否有选择原conversation／kernelSession的权限命令，以及它调用哪个adapter。保持零模型、零生产请求。
2. 查已有Daimon实例的官方发现与用户授予第三方连接的机制；不自动启动第二daemon，不从进程内存／Renderer注入取token，不启用调试或远控。
3. 即使找到了setter，也要验证owner/generation、已加载判定、当前轮次或下一轮、pending approval、全部任务范围、用户新修改／撤回、退出恢复；不能用改默认配置替代。
4. main既有Code CLI默认同步应保留，但与普通Work独立标识。普通Work live接管在缺乏上述证据时保持未接管，用户正常操作继续原审批链路。

本轮获得“普通Work确有本地控制传输、App设置层支持会话覆盖、内部turn权限setter与恢复存在”的新证据；尚未将它们闭合为可供Studio正式使用的原任务权限接口，未做生产实现或提交。
