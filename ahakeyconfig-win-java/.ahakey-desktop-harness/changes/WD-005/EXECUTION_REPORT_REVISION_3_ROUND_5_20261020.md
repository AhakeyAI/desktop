# WD-005 revision 3 / round 5 修复执行报告

角色 DIB，模式 FIX，日期 2026-10-20。仅三项 R4 P2 缺陷的原合同内修复；等待原 DLA 实际复审，不是自审通过。

## 身份与范围

HEAD 为 f595262207796dbf325cb9951ed3dc02b4887362，仅源码存档；本轮没有 Git 写入。
原起点 41c034171e60b2d4962b0adbe8f3cffbf80a0436、有效 R3 批准、隔离记录、冻结报告及旧审阅不改。
修前指纹 e298ea1dd15131f508a602deed06181e0a53c6ff8b5c2366674dfc0cfb44d49d。
修后指纹：1fca9345199cd1166acd8b4df7125d3e17f1cad4032c7736dc1060361a2d3ccf。
生产指纹相对修前仅改变 AiRuntimeDisplayService.java、BleManager.java 和新增 displayconfig/DisplayConfigRound5Checks.java。开工、收尾 preflight 均 PASS。

## 修复与实证

- R4-F1：在后台来源过滤后、SINGLE 显示仲裁前保存精确身份的可信事实。A 的终态可更新事实但仍返回显示 IGNORED，不覆盖 B 的显示或 pending。新增测试覆盖立即和租约期间 A开始/B开始/A完成，调用实际 prepareApply、applyToKeyboard 和 0x99 序列化，验证 A 为 DONE，B 为 RUNNING；重连后两者事实均 EMPTY。
- R4-F2：使用进程内 SingleOwner(provider, sessionId) 表示显示占用，null 仅表示没有占用。匿名事件的空 sessionId 保持为空，不造 ID，不写匿名 liveFacts。来自其他具名或匿名工具的迟到终态不能覆盖当前工具。匿名自身正常开始/完成仍可发送。保留限制：同一工具的多个匿名会话无法区分，未声称解决这种身份缺失，也未改变 Hook 权限策略或引入会话聚合。
- R4-F3：flush 直接发送已保存的状态，不再经过会更新时间的事件接收入口。IOException 保留原事件时间；仅新事件重置时间。测试在第4分钟受控写失败，再把有效年龄推进2分钟，确认第6分钟不发送；另证新事件、最新替换、未知ACK保护与重连清理。

未改变五分钟 TTL、0x98/99/9A协议、MULTI匹配/主槽规则、后台过滤或允许策略。没有新增时钟/定时器/自动盲重试。时间测试利用现有私有时间字段受控调整，无需真实等待六分钟；传输使用内存替身并抛真实 IOException。

## 第五轮实际执行

全部日志在 .ahakey-desktop-harness/evidence/20261020-wd005-r5/，execution.json 保存精确命令和退出码。

| 检查 | 本轮结果 |
| --- | --- |
| 新增测试修前复现 | 13个断言失败，测试进程退出1，runtime-red.log |
| 离线 test-compile | 退出0，compile-final.log |
| DisplayConfigRound5Checks | 46项 PASS |
| DisplayConfigChecks | 175项 PASS |
| DisplayConfigFxChecks | 36项 PASS |
| DisplayConfigRaceChecks | 72项 PASS |
| DisplayConfigRevision3Checks | 72项 PASS |
| DisplayConfigRevision3UiChecks | 42项 PASS，生成 ui-round5.png |
| git diff --check -- src | 退出0 |

共443项实际执行断言，本轮重新运行旧397项并新增46项，未冒用旧日志。局部 FX/CSS 测试不等于完整产品UI/高DPI或真实设备验收。本轮未重做不受修改影响的中文编码探针，也未声称真实进程编码已验证。

首次新增测试编译因误用枚举 getCode() 失败，改为实际 getProtocolValue() 并修正帧内状态索引；compile-red.log 与后续 compile-red-02.log 均保留。正确编译后再执行修前红测试，随后才修改生产实现。

JDK D:\jdk-17.0.19.10-hotspot；Maven 3.9.12，离线本地 .m2repo。仅 test-compile 和隔离 main 测试，没有 clean/package、真实 App、网络监听、Hook安装、桥接/设备写入、烧录、发布。

## 正式提交绑定与未完成事项

本轮报告与检查表通过四项 record-check 的 evidence 参数绑定，再使用正式 submit。根 EXECUTION_REPORT.md 仍冻结；现有helper的 report_sha256 仍指向旧根报告，不可将其解释为第五轮报告。第五轮的有效执行依据是 verification 内四项的本报告/检查表/真实日志。最终是否 submit 及路由以新工具日志、builder_submission、IMPLEMENTATION_RECEIPT、STATE 为准，不由本报告提前认证。

保留 UP-01/UP-02 真机根因与恢复、缺来源后台事件、RT-03固件行为、BLE硬件A/B、桥接功能与产物身份、完整应用及USB/BLE验收。固件只读，不消费本次修复去宣告这些事项关闭。

当前无本轮实际测试包或 formal candidate。旧Preview与源码存档均不代替新包。下一步交回原DLA实际累计diff复审；高影响fresh审阅、候选、Preview/正式打包、固件/桥接身份和Owner UAT分别保留，不自动执行。
