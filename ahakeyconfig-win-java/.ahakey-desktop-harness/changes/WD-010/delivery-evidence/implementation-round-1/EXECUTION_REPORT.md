# WD-010 执行报告

2026-11-05，DIB / IMPLEMENT，第1轮。云端账号、AhaType final 管线及设备恢复实现完成，提交 DLA 实际审阅。本报告不是 DLA 审阅、正式固件回执、真机、付款或 Owner UAT 结论。

## 身份与范围

仓库：C:/Users/20825/Desktop/windows软件代码/desktop/ahakeyconfig-win-java。HEAD：70ccc3361ecd90e6c67828bac581a6975ebdccb2，分支codex/win-zxy-work；本轮没有Git写入，尚无WD-010 Git candidate。

保留起点指纹：b184b8b7478757a45d39a65e803a677914a1ab8eb2c7d17a24704e6cedc47775。最终指纹及逐文件SHA见evidence/IMPLEMENTATION_CODE_IDENTITY.json。37个变化文件（30个产品/资源/POM，7个测试）均属于批准的34个路径/目录。使用已批准revision 1 / J007、J017、J018、J019；未改Contract、批准或Harness核心。原有BLE bridge和其他任务脏文件保留，Firmware/eternal未写入。环境Java17.0.19，Maven缓存.m2repo；新增ZXing core3.5.3用于真实二维码编码，没有下载语音模型。

## 实际差异

1. AhaTypeConfig、WindowsCredentialStore：DPAPI加密账号配置；旧明文在原子替换成功后才加载，失败保留原字节且不覆写。取消记住密码删除保存密码；退出使内存会话立即失效。保留历史环境变量优先级和已核验接口。
2. AhaTypeService、CloudAccountManager、CloudAccountDialog：单实例账号窗口、登录/注册、真实资料刷新、额度/有效期、兑换、历史三类套餐、独立微信二维码和限时查询。写成功与资料刷新失败分开，未知结果不自动重发。用户确认时冻结Session；旧登录/兑换/订单/查询不能应用到新账号。401资料刷新回到登录页，普通登录失败保留输入。历史数值字符串、camelCase、业务code/data过期及支付状态映射已覆盖。readyStatus与实际process共用资格判断，已知到期/额度用尽如实显示且不误注销；当前请求更新整理中/回退状态，旧Session不得覆盖。
3. VoiceInputManager：仅本地识别final异步整理，partial不上传；保留录音代次、单次最终输出承诺。成功只输出整理结果，失败只回退一次原文；取消、下次录音、关闭、退出/换号后不交付旧结果，包括原文回退。HTTP请求20秒、连接15秒。
4. FactoryResetProtocol：严格查询v1/sub30与启动v2/sub31，核对17字节响应、nonce、attempt、状态。共用0x9E保留K1解析；覆盖USB/BLE二进制拆帧。修复真实图片读回暴露的0x83固定长度和mode0解析。
5. FactoryResetService/Store/State/Dialog：服务拥有恢复任务，确认默认取消；持久化最小意图→丢弃草稿→只发一次启动。不以ACK/断连表示完成。未知/未完成/读回失败保留记录及只读，关闭窗口不取消任务，重启不重发。明确拒绝旧attempt表示未启动，经当前配置读回后才解除只读，允许另行显式确认。
6. 人工关联绑定任务ID、attempt、Target/transport/generation，弹窗期间换USB使凭证失效。可靠同BLE地址才自动关联，明确不同设备不可人工覆盖。未知USB在异步quarantine前也由传输边界阻止写入。
7. 工厂专用只读权限先读真实catalog，再读16普通键、4完整K1路由、4图片选择、拨杆、待机、状态、亮度、36灯效、19条基础及完整性metadata。全部成功后应用UI并保存；失败不解锁，不用本地默认填充。无独立读口的固件内部字段仍依赖固件COMPLETE语义，未声称独立验证。
8. DeviceMaintenanceCoordinator、BleManager、K1、显示队列/草稿失效；setDisplayMode/onDeviceReady在真正发送锁内核对维护epoch，迟到FX回调同样核对。旧MULTI不能在解锁后补发。保存、Inspector、模式切换和待核实入口接入原UI，不重设计应用。

## 实际检查

完整命令、独立home、退出码、覆盖数及日志SHA见evidence/EXECUTION_EVIDENCE.json；全部日志和ui-02截图哈希见evidence/LOG_MANIFEST.json。网络仅本地HttpServer和合成账号；设备仅内存端点；DPAPI实际调用Windows API但不读取用户账号文件。

