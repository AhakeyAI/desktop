# WD-005 revision5 / round9 正式候选构建细节

日期：2026-10-22；DIB，BUILD_ONLY。
Owner授权记录：.ahakey-desktop-harness/evidence/20261022-wd005-formal-build-only-owner-authorization.md。
正式preflight PASS后build-open生成token：20261022T004444327311Z-731fe2。
本文件为独立细节记录，不替代工具生成的BUILD_REPORT/BUILD_RECEIPT，不修改冻结EXECUTION_REPORT。

## 输入和执行

- 候选HEAD：e08524cc07077a06d34b79130ddea074355ea2fb，candidate-check已通过，未push；本轮无Git写操作。
- 原起点保留：41c034171e60b2d4962b0adbe8f3cffbf80a0436。
- 源码前后指纹相同：98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9。见FINGERPRINT_BEFORE/AFTER.json。
- 有效批准：5ca53dc27d3bb53b05e7b48932f7a39b8db387fb730f112fa6e6c031e69ec6cf。
- cwd：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java。
- JDK：D:\jdk-17.0.19.10-hotspot，Microsoft OpenJDK 17.0.19+10-LTS 64-bit。
- Maven：C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd，3.9.12；实际runtime为上述JDK。
- 仅子进程设置JAVA_HOME与MAVEN_OPTS=-Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8；没有改系统配置。平台默认GBK、pom源码/资源UTF-8，stdout/stderr参数UTF-8，不混称默认编码。

实际构建命令：
```text
"C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd" -o "-Dmaven.repo.local=C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.m2repo" --batch-mode --no-transfer-progress package -DskipTests
```

BUILD_EXECUTION.json保存全部参数、cwd、开始/结束时间和退出码。Java/Maven身份及package首次均退出0；无本轮失败重试。stdout/stderr用BaseStream原字节复制，空stderr保留，LOG_MANIFEST绑定全部日志及静态分析输出。
Maven BUILD SUCCESS；未clean，是当前候选工作区的增量package。日志未显示重新编译源码，不能说本轮重编译全部class；主JAR由本次package生成。依赖复制报告已有文件，全部18份依赖另核对哈希。
日志有与Preview相同的6项JavaFX effective-model warning，未改依赖或额外运行-X。Tests are skipped；656项是既有证据，本轮未重跑。

## 本轮运行产物

根目录：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\changes\WD-005\builds\20261022T004444327311Z-731fe2\runtime-jar-classpath。
仅复制本轮package后的主仓target主JAR和全部lib到新的令牌目录；没有改写或借用旧Preview。19个文件、113775952字节。
主JAR：ahakey-studio-1.0.0.jar，647301字节，SHA256=f63f816586d88f7ee44da2c40be419b408948c6b717bfe26a47e90a719af1f1c。
ARTIFACT_MANIFEST逐项记录来源、大小和SHA；复制后与来源逐项核对一致。

STATIC_INSPECTION.json：Main/App及核心类存在；149个应用class均major61；8份资源与当前源码资源字节相同。JavaFX Windows、JNA win32-x86-64、ONNX win-x64、SQLite Windows/x86_64原生条目存在。只检查ZIP字节，不加载类/原生库，不启动应用。

## 与已测Preview的只读对比

比较对象：preview-20261021T024920511394Z-2ae03d/runtime-jar-classpath，原主JAR SHA256=97a5ae072c18a0ed229538fee7766426bd9f6c8ba807607aee10f141efa3052b；本次重新核对该哈希。
PREVIEW_COMPARISON.json逐条列出两个主JAR全部178个ZIP条目的解压内容SHA、大小、压缩大小和时间戳，并列出18个依赖SHA。

- 两包均178个条目，无增删。173个条目解压内容逐字节一致，但条目时间/容器元数据不同。
- 18个依赖JAR全部逐字节一致，无新增/缺少/不同文件；因此依赖内部ZIP内容亦相同。
- 5个条目解压内容不同，不能归类为“仅ZIP元数据差异”：
  - fxml/VoiceInputPanel.fxml：仅CRLF/LF，当前20处CRLF，Preview为0。
  - logback.xml：仅CRLF/LF，当前37处CRLF，Preview为0。
  - model_config.properties：仅CRLF/LF，当前1处CRLF，Preview为0。
  - META-INF/maven/com.example/ahakey-studio/pom.xml：仅CRLF/LF，当前158处CRLF，Preview为0。
  - com/example/ahakey/view/CanvasPane.class：均8527字节，仅两个常量池Utf8合成局部变量名不同。

PREVIEW_DIFFERENCE_ANALYSIS.json对4个文本使用严格UTF-8解码，仅将CRLF规范成LF后全文精确相等；没有忽略其他空格或任意文本。

CanvasPane逐字节结论：当前patt3223$temp / patt2763$temp，Preview为patt3151$temp / patt2700$temp，各自仅出现一次。仅在内存中作这两个等长名称替换后，整个class字节完全相等。没有改写class或JAR。javap -p -c -l -verbose原始输出证明名称位于常量池#359/#372，并被LocalVariableTable引用；没有其他字节码指令、方法、运行常量、字段或属性差异。JAVAP_EXECUTION和JAVAP_DIFFERENCES记录命令/退出码/输出差异；两个javap均退出0。

CANVAS_SOURCE_COMPARISON记录源码只有换行差异（当前112处CRLF、Preview为LF）。合成变量名中的数字变化与源码位置偏移相符，这是原因推断；class差异界定依据是实际反汇编与全字节比较，不是仅凭相同源码指纹推断等价。
早先无显式UTF-8参数的javap输出亦保留；正式阅读使用*.utf8.javap.txt。只有只读分析，没有clean、第二次package或源码修复。

结论：未发现执行指令/配置文本语义变化，但新旧包不是字节相同的产物。上述解释不能代替新包启动、真实UI、固件配对或Owner UAT。是否复用既有Preview验收证据及补测差额由DLA按正式流程决定。

## 启动配方，仅记录

cwd必须为上述runtime-jar-classpath，PowerShell控制台/管道UTF-8：
```powershell
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' '-Dsun.stdout.encoding=UTF-8' '-Dsun.stderr.encoding=UTF-8' '-cp' 'ahakey-studio-1.0.0.jar;lib/*' 'com.example.ahakey.Main'
```
不使用java -jar，未执行启动。包不带JRE、现场BLE桥接配置/程序或本地模型，不能称全功能自包含或EXE安装包。真实启动仍可能访问用户配置、开启服务和退出时停止桥接；本轮未触发。

## 交付边界

原DLA、formal fresh、Owner Preview的已有PASS按当前记录保留，不扩大为本轮新包UAT。正式UAT仍pending。
UP-01/02、来源缺失事件、RT-03、BLE性能、完整应用及正式交测未覆盖项不自动关闭；固件准入由DLA另行处理。
本轮不改生产/测试/pom/桥接/固件/Harness核心或历史dirty，没有Git写入、设备、Hook、烧录、发布、下载模型、kill或应用运行。
正式build-finish绑定当前候选/产物/日志；回执只能由工具生成。本细节报告不预写工具负责的BUILD_REPORT.md。
