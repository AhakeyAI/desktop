# WD-005 第五轮接续核验

日期：2026-10-20；角色：DIB。此文件为追加观察记录，不是正式提交回执、DLA actual review 或 fresh review。

本次接续先运行 DIB preflight，退出0并 PASS。读取过程中同一工作区的第五轮测试、两处生产修复和执行记录继续落盘，因此保留全部已有工作，未还原或覆盖。一次测试修补 apply_patch 因目标已被修正而未应用，没有由此改变文件。随后核验实际差异并单独运行以下验证，不冒称本次重新编写了已经落盘的修复。

## 当前身份与实际结果

- HEAD：f595262207796dbf325cb9951ed3dc02b4887362，仅原源码存档；未执行 Git 写入。
- 验证前后 fingerprint 均为 1fca9345199cd1166acd8b4df7125d3e17f1cad4032c7736dc1060361a2d3ccf。
- 两处生产差异为可信会话事实与 SINGLE 仲裁分离、带工具来源的匿名占用，以及补发不重置原事件时间；测试为 DisplayConfigRound5Checks。
- 使用 JDK 17、离线 Maven test-compile，退出0；不 clean/package。
- 单独复跑 175+36+72+72+46+42=443 项断言，六个进程均退出0。先行46项快速核验也通过，不重复计入443。
- 未启动完整应用、网络服务、Hook、真实设备，不修改桥接或固件。隔离 FX 不代表 Owner Preview/UAT。

日志目录：.ahakey-desktop-harness/evidence/20261020-wd005-r5/。
编译命令：`C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd -o -Dmaven.repo.local=C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.m2repo -DskipTests test-compile`。
JAVA_HOME=`D:\jdk-17.0.19.10-hotspot`；MAVEN_OPTS=`-Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8`；PowerShell 输出使用 UTF-8。
测试命令：`D:\jdk-17.0.19.10-hotspot\bin\java.exe -Dfile.encoding=UTF-8 -Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8 -cp "target/test-classes;target/classes;target/lib/*" com.example.ahakey.displayconfig.<测试类>`。
UI 测试另传 `.ahakey-desktop-harness/evidence/20261020-wd005-r5/ui-continuation.png`。

| 新增核验日志 | SHA256 |
| --- | --- |
| compile-continuation.log | a3a14abfeb0eb65127e819422bdb2ee8c333cd81fbdd0cda93fab479b849644a |
| DisplayConfigChecks-continuation.log | b5e39be632f1691a43c0c61fd76fd7cb3ab6f267f0f89da8ebbf8e9465e8ace7 |
| DisplayConfigFxChecks-continuation.log | 5e1389f94e665650044e62fc4d755d6c22515b0f17ef171ab949c218d08da8e0 |
| DisplayConfigRaceChecks-continuation.log | 28329107bc62a51b58e432d4258052a3fc6e451c0ac6fc07db3c157bdef532fb |
| DisplayConfigRevision3Checks-continuation.log | 03eb5ae2937fd86857018f61c4a01622f5269256f11bc5dcb2ec5d9f2a029fca |
| DisplayConfigRound5Checks-continuation.log | 58ae7941b0c56a39530aa17e006fe858b79b81be8c27792070f611f7148cd461 |
| DisplayConfigRevision3UiChecks-continuation.log | 4d3d531442fcb3d1ad440d8f4ef8782969078743a18a5ca4f86baba09b245f13 |
| runtime-continuation-check.log | 7e444ec94aec19edc61975b9e7fd7dd255d731bee69b3ceb6ce116d38f58a699 |
| ui-continuation.png | b9590c373619fe26426e78ce790a953a778984407cb8bf821430b64769898568 |

## 正式提交观察

核验结束时正式 IMPLEMENTATION_RECEIPT 与 builder_submission 已存在，时间为 2026-10-20T02:24:23+00:00，round=5，源码指纹与上列一致。STATE=VERIFY/DLA_REVIEW，next_actor=DLA。不重复运行 submit，不手写或覆盖正式回执。

四项 machine/core_regression/special_regression/mock 均绑定 round5 和当前指纹；逐一重新计算其 evidence 的文件 SHA256，全部匹配。第五轮执行报告/检查表保持不变。根 report_sha256 仍绑定冻结历史报告，不能解释为本轮报告；本轮依据见 verification 内第五轮文件。

原DLA实际复审、高影响fresh、正式candidate、新包、固件与桥接身份及真机验收仍待完成。同一工具多个匿名会话不可区分；UP-01/02、来源缺失事件、固件主槽回退、BLE性能和完整应用覆盖仍保留，不因443项通过关闭。
