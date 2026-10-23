# WD-005 round6：测试隔离的窄接口协调请求

角色：DIB；日期：2026-10-20。结论：R5-F1 未修复，未执行测试，需原 DLA 协调生产接口责任后再实现。

## 正式位置与动作

- 已读取 R5 actual review 的 Markdown/JSON、当前 change/批准、STATE/local、原起点与隔离记录；继承当前对话已读取的正式规则与合同，不重新解释历史草案。
- 本次 `python .agents/skills/ahakey-desktop-harness/scripts/desktop.py preflight --role DIB --id WD-005` 退出0，PASS。
- 当前 revision=3、build_round=6，STATE=IMPLEMENT/FIX，next_actor=DIB。本记录不手写路由、不代表 submit。
- 当前指纹仍为 1fca9345199cd1166acd8b4df7125d3e17f1cad4032c7736dc1060361a2d3ccf；生产和测试均未修改。
- 没有编译、运行测试、启动应用、网络服务、硬件探测或设备操作。静态已确认危险可达路径，不为动态复现而执行危险夹具。
- R4-F1/F2/F3 已获 DLA 确认的生产修复保留。第五轮历史日志和声明原样保留；不能由旧443项推导硬件隔离，也不据可达性断言历史确实写过设备。

## 静态证据

以下行号以本次未变源码为准，路径相对工作目录。

1. `src/test/java/com/example/ahakey/displayconfig/DisplayConfigChecks.java:390` 的 FakeSession 直接创建 BleManager，只有 TCP outputStream 为内存流。BleManager.java:42 的 usbTransport 默认仍为真实实例。
2. BleManager.java:450 的 sendCommand 保留实际准入/锁，:462 调用 private ensureUsbConnected；:1019 即使反射替换成关闭的 USB 替身，:1022 仍直接调用静态 UsbHidTransport.isPresent，无法由实例 override 截获。
3. UsbHidTransport.java:45/295/312 的静态链进入 Hid/SetupApi 枚举；BleManager.java:1029 随后 open，真实传输可进入 CreateFile/WriteFile。
4. BleManager.java:117 resetDisplaySession 清除 lease 和 uncertain，但不提供持久的发现替换点；:93 notifyDisplayIdle 会补发。因此仅在 lease 期间隔离不够，不能设置 read/write quarantine 来永久跳过发现。
5. BleManager.java:283 connect 建立线程，tryConnectUsb 在 :994 另有静态发现调用；:310/311 创建 Socket 并连接。测试可用覆写 connect 的失败关闭替身阻断此入口，但这本身不能阻断 sendCommand 的 private 自动USB发现。
6. 共享夹具调用者包括 DisplayConfigChecks、DisplayConfigFxChecks、DisplayConfigRaceChecks、DisplayConfigRevision3Checks、DisplayConfigRound5Checks。RaceChecks:266 和 Revision3Checks:162 有 always-open USB 替身，但只覆盖各自USB场景，不覆盖共享BLE/补发场景。
7. DisplayConfigChecks.java:320 现有 A10 测试用 displayReadUncertain 固定 TCP；后续修复应移除这类隔离捷径，真实未知ACK测试中的 quarantine 则必须保留实际业务含义。
8. DisplayConfigChecks:208/216/296 的其他直接 new BleManager 仅做反射报文解析。仍建议统一安全构造，避免未来用例新增发送而漏隔离；Revision3UiChecks/EncodingProbe 不创建该夹具。

## 为什么此处交回协调

没有找到能同时保持真实 sendCommand/ensureUsbConnected 的 BLE 分支、且可替换其静态发现的方法入口。以下方法不采纳：

- 所有测试强制 USB isOpen=true：虽提前返回，却把 BLE 与受控 TCP IOException 用例改成另一传输，不能继续声称原分支覆盖。
- 以 uncertain 固定传输：污染被测恢复/ACK未知语义，reset 后还会失效。
- 覆写整个 sendCommand：绕开本任务要验证的真实互斥/准入/传输逻辑。
- 同名生产类遮蔽、字节码改写、反射改原生静态实例：引入额外测试机制及身份风险，不作为窄修复默认方案。
- 要求 Owner 拔设备或先运行测试看看：不满足离线安全边界。

## 提请 DLA 评估的最小方案（尚未授权或实施）

仅 BleManager.java 新增一个受保护的实例发现判断（例如 protected boolean isUsbDevicePresent），默认转调 UsbHidTransport.isPresent；tryConnectUsb 和 ensureUsbConnected 的两处静态调用统一经过此入口。默认连接策略、锁、事务、时间、ACK和协议保持原样。不修改 UsbHidTransport 或其他生产模块，不引入全局测试开关。

displayconfig 下的测试专用 BleManager 子类覆写该入口为可控内存结果，并覆写 connect 为失败关闭；统一安装 USB 替身，覆盖 open/sendCommand/sendData/close/isOpen，使任何方法均不落入原生实现。TCP 流保持内存，不启连接线程。是否需要包可见注入而非 protected 方法由 DLA 审核，不在 DIB 当前范围内先行改动。

最低补充验证：

- 模拟 USB 存在/不存在，确认只调用发现替身和假 open/send；不枚举物理设备。
- FakeSession 初始化、无lease发送、lease关闭、reset后再发送及迟到回复，隔离策略均不丢失。
- 禁止 connect 的探针在启动线程/Socket之前失败，USB替身所有操作均内存化。
- 同时保留真BLE编码/内存输出链和USB替身链，受控IOException仍发生于目标分支。
- 去掉为隔离硬件而注入的假quarantine，保留真正未知ACK/TTL/连接代次测试。
- 先形成完整静态I/O核验，再运行适用回归；匿名自身终态在lease期间补发可补确定性断言，不重开产品语义。

请 DLA 按正式流程明确该窄生产接口职责是否获准，必要时维护有效合同/派工；不要仅因 BleManager 在 allowed_paths 内便默认整个类可改。获准并重新 preflight 后 DIB 实施、生成第六轮或届时有效轮次的新证据，再 record-check/submit。

本轮无新 PASS 检查表或提交回执；不更新旧检查，不降低门禁。Preview、fresh、candidate、配对身份及真实验收仍待原流程。其他跨端待办保留。
