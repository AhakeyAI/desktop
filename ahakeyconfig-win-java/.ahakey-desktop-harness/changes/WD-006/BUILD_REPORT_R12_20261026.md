# WD-006 R12 完整本地模型修正版构建报告

完整本地模型版1.0.12已构建，适用内容及离线运行检查通过。尚未安装或烧录，不代表Owner最终验收。

## 实际产物

- EXE：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\WD006-R12-LocalModel-1.0.12\installer\AhaKeyStudio-1.0.12.exe`
- 大小：296233528字节
- SHA256：`79dba91a2da3e12997a0318cac6c93e822bc887c490425a653797ad3bf11b1b1`
- buildId：`e0304803ef8023f82a4e915b2b2f3ea7946104cb9d9f34594335854970ab2ddb`
- ProductCode：`{5397F6E9-E543-4E8A-9270-706CC27A2C3E}`
- PackageCode：`{AF42F0E8-FA67-4E24-92A4-29844D5B6F3A}`
- UpgradeCode：`{03E5A934-FFCA-3815-B455-7D49BF1CA1DC}`
- 实际嵌入MSI SHA256：`9a529b4d48c92d76cc946bda890c97d8e5587c6dd9142a05329fe2fcc52c74f1`
- 候选：`b21186cdece0e567a4b863c74fd6c0906776b6ab`；构建token：`20261026T043634004157Z-0d2c22`。

## 来源与核验

只从固定候选导出169份输入；106项审阅清单及13项installer配方核对一致。沿用已通过R11配方、离线模型/JNI、BLE运行时、DTF5.0.2和固定发行公钥。新ProductCode与buildId均不同于R11，未构建1.0.11，所有旧安装包保持。

实际MSI展开313个载荷文件，逐一与app-image比对；31项候选资源、96项BLE运行文件、13项WCH/驱动载荷、模型/JNI及许可/来源逐项核对。最终JAR只有模型开关和发行元数据两个声明覆盖。

特别核验BootDeviceDetector、UsbHidTransport的完整class家族与候选隔离Maven输出完全一致，共享worker资源与候选字节完全一致，共16项。包内真实Java运行时确认类来源、元数据和共享literal提取，未执行worker入口或设备API。

实际MSI表及嵌入DTF/CAB验证保留原目录继承、同版升级、首次安装目录选择、事务内旧版移除和用户配置保护。仅静态解析CA，不执行安装或原生CA探针。固定发行签名验证通过，签名前后MSI字节不变；Windows Authenticode仍为NotSigned。

包内运行时通过61项真实无害子进程检查，以及两份固定WAV真实识别、重复识别和释放。未打开麦克风或键盘注入。未启动完整App、GUI、Hook或连接设备；本轮不重跑UI截图与旧OTA双版本对照。

HEAD、真实index、106项工作源码、候选导出输入、冻结实现报告及旧R11包均未变化，见build-r12-evidence-20261026/POSTFLIGHT.json。

## 后续

DLA复核最终收据和产物后交Owner手动安装、烧录、正常重连及版本回读。源码阶段的真实只读检测通过不代替这些端到端测试；本轮没有自动执行任何安装或设备写入。

完整身份、输入、命令、退出码、内容与机器日志索引见同名JSON；生产源码和冻结IMPLEMENT报告未修改。