- mvn -Dmaven.repo.local=.m2repo -DskipTests test-compile：compile-08.log exit0；102个产品源码、42个测试源码。编译不是测试或打包。
- CloudChecks-04：52项；DPAPI迁移/失败保存原字节、实际20秒HTTP超时、数值字符串/camelCase、过期/额度/空响应、账号代次及状态显示。
- VoiceFinalChecks-04：32项；真实AhaType→VoiceInputManager→捕获输出，final一次、取消/下一次/退出/换号、成功/异常/服务端过期迟到。
- RestoreChecks-03：603项；协议/拆帧/边界、持久化失败、拒绝/丢回复/attempt不符/未完成显式重试、清记录失败、重启/人工关联换USB/明确不同BLE、损坏记录。
- RestoreProductionUiChecks-02：21项；真实Controller/TopBar/生产adapter/JavaFX和内存USB，全字段读回含Mode4合法空配置；最后metadata故障保持只读；重查零恢复写入；UNKNOWN身份在工厂锁内读真实catalog。
- CloudUiChecks-02：7项；真实FX事件→HTTP，401回登录页、失败保留输入、兑换拒绝可手动重试、排队兑换换号零请求。
- RuntimeRestoreRaceChecks-01：7项；真实setDisplayMode/onDeviceReady线程阻塞在传输monitor，跨恢复epoch解锁后旧0x98/0x99零帧，旧回调不恢复MULTI。
- 既有相关回归通过：SpeechLifecycleCheck37、CursorWaitingChecks148、HookManagementChecks135、Wd009UiChecks42、Wd009HookUiChecks23、DisplayConfigIsolationChecks64、DisplayConfigRaceChecks72、FirmwareIdentityCompatibilityChecks85、WindowCloseChecks23，以及K1RouteProtocolChecks、DeviceMaintenanceChecks。日志逐项保留，旧测试未修改。
- git diff --check -- src/main pom.xml src/test/java/com/example/ahakey/wd010 exit0；DIB preflight再次通过。

### 额外旧检查失败：保留，不计PASS

DisplayConfigCapabilityChecks-01在C04-basic-version-fallback-false失败(exit1)。旧检查要求精确V1.2，既有产品附加“完整标识未读到”。替换为HEAD原始DeviceStatus也失败；未修改1.0.19成品JAR/lib运行同一检查同一行失败(exit1)，见DisplayConfigCapabilityChecks-old-1.0.19-01.log。现行FirmwareIdentityCompatibilityChecks85项通过。

K1RouteEditorChecks-01、带独立退出包装器的K1RouteEditorChecks-02均在old early K1 read cannot authorize unknown capability失败(exit1)。同一旧测试在未修改1.0.19包也在connectionOrdering第45行失败(exit1)，见K1RouteEditorChecks-old-1.0.19-01.log。本轮不改旧检查或既有无关K1语义；DLA应判断后续是否单列历史测试维护。首轮测试进程后来自行退出，未kill进程。

HookManagementChecks-01因隔离home名称不含其强制wd009-hook-r3而exit1，尚未执行Hook写入；按要求改独立home后HookManagementChecks-02 exit0/135项。未触碰真实用户Hook。

对照包：target/WD009-Preview-R4-LocalModel-1.0.19/image/AhaKeyStudio/app/ahakey-studio-1.0.0.jar；SHA256=22d37934b5ad79f3ca3eb41e053642af4bb1adbf084a5e1c0b631b3e78af1f95，与target/wd009-preview-build-04/BUILD_RECEIPT.json一致。使用包内runtime/lib加测试class，classpath无当前产品class，未改历史成品或回执。核心回归PASS只覆盖上列实际通过的适用套件，不将这两套额外诊断改写为PASS。

### 界面与预审修复

已查看ui-02/account-window.png、factory-confirm.png、main-pending.png、main-readback-complete.png；确认文案完整、默认取消、待核实入口/只读可见，使用实际/style.css。主页面是测试组合视图，非App.start完整窗口；模拟设备名/电量无真机含义，本机9000端口占用提示未通过杀进程消除。不将截图作安装包UI/真机PASS。

fresh-review/EARLY_FINDINGS.md的EF-01由CloudUiChecks实际排队换号覆盖；EF-02由RestoreChecks换USB零查询覆盖；EF-03由RuntimeRestoreRaceChecks真实发送锁/回调覆盖；EF-04由RestoreProductionUiChecks冷身份锁内catalog覆盖。另补401页面及已知资格状态修复。此段只是DIB处理映射，独立审阅仍须复核最终固定身份。

## 产物、限制与下一步

本轮仅生成编译class和测试证据，没有新JAR、Preview、EXE、installer、安装或发布；旧包只用于回归对照。无Git candidate，不提供WD-010可交测安装包身份，不能把class检查当EXE通过。

未执行真实账号/后端部署核验、兑换/付款、麦克风/模型推理/SendInput、实体USB/BLE恢复/断电、驱动/Hook安装、烧录。正式恢复v2固件Gate与Artifact仍需DLA只读发现；mock不能填补。real_device、owner_uat、review保持pending，DIB不填写这些结果。没有Git写、模型下载、kill、设备写入或Firmware改动。

提交后由DLA实际diff审阅、固定review pack并完成高影响独立审阅，再沿Owner既有自主授权继续带本地模型EXE，按Harness隔离构建。无须Owner手工搬运已有仓库事实；本轮不要求Owner安装、付款或刷机。
