# WD-005 revision 3 / build_round 4 执行报告

日期：2026-10-18。角色：Windows DIB。结论：Windows 范围修复及离线证据已保存，正式提交被兄弟目录归属门禁阻塞；不是 VERIFY、Preview、真机或 UAT PASS。

## 身份与边界

- 正式输入：PREVIEW_FIX_CONTRACT_R3_20261018.md、CROSS_COMPONENT_WORK_20261018.md、CONSOLIDATED_FIX_ROUTE_RESULT_20261018.md、revision 3 effective approval。
- 开工 DIB preflight 实际通过；收尾复核失败，见下文。正式 STATE 仍 IMPLEMENT/IMPLEMENT、next_actor=DIB，未手改路由。
- 本轮开始源码指纹：aea60d8c7eb936cb937cc59522fed7224c845ecf7947cedb17e8f029ad1656c8。
- 当前只读观察指纹：e298ea1dd15131f508a602deed06181e0a53c6ff8b5c2366674dfc0cfb44d49d。该值不是门禁合格证明。
- HEAD 与原起点：41c034171e60b2d4962b0adbe8f3cffbf80a0436。
- source scope_observation 显示 Windows out_of_scope_paths=[]；独立的 sibling guard 仍失败，不用前者绕过后者。
- 旧 EXECUTION_REPORT.md SHA256 仍为 749264589c44656848f062fcf3b4ecf35784bef80f7356dc1f204834d69a19a2。原批准、冻结回执、旧 Preview、历史 dirty、本地 BLE 配置均未主动改写。
- 没有 package、真实应用启动、网络监听、Hook 安装、设备命令、烧录、Git 写入或发布。传输测试只用内存替身。编码探针及 JavaFX 局部组件不是产品入口。
- 产物仅 target/classes、target/test-classes 及本轮证据；未生成本轮交测包。

## 已实施范围

| 问题 | Windows 实施 | 已执行证据 / 限制 |
| --- | --- | --- |
| UI-01 | 局部 OLED 卡片 label 深色、禁用态可读；没有全局改色或取消禁用 | 实际 style.css + 隔离 FX 42项；正文对比度正常/禁用达到4.5:1以上，禁用样本6.70；截图已目视检查。完整 Inspector 未启动 |
| LOG-01 | 新进程级 UTF-8 配方说明及独立中文探针，不改生产 logback/App/Main | stdout、stderr、JUL及UTF-8文件含精确中文样本；不代表真实新 Preview 启动已验证 |
| UI-02 | OLED MULTI附近增加“多任务展示开关位于灯光页。” | Inspector 实际调用链及中英资源；OLED类别不切运行模式 |
| UI-03 | 灯光顺序：全局展示模式、亮度、SINGLE、MULTI；非当前区浅色禁用，管理弹窗叠加锁 | 真实绑定helper测试模式往返、忙碌/待ACK、草稿保留；旧72项含模式成功/失败。完整面板集成和Owner视觉确认待执行 |
| FB-01 | Hook 返回 delivery=SENT/PENDING/IGNORED/FAILED；displayUpdated仅在真实发送路径成功时true | SINGLE租约冲突、未知隔离、断连；直接调用真实Hook处理方法，不监听端口。SENT仍非“屏幕已显示” |
| RT-01 | 只读有界来源查询，明确后台预测/guardian元信息才忽略；UNKNOWN不当后台；SINGLE交错迟到终态不覆盖另一个当前会话 | 临时SQLite、真实新会话/索引延迟、交错A/B、匿名legacy Claude/Kimi/Cursor、最新事实补发测试。无法取到来源元信息的真实预测会话仍是未收口项 |
| RT-02 | 稳定ID精确匹配；冲突不被路径救回；无ID只允许唯一精确transcript；取消cwd/project与无身份终态兜底；Cursor仅conversation/composer身份 | 同目录不同ID、冲突ID+相同transcript、歧义transcript、Cursor错误别名；磁盘仅保留绑定，运行事实留内存，按原5分钟与连接代次使用 |
| UP-01/02 | Begin/Chunk/Commit分段日志和错误、连接代次/entry/offset、已确认字节、耗时及恢复提示；无自动重试 | USB与BLE替身覆盖Begin拒绝、真实15秒Chunk超时、Commit中断未知、迟到ACK；不宣称首次失败或传输超时根因已修复 |
| BLE-PERF-01 | 上传进度含已确认百分比/耗时/累计平均B/s，日志含queue/write/ACK微秒；上传忙时可选状态查询1秒合并 | 显式审批状态刷新不合并，连接/身份感知未暂停；不改48字节/CRC/ACK，不承诺吞吐提升 |
| RT-03 | 未伪造foreground/valid或抹去其他槽位 | 外部固件依赖，屏幕回退行为待正式固件配对；未测试也未关闭 |

