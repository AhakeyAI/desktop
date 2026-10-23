# WD-005 第二轮退修执行报告

2026-10-16，Windows DIB，IMPLEMENT/FIX，build_round=2。
本页为独立的第二轮报告，不追加或替换第一轮 EXECUTION_REPORT.md。
本轮机器检查通过仅覆盖以下实际执行范围；不代表原 DLA/fresh 审阅、Owner Preview、正式配对或真机通过。

## 身份与授权

- 原 DLA 退修：F1-F3 及 R1，REVIEW.json 与 DLA_ACTUAL_REVIEW_20261016.md 保持原样。
- 审阅输入指纹 3a967e3f34a85f7d346bdf3e35110bbe191a4d980effdb13218de4307659bb93。
- HEAD/原可恢复起点 41c034171e60b2d4962b0adbe8f3cffbf80a0436，未执行 Git 写入。
- Owner 本轮回复“我授权”，对应仅本地编译与离线/隔离 JavaFX 测试；记录见
  ../../evidence/20261016-wd005-round2-test-authorization.md。
- 没有打包、启动正式应用、访问设备、Hook 操作、烧录、安装或发布。
- 未编辑固件、Harness 核心/规则/seal、旧批准/起点、原冻结执行报告、历史 dirty 或 BLE 配置。
- 本轮先前未执行状态保留在 FIX_ROUND2_PROGRESS_20261016.md，不回写当时事实。

## 实现范围

第二轮只修改七个原 allowed_paths 内文件：

| 文件（Java 路径在 com/example/ahakey 下） | 本轮修改 |
|---|---|
| service/BleManager.java | 自动显示回读与旧命令共用 transaction monitor；有限等待 legacy waiters；释放 monitor 后执行 idle 回调；0x98/99 确认和捕获代次；reset 清 SINGLE 待发 |
| service/DisplayConfigService.java | Mode 确认期间取消过期回读、确认后刷新；FX 提交检查操作号/连接；旧错误不覆盖当前提示；ACK 时间预览与真实逐项 ACK 日志 |
| service/AiRuntimeDisplayService.java | 冲突不改偏好，0x98 ACK 后再持久化；失败回调；pending snapshot 绑定代次并传到实际发送入口；保留连接偏好同步 |
| model/DisplayConfigState.java | 本地编辑 revision 防止同值新意图被旧保存清除；预览截止以 ACK 时间为起点 |
| app/StudioController.java | CP1 controller 准入和真实完成提示；连接时先启动身份请求，再安排显示回读 |
| view/InspectorPane.java | CP1 模式控件 busy/loading/pending 锁定，不提前显示新模式成功 |
| displayconfig/DisplayConfigRaceChecks.java（测试目录） | 新增内存传输、控制 ACK/FX 顺序的时序回归，无新增依赖 |

详细调用链与修改理由见 FIX_ROUND2_PROGRESS_20261016.md。本轮未扩大 UI/协议合同。
上传整笔互斥、未知 ACK 隔离、按需读取、无 heartbeat、原 CP1 绑定/主槽位/TTL 算法均保留。
原 DLA 仍须审阅实际累计 diff，不能由本报告替代。

## 实际执行

所有命令均在当前工作目录执行，Maven 使用离线依赖，未改系统 JAVA_HOME。

```powershell
$env:JAVA_HOME = 'D:\jdk-17.0.19.10-hotspot'
& 'C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd' -o -DskipTests test-compile
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' '-Djava.awt.headless=true' -cp 'target/test-classes;target/classes;target/lib/*' com.example.ahakey.displayconfig.DisplayConfigChecks
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' -cp 'target/test-classes;target/classes;target/lib/*' com.example.ahakey.displayconfig.DisplayConfigFxChecks
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' -cp 'target/test-classes;target/classes;target/lib/*' com.example.ahakey.displayconfig.DisplayConfigRaceChecks
git diff --check -- src/main src/test
python .agents/skills/ahakey-desktop-harness/scripts/desktop.py preflight --id WD-005 --role DIB
```

每个 Maven/Java 命令完整输出使用 Tee-Object 保存到对应新日志，紧接着 exit $LASTEXITCODE，
下列退出码来自实际进程完成，不从日志 PASS 文本推测。

日志均在 .ahakey-desktop-harness/evidence/，哈希见 IMPLEMENTATION_CHECKS_ROUND_2.json。

