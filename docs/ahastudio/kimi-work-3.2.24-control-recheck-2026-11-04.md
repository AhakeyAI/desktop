# 普通 Kimi／Work 3.2.24：公开发行包原任务权限接口复核

日期：2026-11-04。补足本机已安装3.2.23与官网3.2.24的版本差。本轮只下载官方公开发行包、验证签名、只读挂载、提取和静态读取文本。没有安装／启动／执行发行包或其中任何代码，没有替换 `/Applications/Kimi.app`，没有连接用户的 Work HTTP／socket／IPC、读取用户 Library／会话／token，未修改生产代码、权限、配置或固件，未调用模型、启用远控、提交或推送。

## 结果

**已取得并验证真正的 macOS arm64 Work 3.2.24／build3.2.24.20；静态检查没有找到新增的、可直接供 Studio 经第三方授权控制原任务权限并可靠恢复的完整通路。** 新包的 Daimon1.0.4／kernel0bf80c96b 仍有内部 live setPermission，但与3.2.23相同，已检查的明确路由表没有暴露对应独立权限 setter，App askMode.set 仍是偏好存储／广播，accepted-turn 自动审批仍持有原请求模式快照。不能把内部能力、App偏好与Bearer控制服务器拼成已验收的原任务接口。

结论限定为本次公开发行包和下面列出的路径；没有穷尽动态插件／所有混淆模块，更没有用缺少直观方法名证明任何隐藏接口绝不存在。不存在已建立的普通Work接管授权，本轮研究也没有实际权限写入许可。

## 官方来源链与包身份

