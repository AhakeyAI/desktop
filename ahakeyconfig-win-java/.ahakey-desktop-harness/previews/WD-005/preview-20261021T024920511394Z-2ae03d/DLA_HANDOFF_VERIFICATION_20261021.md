# WD-005 revision5 / round9 Preview交接核验

## 结论与权限

原DLA只读核验包身份和静态结构通过；Owner已确认本次键盘刷入下述FFB920修复HEX。可由Owner先离线UI、再有线USB进行OWNER_PREVIEW。不是formal candidate、high-impact fresh、整应用运行通过、设备验收或Owner UAT PASS。DLA没有启动App、构建、Git写入、Hook、设备连接/写入或烧录。

全局仍VERIFY/DLA_REVIEW、next_actor=DLA，不手改路由。旧PREVIEW_RESULT_LATEST中的fail是旧令牌反馈，不是本轮结果。正式review check因当前pack的fresh未完成保持pending。

## Windows身份

- token：preview-20261021T024920511394Z-2ae03d，PREVIEW_RECEIPT.status=ready_for_owner_preview。
- 回执SHA256：d266801837ccb4d16fa23f9593324c89dcbb882a700e54aaebe441ff270f0b2a。
- 工作区指纹：98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9。
- 快照指纹：b33465cede33f144802676c9f9a141291775d8c0e580b846bf34383e5d08ae02。
- 主JAR SHA256：97a5ae072c18a0ed229538fee7766426bd9f6c8ba807607aee10f141efa3052b。
- 运行目录：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261021T024920511394Z-2ae03d\runtime-jar-classpath。

19个运行文件与receipt、manifest、snapshot target来源、大小和SHA全部一致，无额外运行文件。9个receipt证据哈希及10份原始日志大小/哈希匹配。FINGERPRINT_BEFORE/AFTER内容一致，DLA重新计算当前两份源码指纹仍匹配。149个应用class均major61，8份资源与source字节一致，无测试类；实际中英文slot-local-note存在，Windows JavaFX/JNA/SQLite/ONNX原生条目存在。只读ZIP，不加载库。

完整读取两轮执行记录和全部原始日志：首次java身份成功，但Maven/package命令包装退出1，GBK stderr为拒绝访问，无Maven输出；第二次修正cmd引号后Maven身份和离线package退出0。失败没有被覆盖，源码/输入未改变。日志明确Tests are skipped，656项是R9已有执行，不是本次重跑。保留JavaFX effective model六项warning，不冒称零告警。

JDK17路径与Maven版本见BUILD_REPORT；包不附JRE、BLE包/配置或本地语音模型。model_config.properties本轮只有status.poll.period.seconds=5，不虚构文件含model.enabled=false。无模型不等于系统语音不可用，也不代表系统语音已验证。

## 固件配对

- 只读根：C:\Users\20825\Desktop\vibe-code。
- 正式CP2 gate：.ahakey-harness/evidence/checkpoints/X1-AI-WORKFLOW-PRESENTATION/CP2/20261018T175441/gate-receipt.json，result=PASS。
- gate SHA256：BF6EFC5AC8380B6420C4DED17492B4BC798CAD46072699C38EDE41945FB5DBAA。
- candidate：70ca334f65d73b6a2f20a0598e55c6da59f26526。
- HEX：C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\builds\ws3-cp2-memory-safety-20261018\HID_Keyboard_582m_vibe_coding.hex。
- HEX SHA256：FFB9208F79084AA24A832AD2562A14DBBEA5DF4D114A135CB5B2EB98D4E05539，实际重新计算匹配gate和当前R5合同。
- Owner本轮直接回答：“已刷入这份 FFB920… 修复版”。这是Owner设备确认，不是DLA读取设备证明。

产品通过当前连接精确r001响应自动准入，已删除人工HEX确认。工程配对核验不恢复产品按钮、不推断同名历史包等同。不回刷旧D7D105包。

当前固件project-state仍accepted_checkpoint=CP2、accepted_source_commit匹配；后续CP2.5工作不纳入本轮。20261021-startup-stdio-heap-amendment记录已接受CP2 ELF首次stdio缓冲申请走一字节回退，违反CP2.5新增普通路径零分配失败要求；该记录明确不是设备崩溃或BLE根因证据，未产生新HEX或撤销CP2。此静态观察保留，不代固件修复，也不声明全栈无风险。出现启动异常、黑屏或重启立刻停止设备测试。

## 桥接现场

现场 C:\Users\20825\Desktop\windows软件代码\desktop\BLE_tcp_driver_package\BLE_tcp_driver.exe 与BLE_tcp_bridge/bin/Release同字节，SHA256=9B8F8C9D18AE7EE93B71ED7C867E1CE1E60040EBC6832498F5F2D00DCBD6106E。
Program.cs=E235BDA01FA4C2C6AE35869D6D5FBB68C02923085146EEF0151B3BAEBA0D50D0；Form1.cs=86A6FD0E6AA940209BDA074CCADD804E6B95840937E93CB273AB90A94C3F4DFC；TcpServer.cs=CD4978E768A8B3028F9CE1B93A3079F0BD574330444557CE0D4B67E4D4013745，均匹配桥接退修报告。

源码归属及离线报告不证明现场EXE来自新版源码；不能声称MTU/队列优化已交付。本包不附桥接，按钮查找运行目录/父目录等位置，不应假定可直接启动外部现场包。现场配置ServerPort=9000，Windows默认127.0.0.1:9000；Hook默认8765，端口冲突会影响路由。仅只读核查，未启动或改现场配置。BLE性能暂不验收，先做USB。

## 数据、运行风险与恢复

源码隔离不等于用户数据隔离：真实运行使用C:\Users\20825\.ahakey草稿/资源/绑定；Hook与语音服务会启动，已有Hook事件可能在连接后触发runtime输出。先从托盘Exit旧实例，暂停主动AI工作，确保未运行其他AhaKey实例；退出应用有停止BLE桥接的既有行为，不能只把关窗口当退出。离线检查要物理断开USB并避免目标BLE连接。

由Owner在所有实例退出后复制整个.ahakey到新时间戳备份目录；不删除或覆盖原数据。若有数据问题，先退出所有实例，把本次.ahakey改名保留，再复制备份回原名，禁止运行中恢复。此操作仅恢复PC草稿，不回滚已写入键盘的资源/灯效；设备恢复需要重新上传保留的旧资源/原灯效，不使用恢复出厂。日志在本运行目录logs/ahakey-studio.log。

测试步骤及启动命令见同目录OWNER_PREVIEW_BRIEF_20261021.md并在聊天正文交付。失败保留首次日志和截图，先分诊，不盲目重试或自动修代码。
