# Windows Stabilization Plan — Java client

> 唯一权威事实源：`desktop/docs/windows-stabilization-plan.md`。适用范围是
> `desktop/ahakeyconfig-win-java` 及其 Windows 发布脚本；固件仓库只读，不在本轮修改。
>
> 最后更新：2026-08-29。状态必须区分代码完成、自动测试完成、软件手工验证和真机验证。

## 1. 生产路径与安全不变式

生产客户端是 `ahakeyconfig-win-java`：

```text
StudioController -> BleManager -> USB HID / BLE TCP bridge -> AhaKeyProtocol -> device
Claude/Cursor/Codex/Kimi hook -> HookDispatchServer -> ApprovalService -> BleManager
```

审批唯一自动允许条件是 `fresh && connected && AUTO`。缓存 AUTO、旧帧、查询前已
进入接收路径的帧、查询超时/中断、断开、恢复中、协议异常和未知拨杆状态全部
fail closed。`DEVICE_INFO_RESP` 和 `BLE_STATUS_RESP` 只能更新连接/UI 诊断，不能
配对物理审批查询。

普通轮询、Hook 审批和 Kimi 9000 兼容桥共享 `BleManager` 的公平物理事务协调器；
审批在轮询之后发送自己的查询，不能复用轮询结果。Java Kimi bridge 只在 USB 且
没有 BLE TCP bridge 占用 9000 时启动。

## 2. 固件/协议合同

`src/main/resources/firmware-capabilities.properties` 是 Java 与发布脚本共享的
合同事实源：bundled firmware `1.4.7`、最低 GIF `1.4.3`、稳定化最低 `1.4.7`、
protocol `3.2`、model `AhaKey-X1 (1)`、capability mask `0x7FF`、最大绝对固件地址
`0x0006FFFF`。

协议命令已明确拆分：

- `0x9D`：有界持久化配置查询，request 为 `[9D resource index offset]`，响应含
  `resource/index/total/offset/count/data`，单块最多 8 字节。资源长度与设备合同
  严格匹配（resource 0: 16×100，resource 1: 4×9，resource 2: 1×2）。
- `0x9F`：设备信息/能力查询；Java 能力校验只接受固定 `0x9F` 响应，不再把 `0x9D`
  当作 capability query。

交叉端 golden fixture 位于
`src/test/resources/protocol-fixtures/ahakey-protocol-3.2.json`，覆盖两条请求、
嵌入 `CC DD` 数据、最大块和末块响应。

`0x9D` 的解析器和 fixture 已就绪，但当前生产 UI 尚没有配置资源逐块读回的调用者；
它不被用来替代普通状态查询或审批配对。后续若接入配置恢复，必须复用同一事务门禁和
session 规则。

正式固件输入还必须有真实 Intel HEX 和同名 provenance JSON。Windows 校验器要求
canonical `capabilityMask="0x7FF"`、`builtAtUtc=yyyy-MM-ddTHH:mm:ssZ`（不接受小数秒）、
版本/model/protocol/sourceCommit/buildCommand 字段；不计算或要求 SHA-256。HEX 校验
包括记录校验和、EOF 后无数据、type 02/type 04 扩展地址、type 03/type 05 起始地址、
绝对范围和重叠数据拒绝。
当前 firmware 1.4.7 开发基线已提供真实 HEX、同名 provenance，且记录了
byte-for-byte reproducibility；这表示软件输入可复现，不表示 WCHISP 或真机已验证。

## 3. 物理接收与 freshness

BLE TCP 在 `BleManager.handlePacket`/receiver callback 进入生产接收路径的第一步捕获
`System.nanoTime()`；USB HID 在 `ReadFile` 成功返回后、帧提取/协议校验/日志/锁之前
捕获到达时间。该值显式传入 `onBleNotify` 和
`PhysicalStatusFreshness.recordPhysicalStatus`，freshness 层不重新生成接收时间。

`PhysicalStatusFreshness` 状态为 `IDLE -> WRITING -> WAITING -> COMPLETED`。成功的
USB `WriteFile` 或 BLE write+flush 返回后才提交 `writeCompletedAtNanos`；写入前或写入
进行中到达的候选帧不会缓存，写失败直接丢弃。只有当前 query/session/receiver 一致、
connected 为真、有效 `CMD_QUERY_STATUS` 物理状态帧且
`receivedAtNanos > writeCompletedAtNanos` 才能完成查询；相等也拒绝。

