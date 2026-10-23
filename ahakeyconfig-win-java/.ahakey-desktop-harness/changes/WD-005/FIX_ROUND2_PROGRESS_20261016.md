# WD-005 第二轮退修接续记录

日期：2026-10-16。角色 DIB；IMPLEMENT/FIX，build_round=2。
状态：源码修复及回归用例已写入，尚未编译或执行；未 submit，不宣称修复通过。

## 身份与权限

- 原 DLA 审阅输入：3a967e3f34a85f7d346bdf3e35110bbe191a4d980effdb13218de4307659bb93。
- HEAD 只读复核仍为 41c034171e60b2d4962b0adbe8f3cffbf80a0436。
- 开工及源码编辑后分别运行 DIB preflight，均 exit 0。它仅证明阶段/范围合法，不是业务通过。
- 原 EXECUTION_REPORT 记载上一轮编译与离线测试窄授权；本轮退修明确不新增运行授权。
  已在聊天询问该窄授权是否继续适用，本记录时尚未收到本轮答复，未执行 Maven/Java。
- 未进行 Git 写入、应用启动、设备/Hook 操作、烧录、打包、安装或发布。
- 历史 dirty、BLE 配置、原批准/起点及冻结报告保留；未修改固件、Harness 核心/规则/seal。

## 已写入的修复

### F1

- BleManager.readDisplayConfig 让自动回读与既有 commandTransactionLock 共用串行入口。
  0x9F、0x97/87、0x92 及连接偏好 0x98 原有流程不再与后台读租约相互直接拒绝。
- 对未使用该 monitor 的 legacyWaiters 使用原 Condition 有限等待；断连/代次改变及超时仍失败。
- 仅按需读取进入此入口；上传仍持有整笔 DisplayLease，sendCommand 的竞争写拒绝没有放开。
- DisplayConfigService 监听 modeSwitching：切换中取消旧读取 ticket，确认结束后读取当前 Mode。
  切换确认中不开放 CP2 写入按钮。StudioController 先启动身份请求，再安排显示回读。
- 读租约先在 monitor 内释放，CP1 idle 回调在 monitor 外执行，避免与 snapshotSendLock 倒序锁死。
- 无无限重试；具体等候时延、取消行为仍须执行新增用例核验。

### F2

- Inspector 的 SINGLE/MULTI 控件在显示配置 busy/loading 或模式请求未完成时禁用。
- Controller 检查 busy/loading；service 独立检查实际租约/未知写结果/已有模式请求。
  冲突不改本地偏好、不发送虚假成功；程序调用同样受 service 约束。
- 支持的在线设备先发送 0x98、校验成功 ACK，再在 FX 回调核对连接代次后改本地偏好并持久化。
  错误回到 controller 提示；未连接/不支持时仍保留原本地偏好行为。
- 0x98/0x99 的设备 FAIL 不再当作成功；新增带 expected-generation 的内部调用，线协议未改。
- UI 点击后暂时恢复原选中项，成功时沿原 displayMode listener 重建，不预先假成功。

### F3

- 每个服务 work 绑定操作号，设备回调还检查捕获连接代次、当前连接状态。
- 亮度成功、逐项灯效成功、全部成功文案及预览建立都走 deviceFx；过期错误不覆盖新连接提示。
- 本地编辑另有 revision，同值再次编辑也不会被旧保存 ACK 清 dirty。
- 每项真实成功 ACK 带连接/操作/Mode/状态/计数写日志，旧连接确认历史不伪装为未发送。
- 预览截止时间从 ACK 后时刻计算，不因 FX 延迟重新得到完整十秒；超期回调不重新建立预览。
- 最终 busy 清理也绑定操作号；本地导入/清除不因设备连接变动被取消。

### R1 核查与有限处理

- 阅读 WD-004 CONTRACT 的事件驱动、无保活、绑定保留及原 onDeviceReady 实现。
- 实际链路：SINGLE 事件在 CP2 lease 期间留在 deferredRuntimeState；旧实现 reset 未清该字段，
  下一连接 lease close 可 flush 它。MULTI 的 pending 标记也可由下一连接 idle 回调触发。
  这是代码可达风险；本轮尚未运行确定性用例，不声称真机复现。
