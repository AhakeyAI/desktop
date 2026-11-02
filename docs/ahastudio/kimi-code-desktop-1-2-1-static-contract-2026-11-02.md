# Kimi Code Desktop 1.2.1 静态合同核验 — 2026-11-02

## 结论

**1.2.1需要新增明确的客户端版本合同。** 签名包实际内嵌Server标注为 **2.4.0**，不是公开CLI最新的2.4.1；`GET /api/v1/meta`的capabilities变为5项，没有旧包的`terminal`。当前生产parser限定2.3.2并要求6项，因此会拒绝这份官方新包。HTTP桥目前使用的目录／status／profile路径均仍存在，相应读写形状没有发现必须更换协议的差异。

建议新增精确“Desktop1.2.1／Server2.4.0”profile，并保留“1.1.3／2.3.2”旧profile；不能将版本放宽为任意2.x或全局去掉terminal要求。静态证据不等于真实实例发现、鉴权、权限切换和恢复联调通过。

本轮仅下载官方DMG、只读挂载、验签和读取ASAR文本；没有安装、启动App／内嵌server、执行下载的JS、读取用户home／凭据／会话或请求模型／权限接口。只在仓库新增本报告，没有修改生产代码或测试。当前安装仍是1.1.3；DMG检查完成已卸载。

## 官方来源与固定字节

