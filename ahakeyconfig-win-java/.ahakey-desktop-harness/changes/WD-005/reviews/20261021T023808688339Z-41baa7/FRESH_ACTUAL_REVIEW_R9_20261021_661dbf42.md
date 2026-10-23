# WD-005 revision5 / round9 独立实际审阅

结论：**PASS（仅固定源码包的fresh实际审阅）**。当前正式状态仍为VERIFY/DLA_REVIEW，不修改路由。

审计运行标识：`wd005-r9-fresh-661dbf42-aca6-4120-80a3-c7eab9e3f37a`。此为真实生成的audit-run标识，不是伪造的Codex线程ID。

- pack：79b4a6d87283e22acae6b537a106a9007f426caf06fb5fcda57b15ea49074087
- 源码：98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9
- 批准：5ca53dc27d3bb53b05e7b48932f7a39b8db387fb730f112fa6e6c031e69ec6cf
- diff：5bdf26aff58dcf1539dbc99018e244b7567bcffbdbe16016d12342371d56a6c7

## 审阅方法与独立性

本记录由收到FRESH_ACTUAL_REVIEW委派的新独立DLA审阅对话生成。session为本轮实际生成并使用的审计运行标识，不声称是Codex线程UUID。没有复制原DLA结论作为本轮分析；原REVIEW仅作流程和输入事实读取。辅助Standards与Spec分支均只读，主审对核心链路及疑点独立复核。

对固定包累计35文件作独立实际审阅，覆盖新增文件全文及既有文件变更hunk和上下游调用。自动准入只能由当前连接0x9F精确响应发布；连接代次/读取身份票据和FX提交双重校验，失败不伪造旧版。CP2整个上传持有lease，帧按固定长度解析，未知ACK不靠新身份或普通回读解锁，逐包不重发。CP1精确会话归属、5分钟事实寿命与原始事件时间补发保留，磁盘绑定不恢复历史运行态。UI操作真实disable且标题原因独立，本地资源成品先提交索引后发布、草稿与设备事实分离。测试仅内存USB/TCP和局部FX；既有656项及Owner Preview通过没有替代审阅。未发现当前生产调用链可达的确定阻断缺陷或未批准范围扩张，decision=pass仅为此固定源码包的fresh实际审阅结论，不是formal review已登记、UAT、候选、安装包或发布通过。

## Standards

命名/分层/资源关闭和异常保护未发现确定规范违规；OLED提交点、局部禁用和测试I/O替身符合仓库要求。维护性风险与覆盖缺口单列，不把启发式code smell作为强制失败。 确定问题0项。

## Spec

有效revision5覆盖自动准入和中性反馈，revision3覆盖运行态修复，累计原合同A01–A11保留。实际控制器入口接到新服务，旧写入过滤、协议布局、资源持久化和草稿隔离符合批准；未发现确定缺失/越界实现。 确定问题0项。

两轴各0项确定问题，没有阻断项。以下风险与覆盖缺口独立保存，不冒充已解决或自动豁免。

## 关键链路

1. Controller连接/刷新 → BleManager事务队列0x9F → 精确r001响应 → generation/identity对象校验 → FX提交 → DisplayConfigService/CP1统一能力门禁。读取失败只保留旧版显示回退，不伪造旧版或能力。
2. Inspector冻结目标 → DisplayConfigService唯一worker → OledUploadService完整lease → Begin/逐Chunk/Commit → ACK后进度或已应用；异常先隔离再释放。0x00可查询，竞争写入被实际发送层拒绝。新身份不清ACK未知；不盲重发、不跨连接续传。
3. Hook → 来源元数据/精确会话 → 内存事实 → SINGLE最新状态或MULTI完整快照。补发保留原始事件时间，当前连接5分钟过期过滤；错误ID不被cwd/transcript救回；原主槽策略不变。
4. 文件导入 → 受限后台解码/160×80黑底RGB565/填充与CRC → 原子索引提交 → 仅成功后发布草稿。设备回读只更新独立事实，清除不删设备资源，旧迁移不复活已清空项。
5. 四分区标题及原因在禁用操作区外，真实disable保留；亮度独立，SINGLE/MULTI按模式限制。R9任务槽实际调用中性说明工厂；测试恢复home覆盖startup异常，不执行真实I/O。