协议没有 request-id。超时进入 `TIMED_OUT_UNRESOLVED` 后不能在同一 session 发送新查询
或复用晚帧。`BleManager` 以 single-flight、2 秒退避的后台恢复器使旧 receiver/session
失效，清空审批/状态时间/模式 pending，待同一公平事务门禁允许后关闭并重建 USB/BLE
会话；旧 reader、callback、响应和断开通知不能进入新 session。恢复中所有审批均为
non-fresh；手动断开和 shutdown 不触发恢复，所有等待有界。

USB 每次 open 创建不可变 generation session。reader 只捕获自己的句柄、consumer、
disconnect callback 和 stop 状态；close 先摘除 active session，再锁外调用
`CancelIoEx`/关闭捕获句柄并有界等待，旧 reader finally 只能关闭自己的句柄。`FrameExtractor`
按报告累积，支持 split/padded/multiple reports；`0x9D` 依 count 定长，因此 payload
中的 `CC DD` 不会被误当 trailer。

## 4. 模式、灯效和 OLED/GIF

`WorkModeSynchronizer` 将离线 UI 选择与真实设备事务分开。只有命令发送成功才建立
pending 确认窗口；发送失败、断开、session 切换立即取消 pending，重连后的设备模式
是权威值。状态恢复调用 `invalidateSession()`。

灯效/亮度/AI 配置底层 API 抛出失败；`LightOperationCoordinator` 在后台线程按命名
步骤执行，首个失败立即停止，并只向 JavaFX 队列发布一次带步骤和原因的最终状态。
只有全部步骤成功才显示“已发送”。`TaskActivityService` 的任务灯效写入失败继续
通过 UI error callback 上报。

GIF 规则唯一来源为 `GifUploadRules`：源帧数小于等于分区上限时保留
`[0,1,...,n-1]` 原序列，只计算统一 interval；只有尺寸/文件/帧数超限才标记
`optimized=true` 并请求确认。超限才按源时间轴降采样，索引严格递增、总时长误差受
设备 interval 舍入限制。窗口打开时 selected file 为空、dirty 为 false，批量写入只
处理 dirty 项；选择器记忆最近 GIF；保存后回读 start/frameCount/frameInterval。旧
FPS 控件已隐藏且不再读取/写入，legacy `oledFps` 仅以 JsonIgnore 接收旧配置。

屏幕动画设置入口位于灯光/AI 状态区域，打开时定位当前 Mode。`uploadStaticImage` 的
语义是“持久化单帧 Flash 写入并回读”，不是预览；内置动画恢复是独立显式操作。

## 5. Hook、生命周期、更新和固件发布

Hook 安装/卸载只操作 AhaKey-owned 脚本块，保留第三方配置；审批对话框 single-active，
超时/中断关闭对话框并返回 deny。退出、托盘、语言重启、更新重启共用 shutdown 服务，
只终止当前实例拥有的 BLE bridge。JavaFX 回调不等待硬件 I/O。

稳定版 manifest 要求 HTTPS、绝对 URL、无 userinfo、固定 `ahakey.com` host；资产仍需
HTTPS。EXE 下载先做 MZ 校验，再由 `WindowsUpdateInstaller` 的可测试 verifier 调用
PowerShell `Get-AuthenticodeSignature`，必须是 Valid 且 signer subject 满足配置的
`ahakey.update.expectedPublisher`；缺少 publisher policy 时 fail closed，不依赖 SHA。
当前 publisher policy 只从 JVM system property 注入，正式 jpackage/release 尚未固定该
配置；签名主体仍是 contains/substring 判定而非 canonical exact identity，因此 WIN-025
只能记为部分满足。

`build-installer.ps1 -PrepareOnly` 允许缺少 `-FirmwareHex`，但输出
`RELEASE_INPUT_VALIDATION=PREPARED_WITHOUT_FIRMWARE`，不能生成发布安装包。正式 overlay
脚本的 sources/allowlist 和 artifact test 必须包含所有新增生产类及
`firmware-capabilities.properties`。

## 6. 当前状态登记