官方[FAQ下载页](https://www.kimi.com/code/docs/en/kimi-code-desktop/help.html)的Apple Silicon按钮指向`https://code.kimi.com/kimi-code/desktop/download/KimiCode-mac-arm64.dmg`，本次302到同路径`https://cdn.kimi.com/`官方CDN。没有猜测版本化URL。

| 项目 | 本次证据 |
| --- | --- |
| DMG大小 | 142,210,583字节 |
| DMG SHA256 | `92a4c243e6c266fd705bc46878308a2ea6e2ea0a5e9bd6dcb337884926c84f73` |
| HTTP Last-Modified | 2026-10-30 10:44:16 GMT |
| Info.plist及ASAR package.json版本 | 两者均1.2.1 |
| bundle ID／架构 | com.kimi.code.desktop／Apple Silicon构建 |
| Developer ID | Beijing Moonshot Technology Co., Ltd，Team `2J9472RW75` |
| 签名验证 | `codesign --verify --deep --strict`加预期Team requirement，退出0 |
| 签名CDHash | `e9333583dfe9741b5942c7156cdfc496f064f261` |
| 公证观察 | 签名详情显示stapled ticket；没有额外在线公证验收 |
| 主分析ASAR条目 | `out/screenshot-BescBNhs.cjs`，5,688,147字节 |
| 该条目SHA256 | `eb31deb309d49a669e8ebdeba4a04ba56b270975462ba2e0af81fd200d8566e5` |

滚动URL将来可更新，复核必须使用上面的完整哈希，不仅看文件名。静态证据根为`/tmp/ahakey-kimi-desktop121-static-20261102/`，保存DMG、artifact-meta、ASAR头、提取文件哈希、static-contract-evidence及隔离parser探针结果；均只来自公开安装包／本次构造数据，不含用户信息。ASAR条目名虽含screenshot，实际捆绑Server及core；未依据文件名判断功能。

## 当前客户端实际使用路径逐项对照

| 当前调用／证明 | 新包静态实现 | 兼容与必须保留的约束 |
| --- | --- | --- |
| 官方App PID／签名／监听归属 | bundle ID和Team相同；启动127.0.0.1、port0 | 原有签名、同用户进程启动身份、监听FD归属与操作前后重验不能去掉；本轮没有运行观察真实PID |
| home及实例目录 | 显式home→KIMI_CODE_HOME→`.kimi-code`；同home的server/instances | 登记JSON仍含server_id/pid/host/port/started_at/heartbeat_at及host_version；15秒心跳保持，实际runtime监听仍需另验 |
| 私密文件Bearer | Desktop同时接受内存token和同home的server.token；文件权限／mtime／inode变更检查分支存在 | 可以继续既有官方共享home合同；本轮没读真实token。不得改用提取进程内存／Renderer注入／私有IPC |
| 前后`GET /api/v1/meta` | body server_version2.4.0、backend v2、ISO毫秒UTC started_at、独立ULID server_id、bypass=false | 需要新version profile；HTTP app ID依然独立于登记ULID，不能强行要求两个ID相等 |
| meta capabilities | websocket/file_upload/fs_query/mcp/tasks全部true，仅5项 | 当前额外要求terminal会误拒。当前HTTP桥不调用终端API；但5旗标本身不承诺权限端点存在，仍须依赖本包实际路由核验 |
| `GET /api/v2/sessions?view=flat&page_size=32` | v2挂载、flat查询、最多100项的常规列表范围存在；items/meta/activity形状保持 | 32项请求在范围内；继续不请求git、历史或正文，丢弃多余字段，只保留授权选择所需信息 |
| 目录分页 | has_more为bool；next_page_token为string或null，token绑定查询条件 | 当前more/token一致性、长度上限、去重及禁止查询条件漂移仍保留 |
| loaded会话过滤 | activity.model来自即时live manager.get→main Agent；没有从持久化model填回 | 取样时非空model仍是loaded main证据；null也可能缺main／未绑定model。新授权只列非归档且model非空项，不把目录所有存储会话都列为已接管 |
| `GET /api/v1/sessions/{id}/status` | legacy status resolveMainAgent会先resume，然后返回permission字段 | 权限仍是manual/yolo/auto；读取可能加载同原应用的已授权会话，不能称纯内存读取；必须有精确授权，不自动takeover其他owner |
| `POST /api/v1/sessions/{id}/profile` | agent_config.permission_mode存在；profile与applyConfig均会resume，再broadcast权限 | 当前只写permission_mode的请求保持；需要独立status读回，不把profile返回id当权限已生效证明 |
| 写入ACK／错误 | envelope code/msg/data/request_id；profile返回wire session id | 当前business code必须严格数值0、精确id、字段类型和响应上限检查继续适用；HTTP200不等于业务成功 |
| WebSocket subscribe | 新包会先resume，然后ensureState；不同于旧1.1.3的直接loaded状态路径 | 当前桥不使用WS，无需为本次适配增加订阅；以后不能把subscribe用作无副作用live-only检测 |
| live-only／CAS | profile schema未增加if_loaded、expected owner/generation、revision或If-Match条件 | 目录取样到POST仍有竞态；“当前值等于最后托管值才恢复”仍不能识别所有并发或用户选回同值的修改，不宣称严格CAS保证 |

相关当前实现：[metadata parser](../../ahakeyconfig-mac/Sources/Shared/KimiDesktopServerMetadata.swift)、[实例发现](../../ahakeyconfig-mac/Sources/Shared/KimiDesktopInstanceDiscovery.swift)、[HTTP桥及前后元数据围栏](../../ahakeyconfig-mac/Sources/Shared/KimiDesktopPermissionBridge.swift)。本轮未扩大普通Kimi/Work或原TUI范围；也未将新包静态合同当这两端的外部接口。

## 可复核的ASAR证据位置

以下为上述固定SHA文件按UTF-8解码后的从0计**字符偏移**，不是字节偏移或上游源码行号：

| 偏移 | 证据 |
| ---: | --- |
| 1764273 | home解析函数cg |
| 3288197／3288405 | JV resume与YV live manager.get明确分开 |
| 3317320／3318096 | status先resolveMainAgent，再读permission.mode |
| 4388817 | profile请求schema：title/metadata/agent_config/permission_rules，无CAS字段 |
| 4820444／4822119 | 实例登记字段及15秒心跳 |
| 4853410 | WebSocket subscribe先resume |
| 4976497 | meta构造：5项capabilities，无terminal |
| 5099764 | applyConfig先resume、permission_mode broadcast |
| 5106753／5111221 | profile及status路由 |
| 5118632 | 目录facts经live map读取当前main model |
| 5159804／5165780／5170938 | v2查询schema、列表路由及/api/v2挂载 |
| 5278939 | Desktop auth兼容共享home私密token |
| 5640149／5640668 | Desktop loopback启动及serverVersion2.4.0字面值 |

## 静态构造fixture：不是实际实例回包

下面用程序中的确定性形状和虚构ID／模型名构造，**没有启动目标App或访问真实HTTP**。时间和ID均为测试值；不能作为进程归属、已加载用户会话或授权的证据。

### meta

```json
{
  "code": 0,
  "data": {
    "server_version": "2.4.0",
    "capabilities": {
      "websocket": true,
      "file_upload": true,
      "fs_query": true,
      "mcp": true,
      "tasks": true
    },
    "server_id": "01AAAAAAAAAAAAAAAAAAAAAAAA",
    "started_at": "2026-11-02T00:00:00.250Z",
    "dangerous_bypass_auth": false,
    "backend": "v2",
    "open_in_apps": [],
    "experimental_flags": {},
    "features": []
  }
}
```

对应登记fixture可使用另一个合法ULID（例如`01BBBBBBBBBBBBBBBBBBBBBBBB`）、host_version2.4.0、数值started_at1793577600000及稍晚heartbeat。HTTP started_at比登记晚250ms；登记ID与HTTP ID不相等是合法形状，不应当作换实例。

### 当前桥使用的flat目录输入形状

```json
{
  "code": 0,
  "data": {
    "items": [
      {
        "id": "session_static_121",
        "workspace": {
          "id": "wd_static_000000000000",
          "cwd": null
        },
        "meta": {
          "title": "Static fixture",
          "last_prompt": null,
          "created_at": 1793577600000,
          "updated_at": 1793577600000,
          "archived": false,
          "archived_at": null
        },
        "activity": {
          "status": "idle",
          "model": "fixture-model"
        }
      }
    ],
    "total": 1,
    "has_more": false,
    "next_page_token": null
  }
}
```

同一fixture应加入cold项`activity.model=null`、archived项以及重复id／more=true但无token等负例。只有前两个用于过滤；后两者应报无效响应，不能悄悄扩大授权目录。

### status及最小profile请求／ACK

```json
{
  "code": 0,
  "data": {
    "busy": false,
    "model": "fixture-model",
    "thinking_level": "",
    "permission": "manual",
    "plan_mode": false,
    "swarm_mode": false,
    "context_tokens": 0
  }
}
```

```http
POST /api/v1/sessions/session_static_121/profile
Content-Type: application/json

{"agent_config":{"permission_mode":"auto"}}
```

桥接层最低成功ACK输入可构造`{"code":0,"data":{"id":"session_static_121"}}`。这是**当前桥实际消费的最小输入**，不是完整wire-session DTO，也不声称真实Server只返回id；必须随后用独立status fixture确认permission为auto。错误id、code=false、permission未知值、HTTP丢ACK及读回不一致分别是必要反例。

## 已运行的生产parser隔离反例

只编译本仓库当前`KimiDesktopServerMetadata.swift`及/tmp中的“Registration两字段类型夹具＋main驱动”，没有执行下载JS或任何真实网络／进程调用。夹具仅供serverVersion和startedMilliseconds两个parser输入；不覆盖真实实例登记、签名、监听或鉴权。

| 输入 | 当前生产parser结果 |
| --- | --- |
| 旧2.3.2＋6旗标 | 接受 |
| 新包派生2.4.0＋5旗标 | 拒绝 |
| 合成2.4.0＋旧6旗标 | 拒绝，证明版本门控独立阻挡 |
| 合成2.3.2＋新5旗标 | 拒绝，证明terminal要求也独立阻挡 |

结果在临时证据根`metadata-probe-result.json`。这提供新增兼容合同的可复现反例，不等于现有功能有安全错误或新版本联调通过。

## 建议的精确适配边界与隔离回归

1. **合同选型而非全局放宽**：将已核验Desktop版本／server版本配对解析成显式profile，再让HTTP前后meta校验使用它。建议固定1.1.3/2.3.2需6旗标、1.2.1/2.4.0需5旗标；两个profile都要求其余原有严格校验。`installedVersion`目前保留在Instance中，但metadata parser只收到Registration；需要明确把profile／已核验安装版本传到围栏处，不仅给serverVersion加第二个字符串。未知版本、混合配对、未核验产品继续拒绝。
2. **新增正反fixture**：新包静态派生meta与flat/status/profile输入可作新增版本的正例；旧profile保留。版本错配、缺必要旗标、数值假bool、bypass=true、非canonical时间、不同HTTP实例／进程重启等仍应在目标操作前拒绝。新2.4.0的5旗标被接受不能反过来令旧2.3.2缺terminal也被接受。
3. **测试调用范围而非只测解析器**：将上述fixture接到真实verifiedExchange与PermissionBridge隔离exchange seam，证明每个目录／status／profile操作前后都核对同一meta，目录只列loaded非归档项，写体只有permission_mode，未授权／换实例时零写入；POST丢ACK后只独立读回、不重试POST。现有lease／用户修改恢复测试须在两个profile下保持。
4. **不引入新副作用**：不增加WS订阅、自动server启动、会话takeover或debug端点。status和profile原本可resume的边界保留，只允许已授权的原应用目标；未获管理权时保持原审批。
5. **保留真实验收缺口**：静态fixture不能证明本机1.2.1的实例登记、鉴权／meta围栏、live筛选及真正权限读写；新版本真实联调及更严格用户修改CAS仍需后续证据。当前1.1.3安装与既有授权保持不变，不能以本报告宣布新版本或三端完整完成。

官方[Server API参考](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/server-api.html)与[Desktop发布页](https://www.kimi.com/code/docs/en/kimi-code-desktop/changelog.html)只作为产品与公开协议背景；本报告的2.4.0／5旗标／resume差异来自上述已验签安装包，不能用公开CLI2.4.1源代码代替实际bundle事实。