- resetDisplaySession 清理旧 SINGLE 待发值；MULTI pending 绑定 generation，idle 回调将捕获代次
  继续传到实际 0x99 发送入口，避免检查后换连接的窗口。
- 保留现有 onDeviceReady 同步展示偏好的 0x98 行为，绑定/主槽位/TTL/已应用槽位算法未重写；
  不新增连接保活，不因新连接任意读租约关闭就发送旧快照，新事件仍走正常事实发送。

## 变更文件

仅以下原 allowed_paths 内文件为本轮手工修改；其余累计实现不是本轮新增工作：

- src/main/java/com/example/ahakey/service/BleManager.java
- src/main/java/com/example/ahakey/service/DisplayConfigService.java
- src/main/java/com/example/ahakey/service/AiRuntimeDisplayService.java
- src/main/java/com/example/ahakey/model/DisplayConfigState.java
- src/main/java/com/example/ahakey/app/StudioController.java
- src/main/java/com/example/ahakey/view/InspectorPane.java
- src/test/java/com/example/ahakey/displayconfig/DisplayConfigRaceChecks.java（新增）

## 检查真相

- 已执行：DIB preflight 两次 exit 0；git diff --check -- src/main src/test exit 0。
  Git 输出已有 LF/CRLF 提示，不是编译结果；diff --check 不覆盖未跟踪文件的语义。
- NOT_EXECUTED：本轮编译、原两个断言入口及新增 DisplayConfigRaceChecks；没有本轮断言通过数量。
- 新用例使用内存 USB 替身、临时资源目录/临时 user.home、真实 service 与协议入口；
  不创建 App/StudioController，不运行 Hook/语音/真实连接，不冒充完整 Controller/UI 验收。
- 用例安排：身份先/回读先、0x97/87 后续链、延迟 0x88 时切 Mode、读/写租约中双向 CP1 拒绝、
  ACK 前后偏好与持久化、FAIL、SINGLE/MULTI 最新一次补发、旧连接隔离、重连偏好保留、
  六种灯光成功回调与断连/新连接交错、新设备回读保护 dirty、同值新草稿和 ACK 起算期限。
- 旧 175+36 项仅属 round 1；不用于新轮资格化，未修改其日志、检查记录或旧 review FAIL。
- 真机、完整窗口/DPI、磁盘故障、全灯效时相、独立 actual/fresh review、Preview、候选及包均未完成。

## 冻结字节与提交接续

复核未改：
- EXECUTION_REPORT.md SHA256：749264589c44656848f062fcf3b4ecf35784bef80f7356dc1f204834d69a19a2。
- IMPLEMENTATION_CHECKS.json SHA256：3b98234005fdf874db313887e70ce3625e15d020309a75b540afb42efde72fe3。
- REVIEW.json SHA256：c88d49fd4a69b1ca793742d3b69966b41ad7bc3f7c24cda1a7aac46dd536eefd。

desktop.py 的普通 submit（约673-680行）目前固定读取 EXECUTION_REPORT.md，CLI 没有 --report。
本轮明确禁止重写冻结报告。因此后续先补独立 round2 执行报告/日志，核清通过新轮
record-check evidence 绑定补充报告是否满足正式提交要求；必要时交 DLA/Harness 维护确认。
不得擅改 helper、改旧报告 hash 或将旧报告冒称本轮执行记录。本记录未尝试绕过 submit。

接续：Owner 明确运行授权后，当前 DIB 核对源码/preflight，实际编译并执行三个测试入口，
修复真实失败、追加新日志/报告/适用检查，再在合法记录绑定下 submit 交原 DLA 实际审阅。
在此之前 STATE 仍为 IMPLEMENT/FIX，不自批 Preview/fresh review/真机通过。
下一次跨对话交接必须在聊天正文完整给出 Prompt。