| 范围 | 代码状态 | 自动测试状态 | 软件手工/真机状态 |
|---|---|---|---|
| WIN-001/WIN-003 freshness、session 恢复 | 代码完成 | 已覆盖生产 BLE 入口、USB extractor、延迟/超时/恢复并发 | USB/BLE 真机待验证 |
| WIN-004 模式同步 | 代码完成 | 已覆盖离线选择、发送失败、快切、延迟和 session 失效 | 真机待验证 |
| WIN-007 自动 GIF 优化 | 代码完成 | GifUploadRules 规则与降采样测试通过 | GIF 真机待验证 |
| WIN-008 最近 GIF 记忆 | 代码完成 | 持久化/选择器测试通过 | UI 手工待验证 |
| WIN-009 GIF 规则唯一来源 | 代码完成 | 规则边界测试通过 | GIF 真机待验证 |
| WIN-010 源时间轴/总时长 | 代码完成 | interval 与降采样测试通过 | GIF 真机待验证 |
| WIN-011 dirty 批量写入 | 代码完成 | dirty/revision 测试通过 | OLED 真机待验证 |
| WIN-012 有界等待与取消 | 代码完成 | 超时恢复测试通过 | Windows UI 手工待验证 |
| WIN-013 保存后回读 | 代码完成 | 回读边界测试通过 | OLED 真机待验证 |
| WIN-014 默认 GIF | 代码完成；视觉素材和尺寸仍需产品确认 | 资源/规则自动测试通过 | 默认动画视觉/设备验收待验证 |
| WIN-015 OLED | 代码完成 | OLED 上传、回读、失败路径测试通过 | OLED 真机待验证 |
| WIN-016 Task UI/灯效状态 | 代码完成 | 成功/失败状态协调测试通过 | Windows UI、灯效真机待验证 |
| WIN-017~020 语音 | 代码完成 | Hook/pressed-state/tensor 释放测试已有 | 键盘/麦克风/模型实机待验证 |
| WIN-021~024 生命周期/持久化/Hook | 代码完成 | 原子保存、实例唤醒、bridge owner 测试已有 | Windows 安装/托盘/已安装 Hook 手工待验证 |
| WIN-025 updater | **部分满足**：HTTPS manifest/asset、MZ、Authenticode Valid 和 publisher policy fail-closed 已实现；仍缺正式配置注入、canonical signer identity 和完整签名流水线 | manifest、下载和签名替身测试通过 | 正式签名/jpackage/release 基线待验证 |
| WIN-026 firmware flasher | 代码完成发布输入校验；WCHISP/安装包集成尚未验收 | provenance、PS5/PS7、HEX 测试通过 | WCHISP、真实 HEX 烧录和真机待验证 |
| WIN-027 灯效运行时写入错误 | 代码完成 | 亮度/灯效失败不覆盖成功状态的测试通过 | 灯效硬件故障注入待验证 |
| WIN-028 普通请求/save/GIF 事务、session/dirty 隔离 | **部分满足**：普通写入与 session/dirty 安全边界已实现；0x9D 配置读回尚无生产调用者 | USB close/reopen、事务门禁和跨 session 测试已有 | USB↔BLE 压力、Flash 真机待验证 |
| WIN-029 Intel HEX/固件合同 | 代码完成；1.4.7 HEX/provenance 在开发基线可复现 | provenance/HEX/边界测试通过 | WCHISP、签名固件和真机待验证 |
| WIN-030 legacy cleanup | **部分满足**：生产路径已明确，仍保留 HookClient、SocketServer、KimiConfigLeverSync 和 AgentManager.installHooks 占位/兼容入口，尚未完成最终删除或兼容边界收口 | 相关单测已有 | 生态兼容性与旧脚本手工确认待验证 |

“代码完成”不等于“真机完成”。当前没有可用于本地正式 overlay 的
`C:\Program Files\AhaKeyStudio` 安装基线时，overlay 只能报告阻断；不得伪造
`OVERLAY_VALIDATION=OK`。

## 6.1 当前待办（不在本轮交付中冒险扩大范围）

1. WIN-025：把 expected publisher 绑定到正式 release/jpackage 配置，并将 signer
   subject 升级为 canonical exact identity；补齐完整签名流水线。
2. BLE bridge 生命周期的精确路径 owner 已在本轮收口；仍需 Windows 手工验证启动、置前、
   Studio 退出和手动断开不重连边界。
3. 固件 EEPROM journal 的连续保存风险属于固件端跨项目待办，本轮不修改固件。
4. GIF 优化原因 UI 仍可能泛化显示尺寸/分辨率/帧数，而不是实际触发项；需补 P1 UX
   细化。默认 GIF 的视觉和体积也需产品验收。
5. 若任务文本要求离线持久化，需另行确认当前实现是内存态还是持久化态，避免误报。

## 7. 本轮交付登记（2026-09-04）

