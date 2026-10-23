# WD-005 R5-F1 测试隔离接口窄范围协调方案

日期2026-10-20；角色DLA。状态：方案已评估，待Owner明确确认及正式contract-reconcile绑定后生效。本文件本身不授权DIB修改生产代码，不改变STATE/批准/轮次，不是测试或修复PASS。

## 分类与必要性

仍属WD-005，不另开产品任务，不重新Grill已确认旅程。R5-F1修复要求隔离真实I/O，现有FakeSession只替换TCP输出，不能截获BleManager两处静态UsbHidTransport.isPresent。将全部测试强制USB、虚设quarantine或覆写sendCommand均会绕过应测的BLE发送/恢复语义。

现有效R3对BleManager文件内职责仅明确诊断、上传可靠性、查询调度和补发；allowed_paths有此文件不等于已授予任意测试接口改造。因此仅补充下述实例发现入口职责，保持原合同、线协议及批准历史；由Owner一次窄确认，再用正式contract-reconcile版本化。high_impact要求保留，不因为改动小降低门禁。

## 生产唯一允许改动

文件：src/main/java/com/example/ahakey/service/BleManager.java。

1. 增加一个受保护实例方法，例如protected boolean isUsbDevicePresent()，默认方法体只return UsbHidTransport.isPresent()。
2. tryConnectUsb及ensureUsbConnected当前两处静态发现调用改为该实例方法。其他控制流、顺序、异常、锁、连接代次、transport选择、超时、缓存、ACK及TTL保持原样。
3. 不添加环境变量/全局测试开关，不新建通用传输架构，不改变构造器、公开connect语义或现有用户配置。方法不是用户可配置功能。
4. 不修改UsbHidTransport及Socket生产实现，不绕过sendCommand。确有额外生产接口需要时再次说明具体原因，不凭本方案扩大范围。

## 测试允许改动

精确目录：src/test/java/com/example/ahakey/displayconfig/。可增加该目录内的专用测试夹具，修改其现有调用者。

- 测试BleManager子类override发现入口，固定为受控内存结果，不调用super；override现有public connect，在创建线程/Socket之前直接失败，禁止真实连接。
- 使用完整内存USB替身：open/sendCommand/sendData/close/isOpen均不可下落到原生实现，不执行静态硬件发现。不增加生产USB类改动；使用已有测试替换机制。
- BLE测试保持USB关闭、发现false、TCP内存流；USB测试用受控发现与假open状态，保留两种真实生产发送分支，不能一律always-open USB。
- 同步核对所有FakeSession调用者及直接new BleManager的解析用例。统一安全构造，避免新增发送时逃逸；不扩展到其他测试体系或生产模块。
- 去掉仅为隔离而设置的假displayReadUncertain；真正未知ACK测试仍应通过被测业务设置/验证quarantine，不降低保护。
- 不覆写sendCommand、exchangeDisplay、sendRuntimeState、flush或reset来制造PASS。reset后发现策略/USB替身仍必须有效。

## 先静态后执行

1. 形成静态I/O入口清单：构造、connect/reconnect、USB发现/open/send/close、Socket创建/连接、lease释放、补发、reset和解析入口。确认夹具所有实际I/O均只落在内存替身，才能运行回归。
2. 受控模拟USB存在/不存在；发现/open/send计数由替身记录，不枚举物理设备。调用测试connect探针必须在启动线程/创建Socket前失败。
3. 覆盖无lease发送、上传lease关闭、reset后发送、迟到回复、IOException补发失败、最新替换和五分钟TTL。USB与BLE分别保留有效断言，尤其TCP IOException不得被假USB绕开。
4. 重跑受影响共用夹具的适用旧用例及新增隔离用例；可补匿名自身终态在lease内补发的缺口，不改变匿名多会话不可区分限制。
5. 先前443项和红/绿日志保留，不冒充新批准/新轮次执行；记录实际命令、退出码、计数、输入和证据哈希。静态可达风险不证明历史已写硬件，旧PASS也不证明隔离。

不要求Owner拔设备作为隔离手段，不通过真实连接来验证风险。不得安装Hook、启动真实应用、写设备或烧录。

## 正式接续要求

确认前：只保存本方案及协调记录，STATE保持IMPLEMENT/FIX、revision3/round6；不改change.json/批准或运行contract-reconcile。

Owner明确批准后：保存原话证据；逐字节保留修改前change/STATE/批准入口；将本方案作为新增批准资产，旧资产不改。通过支持的contract-reconcile生成新有效批准/派工，不能手写phase或build_round，不使用repair-origin。以工具实际输出为准交DIB preflight。

生产指纹必须仍与当前1fca9345199cd1166acd8b4df7125d3e17f1cad4032c7736dc1060361a2d3ccf一致；若漂移先调查。无新协议/固件引用变更，不更换原起点，不覆盖旧报告/审阅/失败。

DIB按届时有效轮次实现、静态确认隔离、执行批准离线验证、新增报告并record-check/submit。DLA再审累计实际diff及测试安全；Preview、formal fresh、candidate、固件/桥接身份和Owner验收分别完成。

UP-01/02、来源缺失事件、RT-03、BLE性能和完整应用待办继续保留。R4-F1/F2/F3已修复语义不重开。本轮不改桥接/固件/Harness规则或seal，不执行Git写入/构建/危险测试/设备操作。