| 日志 | 退出码 | 实际结果 |
|---|---|---|
| 20261016-wd005-round2-compile-01.log | 0 | 65 生产/3 测试源编译成功 |
| 20261016-wd005-round2-races-01.log | 1 | 夹具接收入口与清理失败，原日志保留 |
| 20261016-wd005-round2-compile-02.log | 0 | 修复测试夹具后编译成功，生产 classes 未变化 |
| 20261016-wd005-round2-races-02.log | 0 | 72 项受控时序断言 |
| 20261016-wd005-round2-offline-01.log | 0 | 175 项离线断言，本轮重新执行 |
| 20261016-wd005-round2-fx-01.log | 0 | 36 项隔离 FX/服务断言，本轮重新执行 |
| 20261016-wd005-round2-races-03.log | 0 | 同一 72 项重复运行通过，不重复计数 |

本轮唯一断言合计 283。不是 283 条完整产品验收，也不是原211项沿用。
offline-01 与上一轮离线日志 SHA 相同，因为测试输出完全确定；本轮确实启动新进程重跑，退出0。
Maven 的6条 JavaFX 模型警告及 FX unnamed-module 警告均保留，未宣称没有警告。

## 首次失败处理

RaceChecks 最初复用 FakeSession.processNotifyFrame 回复，未经过 onBleNotify 更新时间戳，
使 Mode 确认等待无法观察到新状态时间。夹具改走真实 onBleNotify 重组/接收入口，预期未放宽。
初次还把 user.home 改到临时目录后启动 JavaFX，导致 .openjfx 原生 DLL 在清理时仍被加载；
清理异常遮住了主流程失败。修正为 JavaFX 初始化完成后再设置临时偏好目录，且清理异常
在已有主异常时作为 suppressed 保留。没有修改生产实现来迎合夹具、没有跳过失败断言。
初次退出日志只直接呈现清理异常；时间戳原因由调用链和修正后结果定位，不补造丢失的异常栈。

## 覆盖与限制

- F1：真实 DisplayConfigService 回读先行、真实身份/输入读取先行两种顺序；身份及0x97/16条0x87
  均完成，OLED14条元数据不丢；延迟0x88并模拟真实 UI 的 modeSwitching/selectedMode 序列，
  真实 setWorkModeAndVerify 完成0x92/0x00确认，取消旧批次、读取当前Mode。
- F2：实际 service 在读/写租约中的两个方向调用均不改偏好、不持久化、不发0x98；
  正常0x98在ACK前不假成功，ACK后持久化，FAIL保持旧模式，反向切换成功。
- F3：刻意阻塞 FX，在设备 ACK 和后台任务完成后、成功回调执行前断连或换代次；
  亮度/九项灯效/预览六种组合均保留dirty、不建立旧预览、不显示旧成功、不遗留busy；
  新设备回读不覆盖意图。日志仍记录旧连接真实1或9项ACK。另验证同值新编辑与ACK起算期限。
- R1：确认 SINGLE/MULTI 同连接最新事实仅补发一次；旧连接待发不会因新连接租约结束重放；
  原 onDeviceReady 的0x98仍执行，新连接的新事实仍可发送。没有扩大重连绑定/TTL语义。
- 重跑原175/36断言，继续覆盖原报告已执行列：编码/存储/协议/整笔上传/超时/部分保存等。

没有创建 App 或 StudioController，没有实际点击完整 Inspector/TopBar；Controller/UI 接线通过源码检查，
不能将服务级时序结果称为完整应用操作通过。测试使用内存 USB 替身，未枚举/连接真实 HID。
FX 组件仍是隔离800x600场景；不代表完整窗口、高DPI或真机。
其余 A01-A11 未验证范围继承原报告和 DLA 列表：真实USB/BLE、断电/Flash、Hook/语音、
全窗口/DPI、磁盘故障穷举、旧迁移全流程、全部灯效时相/物理输出等，均未自动豁免。

## 新旧报告绑定

普通 submit 仍固定 report_sha256 为根 EXECUTION_REPORT.md；本轮不修改该历史字节。
第二轮执行报告/检查表和实际日志作为正式 record-check 的 evidence 同时绑定当前代码指纹、
build_round=2 和批准身份，随后由原 submit 检查这四项当前轮证据再路由 DLA。
因此 submit 的 report_sha256 仅指历史基报告，不可据此把第一轮结果当成本轮结果；
DLA 必须连同 verification 中直接绑定的本报告和 IMPLEMENTATION_CHECKS_ROUND_2 阅读。
这是使用现有检查证据字段追加轮次材料，不修改 helper、不重写旧批准/报告、不减免检查门。

当前无新候选提交、正式构建回执、Preview/交测包或设备操作；提交状态以 helper 实际结果为准。
原 DLA actual review 通过后再决定 Owner Preview，正式配对仍需 high-impact fresh review、
Git candidate、真实包、Firmware identity及Owner真机反馈。
