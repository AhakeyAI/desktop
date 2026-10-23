# WD-005 第二轮原 DLA 实际差异复审

日期：2026-10-16。结论：原 DLA actual review PASS；F1-F3 已修复，R1 已核清并处理。
无新增阻断发现。本结论不是 fresh 独立审阅、完整 A01-A11、Owner Preview、真机或 UAT 通过。

## 输入身份和实际审阅范围

- build_round=2；HEAD/原起点：41c034171e60b2d4962b0adbe8f3cffbf80a0436。
- 提交代码：aea60d8c7eb936cb937cc59522fed7224c845ecf7947cedb17e8f029ad1656c8。
- PACK：reviews/20261016T081132690299Z-1be30b/PACK.json。
- pack_sha256：2e7ab919025f1b0ca1ae339d01eb3d9fffeb8825c35a938adec008f0110f8ab0。
- 累计24个文件，无missing_start_bytes；对比第一轮pack的after及累计diff，实质改动7文件：
  StudioController、DisplayConfigState、AiRuntimeDisplayService、BleManager、DisplayConfigService、
  InspectorPane、DisplayConfigRaceChecks。其余17段累计diff不变（比较忽略段末空白）。
- 逐文件/逐问题结论写入REVIEW.json，并在本pack的DLA_REVIEW_ROUND_2.json保留副本。
- 第一轮fail报告及pack内DLA_REVIEW_20261016.json不变。原批准、起点、隔离和冻结基报告不重写。
- 本次只审阅源码/文档/历史日志，未重跑编译/Java断言、未运行完整应用、未作Git写或设备操作。

## F1：后台回读与既有流程协调

关闭依据：
- BleManager.readDisplayConfig:139开始，整个后台读批次持有commandTransactionLock；
  与readFirmwareCatalogKey/readSideSwitchConfig/readOrdinaryKeyConfig/setWorkModeAndVerify共同串行。
- monitor后取得commandLock；已开始的legacyWaiters用Condition有限等待，await释放commandLock，
  接收线程仍可回包，最后归零signalAll，不新增无限重试。
- read批次的lease.release在monitor内完成，notifyDisplayIdle在monitor外执行：
  避免CP1 snapshotSendLock -> commandTransactionLock 与回调逆序等待。
- DisplayConfigService监听modeSwitching；进入确认立刻取消loadGeneration，确认中不排新读，
  结束后按实际当前Mode刷新；旧已在途的一包允许完成，后续过期批次停止。
- StudioController.applyBleStatus先启动身份请求后安排显示回读；
  正确性不单靠线程启动先后，真正排他由shared monitor承担。
- 写入仍使用原整笔DisplayLease，竞争旧命令仍拒绝；没有为解决读竞争放开上传写互斥。

证据：RaceChecks.identityOrdering(true/false)让两个方向先取得响应等待，
后续0x9F、0x97、16条0x87、14条OLED元数据均完成；modeOrdering模拟实际model事件顺序，
调用真实setWorkModeAndVerify完成0x92/0x00、取消旧读并刷新新Mode。
这些测试未构造StudioController；实际事件接线另以源码复核，不冒称完整UI验证。

## F2：CP1模式冲突准入和确认提交

关闭依据：
- Inspector的busy/loading/modeChangePending禁用两个模式按钮；
  点击后展示仍恢复为service已确认值，既有displayMode listener在成功提交后rebuild。
- StudioController不再立即显示成功，依据service completion给出结果；busy/loading先拦截。
- AiRuntimeDisplayService.setDisplayMode独立检查实际lease/未知写/pending；
  冲突不改偏好，在线支持的设备收到0x98成功ACK且FX代次仍相符才持久化；
  FAIL/连接变化不会虚假切换。离线本地偏好行为保留。
- BleManager的0x98/99等待均检查非零错误，并关闭跨断线等待；捕获代次检查到实际发送和返回。
  不新增固件字段、query或request-id。

证据：cp1Admission在读/写租约中分别测试两个切换方向，确认零0x98、不改持久偏好；
延迟ACK验证确认前不成功，成功后提交；FAIL保持旧模式；反向正常成功。
实际按钮点击/完整应用仍待Preview，不能把72项服务断言当作完整Controller验收。

## F3：灯光FX提交、编辑意图与历史ACK

关闭依据：
- DisplayConfigService的Operation/current/deviceFx于FX提交时检查操作号、连接代次、
  wasConnected、BleManager及cachedStatus；亮度、每项灯效、最终成功提示、预览全部使用。
- 异常回调同样过滤旧设备上下文；finally按操作号清busy，不让过期结果冒充当前设备事实。
- DisplayConfigState对亮度/每项灯效记录编辑revision，同值再编辑也不能被旧ACK清dirty。
- 成功ACK按连接/操作/目标/数量写日志，不将旧连接的真实确认历史抹成“从未发送”。
- 预览时限从ACK后时刻起算；延迟超过10秒的FX回调不再重建预览。
- 本地导入/清除不因设备变化被取消；OLED结果保留冻结entry及unknown降级逻辑。

