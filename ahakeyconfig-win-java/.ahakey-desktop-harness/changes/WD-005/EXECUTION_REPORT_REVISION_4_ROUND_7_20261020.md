# WD-005 revision4 / round7 实施报告

日期2026-10-20；DIB。本轮实现R5-F1测试隔离，等待原DLA实际复审；不是自审、Preview或真机通过。

## 身份与边界

- HEAD f595262207796dbf325cb9951ed3dc02b4887362仍是源码存档；本轮没有Git写入。
- 原起点41c034171e60b2d4962b0adbe8f3cffbf80a0436与历史批准/报告/审阅保留。
- 当前有效合同revision4/build_round7，Owner批准记录20261020-wd005-isolation-interface-owner-authorization.md；R6方案的历史待确认文字不替代effective approval。
- 修前指纹1fca9345199cd1166acd8b4df7125d3e17f1cad4032c7736dc1060361a2d3ccf。
- 修后指纹e10b4d65ad9b3f62221b7790b659c09429243a96a43a169db575dce6b4c18e8a。
- 开工及收尾preflight均退出0/PASS。修前/后完整指纹在evidence/20261020-wd005-r7/before.json、after.json。

## 实际修改

生产本轮仅BleManager新增protected isUsbDevicePresent，默认原样return UsbHidTransport.isPresent；tryConnectUsb及ensureUsbConnected两处调用统一经过该入口。其他生产字节不变，R4-F1/F2/F3保持修前内容。没有新构造器、环境开关、协议或连接策略。

测试新增OfflineBleManager和DisplayConfigIsolationChecks；修改DisplayConfigChecks、DisplayConfigRaceChecks、DisplayConfigRevision3Checks、DisplayConfigRound5Checks，共六个测试文件。共享FakeSession与纯解析用例都改用安全构造，反射字段按BleManager基类读取。USB用例由useUsb开启完整内存替身；BLE保持USB关闭和内存TCP。删除A10中仅为绕过发现而注入的displayReadUncertain；实际未知ACK用例不删、不假设恢复。

OfflineBleManager为final测试类：发现只返回内存标志，connect直接AssertionError拒绝；MemoryUsb覆盖全部五个可达USB实例方法，无super调用或原生句柄。sendCommand/exchangeDisplay/sendRuntimeState/flush/reset均保留生产实现。

## 先静态后执行

STATIC_IO_ISOLATION_R7_20261020.md于第一次本轮编译/测试前保存，列明构造、USB发现/收发、TCP连接、lease关闭、reset、补发和全部调用者。没有运行修前不安全夹具作红测试，也没有要求Owner拔设备。静态检查确认原Socket路径由connect override阻断，真实USB静态入口由实例override截断；模拟设备存在时只调用假open/send。

新增隔离测试调用真实tryConnectUsb/ensure发送链，分别模拟存在/不存在，检查发现/open计数、内存发送、reset后策略、关闭后再发现、disconnect假close、connect在线程/Socket创建前拒绝。socket/inputStream/readerThread为null。补充匿名自身终态在lease内PENDING并只补发最终状态。纯内存模拟不是物理设备验证。

## 本轮真实执行

日志根：.ahakey-desktop-harness/evidence/20261020-wd005-r7/。

| 执行 | 退出码 | 断言 |
| --- | --- | --- |
| 离线test-compile，compile-01.log | 0 | 编译不是测试 |
| DisplayConfigIsolationChecks，isolation-01.log | 0 | 64 |
| DisplayConfigChecks | 0 | 175 |
| DisplayConfigFxChecks | 0 | 36 |
| DisplayConfigRaceChecks | 0 | 72 |
| DisplayConfigRevision3Checks | 0 | 72 |
| DisplayConfigRound5Checks | 0 | 46 |
| DisplayConfigRevision3UiChecks | 0 | 42 |
| git diff --check -- src | 0 | 仅LF/CRLF提示，无空白错误 |

合计507项=旧443项在新隔离夹具下本轮重跑+新增64项，不复用第五轮PASS。受控TCP IOException、原五分钟TTL、最新事件替换、连接代次、迟到ACK与真实超时隔离仍经过实际生产发送/补发链。USB与BLE上传分支分别执行。局部FX截图为ui.png，不是完整Inspector/App/高DPI验收。

JDK：D:\jdk-17.0.19.10-hotspot；Maven：C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd。
编译：`mvn.cmd -o -Dmaven.repo.local=C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.m2repo -DskipTests test-compile`；JAVA_HOME使用上述JDK，MAVEN_OPTS为`-Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8`，PowerShell输出为UTF-8。
所有测试命令：上述JDK的`java.exe -Dfile.encoding=UTF-8 -cp "target/test-classes;target/classes;target/lib/*" com.example.ahakey.displayconfig.<类名>`。UI类另传日志根/ui.png。六项既有入口精确命令及退出码在execution.json；新增隔离入口按本段命令调用DisplayConfigIsolationChecks。

未clean/package，不下载依赖，不启动App/StudioController/Hook/真实网络服务，不连接或写真实设备，不改桥接/固件/用户配置或Harness规则。未重跑不受本次修改影响的编码探针。不推断历史测试是否曾写设备，旧报告不倒改。

## 登记与待办

本报告、IMPLEMENTATION_CHECKS_ROUND_7_20261020.json、静态清单和真实日志通过四项record-check绑定当前轮次。root EXECUTION_REPORT.md仍冻结；helper的report_sha256仍指向历史根报告，不能冒充本轮执行。正式提交结果以工具输出、IMPLEMENTATION_RECEIPT、builder_submission和STATE为准，本报告不预写提交成功。

R5-F1实现及受控验证已完成，关闭须原DLA实际复审。仍保留同工具多个匿名会话不可区分、UP-01/02上传真机根因与恢复、来源缺失事件、RT-03固件主槽回退、BLE性能、桥接功能/新产物身份、完整应用及USB/BLE真实验收待办。没有本轮formal candidate或新Preview；fresh、候选、包、Firmware identity及Owner UAT分别收口。