1. 官方[产品下载页](https://www.kimi.com/products/download)的 Apple芯片下载链接是 [public latest macOS download](https://appsupport.moonshot.cn/api/app/pkg/latest/macos/download)。本轮实际GET返回302，Location为 [kimi_3.2.24.dmg](https://kimi-img.moonshot.cn/app/download/mac/kimi_3.2.24.dmg)，随后200；不是猜测版本文件名或使用私人token。
2. 响应 Content-Length **411195673**，Last-Modified **Mon, 02 Nov 2026 14:07:23 GMT**。完整下载 DMG SHA256 **e40df5954aacdfe69f5e56f9d679ef86a7d25f9134769ffe1b7ea382c77ca8fd**；ETag `b1f52ab9a0b6a9570fba4b3e84dd4b3e` 只作为响应元数据，不当作签名。
3. 官方[Work发布记录](https://www.kimi.com/help/kimi-work/release-notes)本轮顶部列3.2.24（2026-11-02），而[公开 updater feed](https://kimi-img.moonshot.cn/app/upgrade/latest-mac.yml)仍返回3.2.23／`Kimi-3.2.23-arm64-mac.zip`／releaseDate2026-10-30。因此没有把旧feed值或下载URL文字当成包内版本证明。
4. `hdiutil attach -readonly -nobrowse -noautoopen` 挂载到临时目录。镜像实际包含 **Kimi Installer.app**，真正App在 `Kimi Installer.app/Contents/Helpers/Kimi.app`，未执行installer。
5. 对installer及nested Kimi.app分别执行 `codesign --verify --deep --strict` 均退出0。nested App `codesign -dv --verbose=2`显示 Identifier `com.moonshot.kimichat`、Mach-O arm64、Developer ID Application **Beijing Moonshot Technology Co., Ltd (2J9472RW75)**、TeamIdentifier **2J9472RW75**、签名时间 Nov2 2026 21:20:20、stapled ticket字段。未额外在线查询公证。
6. nested Info.plist 独立确认 **3.2.24／3.2.24.20**。其 `Resources/resources/daimon-bundle/bundle.json` 为 **1.0.4**、kernelCommit **0bf80c96b**、darwin-arm64、createdAt **2026-11-02T04:12:52.861Z**；186 chunks。不是 Kimi Code Desktop，也不证明用户当前运行进程已升级。
7. nested `Resources/app.asar`：**218907629** bytes，SHA256 **6df3c9f1128f3bb5ec9e768809d6f98656d127d16dbdabfd2e40db24aae004d6**。提取条目 `out/main/index.js`：9762647 bytes，SHA256见下。

## 与3.2.23相同路径的限定比较

基线：[3.2.23当前安装包审计](kimi-work-3.2.23-control-recheck-2026-11-04.md)，而不是更旧0.6.8 adapter的unsupported结论。

| 检查路径 | 3.2.24直接静态证据 | 可承诺范围 |
| --- | --- | --- |
| App askMode get/set | main `_0x262033` 注册 app.askMode.get/set/importIfEmpty；get返回 initialized/defaultMode/effectiveMode/byConversation；set调用 `_0x438768` 写store、persist、返回快照并广播 | 支持偏好默认及conversation覆盖；setter本体没有原core live切档或修改accepted-turn快照 |
| 内部 kernel live setter | c-WC533JKF.js 的 DaimonKimiCodeV2KernelRuntime.setPermission(request) 调用 requireClient().setPermission({sessionId:request.kernelSessionId,mode:request.permissionMode})并更新该session cache | 内部持有者能力真实存在；本体不是unsupported，也未要求新建同名session或发送新消息 |
| 明确对外 routes | c-HE2VAK3I.js 的createDaimonControlRoutes包含 conversations.send/setModel/setThinking、interaction.respond、config等；与3.2.23选取相同conversations/control/config/interaction命名空间的直接注册方法集合比较，新增0、删除0 | 没有找到conversations.setPermission或control.command／control.commands.list直接注册；App残留generic别名不能当作server实现 |
| config.set | 同chunk返回requiresRestart，一般配置为true，step-limit独立即时机制为特例 | 没有确认permission通过配置重载即时应用到原任务；不能为切档重启daemon |
| 认证与传输 | bundle README仍给出loopback WebSocket ready行URL/token、Authorization Bearer及继承fd3/4；c-JQ3YLN53.js的isAuthorizedControlUpgrade检查loopback-dev-token并timingSafe比对Bearer | 有真正认证控制面；不是“只有Renderer IPC”。但未发现第三方经用户授予取得原实例端点／token的完整发现合同 |
| 原owner代际 | main `_0x5c4c96`解析子进程ready行，class `_0x43fdcd`维护runtimeGeneration/controlClient等 | App内部有owner生命周期管理；不能直接当作对Studio公开的认证发现／权限读回 |
| accepted-turn fallback | main class `_0x3b428f`保存accountId、conversationKey、requestId、kernelSessionId及clientPermissionMode或permissionMode；intercept按该记录auto状态自动respond | App偏好变化、core变更、原请求fallback收回必须分别证明，不能只验证某一层 |
| context socket | main handler仍仅接受get_app_info/get_user_info/get_access_token/flush_slides_decks，其他op拒绝 | 未提供通用permission RPC转发；账号token不是control授权发现合同。本轮未连接或取token |

route factory仍包含registry.installRoutes及功能工厂spread；本轮不是对所有动态贡献的穷尽证明。现有证据足以排除“普通注册表新增明显权限入口”这一推测，但不足以证明所有外部接口均不存在。

原始代码有强混淆。本轮复用纯Python静态字符串数组／常量rotation解码，合并字面量字符串拼接以辅助检索，**没有执行JavaScript、import、CLI、installer或runtime方法**。辅助解码可能存在同名数字属性的作用域歧义；关键setter、注册表、ready解析和fallback均与原始唯一符号／调用结构核对。下面提供原文件哈希及字节偏移，辅助文本不冒充官方公开源码。

## 原文件哈希与定位锚点

main.js 是ASAR `out/main/index.js`的临时提取名；c-*.js均是nested App的 `Contents/Resources/resources/daimon-bundle/app/daimon/dist/_internal/` 条目。offset为原始UTF-8 **0-based byte offset**，不是辅助解码后的字符位置。

- `main.js`：9762647 bytes；SHA256 `d8a84ca0ae0e70caa57e83839c34529c8294a7b0c7bc295810be3478fd23d4f6`。
  - `function _0x438768`：byte 4599710，line 69818。
  - `const _0x262033`：byte 4600877，line 69843。
  - `function _0x5c4c96`：byte 5199099，line 79156。
  - `class _0x43fdcd`：byte 5199921，line 79169。
  - `class _0x3b428f`：byte 7970029，line 118295。
- `c-HE2VAK3I.js`：1615123 bytes；SHA256 `2cc1d291b7ba89cbebb031da83581a03db6e6ecfa0b1a1510daca4ae7105e2ec`。
  - `createDaimonControlRoutes=`：byte 1576242，line 1。
  - `createDaimonControlConfigSetRoute=`：byte 1065506，line 1。
- `c-WC533JKF.js`：534598 bytes；SHA256 `106df4228fd6e0b8cae7e21e05688d73224767fe621daa5e99becab10ef0fa37`。
  - `DaimonKimiCodeV2KernelRuntime=`：byte 275291，line 1。
  - `(_0xe45811)`：byte 369567，line 1。
- `c-JQ3YLN53.js`：147457 bytes；SHA256 `eb7b3719d1b6100efe3c9350d3bedd95d5e7c988e526317158afa479f7a08926`。
  - `isAuthorizedControlUpgrade=`：byte 32438，line 1。

## 对产品实现的决定

3.2.24复核关闭了“仅因安装版本旧而尚未看见新版能力”的特定证据缺口，但没有闭合原Work运行态权限接管。当前仍不应新增普通Work production adapter，更不能标为原任务实时同步已完成。既有Code Desktop整合及CLI默认同步保持独立验收。

后续最小所需证据仍是：原实例的用户授权发现入口、明确的kernelSession/conversation permission get/set路由、真实已加载owner／generation校验、App fallback与core一致生效，以及带来源／revision或等价条件写入的恢复合同。只比较“当前值等于最后托管值”无法识别用户主动选回同值并消除竞态。本轮检查的askMode请求及live setter没有给出这整套合同；不声称整包没有其他revision字段。

没有采用私有文件改写、猜端口／路由请求、读取用户token、Renderer注入、自动开启远控、发空消息、第二core冷恢复或重启作为替代。真实全部授权任务、busy／pending／子任务、断连／退出／崩溃、用户主动修改的动态验收均未进行。

## 复现与清理

公开下载及只读挂载核心命令：

```sh
curl -fLsS --max-time 30 https://kimi-img.moonshot.cn/app/upgrade/latest-mac.yml
curl -fLsS --max-time 300 --dump-header /tmp/kimi-work-324-recheck/download-headers.txt --output /tmp/kimi-work-324-recheck/Kimi.dmg https://appsupport.moonshot.cn/api/app/pkg/latest/macos/download
shasum -a 256 /tmp/kimi-work-324-recheck/Kimi.dmg
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint /tmp/kimi-work-324-recheck/mount /tmp/kimi-work-324-recheck/Kimi.dmg
codesign --verify --deep --strict '/tmp/kimi-work-324-recheck/mount/Kimi Installer.app'
codesign --verify --deep --strict '/tmp/kimi-work-324-recheck/mount/Kimi Installer.app/Contents/Helpers/Kimi.app'
codesign -dv --verbose=2 '/tmp/kimi-work-324-recheck/mount/Kimi Installer.app/Contents/Helpers/Kimi.app'
```

Python仅用plistlib／json读取metadata，以struct按ASAR header offset提取main，hashlib计算SHA，再作静态文本检查。HEAD请求被官方入口以400／AllowGET拒绝；实际GET正常302→200。临时目录保留DMG、响应头、metadata副本、raw选定chunks、提取main、辅助解码文本和evidence.json。没有用户数据。完成后卸载本研究挂载的镜像；安装的 `/Applications/Kimi.app` 保持3.2.23不变。
