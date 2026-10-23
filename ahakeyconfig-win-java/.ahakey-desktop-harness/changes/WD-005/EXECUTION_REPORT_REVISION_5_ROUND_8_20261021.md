# WD-005 revision5 / round8 执行报告

日期：2026-10-21；角色DIB；自动能力准入与灯光禁用反馈。保存时完成实现与隔离验证，等待正式record-check/submit及原DLA实际复审，不自批审阅。

## 输入、批准与范围

- 有效批准：`5ca53dc27d3bb53b05e7b48932f7a39b8db387fb730f112fa6e6c031e69ec6cf`，依据AUTO_CAPABILITY_UI_CONTRACT_R5_20261021及正式协调记录。
- 修前源码：`e10b4d65ad9b3f62221b7790b659c09429243a96a43a169db575dce6b4c18e8a`。
- 本轮最终测试输入与执行后源码相同：`3c1e7cf6a1180291d396d2ad288f44a9b57b5a7e74b27b6334d3299b801b7c3c`。
- HEAD仍为`f595262207796dbf325cb9951ed3dc02b4887362`，仅源码存档，不是本轮正式candidate。原起点`41c034171e60b2d4962b0adbe8f3cffbf80a0436`及隔离、旧批准、旧报告、旧Preview均保留。
- 本轮before/tested-input/after指纹逐文件核对：11个合同表内生产文件与4个displayconfig测试文件变化，无表外生产修改、桥接/固件修改、Git写入、依赖/pom变更。
- preflight开工与最终核对均PASS；diff --check退出0（Git换行提示保留）。这不是实际审阅或UAT结论。

## 实现

1. BleManager私有发布不可伪造的FirmwareIdentity事实（连接代次、票据、状态、catalog），仅当前连接0x9F精确响应可准入。即使调用者设置cachedStatus字符串或构造另一个record，也不能授予权限。移除人工HEX方法/按钮/提示，不后台调用旧confirm。
2. AhaKeyProtocol严格检查响应原字节为精确r001及可选NUL填充，避免旧显示解析器清理空白/控制字符后错误准入；保留旧版本文本显示解析与基础V主.次回退。未知、空、未来、乱码、超时不开放；无可靠旧版catalog时标UNKNOWN/FAILED，不伪造LEGACY。UNSUPPORTED枚举/文案保留但无猜测路径。
3. 0x9F共用事务队列，等待整笔显示租约后才撤销旧准入并开始读取；同一并发读取去重，超时可明确刷新重试，不无限自动轮询。主动清理身份不打断活动显示租约。识别不解除读/写未知ACK保护，不自动上传/保存。
4. 请求、缓存、会话收包与FX提交核验连接/票据。BLE包的代次检查与处理同锁，USB沿原代次接收；reset/USB切换立即使旧准入失效。控制器首次读取标记绑定连接代次，防止USB/BLE切换后漏读；重复成功处理去重。旧失败/FX票据不清新事实。
5. 服务、CP1多任务与CP2入口使用同一事实。CP2只经已准入lease/exchange发送（含0x88），raw sendCommand不能绕过；0x98/99在发送前和自动USB切换后复核。legacy SINGLE 0x90不被新准入一刀切禁用。保留原锁、TTL、最新事实、上传与ACK语义。
6. 四分区顺序为运行展示模式、亮度、单任务灯效、多任务任务槽。标题/原因在禁用操作区之外；设备应用与预览按能力/忙/切换限制禁用，非当前模式仅锁相应本地操作区；亮度不被SINGLE/MULTI误锁。本地资源/绑定/草稿保持，OLED显示设备动作不可用原因；中英文资源同步。

生产文件：AhaKeyProtocol、DeviceStatus、DisplayConfigState、BleManager、DisplayConfigService、AiRuntimeDisplayService、StudioController、InspectorPane、style.css、messages_zh.properties、messages_en.properties。

测试文件：新增DisplayConfigCapabilityChecks；FakeSession改为真实内存0x9F准入（可选择未准入初始化）；DisplayConfigIsolationChecks将构造隔离检查放在身份回读前；DisplayConfigRaceChecks模拟控制器在识别成功后恢复按需回读的通知。不降低原断言，不以假quarantine绕过。

## 真实执行

证据根：`.ahakey-desktop-harness/evidence/20261021-wd005-r8/`。所有最终结果绑定`tested-input.json`，与`after.json`相同。

环境：`D:\jdk-17.0.19.10-hotspot`；Maven=`C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd`。仅进程级JAVA_HOME及MAVEN_OPTS=`-Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8`；控制台输出UTF-8，未改系统环境。

