# WD-005 R7 Preview build-only 交接

## 当前结果

原DLA第七轮actual review已通过，R5-F1关闭；正式high-impact fresh仍未完成，verification.review已通过record-check登记pending并直接绑定本轮实际审阅证据。旧root REVIEW已按原字节保存在 reviews/20261020T063958914747Z-fa224e/REVIEW_ENTRY_BEFORE_R7.json，当前入口与DLA_ACTUAL_REVIEW_R7_20261020.json一致。全局仍VERIFY/DLA_REVIEW、next_actor=DLA；Preview令牌授权是独立build-only依据，不手改IMPLEMENT路由。

Owner授权见 .ahakey-desktop-harness/evidence/20261020-wd005-r7-review-preview-owner-authorization.md。

正式preview-open退出0，token=preview-20261020T065100738948Z-669e97，build_round=7，status=build_authorized。

令牌目录：
C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261020T065100738948Z-669e97

源码快照为上述目录下source，目标运行包为同级runtime-jar-classpath。当前尚未构建，不声称目录内已有JAR。

工作区源码指纹：e10b4d65ad9b3f62221b7790b659c09429243a96a43a169db575dce6b4c18e8a。
隔离快照指纹：5683e49cf090a14c1a56159617408ce3a444a6d0f0b107732c459958b5d5bd62。
当前批准：24063e69998760c474b5c3ab426fd1999f40f3724a891337fe2c4dd8b4ffc781。

DLA已只读验证两份指纹以及33个已审文件与snapshot字节全部匹配。首次组合核验命令退出1，定位为pom原字节比较失败：snapshot来自Git的LF、工作区为CRLF；UTF-8规范化换行后内容完全一致，未修文件或放行其他差异。已静态读取pom，package只有编译/资源/JAR/运行依赖复制，javafx:run未绑定package。入口使用现有Main，不用java -jar。

## DIB允许操作

读取适用AGENTS、Builder/Harness Skills、START、当前批准、R7审阅与本交接。使用原工作区Harness脚本，不给snapshot补造STATE；不调用formal build-open或重复submit。只读source_fingerprint函数可核对snapshot；前后两份源码指纹必须保持一致。

临时为本构建进程设置：

```powershell
$env:JAVA_HOME = 'D:\jdk-17.0.19.10-hotspot'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$env:MAVEN_OPTS = '-Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8'
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261020T065100738948Z-669e97\source'
& 'C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd' -o '-Dmaven.repo.local=C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.m2repo' --batch-mode --no-transfer-progress package -DskipTests
```

自行以原生工具保存真实完整stdout/stderr、退出码、JDK/Maven实际身份到新令牌目录，不覆盖旧日志。不得clean、下载依赖/模型、改pom或源码。离线缺依赖则停止回报，不去网络补装。package会编译测试源码但不执行测试；507项仍为第七轮既有结果，不能说本次打包重跑。

成功后只从本snapshot的target复制主JAR和lib到本token/runtime-jar-classpath。静态核对Main/App/关键服务class、Java17 class版本、FXML/CSS/文案/配置、JavaFX Windows与原生依赖条目，生成完整文件/大小/SHA256清单；不得拷入主仓target、用户数据或现场BLE包。

独立保存BUILD_REPORT、ARTIFACT_MANIFEST、构建/静态核验日志、前后指纹，随后从原工作区调用正式preview-finish（参数以--help确认），绑定本token、真实runtime目录、日志、实际命令及Main/classpath入口。不得手写PREVIEW_RECEIPT；失败保留日志交DLA，不改冻结快照。

## 只记录，不执行的启动配方

运行工作目录应为实际runtime-jar-classpath，PowerShell编码同上：

```powershell
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' '-Dsun.stdout.encoding=UTF-8' '-Dsun.stderr.encoding=UTF-8' '-cp' 'ahakey-studio-1.0.0.jar;lib/*' 'com.example.ahakey.Main'
```

包不附JRE、BLE_tcp_driver.exe/配置、本地模型，不称自包含或EXE通过。隔离只涉及源码/产物，运行仍可能使用用户.ahakey数据、启动真实服务，退出有停止桥接的旧行为；DLA交测前说明数据/旧实例/端口与恢复。

CP2代码仍要求人工确认既有D7D10510482228B74A2978BD8272F6A4E32668CF6B4F31F491A8503B0DC11E2E固件身份；新固件/桥接配对由DLA核对，不因构建成功推断已刷/性能/RT-03通过。仅构建不需要接触设备，也不需要Owner再次提供仓库已有事实。

禁止生产/测试/桥接/固件修改、规则/seal改动、旧报告/起点/批准覆盖、Git写入、启动应用、Hook安装、设备连接/写入、烧录或发布。完成后交原DLA核验产物和中文测试说明；formal fresh、candidate和UAT仍分层完成。