修改主体为 InspectorPane/StudioController、DisplayConfigService/OledUploadService/BleManager、AiRuntimeDisplayService/HookDispatchServer/CodexSessionDiscoveryService/AiRuntimeStore、局部CSS与messages。三份新增测试文件。检查表相对旧Preview的字节清单还含 AiRuntimeSlotBinding；git diff --no-index 返回0，属于快照换行字节差异，不宣称模型有新逻辑实现。

## 运行态语义及兼容边界

- 磁盘 lastIdeState 读取时清空，仅当前进程可信事件可用于新快照；保存绑定也不再序列化运行事实。用户绑定、标题、目录与主槽选择保留，不删除用户文件。
- 运行事实内存记录带单调时钟与连接代次，五分钟过期或换代后不得重放；没有保活定时器。解除租约仍只补最新事实。未知隔离下的空闲通知不得延长原事实TTL。
- SINGLE以当前最近有身份的非终态归属防止别的会话迟到终态污染；未定义多任务聚合新策略。来源未知仍允许兼容发送，不能声称所有“无可见任务却运行”已消失。
- MULTI新快照只使用未过期、同连接事实；0x98仍set-only，0x99仍完整快照，0x9A仍ACK-only。保护锁、未知ACK、连接代次、Quiet/Sleep与固件显示决策没有放开。
- 来源查询仅读取 state_5.sqlite 中稳定ID对应的 source/thread_source，readonly URI、参数化查询和超时；不读聊天正文。仅明确 composer_predictions / guardian_review / subagent.other=guardian 或 composer_predictions 为后台。
- 已调查症状中的会话 01a14df4-5a2a-7b83-8856-8faa311e3e1c 在当时当前state表未命中，所以那一具体症状不能靠本次SQLite分类直接宣称已解决。没有扩大到扫描历史聊天；交DLA判断来源接入是否需后续协调。
- 新诊断不存原始stdin、cwd、transcript或聊天正文；未知事件和JSON解析失败日志也不再回显原始输入。匹配日志只含稳定ID/分类/状态/结果/连接代次。
- 上传异常后本地资源保留，未知结果时提示AI发送暂停、断开重连同步。Begin FAIL不承诺旧资源有效，重连不连续传输，Commit未知不标已应用。
- B/s为从开始计时的累计平均已确认有效字节速度，不是瞬时BLE无线吞吐或完成时间预测。

## 真实执行

