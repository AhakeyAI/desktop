# WD-005 R4 / round7 Preview 交接核验

日期：2026-10-20。角色：DLA。仅追加交接证据，不修改 STATE、源码、冻结报告、产物或正式回执。

## 结论

包身份及静态结构核验通过，可由 Owner 在物理断开目标 USB/BLE 后进行离线 UI Preview；不是运行通过。
设备 Preview 暂缓：包内人工固件确认仍绑定旧 D7D105... HEX，而固件仓已接受内存安全修复后的 FFB920... HEX。不能用点击旧确认的方式冒充新固件配对，也不能让 Owner 回刷已有失败记录的旧 HEX。

这是交付配对身份问题，不是 R5-F1 测试隔离问题复发，也不等于已经证明两端线协议不兼容。
未登记 Owner Preview FAIL，因为本令牌尚无 Owner 实测反馈；未改全局路由。全局仍 VERIFY/DLA_REVIEW。

## Windows 输入和产物

- token：preview-20261020T065100738948Z-669e97。
- revision=4，build_round=7；HEAD=f595262207796dbf325cb9951ed3dc02b4887362，仅源码存档。
- workspace fingerprint：e10b4d65ad9b3f62221b7790b659c09429243a96a43a169db575dce6b4c18e8a。
- snapshot fingerprint：5683e49cf090a14c1a56159617408ce3a444a6d0f0b107732c459958b5d5bd62。
- PREVIEW_RECEIPT SHA256：f91fc0f2946b886fdb2bfd4e6b45b6ac35e1e60c655663debe685717c3673a39。
- 主 JAR SHA256：c0b3f122fc2f69021514e5ed910265ef1b3c205f722da14f105dfc87b00022b1。
- 原 DLA R7 实际审阅：changes/WD-005/DLA_ACTUAL_REVIEW_R7_20261020.md；固定 pack canonical SHA256=d835f4929b834b48d3a194936b535d4b3d94fb3de480c192ef3d382c730833a7。

DLA 只读核验：19 个运行文件与 manifest/receipt/复制来源一致；12 项 receipt 日志证据哈希一致；LOG_MANIFEST 六份原始 stdout/stderr 的长度与哈希一致，包括真实空 stderr。构建前、构建后、复制后及当前源码指纹一致。

ZIP 静态核验：入口及主要服务 class 为 Java17 major61，8 项资源与快照一致，未把测试类打入主 JAR，native ZIP 清单与 STATIC_INSPECTION 一致。读取 class 字节确认 BleManager 保留旧固件 SHA；没有加载或执行 class/native。

BUILD_EXECUTION/实际日志支持一次离线 Maven package -DskipTests 退出0；测试源码编译，测试未运行。507项为已有本轮实现证据，不是打包复跑。保留六项 JavaFX effective-model warning。首次 finish 因直接提交空 stderr 被拒，后续绑定真实日志清单完成；没有第二次构建，没有伪填日志。

## 固件配对差异

只读根：C:\Users\20825\Desktop\vibe-code。

最新正式 CP2 gate：
`.ahakey-harness/evidence/checkpoints/X1-AI-WORKFLOW-PRESENTATION/CP2/20261018T175441/gate-receipt.json`

- result=PASS。
- gate 文件 SHA256：BF6EFC5AC8380B6420C4DED17492B4BC798CAD46072699C38EDE41945FB5DBAA。
- candidate_commit：70ca334f65d73b6a2f20a0598e55c6da59f26526。
- project-state.yaml accepted_checkpoint=CP2，accepted_source_commit 同上。后续 CP2.5 仍属另一阶段，不纳入 Windows 本项。
- 正常修复 HEX：C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\builds\ws3-cp2-memory-safety-20261018\HID_Keyboard_582m_vibe_coding.hex。
- 实际文件 SHA256：FFB9208F79084AA24A832AD2562A14DBBEA5DF4D114A135CB5B2EB98D4E05539，与 gate 一致。

Windows StudioController.java:612 附近的人工确认提示和 BleManager.java:110 附近的确认校验仍使用：
`D7D10510482228B74A2978BD8272F6A4E32668CF6B4F31F491A8503B0DC11E2E`。
该机制是人工确认、与连接代次绑定，不是设备读取 HEX 哈希；不能声称“自动识别新固件后拒绝”，也不能让用户对新设备确认旧哈希。

Firmware closure-prep/20261018-memory-fix-owner-pass/handoff.md 记录旧固件随后黑屏/重启；FIX1 有明确恢复反馈，正常修复版有整体通过反馈，但不虚构逐项 UAT 或本设备此刻已刷入证明。正常修复减少初始化栈占用及图像局部缓冲，不能用这一事实声称上传耗时、首传失败或 RT-03 均已解决。

需要窄范围修正 Windows 配对身份及相关回归证据，轻量实际复审后重建新 Preview。不要修改本冻结包，不加入 CP2.5，不去掉身份确认或连接代次保护。本轮没有授权实现该修改，未向 DIB 发执行消息。

## 桥接身份

现场 `C:\Users\20825\Desktop\windows软件代码\desktop\BLE_tcp_driver_package\BLE_tcp_driver.exe` 与桥接 bin/Release 文件相同，SHA256：
`9B8F8C9D18AE7EE93B71ED7C867E1CE1E60040EBC6832498F5F2D00DCBD6106E`。

当前源码哈希与 BRIDGE-01_REPAIR_REPORT_20261018.md 匹配：

- Program.cs：E235BDA01FA4C2C6AE35869D6D5FBB68C02923085146EEF0151B3BAEBA0D50D0。
- Form1.cs：86A6FD0E6AA940209BDA074CCADD804E6B95840937E93CB273AB90A94C3F4DFC。
- TcpServer.cs：CD4978E768A8B3028F9CE1B93A3079F0BD574330444557CE0D4B67E4D4013745。

源码归属接受不等于桥接功能复审通过，现场 EXE 身份不能证明由这些修复源码构建。此 Windows Preview 不附桥接；不得称新版队列/MTU优化已经交付或性能通过。不自动替换 EXE/config_server.json。

## 未完成项

上传首传失败根因、来源缺失后台事件、RT-03主槽回退、BLE性能、完整应用和真实 USB/BLE 验收均保留。当前 pack 的独立 fresh、formal Git candidate、配对产物身份及 Owner UAT 分别完成，不能用507项断言、源码存档或本核验替代。

本轮未构建、启动、安装 Hook、连接设备、写设备、烧录或 Git 写入。
