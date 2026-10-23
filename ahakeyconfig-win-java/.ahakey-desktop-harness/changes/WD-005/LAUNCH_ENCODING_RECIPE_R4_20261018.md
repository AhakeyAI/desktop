# WD-005 revision 3 进程级 UTF-8 配方

本轮仅独立编码探针已执行；没有运行真实应用。供 DLA 在下一份合法新 Preview 启动配方中采用，不授权启动旧包或当前 target 应用。

## 已实际执行

工作目录：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java。

```powershell
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' `
  '-Dfile.encoding=UTF-8' '-Dsun.stdout.encoding=UTF-8' '-Dsun.stderr.encoding=UTF-8' `
  -cp 'target/test-classes;target/classes;target/lib/*' `
  com.example.ahakey.displayconfig.DisplayConfigEncodingProbe `
  .ahakey-desktop-harness/evidence/20261018-wd005-r4-encoding-file.log `
  1> .ahakey-desktop-harness/evidence/20261018-wd005-r4-encoding-stdout.log `
  2> .ahakey-desktop-harness/evidence/20261018-wd005-r4-encoding-stderr.log
```

实际进程退出码0；三个文件使用严格 UTF-8 解码均包含完整样本“中文编码样本：上传并应用，草稿已保留。”。stderr含 System.err 和 JUL，file为JUL FileHandler。探针给两个JUL Handler显式UTF-8，不宣称覆盖产品全部第三方logger。生产测试日志也已使用新进程UTF-8输出；未改原 logback.xml 或已正确编码的历史日志。

## 新 Preview 配方合入条件

- DLA先获得本轮实际审阅通过及合法Preview令牌；构建者绑定新JAR、lib、运行依赖及工作目录，不把本说明当产物回执。
- 仅对该次 PowerShell 进程设置上面两行输出编码，Java入口仍使用正式回执中的 Main/classpath，在入口前增加上述三个 -D 参数。不能将旧Preview路径替换成当前target冒充新包。
- stdout/stderr日志落在新令牌目录，新进程默认文件编码UTF-8；已有Logback编码器沿用其既有配置。DLA需在真实新包启动时复查JUL、stdout/stderr、日志文件；本次仅探针/隔离服务验证。
- 不修改系统区域、注册表、PowerShell profile、系统JAVA_HOME、用户配置或历史日志编码。
- 不把应用配方的 file.encoding 标志强套给旧Maven缓存：本轮试验中旧 inputFiles.lst 是原默认编码，强设UTF-8会读取失败。最终离线编译保留Maven默认文件编码，仅其控制台输出设UTF-8；没有clean或删除缓存。

本说明不是当前Owner可立即使用的启动命令；没有新包，不要求Owner现在测试。