本轮基于只读 Firmware `firmware-stable-rebase-79` 稳定基线（runtime commit
`79ecabad3c8fd013aba7a6e12a13b5836fbc8924`，文档 commit
`26c03afe9dd2cbfe95fbcac9f6f1b79458dfbd20`）收口 Windows 代码。固件仓库未修改。
交叉审计结论保留为：`79 = confirmed GOOD`、`a103 = confirmed first BAD`、
`4d465af = historical BAD stabilization line / HV-003 evidence`；后两者不是本轮
生产固件输入，也不应被 cherry-pick 到软件工作区。

* HV-005 GATT discovery race 已在 `5801b0d` 固化修复：发现线程同步分类并形成最终
  snapshot，UI `BeginInvoke` 只负责显示；此前真机诊断曾观察到 0x7340/7341/7343/7344
  均由 Windows 返回，当前状态仍标为“Fixed in Code / Pending Hardware Regression”。
* BLE bridge 生命周期已在 `b478ebd` 收口：稳定窗口标题、single-instance/adopt、
  精确 executable-path owner；Studio 退出不再按进程名全局终止。Windows 手工验证待执行。
* HV-002 WCHISP 已在 `a05914b` 使用仓库内固定哈希的 3.6.1 五槽脱敏 baseline，按已知
  layout 只 patch CH582 槽；发布阶段拒绝 `.excluded` 和开发者绝对路径。代码/自动测试完成，
  WCHISP ISP 检测和真实烧录待真机验证。
* 首页 OLED 入口已在 `d9bea69` 改为“配置屏幕动画”，只导航到现有设置对话框，不再从首页
  直接上传。
* 当前资源预览已在 `e8af234` 增加受控 managed cache 与 profile×state 元数据；只有设备
  上传回调成功后才复制并保存 metadata，重启从 `StudioStore` 恢复，预览不读取设备 GIF 数据。
  自动测试完成，GIF/OLED 真机和 UI 手工验证待执行。

本轮新增 11 个定向测试（BLE driver locator 3、BLE readiness 2、WCHISP runtime/error mapping/log retention 6）；完整 Maven
结果以下一节以实际命令输出为准。当前工作区外层 `C:\aha\ahakey-windows\windows-stabilization-plan.md`
不存在，无法伪造同步；本文件仍是 `desktop` 工程唯一可用事实源。

提交边界：`5801b0d` HV-005 discovery、`b478ebd` BLE bridge 生命周期、`a05914b`
HV-002 WCHISP、`d9bea69` 首页导航、`e8af234` 当前资源预览、`29f5bd4` 文档，另有
`2900806` 发布清单 fixture 和 `91c264a` WCHISP 隐私哈希门禁测试。

## 8. 验证记录维护

每次交付追加实际命令和精确结果：

```text
mvn clean test
mvn clean package
git diff --check
PowerShell syntax checks (Windows PowerShell 5.1 and pwsh 7 when installed)
Test-ReleaseArtifactContents.ps1
preview-part3-release-overlay.ps1 (only with a real release baseline)
```

本轮最终测试数量、失败/错误/跳过数、package、发布 artifact、overlay 和真机状态
必须以命令实际输出更新；Authenticode 签名、WiX、正式发布基线、WCHISP、
USB/BLE/GIF/OLED/语音设备均属于外部依赖；firmware 1.4.7 HEX/provenance 开发基线已在本机。

本轮实际结果（2026-08-29）：使用仓库工具目录中的 Maven 3.9.16/JDK 17 执行
`mvn clean test` 通过（159/0/0/0），`mvn clean package` 通过（同样 159/0/0/0，内置
`RELEASE_ARTIFACT_CONTENTS=OK`）；Windows PowerShell 5.1 和 pwsh 7 均解析 9 个脚本
成功；独立 `Test-ReleaseArtifactContents.ps1` 与本地 JAR 清单检查成功。
`preview-part3-release-overlay.ps1` 未运行到编译阶段：缺少
`C:\Program Files\AhaKeyStudio\app` 发布基线；`build-installer.ps1 -PrepareOnly`
已确认允许省略 FirmwareHex，但因同一基线缺少 `AhaKeyStudio.ico` 退出。
以上不替代正式 overlay、签名安装包或真机验证。

