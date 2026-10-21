# WD-005 revision5 / round9 执行报告

日期：2026-10-21。角色：DIB。依据 revision5 有效批准及正式 R8-F1/F2 request-fix，在 IMPLEMENT/FIX 内完成窄修；不是重新设计或扩大协议。

## 身份与范围

- HEAD：f595262207796dbf325cb9951ed3dc02b4887362，仅历史源码存档，本轮无 Git 写入。
- 原起点：41c034171e60b2d4962b0adbe8f3cffbf80a0436，未重置。
- 批准：5ca53dc27d3bb53b05e7b48932f7a39b8db387fb730f112fa6e6c031e69ec6cf。
- 修前源码：3c1e7cf6a1180291d396d2ad288f44a9b57b5a7e74b27b6334d3299b801b7c3c。
- 本轮已编译并执行输入：98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9；tested-input 与 after 一致。
- preflight PASS；source-delta.json 记录相对本轮开始只有四个文件变更，无文件删除。历史 dirty、固件、桥接和冻结记录保留。

## 两项修复

R8-F1：InspectorPane.java:964 的实际任务槽内容改为调用 runtimeSlotSupport()。该工厂创建中性、本地保存说明，不再读取 isDeviceSupported 或以 !supported 判断固件不支持。中英文资源新增 display.slot-local-note；真实身份阻塞原因仍由原 addDisplayReason/decorateDisplaySection 绑定显示，不改变按钮准入或任务槽绑定。

新增隔离回归直接反射调用实际工厂，核对中英文精确文本、换行及样式；将该实际 Label 放入现有生产装饰器，遍历 reading/failed/unknown/unsupported/disconnected/已识别无阻塞，验证本地说明保持中性且身份原因仍准确。没有构造真实 Controller 或完整 Inspector。

R8-F2：DisplayConfigCapabilityChecks 的 Platform.startup 位于 withIsolatedHome 的异常安全边界内。启动、主体和退出发生异常时仍恢复原 user.home（原本未设置则 clear），并尽力清理当前测试临时目录。退出异常不覆盖原始失败，作为 suppressed 保存；单个清理失败记录 stderr 并继续。临时 .openjfx 缓存因 Windows 加载 DLL 继续保留并报告路径，不访问真实用户缓存。

新增受控测试覆盖启动 IOException、初始化 Error、主体 Error 叠加退出 IOException、正常退出；核查临时 home 生效、原异常、清理和恢复。缓存哨兵为本次新建临时目录，验证只保留缓存；哨兵自行清理，不删除实际已加载 JavaFX 缓存。

新增48项：说明组件28项，异常/清理20项。不删改已有101项能力断言或其他507项回归；保留真实内存 USB 与 BLE/TCP 两发送分支。生产改动仅 InspectorPane 和两份 messages 资源，服务/协议/锁/TTL/连接代次/ACK隔离未变。

## 真实执行

证据目录：.ahakey-desktop-harness/evidence/20261021-wd005-r9/。
执行前静态核查：STATIC_IO_ISOLATION_R9_20261021.md；OfflineBleManager/MemoryUsb/FakeSession 入口仍封闭真实 USB 发现、open/send 与 Socket connect。没有以假 quarantine 或覆写整个 sendCommand 绕过被测逻辑。

JDK：D:\jdk-17.0.19.10-hotspot；Maven：C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd。
进程级 JAVA_HOME 与 MAVEN_OPTS=-Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8；控制台 UTF-8，不改系统环境。

离线编译实际命令：mvn.cmd -o -Dmaven.repo.local=C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.m2repo --batch-mode --no-transfer-progress test-compile -DskipTests。
compile-01.log：退出0，65个生产源文件及10个测试源文件编译完成。未 clean/package/download；编译不计入行为断言。

测试：java.exe -Dfile.encoding=UTF-8 -Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8 -cp "target/test-classes;target/classes;target/lib/*" com.example.ahakey.displayconfig.<检查类>。UI类额外参数为本证据目录/ui-01.png。完整 argv 与退出码见 tests-01.json。

| 检查类 | 本轮断言 | 退出码 |
| --- | ---: | ---: |
| DisplayConfigCapabilityChecks | 149 | 0 |
| DisplayConfigIsolationChecks | 64 | 0 |
| DisplayConfigChecks | 175 | 0 |
| DisplayConfigFxChecks | 36 | 0 |
| DisplayConfigRaceChecks | 72 | 0 |
| DisplayConfigRevision3Checks | 72 | 0 |
| DisplayConfigRound5Checks | 46 | 0 |
| DisplayConfigRevision3UiChecks | 42 | 0 |

总计656项，本轮重新执行旧608项并新增48项，不复用旧日志冒充本轮。八个进程全部退出0，本轮无失败重试。原始日志均为各类名-01.log。git diff --check 退出0；只出现既有 CRLF 转换提示，无 Git 写操作。

检查了 ui-01.png：既有隔离 OLED/灯光局部布局的文字和禁用状态可见。它不是完整 Inspector，也不是新增 support Label 的实景截图；新增实际 Label 由上述构造/状态断言验证，不宣称完整应用、真实交互或高DPI通过。

## 验收与保留缺口

R8-F1/F2 修复和隔离回归已完成，等待原DLA实际复审，不由DIB自批关闭。
C01-C04/C07 按现有149项能力及其余回归重新执行；C05/C06只证明实际组件与隔离节点范围，不扩张为完整应用验收。A01-A11完整链路没有全部 PASS。

UP-01/02上传根因、来源缺失事件、RT-03、BLE性能、完整应用、高DPI、真实键鼠交互及真机缺口继续保留；没有将覆盖缺口宣称成新功能故障。
formal fresh、Git candidate、新Preview及正式配对的固件/桥接身份、Owner UAT 分别收口。旧源码存档不是本轮candidate，旧Preview不是本轮新包。

本轮无真实应用启动、设备连接/写入、Hook安装、烧录、发布、Git写入或打包。正式提交仅登记当前轮次 machine/core_regression/special_regression/mock 的已执行范围。
冻结根 EXECUTION_REPORT.md 的 SHA256 仍为749264589c44656848f062fcf3b4ecf35784bef80f7356dc1f204834d69a19a2，不追加。正式回执若引用此历史基报告，应以 verification 绑定的本报告、检查表及日志识别第九轮证据。
