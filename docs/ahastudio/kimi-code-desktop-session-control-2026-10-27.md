# Kimi Code Desktop 原会话权限接管 — 2026-10-27

## 当前产品决定

Owner已确认：允许官方Code Desktop加载已经授权但当前未加载的原会话；不新建会话、不另起Server或托管TUI。三端总目标仍包含普通Kimi/Work、Code Desktop、官方CLI TUI，自动档对应官方`auto`，手动档为`manual`；管理全部明确授权会话，停止接管恢复原设置并保留后续识别到的用户修改。新增授权仅从当次核对为已加载的官方Code Desktop会话中选择，首次授权前再次核对；授权与配置文件默认权限同步分开。

## 已接线的Code Desktop路径

现有设备信息 → “Kimi Code Desktop 会话权限” → 用户主动检测 → 只列出官方实例已加载且未归档的会话 → 对所选会话明确确认 → 私密持久化授权范围 → 通知现有Agent → 查询新鲜实体档位与出厂自动绑定 → 读取原权限 → 写前持久化恢复记录 → 官方profile接口设置 → 独立status读回。

授权按配置home和会话ID绑定，保留初始server亲和；每次HTTP前核对原进程、签名、loopback监听和元数据。不自动启动服务、创建/复制对话、接管其他进程会话锁、提交模型提示、回复审批或开启debug端点。找不到原server时仅接受同home唯一已验证官方实例；多实例归属不明时停止，不猜测。

连接变化／手动／自动变化和授权操作触发串行协调，重复相同信号不轮询对话；仅失败或待恢复时每30秒重试。暂停、断连和正常退出走恢复；进程重开保留恢复记录，旧完成不能清新操作。全局停止反馈同时等待Codex与Kimi日志清空，分客户端等待不被另一端的正常接管拖住。

正常SIGTERM/SIGINT先将原生权限authority置为unmanaged、阻止迟到的Hook批准/默认值回写，再并行恢复Codex和Kimi；Kimi会取消并等待旧协调操作，给新恢复最多5秒预算。超时保留恢复记录，下次后台启动继续，不将取消称作已恢复。单次HTTP交换也有5秒总预算，拒绝慢响应无限延长关闭。

用户权限改变为非托管值时停止覆盖；暂停标记写入私密记录，重开及同档重连保持，用户再次拨到另一档或重新明确授权后可恢复控制。丢回复保留所有可能托管值，HTTP成功不算实际生效。恢复保留原`manual`/`yolo`/`auto`，不统一改成手动。

## 真实合同纠正与上游更新

固定核验官方Desktop1.1.3安装包（原静态证据的bundle SHA256为4987ed8984e7d52d2bc2526a5d4ddc3a05a263da9237d764e5ae562e9111c9a7）：内嵌server2.3.2的`/api/v1/meta.started_at`是`Date().toISOString()`，实例登记则用更早的`Date.now()`。旧离线夹具误用数字且要求完全相等，会拒绝合法实例。本次用实际字符串形状先跑出6个失败断言，再修复为严格UTC毫秒日期、同server/进程绑定和最多60秒启动间隔；不是接受任意新时间/新版本。另经真实registerApiV1Routes与静态bundle复核：HTTP app的`server_id`另行生成ULID，不能要求等于登记ULID。现分别验证登记/原进程/监听归属，以及操作前后HTTP app的独立ULID与启动事实稳定；错误的“两个ID相等”夹具已先复现失败，再被真实形状替换。Desktop六个能力旗标与公开通用Server的五个旗标不同，仍按已核验Desktop合同检查，不放宽为未知版本。