本轮复核结果（2026-09-04）：`mvn clean test` 通过（171/0/0/0），`mvn clean package`
通过（171/0/0/0），并由 package 内置及独立 `Test-ReleaseArtifactContents.ps1` 验证
本地 JAR 含 BLE/审批/状态/模式类、`ScreenAnimationAssetStore`、WCHISP 脱敏资源和
`firmware-capabilities.properties`。五个 PowerShell 脚本解析通过；WCHISP privacy fixture
返回 `WCHISP_RELEASE_PRIVACY=OK`。使用本地构造的基线 JAR 做 overlay smoke test 返回
`OVERLAY_VALIDATION=OK`；正式 `C:\Program Files\AhaKeyStudio` 基线仍缺失，因此正式
overlay 和签名安装包未宣称完成。MSBuild 未在当前环境 PATH/常见 VS 路径发现；bridge
Release EXE 已存在于 `BLE_tcp_bridge\\bin\\Release\\BLE_tcp_driver.exe`，其此前重建结果
为 0 warning/0 error。USB/BLE、WCHISP、GIF/OLED、语音、Hook 和 Windows UI 真机仍待验证。

## 9. 历史记录

早期 132/148 tests、旧 `0x9D` capability 说法和 1.4.3 bundled 结论均为历史记录，
不再代表当前合同。历史 patch 可追溯，但不得覆盖本文件上述当前事实。

## 10. SW-001/SW-002/SW-004 交付记录（2026-09-06）

本轮仍基于只读 Firmware `firmware-stable-rebase-79`（runtime origin
`79ecabad3c8fd013aba7a6e12a13b5836fbc8924`）。固件、协议、GATT schema、GIF Flash
layout 均未修改。

* SW-001：Java 运行时优先解析 `<app-root>\ble-driver\BLE_tcp_driver.exe`，再尝试
  兼容旧 app 布局，最后才从应用/仓库祖先目录解析开发期
  `BLE_tcp_bridge\bin\Release\BLE_tcp_driver.exe`；找不到时列出全部尝试路径。发布
  输入强制将 Driver 放入 `app/ble-driver`，并输出 `BLE_DRIVER_BUILD`、
  `BLE_DRIVER_PACKAGED` 和 canonical path 门禁。窗口启动/置前/精确进程 ownership
  仍由 `BleBridgeProcessOwner` 管理；启动后在后台对 TCP 9000 做 5 秒有界就绪探测，
  端口未就绪会精确停止当前 owner 并向 UI 报告失败。
* SW-002：新增 `wchisp-runtime.json` 运行时合同，固定 3.6.1 tool/DLL/config contract、
  CH57x/CH59x、CH582 和配置 layout fingerprint；缺少组件、混合版本或未知配置均
  fail closed。`-u get` 的 exit 100 现在区分“Windows 已枚举 WCH ISP 但 UID 读取失败”
  与“未枚举设备”，并将 command/stdout/stderr/console/result/runtime-version/
  config-fingerprint 持久到 `%USERPROFILE%\.ahakey\logs\wchisp-last-failure`。
* SW-003：本轮只做回归确认，首页“配置屏幕动画”入口和无直接上传行为保持不变。
* SW-004：当前资源仍定义为 Studio managed cache 的 profile×state 本地记录；只有
  设备 ACK 成功后才更新 metadata，重启可恢复，不读取设备完整 GIF。

当前状态：SW-001 为“Fixed in Code / Pending Hardware & Release Regression”；SW-002
为“Fixed in Code / Pending Real WCHISP Runtime Hardware Validation”；HV-002 为
“Fixed in Code / End-to-End Blocked by SW-002”；SW-003 为“Fixed / Regression
Verified”；SW-004 为“Fixed in Code / Pending UI/Device Workflow Regression”。
这些状态均不等同于真机通过。

本轮最终验证（2026-09-06）：`mvn clean test` 与 `mvn clean package` 均为
`182/0/0/0`（failures/errors/skipped 均为 0），package 内置和独立
`Test-ReleaseArtifactContents.ps1` 均返回 `RELEASE_ARTIFACT_CONTENTS=OK`；合成发布基线的
`preview-part3-release-overlay.ps1` 返回 `OVERLAY_VALIDATION=OK`，正式
`C:\Program Files\AhaKeyStudio\app` 基线不存在而未能执行正式 overlay。6 个 PowerShell
脚本语法检查通过，BLE packaging fixture 和 WCHISP privacy fixture 分别返回
`BLE_DRIVER_PACKAGED=PASS`、`WCHISP_RELEASE_PRIVACY_GATE=PASS`。本机没有 MSBuild，
`dotnet build BLE_tcp_bridge` 因 .NET 9 x86 `GenerateResource` task-host 不可用失败；已有
`BLE_tcp_bridge\bin\Release\BLE_tcp_driver.exe` 仅作为待人工复核的现存产物。外层
`C:\aha\ahakey-windows\windows-stabilization-plan.md` 仍不存在，未创建伪权威副本。
