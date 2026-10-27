# R13 完整本地模型 1.0.12 Preview 构建

构建与最终包内验证通过，待DLA交付Owner测试；不是正式UAT通过。

- Preview token：preview-20261026T105435810998Z-dfc116
- 实际EXE：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\WD006-R13-LocalModel-1.0.12\installer\AhaKeyStudio-1.0.12.exe
- EXE大小：296237624 字节
- EXE SHA256：21de9ab7c4e5c5b915cbd92c7f0f3d62b003ef90f9df20ceb962b46ae0b36af7
- 包内JAR：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\WD006-R13-LocalModel-1.0.12\image\AhaKeyStudio\app\ahakey-studio-1.0.0.jar
- JAR SHA256：7ec21ce3538cd5a1eb0efb6749118bba03567197d296933704b7c6ed3a54b340
- 新ProductCode：{E21DA129-27AB-4186-AC82-627016B26DD2}
- buildId：96d9a365a0296b9dcf5e4e5f9782f13cd6cd706ab4ff4884a21c37c5a664a988
- 固定UpgradeCode：{03E5A934-FFCA-3815-B455-7D49BF1CA1DC}
- 实际MSI SHA256：75ce8e73b5076aeecd62de10cdf15c3762bb221590ecf3e7d4b3193fe099cec7

## 构建输入与验证
163个已审阅Preview快照文件逐字节复制到独立target目录，另补13个不变的R12已审安装配方文件；与当前工作区/R12来源/构建输入逐项同hash，全部清单在source-manifest.json及报告JSON中。未改snapshot/helper。新输出保留R12。

完整Maven编译打包成功。EXE实际MSI提取的313项安装载荷与app-image全部一致；31项资源仅允许model_config与app-release两项构建覆盖；固定模型/JNI、96项BLE运行文件、13项WCH文件、DTF5.0.2及安装序列校验通过。新buildId依配方实际输入复算吻合，RSA发行封套由Java/worker验证；Authenticode仍NotSigned。

最终JAR四个改动类家族共14项class字节与本快照完整编译输出相同；包内JVM核对实际身份与类来源。原始两份现场记录直接回放成功；79项解析/回执检查通过；23项隔离实际窗口关闭检查通过，包括未知进程拒绝、后台清理、重复点击和晚到回调遇新维护。按派工不重复无关语音WAV检查。

## 限制与保留
本轮未安装/写设备/运行WCH/驱动/完整App.start或shutdown/kill；实际verify与正常重连版本回读仍待Owner。源快照、生产工作区、冻结实现/正式构建报告、Git HEAD/真实索引及R12 EXE保持原样。只登记独立Preview回执，不覆盖R12 formal BUILD_RECEIPT。全部命令、真实退出码、日志、补充配方依赖及后检见同名JSON。
