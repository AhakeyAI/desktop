# WD-005 revision 3 / round 5 原DLA实际复审

日期：2026-10-20。结论：原DLA actual review FAIL。上轮R4-F1/F2/F3的生产修复成立，但新增测试夹具未隔离真实USB自动发现/打开/发送，确认R5-F1 / P1阻断。不是formal fresh、candidate、Preview包、设备或Owner UAT通过。本DLA没有执行测试、构建、真实应用、Hook、设备或Git写操作。

## 固定输入

- 原起点41c034171e60b2d4962b0adbe8f3cffbf80a0436保留，HEAD=f595262207796dbf325cb9951ed3dc02b4887362仅源码存档。
- 当前源码指纹1fca9345199cd1166acd8b4df7125d3e17f1cad4032c7736dc1060361a2d3ccf。
- 正式submit时间2026-10-20T02:24:23+00:00，receipt/submission均round5；批准92a815701ffe38af7a6c8028e872f9146859055b654e06f703aa5bc3b3e5fd72。
- 固定包reviews/20261020T025357091458Z-f904f3/PACK.json；canonical pack SHA=4718a62c2fc00519aefe2c6388f57df88fb74f6b080afcd1f0c51dd19bf763c6。
- 累计ACTUAL_DIFF SHA=92f9f57aecdb4496fa61fb10980f9d5fed39765d63e9fd2dd512ac5af9a5081f，共31文件，无missing_start_bytes。
- 与第四轮固定after快照比较：28文件逐字节一致，仅AiRuntimeDisplayService.java、BleManager.java变化，新增DisplayConfigRound5Checks.java；31份当前工作区文件均与本轮after快照匹配。以原起点累计审阅为范围，不以HEAD下的两文件diff代替整个范围。

## 三项修复闭环

### R4-F1：可信事实与SINGLE展示分开

AiRuntimeDisplayService.java:309先更新有精确身份且未被判定后台的liveFacts，再在314判断是否覆盖当前SINGLE。A开始/B开始/A完成后，A终态保留但不发送，不覆盖B或上传pending。prepareApply/applyLiveFact/sendAppliedSnapshot沿用最新事实、五分钟TTL和连接代次；转MULTI时A为DONE而非旧RUNNING。

新增测试直接调用prepareApply、applyToKeyboard并检查0x99序列化字节，同时覆盖立即发送及lease延迟路径；重连后A/B均EMPTY。没有使用文件mtime制造状态，没有改变MULTI精确ID和唯一transcript规则。

### R4-F2：匿名来源仍保留显示占用

SingleOwner(provider, sessionId)把匿名工具占用与null无占用分开。匿名sessionId仍为空，不生成伪ID、不写匿名liveFacts。跨工具或不同具名身份的迟到终态不覆盖当前占用；同工具匿名自身正常终态仍可发送。

新增用例覆盖Codex→匿名Kimi→Codex迟到终态、反向具名占用、Kimi/Claude匿名交错以及正常自身完成。匿名自身终态目前在释放lease后断言，未单独断言lease内自身终态补发，这是覆盖缺口而非已确认功能故障。同一工具多个匿名会话无法区分的限制继续保留。

### R4-F3：补发不再推进观察时间

BleManager.java:785-789直接发送保存的deferredRuntimeState，不再进入会更新时间的sendRuntimeState。IOException在清空pending之前抛出，保留原时间；仅新事件在772更新时间。五分钟清理、cachedStatus连接检查、writeUncertain和lease准入保留。

受控传输在第四分钟抛IOException并检查时间原值；再推进有效年龄到六分钟，验证不发送且清pending。另覆盖新事件重置时间、最新事件替换、未知ACK禁止补发和resetDisplaySession清除旧代次。未新增时钟、保活、轮询或自动盲重试。

## 累计调用链与旧行为

逐文件记录见同名JSON；未变28文件沿用第四轮已实际逐文件审查，并在本轮验证字节一致与本次调用关系。再次核对HookDispatchServer分发、prepareApply/0x99、lease.release/notifyDisplayIdle、OledUploadService异常关闭前隔离和resetDisplaySession。没有新增锁顺序、权限allow、设备管理或协议变化。

原累计UI草稿/禁用与全局亮度、CP2上传固定目标/传输/连接、逐ACK、未知隔离、后台读88与身份/Mode/输入串行、FX操作/编辑身份、全量保存过滤84/85维持上轮结论。相关旧0x00/92/87/97/95/96/9F和重连偏好检查已由DIB重跑，但不据此宣称全部硬件回归完成。

