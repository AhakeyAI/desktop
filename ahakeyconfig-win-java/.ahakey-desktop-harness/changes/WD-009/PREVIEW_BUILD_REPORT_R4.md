# WD-009 Hook 修正 R4：完整本地模型 1.0.19 Preview 构建报告

完整安装包已构建并通过包内离线检查。本报告仅描述 Preview 构建，不是正式发布、Git candidate 或 Owner 真机/安装验收。冻结 EXECUTION_REPORT 和 R2/1.0.18 报告、旧包均未修改。

## 授权和来源

Preview token：`preview-20261103T072949372746Z-2afea7`，build_round 4，DLA实际与独立审阅通过。冻结实现 fingerprint `b184b8b7478757a45d39a65e803a677914a1ab8eb2c7d17a24704e6cedc47775`，snapshot fingerprint `353270a525a556791fc080228dcc33b4d646136091a4d9bbe9979e39b46d91fd`。构建后逐项复核冻结源码、snapshot 和派生源输入未改变。

全新派生源 `C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\WD009-Preview-Source-R4-1.0.19`，187 个输入：本轮 snapshot（含新 pom）加13个已核对当前Git保存基线与1.0.18成功来源字节相同的安装配方。没有旧target缓存。仅恢复已知WCH chiplist及内置HEX的CRLF原字节，并先验证与snapshot仅换行不同。bridge patch保持本轮build02匹配字节；没有用旧pom或旧patch覆盖本轮输入。

构建用既有package-local-model.ps1、现有模型/native/DTF、固定发行签名key。完整参数见 `target/wd009-preview-build-04/COMMAND.json`，命令 `pwsh -NoProfile -File target/wd009-preview-build-04/run_package.ps1`。延续此前已批准的隔离沙箱外WiX构建方式，保留ICE验证，没有关闭安全软件、修改系统设置或安装产品。离线Maven package、jlink、jpackage EXE、MSI提取、Java/worker双发行签名校验与MSI结构检查全部成功，exit 0。

## 最终成品

- 路径：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\WD009-Preview-R4-LocalModel-1.0.19\installer\AhaKeyStudio-1.0.19.exe`
- SHA256：`a4d4d880fc163d8372573c9b62023b444cdae11b057bccce261a8b831ccaf7e3`
- 大小：296757816 bytes。
- 身份：1.0.19 / local-model / x64，ProductCode `{0A9DA92B-B51C-421F-A4A6-C42BCF4B9F5F}`。
- MSI SHA256：`524089e2e0a4d5d59e0fa9e49b3ed63ad90d1138b56afd0f63f1d1b9c9572640`。
- 包内主JAR SHA256：`22d37934b5ad79f3ca3eb41e053642af4bb1adbf084a5e1c0b631b3e78af1f95`。
- BLE桥SHA256：`90ee250231048a1af7e0511881dfc924e6ec9e6dca9aa30019156abcd55e303d`，与R2 build02和1.0.18相同。
- 固定应用发行签名有效；Windows Authenticode仍为NotSigned，两者不混称。

## 包内实际验证

完整app-image共317文件，测试后所有PACKAGE_IDENTITY文件哈希逐一重验一致。新依赖tomlj1.0.0、antlr4-runtime4.7.2、jsr3053.0.2全在包内lib，字节与R4已记录缓存一致；不需用户另装依赖。源配置保持原值，最终主JAR确认model.enabled=true且release version=1.0.19。模型3项、Sherpa/native、WCH13项及内置HEX沿用严格校验。

使用最终包自己的runtime/bin/java.exe、主JAR、lib运行测试，classpath仅额外加入隔离测试classes，不含任何实现classes。测试源码重新针对包内依赖编译成功；测试类未混入产品JAR。

11组均exit0：Hook管理135、Hook UI23、Kimi路由44、审批事实53、Cursor等待148、既有UI42、WD008固件身份85、Display175、K1路由、备份恢复、维护。Hook测试仅隔离user.home；UI中的源码接线检查不冒充真实渲染。实际本机Kimi consumer原函数通过包内Java的23场景回放全部通过（内存USB/BLE、延时/超时、换代次/维护）。详细结果和SHA链在 `target/wd009-preview-build-04/BUILD_RECEIPT.json`。

## 待 Owner 测试

本轮没有安装软件、写真实用户Hook、启动/杀真实桥、发送系统按键、修改或烧录键盘。真实Hook平台回调、安装/原路径升级、本地模型推理、三固件×USB/BLE、Cursor灯效和UI渲染仍待Owner验收。本包交测前请正常退出旧软件/旧BLE桥；新服务遇9000占用会持续提示，不能声称已接管。

本轮构建一次成功；历史1.0.18 R1–R3失败与证据保持，R4实现中的失败及修正见冻结EXECUTION_REPORT和IMPLEMENTATION_CHECKS_R4。最终preview-finish回执另存，不回写实现报告。