最终编译：`mvn.cmd -o -Dmaven.repo.local=C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.m2repo --batch-mode --no-transfer-progress test-compile -DskipTests`，退出0，见compile-05.log/json；无clean/package/download。编译本身不算行为测试。

实际Java检查：`java.exe -Dfile.encoding=UTF-8 -Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8 -cp "target/test-classes;target/classes;target/lib/*" com.example.ahakey.displayconfig.<检查类>`；UI检查另传本轮ui-05.png路径。完整argv及各退出码在tests-05.json。

| 检查类 | 断言数 | 退出码 |
| --- | ---: | ---: |
| DisplayConfigCapabilityChecks | 101 | 0 |
| DisplayConfigIsolationChecks | 64 | 0 |
| DisplayConfigChecks | 175 | 0 |
| DisplayConfigFxChecks | 36 | 0 |
| DisplayConfigRaceChecks | 72 | 0 |
| DisplayConfigRevision3Checks | 72 | 0 |
| DisplayConfigRound5Checks | 46 | 0 |
| DisplayConfigRevision3UiChecks | 42 | 0 |

总计608项，新增101项加本轮重新执行507项；不是复用旧507项日志。最终日志均为`<检查类>-05.log`。

## 验收增量覆盖与限制

- C01：内存USB/BLE合法自动准入；伪造缓存、旧显示、空、未来、乱码、前置控制字符、尾随垃圾、真实15秒超时、显式重试；直接CP1/CP2入口及服务无未准入写入。基础版本回退保留。
- C02：两传输旧代次回包、旧读异常、缓存清空、旧请求不能清新结果、FX票据拒绝；实际ensureUsbConnected内存切换后0x98未发到新USB，重新0x9F才准入。完整控制器生命周期仍仅静态审查，未启动整应用。
- C03：lease期间身份等待与主动清理不撤销准入，活动事务仍可发送，lease结束恢复身份读取，并发去重；真实requireDisplayRecovery后识别成功仍拒绝新写入；回归覆盖取消/ACK/TTL/最新事实及部分保存。
- C04：0x90适用路径实际可发送；既有输入/模式回读模拟未回归，未改按键/侧拨/语音业务实现。真实旧设备、系统语音和完整应用未测，不以模拟替代。
- C05/C06：生产UI装饰/原因绑定函数在隔离FX节点上验证分区原因优先级、真实disable属性、标题/原因不disable、亮度不误锁、草稿保持及CSS颜色；既有42项CSS/布局与36项局部FX回归重跑。没有构造完整Inspector/StudioController，没有实际鼠标键盘遍历或高DPI验收，留Owner Preview。
- C07：执行前STATIC_IO_ISOLATION_R8_20261021.md；完整内存USB/TCP夹具、受控发现/connect阻断、lease/reset/补发/IOException/TTL/未知ACK回归通过。没有真实USB发现/Socket连接或设备写入。

## 过程失败保留

- 初次CapabilityChecks的92项断言已完成，但finally删除进程内加载的JavaFX DLL失败，退出1，不能计PASS。现仅保留该测试临时目录下的.openjfx缓存，其他测试数据清理；日志报告实际缓存目录，未删用户缓存。
- 第二次旧IsolationChecks仍假设共享夹具初始化没有USB发现；新增0x9F合法内存初始化使此假设过时。改为先未准入构造核查零发现，再明确通过内存回读准入；其他传输分支断言不减。
- 第三次旧RaceChecks在身份读取期间进入OLED后未模拟新的capabilityChanged通知，少了14次按需读。补上生产控制器已有的成功准入通知，保留原计数断言。
- 第四次全部607项通过后，继续补齐“主动身份清理不影响活动lease”的保护与断言；第五次最终608项全部重新执行通过。
- compile-01..05、各次已执行测试原始日志与tests-01..05均保留，不覆盖历史失败，也不把中间结果资格化最终输入。

## 待DLA与外部边界

同名r001中间固件无法由版本串区分是产品策略的已知限制；自动准入不宣称读到了HEX。工程固件仍由DLA按本轮合同所列FFB9208F…正常修复HEX、正式Gate及桥接身份核对，不由本实现代验已刷设备。

UP-01/02上传根因、来源缺失事件、RT-03、BLE性能、完整应用和真实设备、正式fresh/candidate/新包/配对/OwnerUAT缺口保留。本轮没有打包、启动App、安装Hook、连接/写设备、烧录、发布或Git写入。

冻结根EXECUTION_REPORT.md不追加。本轮检查通过新report/checks/logs登记到当前revision5/round8；submit回执若仍引用历史根report_sha，它是基报告身份，不代表本轮执行报告。以verification绑定的本报告和检查表为本轮结果依据。