JDK：D:\\jdk-17.0.19.10-hotspot；Maven：C:\\Program Files\\apache-maven-3.9.12\\bin\\mvn.cmd。
离线编译命令：mvn.cmd -o -Dmaven.repo.local=<主仓绝对路径>\\.m2repo -DskipTests test-compile。
仅执行test-compile，没有clean/package。各main测试使用 target/test-classes;target/classes;target/lib/*，不调用App/Main/StudioController构造或Hook.start。

| 执行项 | 实际结果 | 日志前缀均为 .ahakey-desktop-harness/evidence/20261018-wd005-r4- |
| --- | --- | --- |
| 初始定向红测试 | 6处断言失败，真实复现假成功/错误归属/重启旧态 | runtime-red.log |
| 最终离线编译 | exit 0，65生产源/6测试源 | compile-final.log |
| DisplayConfigChecks | exit 0，175断言 | final-DisplayConfigChecks.log |
| DisplayConfigFxChecks | exit 0，36断言 | final-DisplayConfigFxChecks.log |
| DisplayConfigRaceChecks | exit 0，72断言 | final-DisplayConfigRaceChecks.log |
| DisplayConfigRevision3Checks | exit 0，72断言 | final-DisplayConfigRevision3Checks.log |
| DisplayConfigRevision3UiChecks | exit 0，42断言 | ui-final.log / ui-final.png |
| 中文编码探针及严格UTF-8读取比较 | exit 0，stdout/stderr/file均含完整样本；stderr含JUL | encoding-stdout.log / encoding-stderr.log / encoding-file.log |
| git diff --check -- src | exit 0，仅换行警告 | diff-check.log |
| 收尾preflight | SIBLING_WORKSPACE_CHANGED，未通过 | preflight-blocked.log |

总计397项断言是本轮最终代码真实执行，不是旧283项证据重绑，不表示整条A01-A11或WS001-004全量验收通过。新增72项含USB/BLE各一次真实15秒分块超时，Commit未知用真实等待代码的线程中断路径，不冒称实际等待Commit超时15秒。

中途 compile-02 失败为新增UI引用错误，已修正；compile-03 因给Maven强行设UTF-8导致旧GBK inputFiles.lst不可读，未删除或改写该旧缓存来凑通过。后续Maven保留默认文件编码、只设stdout/stderr UTF-8，compile-04及final通过。应用/独立探针是新进程，使用UTF-8文件编码。所有失败日志保留，未覆盖。

A01-A11原验收不删：基础映射/编码/本地恢复/传输/灯效模拟/局部FX/竞态有上述已执行覆盖；完整应用所有点击路径、真实Hook来源、真机USB/BLE联调、长期运行、Quiet/Sleep、固件版本身份和Owner视觉反馈均未执行。Hook权限allow策略未修改；没有运行真实审批弹窗、Hook安装或真实会话工具操作。

## 收尾门禁阻塞

preflight实际报告以下兄弟文件变化：
- BLE_tcp_bridge/BRIDGE-01_IMPLEMENTATION_BOUNDARY_20261018.md
- BLE_tcp_bridge/Form1.cs
- BLE_tcp_bridge/Program.cs
- BLE_tcp_bridge/TcpServer.cs

当前DIB没有写这些文件，不能在此猜测/批准其归属。收到阻塞后没有再改生产/测试代码；仅收取已启动测试结果、只读核查、保存本轮报告/检查表。未reset、恢复、暂存或提交它们。

正式record-check也经过相同changes guard；没有绕过守卫手写verification或submission。本轮未执行record-check/submit，旧第三轮回执不代表本轮。STATE保留，不伪造已路由DLA。

下一动作：原DLA按正式维护流程核实并列桥接工作的责任、Owner授权及归属；需要Owner确认时只询问真实缺失授权。合法reconcile-foreign完成后由DIB重跑preflight、核对源码/证据哈希与适用性，再正式record-check/submit。若期间代码变化，重测受影响项，不能机械复用本报告。正式提交后DLA才做当前actual review；高影响fresh/candidate/新Preview及真机分别处理。

## 未解决与外部依赖

1. UP-01首次Begin拒绝根因未定位；没有静默重试或降低保护。
2. UP-02 Windows诊断/恢复路径有证据，但真实ACK超时的桥接/固件根因与恢复体验未验证。
3. RT-01有确切来源的后台事件已过滤；元信息缺失的真实后台事件仍保留UNKNOWN，需DLA协调来源证据。
4. RT-03固件主槽回退未改、未验。
5. BLE-PERF-01历史221.760秒是旧单次基线；本轮没有硬件A/B或速率承诺。
6. 完整灯光/OLED面板布局、模式往返所有草稿、中文真实新包启动、设备固件身份须后续Preview与配对验收。
7. 三项旧P2固件测试覆盖缺口不在本轮Windows修复范围，不改写为真实功能故障或自动豁免。