## 逐文件结论

行号均指固定包after快照；每项全部累计hunk范围及前后SHA详见同名JSON。

### src/main/java/com/example/ahakey/app/StudioController.java

69–128、182–219、331、432、537–566、606–647、700–730、776–856：创建/关闭唯一显示服务；导入与确认冻结资源、过滤全量保存中的旧0x84/0x85、将原OLED raw路径替换为CP2；身份回调与FX提交核对generation/身份对象；按键、侧拨、语音和模式抑制逻辑保留。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/model/DeviceStatus.java

9–13、74–80、110–121：身份枚举单独存储；清理根据连接归UNKNOWN/DISCONNECTED；基础主次版本显示回退保留。可写缓存字符串不等于BleManager可信准入。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/model/DisplayConfigState.java

34–44：19目标及busy冻结；49–73：编辑revision保护后到ACK，亮度与九项灯效分别dirty；78–89：设备预览以ACK时刻起算，结束不重置独立本地模拟。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/model/LightEffectStyle.java

50–62：新增fromCodeOrNull供新界面保留未知；原fromCode仍保持OFF回退，未改变其他调用方含义。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/model/OledResourceState.java

13–55：字节防御复制、CRC/slot填充/容量校验；69–111：草稿、失败、历史已应用和当前设备known分离。Metadata交叉拒绝BASIC/INTEGRITY矛盾；Commit未知仅完整匹配后可确认，普通同CRC草稿不擅自应用。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/model/StudioState.java

23–24：增加唯一DisplayConfigState及访问器，旧按键、语音和模式模型未迁移或重写。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java

9–84、199–207：19目标、8/12帧、48字节Chunk、LE元数据和固定28672 slot；0x9F逐字节精确r001及零填充，不按字符串大小放行未知版本；保留既有命令编码。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/protocol/AhaKeyResponseParser.java

8–57：6字节FAIL/ACK和8/10/18字节读取严格分流，selector、状态、长度和完整性校验；CP2二进制CRC中的帧尾不能提前截断，旧opcode仍走旧解析。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/service/AiRuntimeDisplayService.java

153–215：能力统一与模式ACK后更新；278–367：按provider/id归属、来源明确才排除后台、当前连接5分钟事实；501–539：ID冲突不走路径/cwd兜底，唯一transcript与快照过滤；579–583：持久绑定不保存运行态。真实发送、等待和忽略分别反馈，保留主槽规则。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/service/BleManager.java

51–253：lease固定线程/transport/generation，写未知与读未知独立；459–487：真正发送入口拦截竞争CP2/CP1；524–596：0x9F队列、去重、票据、失败发布；834–858：SINGLE最新补发不更新旧TTL；1067–1120、1245–1403：USB/BLE会话回包隔离；1460–1495：CP2定长重组与ACK投递。readDisplayConfig退出事务monitor后才补发，避免snapshot锁反转。公开API的条件性并发风险另列。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/service/CodexSessionDiscoveryService.java

29–51、69–75：只读SQLite按稳定ID取有限source/thread_source；仅明确guardian/prediction排除，缺失/异常UNKNOWN保留新用户会话；原标题和索引发现优先级未替换，不读取聊天正文。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/service/DisplayConfigService.java

22、107–162、164–223、242–315：后台导入先存后发布、清除保留设备事实、冻结上传目标；按区域串行读取与load/connection票据；亮度独立保存，灯效逐项ACK/部分成功；设备FX过滤旧连接，关闭worker。当前唯一worker排除旧exchange与新CP2事务并行退出。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/service/FirmwareLightSimulator.java

6–115：0–16效果、整数亮度、运动/相位逻辑与固件算法对应；结果是本地模拟，不调用设备，不宣称光度等同实机。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/service/HookDispatchServer.java

173–177、243–262、273–277：接收与发送分离，返回SENT/PENDING/IGNORED/FAILED；不把待补发写成displayUpdated；原权限/端口保留，未知输入和解析失败不记录原始正文。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/service/OledResourceStore.java

34–68、77–138：损坏库拒绝覆盖，immutable成品先写、原子索引为提交点；清除留下tombstone防旧路径迁移复活，共享文件保护；删除失败明确索引已提交。无引用旧版保留符合合同。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/service/OledUploadService.java