## 证据核验

verification四项machine/core_regression/special_regression/mock均绑定round5和当前指纹。逐项重算verification及IMPLEMENTATION_CHECKS_ROUND_5_20261020.json所列evidence，全部匹配。根EXECUTION_REPORT及receipt的report_sha仍属历史冻结基报告；第五轮依据为verification直接绑定的第五轮报告、检查表、真实日志和接续记录。

修前runtime-red.log有13项失败，修后新增46项PASS。旧397项本轮重跑，合计443项；接续再次复跑443项不重复计数。本DLA只检查源码、日志和哈希，没有重跑测试。中文编码探针本轮未重跑，不能声称完整产品进程编码已验证。

## 未完成与下一步

UP-01/UP-02真实上传根因及恢复、缺来源后台事件、RT-03固件主槽回退、BLE性能A/B、桥接功能复审/实际EXE身份、完整应用与真实USB/BLE均待收口。以上不以此次Windows三项修复冒称完成，也不以缺少全部测试倒推本轮代码故障。

当前不能放行新Preview：须先修复下面的测试安全隔离问题，再对受影响证据重新核验/submit。正式high-impact fresh必须绑定有效pack，辅助子审不代替。正式candidate、新包、固件/桥接身份、刷入确认及Owner实际反馈各自准入。

本轮新记录独立保存，不覆盖第四轮FAIL或历史根REVIEW.json。Preview工具当前读取根REVIEW入口；下一步准备时需保留旧入口完整原字节并依法更新当前入口，再开新token，不能拿旧Preview token或旧fresh冒充当前轮。

## R5-F1 / P1：新增隔离测试仍可自动连接并写真实USB键盘

位置：src/test/java/com/example/ahakey/displayconfig/DisplayConfigRound5Checks.java:32-37、54-57、99-112；共享FakeSession位于DisplayConfigChecks.java:390-405。标准依据：PREVIEW_FIX_CONTRACT_R3_20261018明确测试不得调用真实硬件或网络服务。

确定调用链：Round5Checks.wire仅替换FakeSession的TCP输出，保留BleManager中的真实UsbHidTransport。interleave(false)首个事件经handleHookEventResult→sendRuntimeState→sendCommand:462→ensureUsbConnected:1017。没有lease/uncertain或已打开的替身时，会调用静态UsbHidTransport.isPresent；若机器插着匹配键盘，则closeTcpOnly/resetDisplaySession/open真实HID，随后发送0x90。模式应用和租约释放后的补发也能进入相同自动发现路径。retryTtl在lease.close后同样可走真实USB，绕开预期的受控TCP IOException。

这不是仅缺一个测试用例，而是测试自身违反已批准的离线安全边界；在开发机器连接键盘时可能写设备，也会令测试结果受现场设备影响。现有执行配方未设置阻断该路径的fixture，模拟BLE环境变量并不约束这个直接new BleManager入口。已有443项PASS不能证明硬件隔离。本轮只确认可达性，不断言历史执行已经连接或写过真实设备。

修复边界：优先只改displayconfig测试夹具/测试文件，在执行任一发送或lease关闭前保证USB发现、open、send及TCP真实连接均不可达。复用现有替身模式，但不能仅替换outputStream或要求Owner拔设备；若用状态字段固定传输，须证明resetDisplaySession后仍维持隔离，不能伪造quarantine从而掩盖被测重连/未知ACK语义。检查共享FakeSession的其他调用者，避免只修新增46项却让重跑旧397项仍触及硬件。需要生产可注入接口的改动若超出文件内职责，先交DLA，不自行扩大。

先静态完成隔离核验，再执行获准离线测试；补充能在“物理设备可能存在”的条件下仍拒绝真实I/O的确定性证据。不得为证明风险而连接或写键盘。保留所有既有日志，新增本轮隔离说明和执行日志；不得倒改第五轮的“未触设备”断言为经过证明的事实。

## 两轴辅助结论与处理

- Spec（Laplace）：R4-F1/F2修复成立；匿名自身终态在lease内的单独断言仍为覆盖缺口，不据此报功能故障。原DLA另行核对F3及真实补发链。
- Standards（Halley）：确认测试USB隔离P1，原DLA逐行复核上述可达路径后接受。没有要求借气味建议重构生产代码。
- 两位均只读、未运行测试，非正式fresh。正式record-check fail/request-fix仅依据新增R5-F1；不重新打开已修复的三项产品语义。
