# WD-005 revision5 / round9 Preview 构建交接

## 当前状态与依据

原DLA actual review通过，R8-F1/F2关闭。formal high-impact fresh仍pending，verification.review按正式record-check记录pending并绑定R9实际审阅。全局仍VERIFY/DLA_REVIEW，next_actor=DLA，不手写路由；DIB只依据独立Preview令牌打包，不再次submit或调用formal build-open。

接续授权：evidence/20261021-wd005-r9-preview-continuation.md；沿用Owner已批准隔离Preview构建及本次“复审通过后再按正式权限推进新Preview”。原批准、起点、旧审阅和产物保留。

- token：preview-20261021T024920511394Z-2ae03d。
- status：build_authorized，preview-open退出0。
- 工作区指纹：98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9。
- 快照指纹：b33465cede33f144802676c9f9a141291775d8c0e580b846bf34383e5d08ae02。
- pack：79b4a6d87283e22acae6b537a106a9007f426caf06fb5fcda57b15ea49074087。
- 批准：5ca53dc27d3bb53b05e7b48932f7a39b8db387fb730f112fa6e6c031e69ec6cf。

令牌根目录：
C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261021T024920511394Z-2ae03d

源码为令牌根/source；目标运行目录为令牌根/runtime-jar-classpath。当前source/target不存在，没有本轮可运行包。

DLA只读核对两份实际指纹及累计35文件，当前工作区与snapshot已审文件全部逐字节一致。pom仅Git换行差异，UTF-8文本一致。START.preserved_foreign为空；既有外部桥接归属由foreign_acceptance保持，现场运行配置不复制入包。没有还原历史dirty或修改其登记。

## DIB构建范围

先读AGENTS、Builder/Harness Skills、START、当前批准与R9审阅、本交接。核对令牌未过期、源码指纹相符；使用原工作区Harness，不向快照补造STATE。只在本token的source执行离线package，不clean、不下载、不改源码/pom。

JDK文件已核实存在：D:\jdk-17.0.19.10-hotspot\bin\java.exe。
Maven已核实存在：C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd。
仅为构建子进程设置JAVA_HOME及MAVEN_OPTS=-Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8，不改系统配置。

实际拟执行命令（cwd=本token/source）：

```text
"C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd" -o "-Dmaven.repo.local=C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.m2repo" --batch-mode --no-transfer-progress package -DskipTests
```

pom package阶段为编译、资源、JAR与运行依赖复制，未绑定javafx:run。package会编译测试源码但不执行测试；656项是第九轮既有证据，不说本次重跑。离线缺依赖或其他构建阻塞保存日志回DLA，不下载或改pom绕过。

保留完整stdout/stderr原字节、起止时间、退出码、argv/cwd、实际Java/Maven身份及前后工作区/快照指纹。成功后只复制本snapshot新target主JAR和lib至本token/runtime-jar-classpath，禁止借用工作区或旧Preview产物。

静态检查Main/App/核心class、Java17 class版本、FXML/CSS、中英文新增display.slot-local-note、配置、JavaFX Windows及原生依赖条目；不加载原生库或启动应用。新增BUILD_REPORT、ARTIFACT_MANIFEST、STATIC_INSPECTION、BUILD_EXECUTION及原始日志/LOG_MANIFEST。完整文件清单含大小/SHA256及来源。保留空stderr，但正式--log绑定真实非空日志或可解析日志清单，不编造内容。

使用原工作区正式preview-finish（先--help）绑定本token、真实运行目录、日志、实际命令、Main/classpath入口和jar_classpath；不得手写PREVIEW_RECEIPT。失败保留真实日志，不覆盖冻结输入；成功交回原DLA。

## 启动配方仅记录，不执行

工作目录为新runtime-jar-classpath，PowerShell控制台和管道UTF-8。启动argv：

```text
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' '-Dsun.stdout.encoding=UTF-8' '-Dsun.stderr.encoding=UTF-8' '-cp' 'ahakey-studio-1.0.0.jar;lib/*' 'com.example.ahakey.Main'
```

不用java -jar；不修改manifest。包不含JRE、BLE桥接包/配置、本地模型，不称EXE或全功能自包含。源码/产物隔离不是用户数据隔离，实际运行仍可能访问.ahakey、开启服务/端口，退出停止桥接的旧行为保留。DLA产物核验后再说明测试前置、备份恢复和当前固件/桥接身份。

R5已移除产品人工HEX确认，按当前连接r001响应自动准入；不得照抄R7报告的人工确认步骤。工程配对仍需实际HEX核验，不由版本同名推定设备已刷最新构建。正式fresh、candidate、UP-01/02、来源缺失事件、RT-03、BLE性能、整应用和Owner UAT未因本次准备关闭。

禁止生产/测试/固件/桥接/Hook修改、规则或seal改动、冻结历史覆盖、Git写入、应用启动、设备连接/写入、烧录和发布。不得把旧Preview当新包。