33–80：整个事务一个lease，48字节逐ACK推进，不重试Chunk；Commit前持久化未知记录；非明确拒绝异常在lease释放前设恢复隔离；失败含阶段/已确认字节与资源需同步提示，不承诺旧资源保留。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/service/UsbHidTransport.java

103–108、145–153：CP2不走失败后二次写，短写报错；157–215：线程捕获本代句柄/消费者并过滤旧回调，退出仅清自己对应的当前字段；230–235：CP2定长提帧。旧命令fallback保留；真实Windows句柄/驱动行为未执行。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/util/AiRuntimeStore.java

46–49：加载清空历史lastIdeState，保留绑定、路径及偏好；运行事实不能凭磁盘旧值恢复。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/util/OLEDFrameEncoder.java

62–137：GIF逻辑画布/局部偏移/disposal、8/12帧拒绝超限及像素上限；139–201：黑底等比、RGB565回解预览和零填充；reader/stream释放，导入由后台服务调用。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/view/CanvasController.java

145–159、199–223、259–287：热点busy锁；由持久化RGB565成品重建预览，设备已有占位和草稿标识分离；50ms灯效和100ms OLED动画，提供停止入口。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/java/com/example/ahakey/view/InspectorPane.java

752–850、876–977、1284–1375：全局亮度独立、九项SINGLE及MULTI槽位按模式禁用；标题/原因位于操作容器之外；R9实际构造调用中性runtimeSlotSupport，身份原因仍由动态绑定决定；OLED本地导入与设备上传能力分开。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/resources/fxml/CanvasLayout.fxml

16–26、62–68：八灯节点、160×80预览与草稿标签对应控制器；未新增全局导航。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/resources/messages_en.properties

247–278：身份/忙/模式原因及本地槽位说明均有对应键；slot-local-note只说明本地保留，不授予设备权限。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/resources/messages_zh.properties

247–278：读取中、失败、未知和不支持区分；中性本地槽位说明与英文含义一致。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/main/resources/style.css

314–317、359–389：八灯尺寸、OLED黑底和局部分区禁用文字对比；未用全局取消disable替代可读性修复。已查看现有局部ui-01.png，未运行新截图。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/test/java/com/example/ahakey/displayconfig/DisplayConfigCapabilityChecks.java

47–162、164–328：startup/body/shutdown异常安全恢复home，保留原异常与suppressed；真实support工厂双语六状态；两条内存传输验证当前响应、代次及未知ACK仍锁定。149项为已有日志，组件断言不是完整Controller/Inspector。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/test/java/com/example/ahakey/displayconfig/DisplayConfigChecks.java

69–144、183–201、204–319、389–414：临时图像与库、真实协议/上传/互斥；FakeSession共用OfflineBleManager，回复内存注入而生产send/lease逻辑保留。175项已有记录。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/test/java/com/example/ahakey/displayconfig/DisplayConfigEncodingProbe.java

9–18：stdout/stderr/JUL/指定文件样本，handler关闭；不是设备或完整应用检查，未将此探针另计入656项。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/test/java/com/example/ahakey/displayconfig/DisplayConfigFxChecks.java

28–95、98–138：显式临时库、关闭服务、Canvas/FXML/亮度spinner检查；36项已有记录，仅局部FX范围。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/test/java/com/example/ahakey/displayconfig/DisplayConfigIsolationChecks.java

20–35、44–118、122–138：临时home、无真实socket/reader、内存发现/断连、真实lease释放补发。64项已有记录，未启动连接服务。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/test/java/com/example/ahakey/displayconfig/DisplayConfigRaceChecks.java

26–60、64–251、262–307：错误保留、受控ACK/FX/generation竞争、MemoryUsb和service关闭；72项已有记录，不替代真实驱动时序。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/test/java/com/example/ahakey/displayconfig/DisplayConfigRevision3Checks.java

20–36、39–115、118–241：临时home/SQLite，来源/精确身份/TTL，Hook内部处理但不启动listener；内存USB/BLE检查Begin拒绝、Chunk超时、Commit未知和无重试。72项已有记录。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/test/java/com/example/ahakey/displayconfig/DisplayConfigRevision3UiChecks.java

