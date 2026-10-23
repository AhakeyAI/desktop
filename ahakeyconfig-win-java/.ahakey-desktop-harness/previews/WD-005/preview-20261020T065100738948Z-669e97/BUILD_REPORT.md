# WD-005 revision4 / round7 Preview 构建报告

## 结论与边界

2026-10-20，DIB按token `preview-20261020T065100738948Z-669e97` 完成隔离离线package，退出码0。未启动应用、连接设备、运行测试、执行Git写入或制作EXE。507项是R7既有执行证据，本次没有重跑。

原DLA actual review已通过，formal fresh、candidate、正式配对与Owner UAT未由本构建证明。全局STATE保持VERIFY/DLA_REVIEW；未调用formal build-open、preflight实现准入或重复submit。独立START令牌为本轮构建授权。

## 输入与环境

- 工作区：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java`
- token根：上述工作区下 `.ahakey-desktop-harness\previews\WD-005\preview-20261020T065100738948Z-669e97`
- 输入：token根下 `source`，构建前不存在target；未clean、未混用主仓target。
- HEAD：`f595262207796dbf325cb9951ed3dc02b4887362`，仍仅源码存档。
- 工作区指纹：`e10b4d65ad9b3f62221b7790b659c09429243a96a43a169db575dce6b4c18e8a`
- 快照指纹：`5683e49cf090a14c1a56159617408ce3a444a6d0f0b107732c459958b5d5bd62`
- 有效批准：`24063e69998760c474b5c3ab426fd1999f40f3724a891337fe2c4dd8b4ffc781`
- JDK：Microsoft OpenJDK 17.0.19+10-LTS，`D:\jdk-17.0.19.10-hotspot`
- Maven：3.9.12，`C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd`
- 实际版本输出见java-version与maven-version的stdout/stderr日志。

构建子进程仅设置JAVA_HOME与MAVEN_OPTS，后者为 `-Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8`。日志按子进程原始字节分别保存，避免PowerShell重编码。没有改系统环境或Maven默认file.encoding，版本报告平台编码GBK，pom源码/资源编码UTF-8。

实际命令（cwd为source）：

```text
"C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd" -o -Dmaven.repo.local=C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.m2repo --batch-mode --no-transfer-progress package -DskipTests
```

`BUILD_EXECUTION.json`保留完整argv、命令、cwd、起止时间、退出码及环境。package编译65个生产源码、9个测试源码，明确输出Tests are skipped。未下载。日志存在JavaFX effective model的6项警告，本轮未增加调试重构建，不能把构建成功理解为零警告或运行验证。

## 产物与静态核验

运行目录：token根下 `runtime-jar-classpath`，仅复制本snapshot新生成的主JAR和target/lib，共19个文件。

主JAR：`ahakey-studio-1.0.0.jar`

SHA256：`c0b3f122fc2f69021514e5ed910265ef1b3c205f722da14f105dfc87b00022b1`

完整文件、大小、SHA256和来源见 `ARTIFACT_MANIFEST.json`，全部逐文件与snapshot target比对一致。

`STATIC_INSPECTION.json`记录：
- Main/App/BleManager/DisplayConfigService/OledUploadService/AiRuntimeDisplayService存在，class major=61（Java17）。
- 8个资源与snapshot源码逐字节相同，含键盘图片、两个FXML、CSS、中英文文案、日志及配置。
- 主JAR不含displayconfig测试类。
- JavaFX base/controls/fxml/graphics的Windows变体存在；graphics内含glass/prism等DLL。
- JNA含win32-x86-64/jnidispatch.dll，SQLite含Windows/x86_64/sqlitejdbc.dll，ONNX含win-x64的runtime及JNI DLL；仅静态目录核对，未加载。
- JAR manifest入口仍为App；配方按现有Main/classpath启动，不修改manifest，不使用java -jar。

`FINGERPRINT_BEFORE.json`、`FINGERPRINT_AFTER_BUILD.json`、`FINGERPRINT_AFTER_COPY.json`证明工作区和snapshot指纹均不变；复制后STATE字节与HEAD亦与构建前一致。这些是观察绑定，不是可复现构建证明。

## 仅记录的启动配方

以下未执行。DLA核验配对和用户数据风险后再给Owner测试说明：

```powershell
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261020T065100738948Z-669e97\runtime-jar-classpath'
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' '-Dsun.stdout.encoding=UTF-8' '-Dsun.stderr.encoding=UTF-8' '-cp' 'ahakey-studio-1.0.0.jar;lib/*' 'com.example.ahakey.Main'
```

## 外部依赖及回交

包不附JRE、现场BLE_tcp_driver.exe/配置、本地语音模型或用户数据，不称全功能自包含。Windows系统HID/SetupAPI/Kernel32及系统语音依赖仍在；旧Sherpa加载器提及的外置库未打包、未验证，该目录存在不代表当前调用链通过。源码当前本地语音模型查找包括models/model_q8.onnx、models/tokens.txt，本轮未补模型。

源码/产物隔离不是运行数据隔离：实际启动仍可能使用用户.ahakey数据、打开真实服务及端口；退出仍有停止BLE_tcp_driver.exe行为。DLA须说明旧实例、数据恢复及桥接影响，不能直接把本报告当Owner测试许可。

CP2人工确认的既有固件SHA `D7D10510482228B74A2978BD8272F6A4E32668CF6B4F31F491A8503B0DC11E2E` 来自本轮交接，未在本轮重新核对固件仓或已刷设备。DLA主动只读核对当前固件/桥接配对身份，不让Owner搬运仓库已有事实。

上传根因、来源缺失事件、RT-03、BLE性能、完整应用、fresh独立审阅、candidate和Owner UAT仍需分别收口。正式PREVIEW_RECEIPT只能由preview-finish生成。本报告与manifest/logs为新增阶段证据，不修改冻结实现报告。
