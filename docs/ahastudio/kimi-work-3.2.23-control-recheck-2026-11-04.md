# 普通 Kimi／Work 3.2.23 原任务权限控制复核

日期：2026-11-04。仅静态读取已安装的官方 App 资源，未运行包内代码，未启动／重启 App、Daimon、server 或模型请求，未连接 HTTP／socket／IPC，未读取用户 Library、对话、运行会话、令牌或凭证，未写生产实现、用户权限或配置，未安装、提交或推送。

## 结论

**新包已能证明 V2 runtime 内部有真正的按 kernelSessionId 设置权限的方法；但仍没有闭合“第三方经授权发现并连接原 Work owner → 设置／独立读回原任务当前权限 → 断连可靠恢复且保留用户修改”的完整通路。当前不能据此实现或宣布完成全部已授权原任务的实时 manual↔auto 控制。**

不能继续把旧报告中的“某外层 adapter 的 setPermission unsupported”直接套在新包上。当前 `DaimonKimiCodeV2KernelRuntime.setPermission` 是实际实现，会调用自身持有的 client；这与对外接口是否注册是两回事。新包仍有真实 Bearer WebSocket 控制面，问题不是没有传输，而是外部权限路由／原实例授权发现／运行态读回及恢复合同未确认。

本结论适用于**本机安装的 3.2.23／Daimon 1.0.3**，不声称已静态穷尽所有混淆模块或未公开扩展。当前官方[发布记录](https://www.kimi.com/help/kimi-work/release-notes)已列 3.2.24（2026-11-02），高于本机 3.2.23（2026-10-30）；此处日期来自父任务官方页面核验。本轮没有取得或检查 3.2.24 安装包，不能把本结论冒充该版本结论，也不能依据更新日志未提权限 API 就证明其不存在。

## 安装版本与可复现证据

`/Applications/Kimi.app/Contents/Info.plist`：普通 Kimi `com.moonshot.kimichat`，3.2.23／build 3.2.23.17。不是 Kimi Code Desktop。父任务直接读取此 metadata，并执行 `codesign --verify --deep --strict /Applications/Kimi.app` 返回 0；本子任务直接执行 `codesign -dv --verbose=4 /Applications/Kimi.app`，看到 Developer ID Application `Beijing Moonshot Technology Co., Ltd (2J9472RW75)`、TeamIdentifier `2J9472RW75`、签名时间 Oct 30 2026 13:34:32、stapled ticket 字段。没有在线公证查询；签名观察不证明运行行为或第三方 API 合同。

ASAR `/Applications/Kimi.app/Contents/Resources/app.asar`：212158422 bytes，SHA256 `12d01ed9b646bc937a3cef744c18a6d022da63aa0f60913eed2c311991417577`（父任务本机哈希）。本子任务用 Python 只读 ASAR header／offset，提取 `out/main/index.js`，10192030 bytes，SHA256 `a9111a0cc66c83824129a6cba3959155f1e89d868362e845fdef342f4c5bf141`。

安装资源 `Contents/Resources/resources/daimon-bundle/bundle.json`（直接读取）记载：version **1.0.3**，kernelCommit **50834ce83**，darwin-arm64，createdAt **2026-10-30T04:09:42.372Z**，186 chunks，`javascript-obfuscator-strong`，不含 TypeScript declarations。`app/daimon/package.json` 同为 1.0.3。README 描述 active kernel 为 in-process Kimi Code／KimiCore。

与 [3.2.18 旧审计](kimi-work-local-control-research-2026-10-26.md)比较：旧 ASAR `6eb027db…`／main `4b20660f…`／Daimon0.6.8／kernel fdc02718d 均已变更。本轮对当前资源重新提取和检查，未把旧偏移、旧 chunk 名或旧 adapter 结论作为新版直接证据。

## 当前权限链路：哪些环节已证实

| 环节 | 本轮当前安装资源证据 | 对落地的意义 |
| --- | --- | --- |
| App 偏好读写 | ASAR main `_0x46d349` 注册 app.askMode.get/set/importIfEmpty；get 返回 initialized/defaultMode/effectiveMode/byConversation；set 验证 mode，调用 `_0x48a0f1`，persist 后广播 app.askMode.changed | 有按 conversation 覆盖及全局默认；返回的 effectiveMode 是 App 偏好，不是 core 当前权限读回 |
| App setter 的实际效果 | `_0x48a0f1` 仅 store.set(conversationKey或默认键,mode)、persist、读取快照；setter 本体没有调用 V2 runtime、遍历任务或更新 accepted-turn 记录 | 不能把 UI 偏好 setter 当成原任务当前权限 setter |
| 本地外部传输 | bundle README 给出 ws://127.0.0.1:port/control、Authorization Bearer；fd-rpc 是继承 fd3/4；main `_0x267e13` 解析子进程 ready 行 URL/token/auth | 真实控制面存在，但凭据是由子进程交给父 App；不是已证明第三方可授权取得的发现入口 |
| 服务端认证 | 当前 c-IC6PM47Z.js 的 isAuthorizedControlUpgrade 检查 loopback-dev-token 模式，通过 getControlRequestToken/getBearerToken 并 timingSafeStringEqual 比对 token | 认证实现确实存在；本轮没有连接或取真实 token |
| 对外方法注册 | 当前 c-7CMJP2CY.js 的 createDaimonControlRoutes 注册 conversations.send/setModel/setThinking、interaction.respond、config 等，未见 conversations.setPermission 或 control.command／control.commands.list 的直接注册 | App 残留命令别名仍不能证明 server 实现了命令入口；未找到能单独切档的明确 route factory |
| **V2 内部 live setter** | 当前 c-XECA7RWQ.js 的 DaimonKimiCodeV2KernelRuntime.setPermission(request) 调用 requireClient().setPermission({sessionId:request.kernelSessionId,mode:request.permissionMode})，随后更新 sessionCacheBySessionId 中对应 permissionMode | 新版内部能力已证实；该方法本体无需创建新 session，也未发送 prompt。仍缺外部 route 把原 owner 中此方法暴露出来 |
| 正常 turn 应用权限 | 同 V2 class 的 fork／resume 路径有 setPermission；以 `_0x46ed47` 为参数的 turn 状态应用方法也调用 core setPermission 并更新 cache | 发送下一轮时设置模式是现有产品内部路径；不可通过发送空消息触发来替代独立切档 |
| App 自动审批 fallback | 当前 main 的 class `_0x11b8e3` 在 rememberAcceptedTurn 中以 accountId/conversationKey/requestId/kernelSessionId 保存 clientPermissionMode或permissionMode；intercept 依该快照是否 auto 自动答复 | 仅改默认／偏好不证明已接受 turn 的 fallback 已被收回；不能只控制 core 一层便宣称完整撤权 |

上表除 README 外的混淆代码阅读使用**静态辅助解码**：Python 解析字符串数组、按常量算式寻找 rotation、替换已识别 lookup alias，并合并字面量字符串拼接。没有执行任何包内 JavaScript、import 或函数。辅助输出不等于官方源码；数字属性映射可能有同名作用域碰撞，故关键结论同时按原文件唯一符号、调用结构、下表哈希／字节锚点核对，不把自动替换作为独立证明。

## 归属、发现与其他入口边界

main 的 `_0x1a8785` 维护 runtimeGeneration、ready control client、当前连接及失效客户端集合；表明 App 本身区分运行代际。内部 V2 runtime 以 kernelSessionId 管理 liveSessionIds 和 cache；这些可以成为今后 owner 校验的基础，但目前没有证明 Studio 能通过受支持的第三方授权拿到这个**原实例**的 endpoint/token/generation，再调用明确权限方法并独立读回。

App `app.*` 方法表和 Daimon WS 上的 routes 是两层 dispatcher。main 的命名空间解析区分 app／daimon；不能因为 app.askMode.set 已注册，就直接向 Daimon `/control` 发送同名方法并假定会到达 App。已检查 route factory 最后还有 registry.installRoutes 和若干功能工厂 spread；本轮确认的是明确注册表中未发现权限 setter，**没有宣称穷尽所有插件／动态扩展或隐藏入口**。

当前 main 的 context socket handler 仍严格限定 get_app_info／get_user_info／get_access_token／flush_slides_decks，其他 op 返回 unsupported_operation；不含通用权限 RPC 转发。账号 token 也不是 Daimon control token 的授权发现合同。本轮未调用这些方法、未读取任何用户目录来找地址或凭证。

Renderer `SET_DEFAULT_PERMISSION_MODE` IPC handler 仍只验证 mode 并调用 `_0x2a0ad4` 更新模块变量 `_0x342bc7`，不是外部本地 HTTP API；本轮没有调用 Electron IPC、注入 Renderer 或启用调试／远控。

## 配置与当前轮／下一轮

当前 c-7CMJP2CY.js 的 config.set 仍读写配置并验证，返回 requiresRestart：除 step-limit 独立失效机制外为 true；检查的函数没有对 permission 调用 live runtime setter。不能为了切权限重启 daemon 或写它的私有配置。

App askMode store 的读回与 changed 广播，只能证明偏好改变。当前 main 可见的正常发送路径先 `_0x5236f2(conversationKey)` 解析覆盖／默认，再转为 core 模式并放进 messageQueue.submit。已接受 turn 的 fallback 使用前述快照。因此需要分开：偏好默认、已排队请求、下一次发送时捕获的值、当前 core 权限、当前 fallback。没有发现把 App 偏好改动即时联动所有这些层的完整调用链；也没有做动态实验验证更新时序或 pending approval。

## 恢复与用户修改保护尚缺什么

setPermission 的内部缓存更新是能力证据，不是 AhaKey 生命周期事务。被检查 App askMode.set 请求只有 mode／可选 conversationKey 的设置逻辑，返回偏好快照，没有在该 setter 中确认托管租约、条件 revision 或写入来源。仅在断连时比较“值仍等于最后托管值”，无法分辨用户主动选回同一值，且有读后写竞态。当前仍未闭合原 core＋accepted-turn fallback 的权限读回、变更归因和条件恢复。

该结论限定为已检查的方法；不声称整包没有其他 ownerEpoch／revision 字段。要实现用户已确认的“全部授权原任务切档并恢复原值、保留用户新修改”，至少需要明确目标 owner、授权范围、独立 runtime get/set、带来源／revision 的变更与条件恢复，再验证 busy／pending／子任务、退出／失联／崩溃与重启。普通 Work 的实际接管授权尚未建立，本轮研究没有实际权限写入许可。

## 可落地决定

1. **当前没有可直接交付的完整安全路线。** 保留现有 Code Desktop 整合及 CLI 未来会话默认同步，并对普通 Work 标为尚未接通原任务实时控制；不得以它们的成功替普通 Work 验收。
2. 后续最短调查是向上游确认：现有 App／Daimon 的第三方授权发现合同、可调用 V2 live setter 的正式路由、原 session permission 读回，以及 App fallback 联动／恢复的来源版本合同。V2 内部 setter 已存在，具体缺口比“内核不支持”更窄。
3. 不采用新建第二 runtime／同名冷恢复、私有文件改写、取账号 token 冒充 control 认证、猜路由调用、Renderer 注入、自动开启远控、发空消息或重启作为补丁。
4. 3.2.24 是后续独立核验对象；本轮未下载／安装它，其是否新增对外权限路由仍未知。

## 原文件定位锚点

以下 offset 为原始 UTF-8 文件的 **0-based byte offset**，不是辅助解码后的偏移。main 来源为 app.asar 条目 out/main/index.js；各 c-*.js 均位于 Contents/Resources/resources/daimon-bundle/app/daimon/dist/_internal/。单行 minified chunk 的行号无定位价值，故同时给 SHA 和唯一符号／byte offset。

- `index.js`：10192030 bytes，SHA256 `a9111a0cc66c83824129a6cba3959155f1e89d868362e845fdef342f4c5bf141`。
  - `function _0x48a0f1`：byte 5388533，原文件 line 82811。
  - `const _0x46d349`：byte 5389728，原文件 line 82836。
  - `function _0x267e13`：byte 5964151，原文件 line 91847。
  - `class _0x1a8785`：byte 5964950，原文件 line 91860。
  - `class _0x11b8e3`：byte 9499678，原文件 line 125612。
- `c-7CMJP2CY.js`：1600577 bytes，SHA256 `8e5ef3d016dc2941aab49fc7b37fb8ac5932fdac4a2b14bd115fedf2acdfce7c`。
  - `createDaimonControlRoutes=`：byte 1561310，原文件 line 1。
  - `createDaimonControlConfigSetRoute=`：byte 1052064，原文件 line 1。
- `c-XECA7RWQ.js`：535784 bytes，SHA256 `f166a3e9dbf26729633dd8860f6be0e1a0f281cf81754c0500d398cdb52dfa1d`。
  - `DaimonKimiCodeV2KernelRuntime=`：byte 276964，原文件 line 1。
  - `(_0x53376c)`：byte 371404，原文件 line 1。
  - `(_0x46ed47)`：byte 414877，原文件 line 1。
- `c-IC6PM47Z.js`：138097 bytes，SHA256 `2d4ef5c98bcbb2d5f3ff94b79f28a2ef55f5d2c13a81a3bc860548e6045e08ef`。
  - `isAuthorizedControlUpgrade=`：byte 25260，原文件 line 1。

临时证据目录 `/tmp/kimi-work-323-recheck/`：提取 main、ASAR header、Python 静态解码脚本、辅助 decoded 文本及 evidence.json。临时目录仅含安装包资源／研究衍生物，不含用户会话或凭据；它不是交付所需依赖。

核心复现操作：

```sh
codesign -dv --verbose=4 /Applications/Kimi.app
cat /Applications/Kimi.app/Contents/Resources/resources/daimon-bundle/bundle.json
cat /Applications/Kimi.app/Contents/Resources/resources/daimon-bundle/README.md
cat /Applications/Kimi.app/Contents/Resources/resources/daimon-bundle/app/daimon/package.json
# Python struct 读取 app.asar 前16字节：4,478172,478168,478164
# JSON header 的 files 节点取 out/main/index.js offset/size；payload 起点为 8+478172
# Python hashlib.sha256 计算所提取条目及上述三个官方 chunk 的哈希
# 仅静态检索／常量解码 createDaimonControlRoutes、setPermission、app.askMode、control-ready、context handler
```

所有包内代码都作为文本读取，没有执行其 CLI、README 示例命令或 runtime 方法。本轮新增产物仅此研究文档；没有修改用户权限、配置、production code 或 firmware。
