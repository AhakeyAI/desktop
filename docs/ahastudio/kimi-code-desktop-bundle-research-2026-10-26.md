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
