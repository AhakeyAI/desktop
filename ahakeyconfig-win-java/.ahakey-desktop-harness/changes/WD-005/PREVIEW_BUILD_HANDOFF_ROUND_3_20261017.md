# WD-005 第三轮隔离 Preview 构建交接

## 实际授权及状态

Owner授权仅构建隔离可运行预览包；DLA已完成当前批准下原DLA实际审阅。根REVIEW更新另获Owner明确授权，旧字节保存不变。formal fresh仍pending当前pack，不把旧fresh移植。未构建、未启动应用、未写Hook/设备、未执行Git写操作。
正式preview-open已成功：token preview-20261017T104547091113Z-0e6fcf。
全局STATE仍为VERIFY/DLA_REVIEW；Preview令牌独立授权build-only，不手改STATE或用formal build-open绕过candidate。
START的basis_kind=formal_review是helper对原DLA审阅来源的分类，不代表当前formal high-impact review门已通过。

## 固定输入

- 源码：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\\.ahakey-desktop-harness\\previews\\WD-005\\preview-20261017T104547091113Z-0e6fcf\\source
- build_round=3；revision=2；HEAD=41c034171e60b2d4962b0adbe8f3cffbf80a0436。
- 当前工作指纹：aea60d8c7eb936cb937cc59522fed7224c845ecf7947cedb17e8f029ad1656c8。
- 快照指纹：06dd1f39c426590e8e43ee717aa5069345670e550924747a6a7b91a348b1a194。
- 批准：0c7004e333198a9c167b49c16ac5933a55b06f61039e24c3c9de5c6724220b71。
- 当前pack：b62fd48300896041a72ef5874dcdc6927734822f01cf3b8a1daf26428a3b84d0。

DLA已通过Harness source_fingerprint核对工作区/快照，并逐字节核对24个审阅文件一致；快照生产清单84项。Snapshot由HEAD重建，仅覆盖allowed_paths；START.preserved_foreign为空，并不声称已有单独foreign登记。工作区历史dirty及本地BLE配置没有被恢复或覆盖。

## DIB构建步骤

1. 读取适用AGENTS、builder/harness Skill及正式Preview规则、START、当前审阅与本记录。先以Harness source_fingerprint核对固定快照；不改生产/测试/pom/资源来修构建。
2. 仅在source目录构建；临时JAVA_HOME=D:\\jdk-17.0.19.10-hotspot，Maven可使用C:\\Program Files\\apache-maven-3.9.12\\bin\\mvn.cmd。主仓.m2repo缓存已存在，使用绝对缓存路径。先离线 package -DskipTests，保留实际命令、JDK/Maven身份、完整stdout/stderr和退出码；不clean主仓target、不下载模型。离线依赖缺失如实交回，不自行扩大下载或修改依赖范围。
3. 目标为runtime-jar-classpath，不制作EXE。pom的package产出target/ahakey-studio-1.0.0.jar及target/lib；复制到令牌目录下新的runtime-jar-classpath。核对JavaFX win平台运行依赖、Main.class、FXML/CSS/文案及资源；外部BLE工具/语音模型等缺失必须单列，不伪称全功能自包含。不要把主仓本机私有配置静默混入快照或包。
4. 在令牌目录（source之外）保存BUILD_REPORT.md和完整构建日志、SHA256清单，记录未启动应用。启动配方应基于com.example.ahakey.Main与主JAR/lib通配classpath，避免直接java -jar触发JavaFX缺失；核对打包字节但不要执行启动配方。
5. 构建后再次以Harness source_fingerprint校验快照仍等于START，工作区指纹未变。构建输出只在snapshot的target及本令牌产物目录；禁止在源码目录添加README等导致身份变化的文件。
6. 在主仓执行正式desktop.py preview-finish --id WD-005 --token preview-20261017T104547091113Z-0e6fcf --role DIB --runtime-kind jar_classpath，并以实际值填写--artifact、--log（均主仓相对路径）、--command、--entrypoint。日志必须有实际成功结果；失败则保留失败日志，不能登记ready。不要用build-open/build-finish或重写冻结EXECUTION_REPORT。
7. 回交原DLA：PREVIEW_RECEIPT、JAR/依赖清单及SHA、构建日志、启动配方、缺失依赖与恢复注意事项。DLA再核对固件身份和中文测试清单；打包本身不是完整UI/USB/BLE/Owner UAT通过。

## 设备边界

固件只读来源C:\\Users\\20825\\Desktop\\vibe-code。当前代码的CP2人工HEX准入SHA为D7D10510482228B74A2978BD8272F6A4E32668CF6B4F31F491A8503B0DC11E2E，绑定当前连接；不能用版本号或0x88推断实际刷入。DIB此轮不做设备身份确认操作、不连接/写设备、不烧录。正式配对与Owner测试由DLA后续准备。

## 禁止与返回

不改主仓或快照生产/测试/固件代码、规则、seal、批准、起点、原报告/旧审阅/fresh；不Git写、不启动应用、安装Hook、设备写入、烧录、发布。真实阻塞交回DLA，不扩大CP1.5或自修功能。
283项为复用第二轮175+36+72，不是本次重跑；重复时序72不重复计数。
下一次交接必须在聊天正文完整显示发往原DLA的中文提示词。
