# WD-005 revision5 / round9 隔离 Preview 构建报告

日期：2026-10-21；角色：DIB；模式：PREVIEW_BUILD_ONLY。
依据正式 preview-open 令牌 preview-20261021T024920511394Z-2ae03d，未执行 formal build-open 或重复 submit。
原DLA actual review 已通过，formal high-impact fresh 仍 pending；本报告不是设备、Preview体验或UAT通过证明。

## 构建身份

- 令牌根：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261021T024920511394Z-2ae03d
- 构建 cwd：令牌根\source；运行目录：令牌根\runtime-jar-classpath。
- 工作区前后指纹：98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9。
- 快照前后指纹：b33465cede33f144802676c9f9a141291775d8c0e580b846bf34383e5d08ae02。
- 原始逐文件指纹：FINGERPRINT_BEFORE.json / FINGERPRINT_AFTER.json，两组前后一致；target 为构建输出，不属于源码指纹。
- HEAD仍为f595262207796dbf325cb9951ed3dc02b4887362，仅历史存档；本轮无Git写入。
- 当前批准：5ca53dc27d3bb53b05e7b48932f7a39b8db387fb730f112fa6e6c031e69ec6cf。

## 实际命令与环境

Java：D:\jdk-17.0.19.10-hotspot\bin\java.exe，Microsoft OpenJDK 17.0.19+10-LTS，64-bit。
Maven：C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd，3.9.12；报告实际Java runtime为上述JDK17。
仅子进程设置 JAVA_HOME 和 MAVEN_OPTS=-Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8；未修改系统环境。Maven平台默认编码GBK，项目资源/源码显式UTF-8，日志流UTF-8；不将平台默认编码冒称UTF-8。

```text
"C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd" -o "-Dmaven.repo.local=C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.m2repo" --batch-mode --no-transfer-progress package -DskipTests
```

完整最终进程参数、cwd、起止时间、环境和退出码见 BUILD_EXECUTION_02.json；package-02 退出0，Maven BUILD SUCCESS。未 clean、联网下载、修改pom或借用主仓target。
stdout/stderr 分别以 BaseStream 原字节复制保存；LOG_MANIFEST.json包括空日志的大小和SHA256。
Maven提示JavaFX有效模型收集有6项warning，构建仍成功；未额外重跑-X或修改依赖。实际Windows依赖条目另有静态核验。

## 初次启动层失败保留

BUILD_EXECUTION.json 及不带02后缀日志为第一次调用，java身份退出0，maven身份和package启动命令均退出1，stderr为“拒绝访问”。当时无Maven构建输出、无source/target。
该次.NET ArgumentList对cmd命令串的引号传递有误，改为cmd原始Arguments后同一Maven和package参数成功；只修正调用包装，不改源码/配置/构建输入、不申请提权或绕过权限。旧日志不覆盖。
第一次记录中的空JSON对象来自PowerShell收集流复制任务返回值，不是额外进程或通过结果；最终有效执行以BUILD_EXECUTION_02.json为准。

## 产物与静态核验

runtime-jar-classpath只复制本snapshot新建target中的主JAR和lib；19个文件，合计113775917字节。
主JAR：ahakey-studio-1.0.0.jar，647266字节。
主JAR SHA256：97a5ae072c18a0ed229538fee7766426bd9f6c8ba807607aee10f141efa3052b。
ARTIFACT_MANIFEST.json列出全部文件、来源、大小和SHA256；每个复制后文件与本snapshot产物哈希一致。

STATIC_INSPECTION.json为只读ZIP/字节核验：
- Main、App、InspectorPane、DeviceStatus、BleManager及CP2/CP1服务入口存在；149个应用class均为Java17 major61。
- 8份资源与source/src/main/resources逐字节哈希一致，包括FXML、CSS、配置、日志和中英文文案。
- display.slot-local-note中英文内容为本轮中性本地说明。
- JavaFX17.0.10的base/controls/fxml/graphics Windows依赖齐全；graphics含glass/prism/font等Windows DLL。
- JNA包含win32-x86-64/jnidispatch.dll；SQLite包含Windows/x86_64/sqlitejdbc.dll；ONNX Runtime包含win-x64的onnxruntime及JNI DLL。
- 仅静态条目/字节核验，没有加载原生库、运行Main/App或操作设备。不把这些检查当全功能运行成功。

package日志明确Tests are skipped；656项是round9已有隔离证据，本次未重跑。不是EXE或安装包。

## 启动配方：只记录，未执行

工作目录必须为本token的runtime-jar-classpath；不用java -jar。JAR manifest仍保留pom产生的App入口，未改写；实际配方使用Main/classpath。

```powershell
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' '-Dsun.stdout.encoding=UTF-8' '-Dsun.stderr.encoding=UTF-8' '-cp' 'ahakey-studio-1.0.0.jar;lib/*' 'com.example.ahakey.Main'
```

包不附JRE、现场BLE桥接程序/配置或本地语音模型；本地识别依赖另列，不能宣称全功能自包含。原有系统语音路径不等于本地模型齐备。
源码/产物隔离不等于用户数据隔离；实际运行可能访问.ahakey、启动服务端口，退出停止桥接的既有行为未改。由DLA核验配对身份、用户数据备份/恢复和测试前置后再交Owner。
R5产品策略为当前连接精确r001响应自动准入，不再要求产品人工HEX确认；工程配对仍须核验实际HEX及桥接身份，不能由同名版本推断已刷最新固件。

## 交回DLA

用原工作区正式preview-finish绑定本目录运行包和日志/报告，PREVIEW_RECEIPT由工具生成，不手写。
本轮不修改全局路由，不改变旧报告、批准、起点、历史dirty或固件/桥接。未启动应用、安装Hook、连接/写设备、烧录、发布或Git写入。
UP-01/02、来源缺失事件、RT-03、BLE性能、完整应用和真实设备缺口继续保留；formal fresh、candidate、配对身份及Owner UAT分别收口。
