# WD-006 Preview 构建失败记录

DIB按DLA授权的preview token `preview-20261023T035100762491Z-0eeedd`、隔离source及指定参数执行打包脚本，没有改生产代码或冻结EXECUTION_REPORT，没有安装/启动/kill。

Maven生产和测试源码编译、package成功（Tests are skipped），jlink和app-image成功，脚本已通过launcher cfg中的API/native classpath检查。最后jpackage安装EXE步骤失败，实际进程退出1，原因是WiX light.exe返回216。安装目录没有成功EXE。既有输出全部保留。

工具记录身份：开始 `b32994`，Maven结束 `0c07ff`，失败 `2bf7e9`。PowerShell Start-Transcript产生build.log，但本管道环境该文件只有命令和头尾，不含原生工具输出；不能将其称为完整构建日志。下一次执行必须外层重定向/runner捕获原生stdout/stderr。

以下为工具实际捕获的失败诊断摘录，不冒充完整日志：
```text
java.io.IOException: Command [light.exe, -nologo, -spdb, -ext, WixUtilExtension, -out, C:\Users\20825\AppData\Local\Temp\jdk.jpackage7709202398802809126\images\win-exe.image\AhaKeyStudio-1.0.6.msi, -ext, WixUIExtension, -b, C:\Users\20825\AppData\Local\Temp\jdk.jpackage7709202398802809126\config, -sice:ICE27, -loc, C:\Users\20825\AppData\Local\Temp\jdk.jpackage7709202398802809126\config\MsiInstallerStrings_zh_CN.wxl, -cultures:zh-CN, C:\Users\20825\AppData\Local\Temp\jdk.jpackage7709202398802809126\wixobj\main.wixobj, C:\Users\20825\AppData\Local\Temp\jdk.jpackage7709202398802809126\wixobj\bundle.wixobj, C:\Users\20825\AppData\Local\Temp\jdk.jpackage7709202398802809126\wixobj\ui.wixobj, C:\Users\20825\AppData\Local\Temp\jdk.jpackage7709202398802809126\wixobj\InstallDirNotEmptyDlg.wixobj] in C:\Users\20825\AppData\Local\Temp\jdk.jpackage7709202398802809126\images\win-msi.image\AhaKeyStudio exited with 216 code
installer failed: 1
```

已存在的app-image launcher为 `target/WD006-LocalModel-20261023/image/AhaKeyStudio/AhaKeyStudio.exe`，SHA256 `2d7064299659d48c3b1180a490cc9f61135bb485f2ccf22b35fa3cbd02fd4b48`。这是便携目录内启动器，不是安装包；其运行时/模型probe交父DLA执行。完整实际路径和已存在文件SHA见同名JSON。
