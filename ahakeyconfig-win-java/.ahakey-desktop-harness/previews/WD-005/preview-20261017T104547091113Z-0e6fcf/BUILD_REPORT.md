# WD-005 第三轮隔离 Preview 构建报告

2026-10-17，DIB，PREVIEW_BUILD_ONLY。仅构建及静态包核验，未启动应用。

## 身份与授权

- token：preview-20261017T104547091113Z-0e6fcf。
- 依据：本目录START.json及changes/WD-005/PREVIEW_BUILD_HANDOFF_ROUND_3_20261017.md，Owner已授权本次隔离构建。
- revision=2，build_round=3；批准指纹0c7004e333198a9c167b49c16ac5933a55b06f61039e24c3c9de5c6724220b71。
- 原DLA actual pass对应pack b62fd48300896041a72ef5874dcdc6927734822f01cf3b8a1daf26428a3b84d0；不代表当前formal fresh通过。
- 工作区指纹aea60d8c7eb936cb937cc59522fed7224c845ecf7947cedb17e8f029ad1656c8。
- 快照指纹06dd1f39c426590e8e43ee717aa5069345670e550924747a6a7b91a348b1a194。
- 构建前后均用原Harness source_fingerprint只读函数核对，两个指纹未变。未更改生产/测试/资源/pom/固件/规则/seal、历史报告或批准。
- 全局路由保持VERIFY/DLA_REVIEW；使用Preview令牌，不调用formal build-open，不伪造IMPLEMENT路由。

## 实际构建

工作目录：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261017T104547091113Z-0e6fcf\source。

实测Maven 3.9.12，运行时Microsoft Java 17.0.19，Windows 11 amd64，默认编码GBK。
仅为构建进程设置JAVA_HOME，未改系统环境。实际命令：

```powershell
$env:JAVA_HOME = 'D:\jdk-17.0.19.10-hotspot'
& 'C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd' -o '-Dmaven.repo.local=C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.m2repo' package -DskipTests 2>&1 | Tee-Object -FilePath '..\BUILD_MAVEN_01.log'
$code = $LASTEXITCODE
"MAVEN_EXIT_CODE=$code" | Tee-Object -FilePath '..\BUILD_MAVEN_01.log' -Append
exit $code
```

实际进程退出0，BUILD SUCCESS，结束时间2026-10-17T18:53:21+08:00。
65份生产源码、3份测试源码被编译；Surefire明确Tests are skipped。
本轮没有运行283项断言；它们仍为第二轮证据复用。没有clean、网络依赖下载或模型下载。
日志保留JavaFX effective-model的6项警告；部分路径受编码显示影响，报告中的绝对路径为实际文件位置，未修饰原日志。

BUILD_MAVEN_01.log SHA256：0d13e5873b9a272f89210505f06fdf72aa1d77b94802162f8889bfa0daf01e79。

## 产物与静态核验

运行目录：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261017T104547091113Z-0e6fcf\runtime-jar-classpath。
复制的输入仅为本快照target/ahakey-studio-1.0.0.jar及target/lib，不混入主仓target、本机BLE配置或其他历史dirty。
逐文件核对复制前后SHA256相同。共19个文件：主JAR及18个依赖JAR；完整名称、大小及哈希见ARTIFACT_MANIFEST.json，正式PREVIEW_RECEIPT亦绑定实际文件。

主JAR为630336字节，SHA256为e8bbe9ee0dc3da54733d057c4bc2ab6ee8d12fa9bdc333290b4947f055e752e5。

- Main.class、App.class及显示配置/上传服务class存在，核对Java class major version=61。
- 八项源码资源全部存在且逐项SHA256相同：图标、日志配置、中英文文案、模型配置、CSS和两份FXML。
- JavaFX base/controls/fxml/graphics 17.0.10的win JAR与关键类存在；graphics包内含glass/prism等Windows DLL。
- JNA、ONNX Runtime、SQLite JAR含Windows x64原生库条目。本轮只读ZIP目录和字节，没有加载DLL或执行Java类。
- 依赖还包括Jackson、JNA Platform、SLF4J和Logback，详见清单。
- Manifest的Main-Class仍是App；启动配方改用现有Main包装类及显式classpath，不修改Manifest或源码，不采用java -jar。

PACKAGE_INSPECTION_01.log为本轮静态核验输出，SHA256：d1d85e73a8e4897eed025f93debeb649d97ed0ec443190d0b1809021a4c3c5a6。
这些检查不证明JavaFX实际渲染、原生库加载、完整应用启动或设备功能通过。

## 启动配方（仅交接，未执行）

由DLA确认启动前置及Owner授权后使用，不把本段视为当前启动授权：

```powershell
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261017T104547091113Z-0e6fcf\runtime-jar-classpath'
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' '-cp' 'ahakey-studio-1.0.0.jar;lib/*' 'com.example.ahakey.Main'
```

启动需要该外部JDK或另行确认的Java17运行时；包不附JRE。当前JDK身份已由Maven版本查询确认，应用启动没有实测。

## 外部依赖与恢复边界

- 不含BLE_tcp_driver.exe及其运行配套文件/本机配置。TopBar会搜索JAR同级、父目录和工作目录；本包不能直接宣称BLE路径可用。DLA应单独确认桥接来源及完整依赖后再安排BLE测试，不静默从主仓拷贝。
- 不含model_q8.onnx、tokens.txt等本地模型。当前包的model_config.properties只有status.poll.period.seconds=5，ModelConfig默认model.enabled=false，未为凑包修改配置。不能宣称本地语音可用，也不能将此JAR当成已验证Lite安装器。
- 系统语音、USB HID、Hook、窗口/DPI及设备行为均未运行验证；Windows原生API依赖目标系统环境。
- 隔离的是源码和产物，不是运行时用户数据沙箱：默认仍使用用户目录下.ahakey/studio-draft.json及.ahakey/oled-resources/v1，可能读取/保存既有偏好和草稿。DLA应先说明备份/恢复边界，不能承诺预览绝不影响已有数据。
- 启动会进入真实Controller生命周期并启动Hook分发服务；退出路径存在停止BLE_tcp_driver.exe的既有操作。DLA需核查同机旧实例/桥接与端口影响；DIB没有启动或停止任何这些进程，也不自动清理它们。
- 固件身份与实际刷入由DLA后续核对。CP2代码人工HEX确认边界不是已刷入证明；本轮没有连接或写设备。
- Preview失败时保留本目录包/日志并交DLA分类，不在冻结快照内修改代码，不自动删除用户草稿、恢复出厂或烧录。

## 流程说明

最初尝试给fingerprint CLI传隔离source目录，因快照没有STATE而退出，未改任何文件。随后按DLA交接要求调用原只读source_fingerprint函数核对成功，没有补造STATE或降低门禁。
本报告写入时等待正式preview-finish生成回执；以实际PREVIEW_RECEIPT及helper输出为准。原283项、fresh、完整UI、真实USB/BLE、设备掉电与UAT没有新增PASS。
不执行Git写入、不制作EXE、不发布、不安装Hook、不启动应用或烧录。回原DLA核对包与固件身份，提供中文Owner Preview步骤后才安排实际体验。
