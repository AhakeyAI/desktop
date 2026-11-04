# WD-008 执行报告

本轮 DIB 已实现最小身份兼容修复并执行离线检查；未打包、未安装、未真机读写，未替 Owner 验收。

## 身份与范围
Receiver HEAD 42696a6bdf0ed72df8d0a416c22e8e3d82e3fb96；Contract revision 1，preflight PASS。工作源是 WD006 产品基线，WD007 保持拒绝与暂停。未 Git 写；原有治理 dirty 不属于此次实现。
## 实际差异
- protocol/FirmwareCapabilities.java：唯一离线集合，仅原 HW1 1.0.0 与正式 HW1/HW2 1.0.1 三个完整标识。未知、空和错误 profile 不授予能力。
- protocol/AhaKeyProtocol.java：普通配置、运行显示、9F 显示响应三个精确旧标识判断接入同一集合；原有响应格式和零填充校验保留。
- firmware/FirmwareCatalog.java：新增 connectionCapabilities 给运行连接使用。原 trustedCapabilities/knownCapabilities/烧录 targets 与备份恢复目录仍只包含旧内置项；不把 HW2 连接支持等同于允许刷 HW1。
- service/BleManager.java：仅将 isFirmwareCapabilityAdmitted 查询切为 connectionCapabilities；当前连接代次/真实9F响应/identity 对象验证不变。
- compatibility/FirmwareIdentityCompatibilityChecks.java：真实 BleManager + 内存 USB/TCP 回包离线矩阵。覆盖正式两版和旧受支持标识、普通键读回、侧拨读写 ACK、显示保存 ACK、运行显示、断连代次/迟到回调、未知/空旧 ACK、无ID基础 K2写入/保存与真实15秒查询超时、维护目录不扩张及跨硬件内置烧录拒绝。
没有修改桥、传输、Controller 动线、K1、语音/Hook、内置 HEX、OTA 或安装脚本。K1 保持真实 9E 能力查询与现有旧分支。
## 已执行机器检查
工作环境 JDK D:/jdk-17.0.19.10-hotspot；依赖为 WD006 R13 既有 app/lib 与 third-party/sherpa-onnx-java-api-1.13.3.jar。新输出全部隔离 target/WD008-implementation；测试 user.home 为其 home，日志在该输出目录，未访问真实 HID/启动桥。

机器编译：javac -encoding UTF-8 -cp <R13 lib/*;Sherpa API> -d target/WD008-implementation/classes @target/WD008-implementation/main-sources.txt，所有生产 Java 编译退出0；测试同理编译到 test-classes，退出0。完整日志 compile-main-r3.log、compile-tests-r2.log。第一次绝对路径 argfile 编译因 Windows 默认编码无法识别中文路径失败，保留 compile-main.log；改用相对 ASCII 路径 argfile 后通过，不改产品代码解决工具路径问题。

测试共同命令：D:/jdk-17.0.19.10-hotspot/bin/java.exe -Dfile.encoding=UTF-8 -Duser.home=<target/WD008-implementation/home> -cp <classes;test-classes;R13 lib/*;src/main/resources> com.example.ahakey.<测试类>。每一测试在隔离输出目录运行，原始输出见对应类名.log，退出码见 test-results.json：
- compatibility.FirmwareIdentityCompatibilityChecks：退出0，85项；USB/TCP均为内存替身，不是真机。
- protocol.K1RouteProtocolChecks：退出0；K1 v1、nonce/CRC、USB/BLE解析及旧ACK/任务隔离相关原回归。
- firmware.BackupRestoreChecks：退出0；原备份恢复实际传输替身检查。
- firmware.DeviceMaintenanceChecks：退出0；原事务准入与维护生命周期检查。
- displayconfig.DisplayConfigChecks：退出0，175项；协议、图像/资源、显示读写/状态原回归。
git diff --check -- src 退出0。未运行应用UI、安装器或六组真机验收；不把 ACK 模拟值称为设备真实持久化成功。
## 实际可运行产物
尚未生成本轮可交测 EXE 或正式 build receipt。classes 仅为实现测试输入。待 DLA actual diff review 后取得 preview-open token，使用隔离快照与已核对 WD006 R13 配方构建完整本地模型 1.0.17 包；不会用旧包冒充新包。
## 交给 DLA
提交给 DLA 做实际 diff 审阅及独立高影响审阅。首次实现对 trustedCapabilities 的扩展已按 DLA 初审改为独立 connectionCapabilities，避免自动恢复策略外溢；旧试验日志 identity-checks.log 保留，最终测试以 compatibility.FirmwareIdentityCompatibilityChecks.log 为准。
两个正式版本协议来源由 DLA 的 FIRMWARE_FACTS 及 immutable candidate 审阅绑定。固件只读。无ID固件没有赋予新版输入回读/显示能力，其原基础写入路径保留；通信超时保持 FAILED。
需要 Owner 后续在两正式固件与最早旧固件分别 USB/BLE 测试实际连接、信息读取、适用保存与重连；未执行应如实记录。本轮未证明 BLE 底层实机不存在其他故障。


## v1.0 交付约束
遵循GUARDED_DELIVERY：原始起点不可重置；实际diff审阅；候选Git与产物绑定；结果与遗留存档。模板不代表通过，不自动Git写。