证据：staleFx覆盖亮度/九灯效/预览 x 断连/新代次六组合，刻意等worker排完回调再切连接，
随后验证dirty/预览/提示/busy；新设备回读不覆盖意图。sameValueEdit和ACK时间断言补充覆盖。
受控队列验证不是所有操作系统调度的穷举，也不代表物理断连已验收。

## R1：跨连接pending隔离，保留既有重连偏好

关闭依据：
- resetDisplaySession在commandLock内清SINGLE deferredRuntimeState；flush同锁执行。
- MULTI snapshotPending关联snapshotConnection；idle捕获代次后传入sendAppliedSnapshot，
  并持续传到BleManager.sendMultiRuntimeSnapshot实际发送前后检查，不只在回调入口检查。
- 原onDeviceReady仍发送当前偏好0x98，不因新连接读租约释放任意重放旧0x99。
- 同连接保留最新事实，原绑定、primary、TTL和事件驱动规则未重新定义；无新增保活。
- pendingGeneration覆盖同连接latest-once、旧连接不重放、连接偏好保留和新事实可发。
这是对原合同内风险的核清和关闭；真实USB/BLE生命周期继续保留后续验证。

## 累计实现与既有功能保护

对照累计diff和真实入口复核上传整笔lease、0x00例外、未知CP2 ACK quarantine、
同连接不盲重试、按需读取/旧ticket取消、资源草稿与设备事实分离。
全量保存仍移除旧0x84/85但保留按键与0x04；新OLED不调用旧raw/0x82写路径。
CP2协议、转换器、库、模拟器及transport累计段与第一轮不变；没有发现第二轮暗改旧协议或资源格式。
固件12项REFERENCES实际文件哈希逐项匹配；Windows审阅不修改Firmware、不代表设备已刷此HEX。
保留第一轮累计审阅已列的继承风险与缺口，不把无关旧问题扩大为本轮修复。

## 第二轮证据绑定

IMPLEMENTATION_RECEIPT/build_round=2、fingerprint与当前pack一致。
receipt.report_sha256仍为历史基报告：
749264589c44656848f062fcf3b4ecf35784bef80f7356dc1f204834d69a19a2。
这不是第二轮报告的hash，不能将旧报告当作新轮执行结果。

verification的machine/core_regression/special_regression/mock四项均直接绑定：
- EXECUTION_REPORT_FIX_ROUND_2.md：
  47edd5b155d39a65ef8959cfccb3414b9420c3d020a6278b7bb948064cbdf96e。
- IMPLEMENTATION_CHECKS_ROUND_2.json：
  92166a4105ddf0e02a192d3be2a5f5ec46288ee5ec0475c4994a2f72e9b72e10。
八个直接绑定逐一重算匹配，四项均是当前round/fingerprint/approval。

检查表七份实际日志逐一SHA匹配；读取结果和新增时序用例：
- 两次compile成功；原175离线与36隔离FX本轮重跑。
- races-02：72通过；races-03为相同72重复运行，不加倍计数；唯一合计283。
- races-01失败日志保持，直接呈现DLL清理AccessDenied；不能补造被覆盖的主异常栈。
  时间戳接收入口的夹具修正与新源码/后续结果相符，不是放宽生产行为或跳过断言。
- JavaFX unnamed-module及Maven模型警告保留，不宣称无警告。
- Owner本轮窄授权记录允许本地编译/隔离测试，不包括Preview打包或启动真实应用。

## 未执行与下一阶段

以下是覆盖缺口，不是已确认功能故障，也没有自动豁免：
完整App/Controller/Inspector/TopBar操作、最小窗口及100/150/200%DPI、
真实USB/BLE/Flash/断电/Hook/语音、磁盘故障穷举和旧迁移全流程、灯效全部时相及物理输出。
缺口须随Preview/后续验收逐项记录实际结果，不可从本轮pass扩大成完整A01-A11。

原DLA通过，代码审阅方面具备进入Owner Preview准备的条件；fresh和Git candidate不是Preview额外前置。
当前仅授权审阅/正式记录，本轮不执行preview-open（其生成build_authorized记录和源码snapshot），
不代Owner新增Preview构建授权；需下一步明确授权仅隔离Preview构建，再按Harness绑定包与启动入口。
可同时将当前固定pack交另一独立DLA会话做high-impact fresh actual review。

formal record-check review pass要求fresh_review_record。本轮不制造fresh，不降低risk；
用review pending登记当前原DLA通过/fresh待完成的正式证据，清楚区分两层结论。
STATE保持VERIFY/DLA_REVIEW，不以手改STATE冒充CANDIDATE_PREP。
正式配对仍需fresh实际审阅、Git候选、实际包、Firmware identity及Owner真机反馈。

