# WD-005 revision5 / round9 实际复审

## 结论

原DLA actual review PASS。R8-F1/F2关闭，无新增阻断项；可按既有授权进入隔离Owner Preview准备。不是formal high-impact fresh、Git candidate、构建或真机/UAT通过。

## Spec

实际任务槽入口InspectorPane.createAiRuntimeGroup调用runtimeSlotSupport()。中英文资源只说明本地绑定保留，不再通过!isDeviceSupported推导不支持。权威身份/忙碌/模式原因仍走原displayReason动态绑定，优先级、按钮准入、槽位算法和业务服务不变。28项新增断言直接调用真实工厂及装饰器，覆盖双语和六状态。R8-F1已修复。

覆盖限制：测试设置原因键，不是完整Controller身份链和实际面板交互；高DPI与鼠标键盘仍需Preview。未发现范围外行为。

## Standards

withIsolatedHome把Platform.startup纳入try，Exception/Error原样保留，退出异常附为suppressed，finally恢复或清除原user.home并尽力清理临时目录。cleanupHome调用参数均来自本次createTempDirectory，不跟随符号链接，保留临时.openjfx加载缓存；不访问真实用户缓存。R8-F2已修复。原硬件隔离类字节未变，仍封闭发现和connect，不覆写完整sendCommand。

20项新增受控生命周期断言覆盖启动IOException、初始化Error、主体与退出双异常及成功缓存保留。未逐项动态注入null home、仅退出失败或删除失败。夹具准备在进入helper前失败可能残留新建临时目录，属于测试进程低风险观察，不是产品/设备故障，不为此扩大本轮重构。

辅助Spec/Standards reader与本DLA结论一致；两者不是正式独立fresh记录。

## 固定输入及累计范围

- PACK：reviews/20261021T023808688339Z-41baa7/PACK.json。
- pack_sha256：79b4a6d87283e22acae6b537a106a9007f426caf06fb5fcda57b15ea49074087。
- code_fingerprint：98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9。
- approval：5ca53dc27d3bb53b05e7b48932f7a39b8db387fb730f112fa6e6c031e69ec6cf。
- 原起点41c034171e60b2d4962b0adbe8f3cffbf80a0436；HEAD f595262207796dbf325cb9951ed3dc02b4887362仅历史源码存档。
- 累计35文件当前字节与pack匹配，ACTUAL_DIFF哈希匹配；相对R8只有4文件变化，31文件逐字节相同。四文件完整hunk审阅；其他文件承接本DLA R8同字节实际分析并复核窄修接入影响，逐文件记录见同名JSON。不使用相对HEAD空diff充当累计审阅。
- 当前REVIEW入口更新前原字节保存在本pack目录REVIEW_ENTRY_BEFORE_R9.json，SHA256=CDECC6D2E58253CFBF2DFD9E944980079DC415ED398193376A88C629A2B7A4C1。R8报告、旧批准、起点和固定pack未覆盖。

## 执行证据

IMPLEMENTATION_RECEIPT为round9，submit时间2026-10-21T02:25:45+00:00。verification四项检查绑定本轮报告及检查表。19项证据哈希匹配；原始01日志八进程退出0，149+64+175+36+72+72+46+42=656，其中48新增、608本轮重跑。DLA只读核验，没有重跑。

根EXECUTION_REPORT/report_sha仍为历史基报告，不能解释为本轮执行。编译通过、组件断言不是整应用或真实USB/BLE。UP-01/02、来源缺失事件、RT-03、BLE性能、完整应用及正式fresh/candidate/实际新包/固件桥接身份/Owner UAT均保留。

## 路由

root REVIEW仅作为当前原DLA实际审阅入口。正式review check保持pending并绑定R9报告，原因是当前pack的high-impact fresh未完成；不得降低风险或引用旧fresh假通过。Preview使用正式preview-open，不手改全局VERIFY/DLA_REVIEW。构建由已有DIB按真实token与snapshot执行，DLA不构建、启动应用或操作设备。
