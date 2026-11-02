# Kimi Code Desktop 1.2.1客户端合同接入 — 2026-11-02

代码固定为 `30693ec6fb3ac35b9a7a9f364345257720472d18`，复核基线 `da9190828a723d5ddb85379a9c5acbffe3fdb29a`。本次只接入已静态核验的Code Desktop版本合同，不改变普通Work／原TUI的范围，不把接口调查当三端接管完成。

## 问题与行为

官方1.2.1签名包实际内嵌server2.4.0，/meta只列5项能力；此前parser限定server2.3.2且要求terminal等6项，故会拒绝新的官方包。先新增真实形状的回归测试，实际执行得到1测试1失败（XCTUnwrap为nil），再修改生产代码。

现在按签名实例读到的App版本与Server版本严格配对：

| App版本 | Server版本 | meta能力集合 |
| --- | --- | --- |
| 1.1.3 | 2.3.2 | websocket、file_upload、fs_query、mcp、tasks、terminal |
| 1.2.1 | 2.4.0 | websocket、file_upload、fs_query、mcp、tasks |

能力键集合必须匹配该版本，值必须是真布尔true；未知App／server、交叉配对、混搭能力集合、登记版本不一致均拒绝。签名实例的installedVersion实际传入每次HTTP操作前后两次meta解析，保留原PID／启动时间／签名／监听归属、home凭据和逐请求授权围栏。

原目录筛选、只写permission_mode、独立status读回及恢复状态机复用。没有新增WS、启动server、替代TUI、向未授权会话写权限或模型请求。原应用加载已授权原会话的既有产品决定不变；上游profile/status的resume及缺少CAS边界依旧存在，未声称彻底解决并发用户修改。

## 验证

- 红例：新增2.4.0/5能力形状先在旧生产parser上运行，1测试1失败。
- 聚焦：18项metadata／verified HTTP exchange测试通过。
- 完整：964项Swift测试、0失败。
- 新增隔离闭环：原Bridge经新meta围栏列出loaded会话、过滤cold会话、未授权目标零请求、manual→auto→manual；只写permission_mode，并保留逐次独立读回。
- 写前版本配对错误不发会话操作；写后版本变化不发布成功、不重试可能已生效POST。
- 两轴独立复核：Standards 0项、Spec 0项。规范依据CONTRIBUTING、architecture和repo-layout；需求依据[签名包静态合同](kimi-code-desktop-1-2-1-static-contract-2026-11-02.md)及已确认逐会话权限方案。

本轮测试使用静态合同派生fixture和本地内存transport，没有启动1.2.1、读取用户凭据或真实权限API。1.2.1真实实例发现、鉴权、权限往返和恢复仍待HIL；旧1.1.3已安装环境不被研究下载包替换。候选打包和覆盖安装状态以单独候选回执为准。

## 当前键盘只读准备

本机当前16键、4个102字节路由及CRC、36灯效、19资源元数据已完整读回并私密备份；没有配置写入，35%亮度、60分钟待机、全部19默认资源保持。15项本地偏好语义一致（灯效事实／草稿字典编码顺序按键值归一后比较），日志关闭、后台恢复连接。此备份为后续集中验证准备，不等同再次授权刷写或清空。见[只读回执](../validation/connect-talk-hil-2026-10-22/k1-candidate-readonly-preflight-2026-11-02.json)。

普通Kimi/Work与原版TUI本次复查仍无已核实的外部原会话setter；[2026-11-02复查](kimi-live-session-interface-followup-2026-11-02.md)保留完整目标和依赖，不以Code Desktop单端兼容代替三端完成。


## 已安装候选及实际旧版只读核对

build529/30693ec6已双架构Developer ID签名覆盖安装，旧build528备份保留，原15项偏好语义一致、4项既有草稿保留，后台连接正常。签名测试DMG 20,211,178字节，SHA256为49c38498677f3b3131ae433b74e71869652c832047c898f7b4399e3133b2c4da；只读挂载的App/Agent字节与安装源一致，未公证，不作最终发布。CI41381020961三项成功。

使用当前生产Shared Bridge作独立只读探针，真实发现1个已签名1.1.3实例，带前后meta围栏的首个目录页请求成功、loaded会话计数1、hasMore=true。仅证明该页旧版兼容，不伪称全部分页或真实权限写入通过；探针权限写入0、模型请求0、未记录凭据或会话ID/正文。后台实际状态synchronized、授权1、管理租约0、待恢复0；不把已有auto基线当作本轮发生权限切换。1.2.1实际实例／鉴权／权限往返仍待集中HIL。见[build529回执](../validation/connect-talk-hil-2026-10-22/local-candidate-build529-2026-11-02.json)。
