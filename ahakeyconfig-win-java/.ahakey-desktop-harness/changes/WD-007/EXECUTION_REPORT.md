# WD-007 R3 主动断开后的USB草稿隔离修复报告

2026-10-31，合法IMPLEMENT/FIX，build_round4，DIB preflight PASS。依据FIX_REQUEST_R3_20261031.md修复原合同G10/A04内IR06。R2历史EXECUTION_REPORT_R2_20261031.md保留，旧review撤销事实由DLA单独记录，本轮不改旧报告或独立结论。

## 修复与影响

USB没有唯一序列号时，相同HID path不足以证明关闭会话期间未换键盘。此前主动断开关闭reader而两次枚举间换B，仍能复用A草稿。现在BleManager.openSelected持commandLock初始化USB会话时分配新UUID草稿身份，每次新配置会话都读取实际配置；同一会话内仍保留未保存编辑。没有清空StudioState.deviceDrafts，旧草稿记录仍独立保存；BLE稳定target身份与草稿恢复策略不变。未新增恢复UI/固件UUID协议，也不把主动关闭记录为physical absence。

## 红测与回归

先仅修改测试，target/wd007-r3-red在R2生产实现上实际失败exit1：same-path B after intentional disconnect reads B actual configuration without A draft。随后增加最小生产修复，离线test-compile退出0，12套targeted检查全部退出0，target/wd007-r3-checks-01/RESULTS.json保存实际命令与SHA。

USB controller链共111检查：当前会话dirty31经历同路径观察仍保留；主动断开A后枚举始终{A}、无absence，B真实读回7且clean，A草稿保留；再编辑32主动重连读回6，以新身份隔离旧草稿；主动断开不能伪造absence。R2原子cancel/failure 40轮、reader排队与openSelected先换B的精确锁交错、晚到回调/generation、未决写隔离仍保留并通过。Safety同路径返回的旧错误恢复断言改为新USB会话不得仅凭path复用。

其余检查覆盖BLE A→B→A可靠身份草稿恢复、bridge旧owner释放、正常/维护命令、写取消/超时、恢复、备份/固件升级、窗口退出、K1协议、草稿/F18和IPC。本轮无变化全套不重跑，原R0 25套及R1/R2全部日志保留。没有真实HID/蓝牙、SendInput、设备写入、安装、麦克风或Owner UAT。

## 身份与路径

R2指纹：0238ca53e8a583c8ef920aaab5c68c7932f94e4e3c39fc9798bcb1fa7764b8f2
R3指纹：9c9dd321bcc7a984e34047aa854b4e0cb344fc4789f5e965315cbd06d4251f58
仅3路径改变：
- `src/main/java/com/example/ahakey/service/BleManager.java`
- `src/test/java/com/example/ahakey/service/Wd007SafetyChecks.java`
- `src/test/java/com/example/ahakey/service/Wd007UsbTerminationChecks.java`

仅BleManager一个USB会话分配点为生产改动，其余两个针对性测试；不改合同/Harness/配方/固件/其他产品语义。详细文件hash及机器日志绑定MACHINE_EVIDENCE_R3_20261031.json。

## 构建历史与交接

R2 candidate7415bf68d0ba1cb7ef654440c7443797734ed27c的最终retry-02 EXE构建与固定WAV检查成功，正式build token20261031T034000574643Z-90430e及Preview tokenpreview-20261031T033233942278Z-93233b已登记真实产物；因IR06该包明确不可交付，仅历史证据保留。DIB本轮未Git写，未对Owner发安装包。

R3 submit后需DLA实际/独立复核、新candidate、新隔离构建。后续按已确认方法：新snapshot一次性补入13原配方依赖、恢复WCH wcfg与catalog HEX原始字节，14项catalog/profile资源逐SHA核对；在标准构建环境保留ICE/签名完整校验，最终包runtime再跑两段固定WAV。不得将R2包或签名通过冒充R3产物。应用发布签名与Windows Authenticode不同，既有配方后者仍NotSigned。构建记录另写阶段报告，不追加冻结IMPLEMENT报告。
