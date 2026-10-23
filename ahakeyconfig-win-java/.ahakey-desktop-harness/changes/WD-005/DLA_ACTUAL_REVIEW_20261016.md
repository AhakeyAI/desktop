# WD-005 原 DLA 累计实际差异审阅（2026-10-16）

## 结论和身份

结论：FAIL，3 个合同内实现问题；退回 DIB FIX。当前不开放 Owner Preview。
这不是因为未有 formal candidate 或 fresh review 而阻止 Preview，而是有具体代码问题。
本记录不修改产品合同、不重新 Grill，不修改生产代码或固件，不代替独立 fresh implementation review。

- 任务：WD-005 / WS3 CP2 OLED 与灯光配置；正式登记 J005/J006，高影响。
- 审阅：Owner 指定的原 Windows DLA 对话，与 DIB 实现对话独立；未声称已取得会话 UUID。
- 起点与当前 HEAD：41c034171e60b2d4962b0adbe8f3cffbf80a0436。
- 本次提交指纹：3a967e3f34a85f7d346bdf3e35110bbe191a4d980effdb13218de4307659bb93。
- 本次 pack：reviews/20261016T061347403259Z-27f0c2/PACK.json。
- pack SHA256：26fc47fdb649dabb07e4f14780313cb7decb2e348ebf6ae1b22792ea423328f8。
- ACTUAL_DIFF SHA256：aebb2bbd7f7d09bc7204db7b58edc3aaf338f319b19a67b09718a2e565288a00。
- 23 个累计变更文件（包括新增文件），missing_start_bytes 为空；逐文件结论在 REVIEW.json。
- 生效需求按 REGISTRATION、change、正式批准理解；原设计草案保持历史快照，不重写。
- 本次只读代码、历史日志和固件资料，写审阅记录及 Harness 合法退修状态；不重新编译、运行测试或应用，不执行 Git 写操作、安装 Hook、设备写入或烧录。

## F1 / P1：自动回读抢占旧身份与模式流程

位置（当前源码）：
- DisplayConfigService.java:62-65 的 selectedMode/selectedPart listener；70-80 connectionChanged；145-156 refresh/openDisplayLease。
- StudioController.java:446-486 模式切换；742/755 连接回调；793-806 固件身份只请求一次。
- BleManager.java:396-397 旧命令在 displayLease 非空时被拒绝，0x00 除外。

实际调用链：
1. OLED 或灯光页打开时，连接状态回调首先调用 connectionChanged，排队 CP2 refresh，随后才请求 0x9F。
2. CP2 worker 若先取得读租约，0x9F 进入旧 sendCommand 时直接失败。controller 已设 firmwareCatalogKeyRequested=true，catch 只降级，不在当前连接重排身份请求。
3. 因而本轮连接可能无法进入正常能力识别及后续 0x97/0x87 和 AI onDeviceReady。若旧命令先进入，CP2 租约获取也可能失败并只显示同步失败，不自动重排。
4. 模式切换在启动 mode-switch-confirm 线程之前先 setSelectedMode，listener 立即排队 refresh；此时虽然 modeSwitching=true，refresh 没有据此避让。CP2 worker 抢先后，0x92 可被拒绝，模式切换失败回退。
5. 每个租约持有期间仍允许 0x00，且等待响应释放 commandLock，因此不是所有线程都被同一锁自动排队；其他旧命令确实可能看到 lease 并被拒绝。

这是新集成产生的可达并发错误，不是“没有测试所以推测坏了”。未宣称已在真机复现；复现取决于调度次序与面板状态。

修复边界：
- 在已批准模块内协调连接初始化、模式确认、按需显示回读的顺序与重排/取消。
- 不取消上传全事务互斥，不允许任意旧写命令穿透租约，不忽略 0x9F 错误冒充识别成功。
- 防止旧回读失败后永久降级，保留旧固件和 CP4C 路径。

需要补的确定性验证：
- 控制 worker/latch，使 OLED 或灯光页连接时 CP2 回读先运行，再启动身份读取；最终身份与输入配置流程必须完成，不能只置 fallback。
- 页面打开时切 Mode，延迟 0x88，验证 0x92/0x00 确认和本地 Mode 不错误回跳。
- 同时检查旧流程先运行的顺序，回读应等待/重排而非丢失；不得引入不受控无限重试。

## F2 / P2：CP1 模式先改本地，0x98 却被 CP2 租约拒绝

位置：
- InspectorPane.java:879-880 SINGLE/MULTI onAction。
- StudioController.java:176-178 直接调用服务并显示“已切换”。
- AiRuntimeDisplayService.java:154-169 先变更并持久化 displayMode，再异步发 0x98；失败只写日志。
- BleManager.java:396-397；AiRuntimeDisplayService 的 display-idle 回调只重发 pending snapshot，不重发模式。

可达路径：
- 在灯光页执行亮度/9项灯效保存，或存在 CP2 读租约时，SINGLE/MULTI 控件仍能操作。
- 用户从 SINGLE 切 MULTI，本地先改且提示成功；0x98 遭租约拒绝，设备仍 SINGLE。
- 后续 0x99 因设备模式不匹配而不能形成预期 MULTI 展示。反方向也同理。
- UI busy 仅用于部分新控件，不覆盖这个旧入口；只在底层拒绝不等于正确的用户层互斥。

修复边界：
- UI 与实际 controller/service 入口使用一致准入，在不允许时不要先持久化本地模式、不要宣告成功。
- 若采用排队而不是禁用，必须与现有确认/错误/连接语义一致，不得扩大协议或重新定义产品行为。
- 保留事务结束后 CP1 最新事实补发、无定时保活规则；不能靠发送所有旧事件解决。

