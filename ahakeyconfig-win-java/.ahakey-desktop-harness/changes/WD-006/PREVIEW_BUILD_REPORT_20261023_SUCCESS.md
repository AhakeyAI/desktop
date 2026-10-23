# WD-006 带本地模型 Preview 构建成功记录

对应token：preview-20261023T035100762491Z-0eeedd。代码/资源来源为该token的隔离source与固定资源manifest；本记录属于BUILD阶段，不修改已冻结EXECUTION_REPORT或产品源码。

## 实际执行与首次失败

DIB /root/voice_builder 按已审阅scripts/package-local-model.ps1及DLA指定参数执行；Maven编译/package、jlink和app-image成功，官方API/native launcher classpath检查成功。最后安装器的WiX light.exe在沙箱内返回216，脚本退出1。失败事实和已存在app-image保留于PREVIEW_BUILD_FAILURE_20261023_01.{md,json}；不覆盖历史失败。

父DLA /root 随后检查到ICE验证访问Windows Installer服务在沙箱内失败，在沙箱外对同一app-image重试相同jpackage安装器生成步骤，实际退出0。完整原生日志INSTALLER_VALIDATED_20261023.log证明正常WiX验证成功；没有为通过而禁用ICE校验，jpackage默认ICE61/ICE69警告如实保留。首次Start-Transcript未完整捕获原生输出的限制仍保留，成功重试日志另行完整捕获。

## 交付产物与内容

安装器：target/WD006-LocalModel-20261023/installer-validated/AhaKeyStudio-1.0.6.exe，288016896字节，SHA256 d34607c4b3cee9650006dc55669f52db250346e0bd0f558f34d5db4df8b07a48。本DIB追加本报告前实际重算安装器SHA和大小一致。

完整app-image：target/WD006-LocalModel-20261023/image/AhaKeyStudio。内含启动器、JRE、app JAR、依赖、模型及许可证；不可只复制其中启动EXE。启动器SHA256 2d7064299659d48c3b1180a490cc9f61135bb485f2ccf22b35fa3cbd02fd4b48。

主线源model.enabled=false未变，staged JAR为true。官方Sherpa1.13.3 API/native及固定Paraformer encoder/decoder/tokens均在包内。

## 父DLA实际机器验证、本DIB读取绑定

1. 使用包内JRE、app.jar、lib及模型执行SpeechNativeCheck，对真实WAV重复识别并release，退出0；日志PACKAGED_RUNTIME_WAV_20261023.log记录中英混合可观察输出及PASS。这是包内运行时验证，没有启动GUI、用户麦克风或键盘注入。
2. 使用dark只读解包MSI，193个payload文件逐项SHA与上述已测app-image一致；PACKAGE_IDENTITY_20261023.json绑定完整文件清单、模型配置、安装器SHA与runtime日志。DIB没有声称亲自执行父DLA的运行时probe/解包。

## Preview边界

此产物为OWNER_PREVIEW_ONLY_NOT_FORMAL_UAT。用户可运行安装EXE体验；尚未实际安装、启动GUI、F18录音或设备联调，旧安装升级/配置保留未替Owner验收。安装EXE构建成功不等于Owner UAT或发布通过。没有修改冻结实现报告、产品代码，没有自动安装、运行GUI、杀进程或设备操作。
