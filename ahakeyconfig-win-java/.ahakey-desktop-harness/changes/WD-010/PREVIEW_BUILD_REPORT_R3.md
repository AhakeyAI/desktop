# WD-010 第3轮完整本地模型1.0.21 Preview构建报告

完整EXE已构建并通过适用成品机器检查。原DLA实际审阅和第3轮独立审阅PASS；本报告是Preview构建事实，不是正式发布、Owner安装/真机/UAT结论。冻结EXECUTION_REPORT及IMPLEMENTATION_RECEIPT未改。

## 来源与构建

Token：preview-20261105T093108031238Z-c5c559。冻结实现：6de1cbfd7a26442edf44ee12c519a957bcd60c4f2366a6ae9b291944261f94c0。快照：3a63edb8204941122418fabeab5c72c16e87e21ec10f605c3f6fb822b57fb1c5。
唯一新源码快照：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-010\preview-20261105T093108031238Z-c5c559\source。
派生目录：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\WD010-Preview-Source-R3-1.0.21。207输入逐项复验，其中13安装配方与已验证旧配方SHA一致，Git基线经CRLF归一化相同；5份原字节存在换行差异，SOURCE_INPUTS保存双方hash。另两项资源按配置锁定SHA恢复CRLF，仅派生输入改变。没有使用旧pom或旧产品class。

命令：pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File target/wd010-preview-build-02/run_package.ps1。COMMAND.json记录完整实参。一次离线Maven package、jlink、jpackage EXE、MSI提取、结构检查和双发行封套验证全部退出0。使用新ProductCode和原UpgradeCode，保留所有1.0.20及以前产物。TEMP/TMP仅本次子进程指向D盘独立目录；无下载、安装、kill或系统环境修改。

## 成品身份

EXE：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\WD010-Preview-R3-LocalModel-1.0.21\installer\AhaKeyStudio-1.0.21.exe
大小：297409080 bytes
SHA256：581f20847c375b6c569798d57459e86df41d307484f66f4556007e16e8710243
版本/形态：1.0.21 / local-model / x64
ProductCode：{112ED1A1-EA6B-431A-B014-4F5A1A5E0F90}
UpgradeCode：{03E5A934-FFCA-3815-B455-7D49BF1CA1DC}
BuildId：52b0f380e5e72e673e623650727594e73c6f7d06f569e9c84d0c4cb9a1d50d71
MSI SHA256：36be66980c59810ce29ce1b84df711e9e0362e63827156d70d8bebecfc2e4505
主JAR SHA256：1611bc7a7efec9976fa641fa4546af634139cb15d1c6dac77e91447fcaae50b1

应用发行封套通过包内Java与Windows worker双验证；Windows Authenticode为NotSigned，二者不混称。最终JAR与本轮源码构建JAR全部条目逐一比较，仅已授权model.enabled=true和发行元数据两处覆盖不同。测试类/probe未混入产品。完整app image 318文件，在所有检查后逐一重验SHA一致。

## 实际成品验证

从快照测试源码对最终JAR/lib重新编译45个测试源码。所有运行classpath仅测试classes、成品主JAR、成品lib，绝不含开发target/classes。

21个适用套件全部exit0：
- 包内runtime 16套：恢复准备61、状态机603、生产UI21、runtime竞态7、维护、显示隔离64、显示竞态72、固件身份85、K1协议、备份恢复、Cursor等待148、Hook管理135、既有UI42、Hook UI23、窗口关闭23、真实SpeechNativeCheck。
- 5套云端fixture需要产品不包含的jdk.httpserver，使用完整JDK17.0.19.10和同一成品JAR/lib：排队交付84、交易窗口47、账号52、语音final32、账号UI7。未改变产品runtime配方；明确这些测试的JVM差异。
- 另以外部Python loopback和临时独立probe在真正包内runtime验证9项：实际登录/兑换/支付窗口HTTP链、DPAPI加密与重载解密、二维码图像解码与订单URL一致、支付成功终态。仅合成账号和本地服务；请求计数验证无重复登录/兑换/建单。

SpeechNativeCheck使用包内java/JAR/lib和包内encoder/decoder/tokens、native JAR，读取已核验公共0.wav（SHA 7d93384ca14702cc584a7a33fe2fed92e89e708549161cb12ea38c916882103b）。实际识别非空、重复输出一致、release两次，exit0；输出“昨天是 monday today day is 礼拜二 the day after tomorrow 是星期三”。这证明实际JNI/模型管线运行，不声称识别准确率或麦克风体验。

包内模型3项、Sherpa API/native、BLE桥、ZXing core3.5.3与已验证输入SHA一致；启动cfg包含依赖，WCH资源和MSI身份也由打包校验核对。完整命令/运行home/temp/退出码/日志SHA见BUILD_RECEIPT.json、PACKAGED_RUNTIME_CHECKS.json和PACKAGED_CLOUD_PROBE.json。

已查看成品fixture账号窗和完整读回后主视图截图；这些是实际JavaFX组合测试界面，不是App.start/真实硬件状态或安装验证。此前1.0.20中SpeechLifecycleCheck默认model-disabled假设导致exit1的日志完整保留；本轮不适用于local-model，不重跑或篡改产品配置。

## 未实测与接续

未安装/升级到Owner环境，未启动App.start的原生服务，未真实账号/付款/兑换、麦克风/SendInput、真实USB/BLE恢复/断电、安装Hook/驱动或烧录。正式Firmware v2 Gate/receipt/HEX配对仍缺，不以源码、mock、EXE或旧closure冒充准入。无需Owner搬运仓库已知事实。

本轮由preview-finish绑定整app image与最终installer及日志，原DLA接续最终交付/配对/Owner验证；不创建Release Batch，不填UAT或CLOSED。完整本地模型EXE已完成本轮构建目标。