补充验证：
- 有读/写租约时两个方向模式切换（含程序调用入口），本地/设备一致、消息真实。
- 租约释放后正常模式切换及最新 snapshot / SINGLE 状态不丢失、不重复旧事件。

## F3 / P2：灯光成功回调缺少 FX 提交时的连接身份校验

位置：
- DisplayConfigService.java:212 previewAccepted；223 savedBrightness；243 savedEffect；245 全部保存成功提示。
- connectionChanged:70-80；fx:265 只检查 closed，没有连接/操作校验。
- DisplayConfigState 的 savedBrightness/savedEffect 会确认设备值并清除对应 dirty。

可达时序：
1. 连接 A 收到有效 ACK，exchangeDisplay 返回。
2. 在对应 Platform.runLater 成功回调执行前，断连/连接 B 的状态更新先执行；connectionChanged 已结束预览并将资源状态标未知。
3. 旧成功回调随后执行，重建“设备预览中”或把新连接上下文的草稿标为已保存。
4. 后续读回可能覆盖已错误清 dirty 的草稿，界面也可能在断开或换设备后仍显示当前成功状态。

传输层返回前的 generation 检查不能覆盖返回后到 FX commit 的时间窗口。此问题不否定连接 A 的真实 ACK，而是结果没有与其所属连接隔离。

修复边界：
- 在 FX 状态提交处检查捕获连接和操作身份；分别处理历史确认事实、当前设备事实和用户未保存意图。
- 亮度、逐项灯效保存、完整成功提示及预览使用一致规则；过期回调不清除当前草稿 dirty、不重建过期预览。
- 部分保存计数如实保留，不把旧连接实际成功抹成“从未发送”。

补充验证：
- 控制 ACK 到达后、FX callback 执行前断连或切新代次。
- 延后执行亮度/逐项灯效/预览回调；新连接不被标已保存，不出现旧设备预览，不丢草稿。

## 实现风险与覆盖缺口（不冒充第四个已证实故障）

R1：BleManager 的 deferredRuntimeState 与 AiRuntimeDisplayService 的 snapshotPending 不是连接代次标记，
resetDisplaySession 未显式使两者失效。需结合 CP1 已批准生命周期，验证旧连接待发事件不会因新连接读租约释放而意外重放。
这是必须核清的跨连接风险；不能仅据字段存在就声称真机已错，也不能擅自取消已批准的重连同步。
DIB 应给出实际调用链/确定性验证和符合既有合同的处理，不新增产品语义。

仍需后续验证：
- 真实 USB/BLE 断连、超时、Flash/断电、生命周期与本机 Hook/语音回归。
- 最小完整窗口及 100/150/200% DPI；隔离 Canvas 图片不代表完整 Inspector 和对话布局。
- 磁盘只读/写满/进程中断、共享资源清理、旧资源迁移全流程。
- 17 灯效全部时相和物理显示效果；若只覆盖初始/部分帧，不能报完整视觉一致。
- 继承 USB native close/read 阻塞行为需真机验证；已捕获旧句柄与session，不据历史风险新增无证据缺陷。
上述未执行项没有自动豁免，也不是仅凭缺测试就判定功能故障。

## 已核对且未发现阻断问题的范围

- 0x88/89/8A/8B/8C/8E 与固件分型响应、ACK语义；19资源目标、160x80 RGB565 BE、
  28672字节补零帧、8/12帧容量、48字节chunk及CRC匹配。
- 上传全事务租约、ACK未知隔离、同连接禁止盲目重试、旧代次传输回调隔离；连接内未知不能假装成功。
- 全量保存过滤旧0x84/85，仍保留按键与0x04；新UI不再走旧raw OLED写入/预览。
- 本地资产/索引原子写入、内容校验与tombstone，避免清除后旧草稿自动复活；
  local/device draft区分及元数据按需读回，普通回读不主动清除dirty。
- 17灯效模拟逐项比照固件renderer；不将本地动画/初始golden等同物理验收。
- references中12项文件SHA与只读Firmware工作文件一致；未修改Firmware。
- 内部固件确认是当前连接的人工配对准入，不是从0x9F自动推断CP2完整能力或已烧录证明。
  绑定HEX SHA D7D10510482228B74A2978BD8272F6A4E32668CF6B4F31F491A8503B0DC11E2E；
  正式交测仍要实际包、Firmware identity、对应固件门和Owner实测。

## 机器证据与审阅界限

实际阅读 IMPLEMENTATION_CHECKS 与以下日志，并核对SHA：
- compile-06：C8C8E7D8397076A3C8BF4A26BA950773C54C305CB30B405B1708D69A7FD6BF8F。
- offline-05：C804F7C17D56A1EB13589FD36B73ADEFBC8999E1905A628E676106E3EB856DA2，175项。
- fx-02：47095D1487108D8C466B7C19A3B161713BE3B5C849EAEB6C0E1A3D9602558BB2，36项。
日志位于 .ahakey-desktop-harness/evidence/20261016-wd005-*。
编译成功与211项断言结论保留为当轮已执行范围，没有重跑、没有提升为全UI/真机/UAT通过。

## 交接限制

DIB 按 request-fix 形成的新 IMPLEMENT/FIX 状态修复 F1-F3、核清R1、增加对应回归。
只在当前 allowed_paths 内最小修改，不改Firmware/协议合同、不修无关旧问题、不触碰历史dirty。
不要重写冻结 EXECUTION_REPORT/原批准/起点；修复报告沿Harness合法本轮记录流程保存。
本退修不新增构建、应用运行、设备/Hook写入、安装或Git写授权；运行检查前核对已有授权，不从旧日志推导新授权。
修复后正式submit，由原DLA重新actual review；通过后可按Harness准备Owner Preview，
formal配对另需high-impact fresh独立实际审阅、Git candidate、实际包与Firmware identity。