17–81：独立FX、局部helper和对比度截图；42项已有记录，既有截图可读但不是完整Inspector/高DPI证明。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/test/java/com/example/ahakey/displayconfig/DisplayConfigRound5Checks.java

19–30、38–127：临时home、发现结果显式替身；匿名/有身份终态、最新替换、发送失败重试不刷新TTL和未知ACK保护。46项已有记录；临时目录清理一致性风险另列。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

### src/test/java/com/example/ahakey/displayconfig/OfflineBleManager.java

20–34、37–64：构造反射注入内存USB，发现只读内存，connect在建线程/Socket前拒绝；open/isOpen/close/sendCommand/sendData均内存实现且不调用super。没有覆写BleManager.sendCommand/exchange/lease/reset。

结论：未发现确定阻断缺陷；执行覆盖限制见全局列表。

## 条件性风险

- RISK-01（非阻断条件性实现风险）：src/main/java/com/example/ahakey/service/BleManager.java:237。exchangeDisplay的finally无条件清displayExpected。若未来允许跨连接多线程直接调用公开CP2 API，旧请求退出可清掉新请求的期待opcode。当前唯一DisplayConfigService.worker串行所有生产CP2操作，旧请求返回前新lease不能发起，故未认定当前可达bug；不得将本风险扩大成需Owner豁免的已发现缺陷。
- RISK-02（非阻断测试维护风险）：src/test/java/com/example/ahakey/displayconfig/DisplayConfigRound5Checks.java:19。旧测试临时目录/FX退出策略不完全统一，Round5临时目录未完整清理可能残留受控临时文件。已检查无真实USB/TCP连接或真实用户配置覆写路径。R9 capability测试修复了本轮已提出的startup异常恢复；不宣称其他套件所有失败组合均已验证。

## 已有证据与未执行边界

22份绑定证据哈希一致，35份after与当前工作区逐字节一致；guard-status原起点/范围/治理及submit通过。原起点41c034171e60b2d4962b0adbe8f3cffbf80a0436保留，缺起点字节列表为空。

R9已有8进程656项记录：149+64+175+36+72+72+46+42；本轮未重跑。读取编译日志、断言完成/故障注入记录并查看ui-01.png。日志中的预期拒绝和超时不当作套件失败；局部截图不当作完整窗口证明。

- 完整Controller/Inspector、实际键鼠、高DPI、完整应用生命周期没有在本轮执行；R9局部VBox/反射helper和ui-01.png只证明其限定范围。
- 本轮只核查既有8进程656断言及日志；没有重跑、没有新增机器测试PASS。生命周期尚无null-home、单独shutdown失败及逐个删除失败全部组合的执行证据。
- USB/BLE均有内存发送分支覆盖；Windows原生句柄时序、真实BLE性能、无线断连/重连、桥接修复源码到现场EXE的身份绑定不能由此证明。
- Owner原话及preview-result为Preview整体通过，清单偏离线UI/有线USB；不自动扩展到非法包、旧固件、上传中断连、长时/持久化或完整A01–A11。
- UP-01/UP-02历史根因、来源缺失事件的全部竞态和RT-03外部固件收口继续保留；正常路径通过不证明这些问题的全部条件已解决。
- 同名r001中间固件不能凭版本字符串区分是已批准产品限制；实际HEX/gate与桥接身份仍需正式交付核验，没有自动纳入CP2.5。
- 上述覆盖缺口未获本审阅豁免或自动后置；原DLA应逐条匹配已有证据，仅对具体差额取得适用验证或明确Owner决定。

## 交回原DLA

返回原DLA。先核对本记录与固定pack/当前源码/批准的绑定，再正式回填fresh及review；随后按CLOSEOUT_PLAN_R9生成审查精确candidate-plan并分层完成候选、构建/配对身份、覆盖及归档。不得把本pass直接当CLOSED或复用Preview为正式UAT。

正式review、candidate及正式构建/交付身份与UAT尚未完成。本次只新增这两份独立审阅文件；没有覆盖旧记录、修改产品/测试/规则、执行测试/构建/设备或Git写入。完整下一步Prompt在本聊天最终回复展示。