本日另锁定上游[78b72fe](https://github.com/MoonshotAI/kimi-code/commit/78b72fe456ac730a1970ded9bb0d28f8b584ab95)，较1011d8b新增21提交，包含2.3.3和interaction通知。目标profile/status设置接口没有改变；通知新增不等同于原版TUI外部控制监听。当前版本门控仍是已静态核验的Desktop server2.3.2，未扩大到未知2.3.3二进制。

## 验证与尚未关闭的边界

首轮55项定点/917项全量通过；独立Spec审查找到正常信号退出授权缺口，主审补查找到独立HTTP身份合同错误，均已修复。修复后71项定点回归通过，最终926项完整Swift回归通过，详见验证回执。覆盖未授权零请求、错误目标、仅写permission字段、同值不写、外部冲突、错误会话ACK、丢ACK单次写/独立读回、真假布尔、目录过滤、授权范围、持久恢复、多个原值、用户修改跨重启保留、旧回调、撤销中途变化，以及App离开后的过期读取。测试只使用临时记录和隔离请求夹具，未读取真实token、未请求模型、未修改实际Kimi权限。

Code Desktop真实服务联调、底层网络/重定向/进程重启矩阵、安装后授权UI、实体档位及正常/异常退出恢复仍待验收。现有官方setter没有原子CAS或修改来源修订号；先读再写之间的用户修改、用户选回相同值、已在执行的工具及原本独立子Agent权限不能仅凭本次夹具宣称全部保证，继续保留完整矩阵和必要上游能力缺口。

普通Kimi/Work与官方CLI TUI现有外部原会话接口仍未闭合，保留main的默认权限和任务状态同步，不以Code Desktop接线冒充三端完成。当前已安装build512/08a2865，双架构签名与安装字节核验通过，CI40474814309成功。设备信息入口默认收起、显式检测在无Code Desktop实例时正确返回未发现会话，后台报告授权/接管/待恢复均0；普通Kimi/TUI未被当作已接管。原2项草稿和Voice保留，只读待机60分钟正常，Agent已重新连接。真实Code Desktop权限联调仍未执行；未公证、未发布。

## 固件链接输入（已解决文件依赖）

2026-10-27已恢复源292a49f组合HEX，完整SHA256 `6EC0413CFC983788CDC99F628F0F8E2A64C6AF147D2A5E1727A03F036BF1123C` 与原门禁一致。文件已随connect&talk归档，不再等待用户提供下载链接。见[精确产物恢复](firmware-artifact-recovery-2026-10-27.md)。此进展不替代Kimi服务权限验证；本轮未刷机或执行Restore。


### 晚间上游与真实环境补查

公开上游更新至[68a2838](https://github.com/MoonshotAI/kimi-code/commit/68a283894163204e93b072cef20db164015a5cad)，较78b72fe仅新增两个提交：[完整比较](https://github.com/MoonshotAI/kimi-code/compare/78b72fe456ac730a1970ded9bb0d28f8b584ab95...68a283894163204e93b072cef20db164015a5cad)。实际Server API文档/API-surface差异为工作区文件树/外部软链接，其他为compaction缓存；未新增原版TUI权限控制接口，不扩大Desktop已核验的2.3.2版本门控。没有读真实Kimi凭据、请求模型或改实际权限。

本机仍缺Code Desktop安装环境。已向Owner提出安装已核验官方1.1.3、仅启动和只读检测的具体确认；尚未收到答复，不安装、不创建会话或自动授权。当前build518实际安装完成，旧固件恢复负例及13项偏好保持通过，不代替Kimi真实服务联调。


## 官方 Code Desktop 已安装并完成只读联调（2026-10-28）

Owner明确授权后，已安装官方Kimi Code Desktop 1.1.3（com.kimi.code.desktop，签名Team 2J9472RW75），源DMG和安装后深层签名核对通过，普通Kimi未替换。启动后通过已安装Studio build518的真实“检测可管理会话”入口，成功列出1个官方实例已加载会话：生产实例身份检查、兼容2.3.2合同的前后元数据核验、带鉴权的只读目录请求实际通过。未记录会话标题、ID、凭据或正文。官方应用启动可能自行初始化／加载本地状态，不能将启动说成完全无副作用。

未点击“允许拨杆管理”，未由Agent创建会话、提交模型请求或测试权限写入；后台只读状态为授权0、接管0、待恢复0。当前Mac蓝牙原本关闭，保持原样；Studio回到非编辑主界面，原2项草稿和AhaType开启状态保留。此次不需要实体键盘操作。

本节替代旧“缺Code Desktop安装环境／等待安装授权”的阻塞；只关闭安装与真实只读发现子项。逐会话授权、实际manual/auto切换、退出恢复和网络／进程故障矩阵仍未验收，普通Kimi/Work及原版CLI TUI接口限制也未消失。源码无改动，无需重复构建或重跑941项测试。回执：[kimi-code-desktop-readonly-2026-10-28.json](../validation/connect-talk-hil-2026-10-22/kimi-code-desktop-readonly-2026-10-28.json)。

### 随后收到具体会话授权，status接口实测通过

Owner已在Studio选择测试会话并确认授权。后台实际报告授权1、接管0、待恢复0；没有实时键盘档位，approvalAutoVerified为false。使用当前生产Shared模块链接的只读探针，对精确已授权且仍由原官方实例加载的会话读取status：两轮各三次均返回auto，授权／租约记录前后一致。探针仅允许同一授权ID的mode=nil读取，拒绝所有写请求；未模拟拨杆authority、未发送模型、未POST权限。故这证明真实status字段和原会话权限读取可用，不能证明拨杆写入或恢复成功。

WBS CSV的Consumer、Kimi、Restore和固件候选行已更新为当前状态，移除已过期的“Mac待接入／尚未安装／等待用户选择”等结论。权限写入和恢复留待真实档位测试，四组开发外部依赖、八组完整验收仍开放。回执：[kimi-authorized-readonly-2026-10-28.json](../validation/connect-talk-hil-2026-10-22/kimi-authorized-readonly-2026-10-28.json)。
