# WD-007 R2 USB attachment 竞争修复执行报告

2026-10-31，合法 IMPLEMENT/FIX，build_round 3，依据 FIX_REQUEST_R2_20261031.md 与已通过 DIB preflight。仅修复独立复核发现的原合同 A02/A04 内竞争缺陷。R0/R1报告、批准、review-pack与历史日志原样保留。

## 实际修复

UsbHidTransport 以单一 AtomicReference 的 OPEN / INTENTIONAL / UNEXPECTED 终止原因替代分离标志。reader意外失效与cancelPendingIo争用同一CAS，终止原因一经锁存不可覆盖；仅意外终止方发通知。BleManager在commandLock内替换旧transport之前，先cancel撤销旧transport，再消费其锁存原因；若确属当前USB的意外终止则退休旧attachment。这样即使旧reader callback排队、openSelected先占锁，旧attachment也不会遗失退休。旧callback的transport/generation护栏继续保护新B。

主动断开仍保留持续存在的同一attachment草稿。意外失败不会伪造physical absence，也不解除资源quarantine。没有改变协议或其他产品语义。

## 实际验证

离线test-compile退出0，日志 target/wd007-preparation/compile-r2-01.log；Java 17.0.19.10、Maven 3.9.12、现有.m2repo。target/wd007-r2-checks-01/RESULTS.json记录12套实际Java命令、退出码0、耗时及log SHA。MACHINE_EVIDENCE_R2_20261031.json绑定本轮指纹及全部原始证据。

Wd007UsbTerminationChecks共106检查：新增40轮主动cancel与reader错误并发，验证通知与原子终止原因一致且后续动作不能覆盖；控制实际commandLock，等待reader锁存意外原因且入锁队列，由同一持锁线程调用openSelected先替换transport，再放行旧callback。验证新attachment、新generation、实际controller读回B值8且不套用旧dirty值44、旧草稿记录保留、晚到callback不影响B、无physical absence假证据。既有正常明确断开再连、同路径失效、未决命令隔离与恢复限制亦通过。

另外11套覆盖连接、旧bridge owner后续退出释放、安全取消/审批wrapper、恢复初始化、草稿读回、窗口退出、维护准入、固件升级、备份恢复、K1协议和IPC。本轮按FIX要求做针对性复跑；原25套全量证据保留在target/wd007-checks-06，不宣称本轮重新全跑。

## 范围与身份

R1指纹：b2cd83bb4d8f26a6bb6fc2e33fed9db718d74d479ce06e62a3e2393ac5895891
R2指纹：0238ca53e8a583c8ef920aaab5c68c7932f94e4e3c39fc9798bcb1fa7764b8f2

本轮仅4路径改变：
- `src/main/java/com/example/ahakey/service/BleManager.java`
- `src/main/java/com/example/ahakey/service/UsbHidTransport.java`
- `src/test/java/com/example/ahakey/service/Wd007BehaviorChecks.java`
- `src/test/java/com/example/ahakey/service/Wd007UsbTerminationChecks.java`

前两项生产生命周期修复，测试fixture仅让Memory.cancelPendingIo调用真实基类终止CAS，并添加上述锁交错测试。未改C#桥、配方、Harness脚本、合同或批准。未Git写、安装、运行产品主程序或操作真设备。

## 构建事实与下一步

上一轮Preview token preview-20261031T032009839275Z-9c2977于Maven package后、jpackage前失败：Git快照将唯一WCH wcfg的CRLF转LF，profile SHA校验阻断。原快照、target/WD007-R1-LocalModel-1.0.13部分目录、日志和BUILD_REPORT_ATTEMPT01/BUILD_FAILURE_ATTEMPT01均保留；无EXE，不能交付，不复用旧token。DLA已授权未来新snapshot按原文件SHA做字节保真补入并记录addendum，不能改profile。

本次submit后交原DLA与独立审阅重新冻结复核；仅收到新Preview token后继续1.0.13 local-model隔离构建。现有桥02、verified-models、native、DTF等不变，后续构建仍需产物内容检查和packaged runtime的固定WAV本地语音验证。没有新正式candidate/EXE/Owner UAT结论。其余范围、既有遗留及真实设备测试缺口继承R0/R1报告。
