# WD-005 revision 5 / round 8 实际审阅

## 结论

request fixes。R8-F1 是当前自动能力/UI合同内明确遗漏，R8-F2 是一并修正的低风险测试清理问题；无需重新 Grill 或扩大合同。DLA 仅保存审阅与正式路由，不修改生产或测试代码。

## Findings

- **R8-F1 / P2**：`src/main/java/com/example/ahakey/view/InspectorPane.java:964` 的任务槽 support Label 在构造时通过 `service.isDeviceSupported() || !deviceStatus.isConnected()` 选择文本。已连接但 READING/FAILED/UNKNOWN 时，false 被解释为“当前固件不支持”，与新动态身份原因冲突。该文本本身不绑定身份变化。保留本地绑定说明，改用中性说明或统一身份状态；不得以“尚未识别成功”推断“不支持”。补实际该说明构造/绑定的隔离回归，而非无关合成控件断言。
- **R8-F2 / P3**：`src/test/java/com/example/ahakey/displayconfig/DisplayConfigCapabilityChecks.java:51` 在 try/finally 外执行 `Platform.startup`。初始化抛异常后无法执行 user.home 恢复与约定清理。将初始化纳入异常安全边界，保留对 Windows 已加载 JavaFX 临时缓存的合理处理，不能操作真实用户缓存。此问题本身不是生产通信故障或历史设备写入证据。

## 审阅身份

- pack：`reviews/20261021T014802199747Z-1f3f15/PACK.json`
- pack_sha256：`df63e71fe522d61a2b5af477d72e973c6961e45527c87ae54983cd39f4343d39`
- code_fingerprint：`3c1e7cf6a1180291d396d2ad288f44a9b57b5a7e74b27b6334d3299b801b7c3c`
- approval：`5ca53dc27d3bb53b05e7b48932f7a39b8db387fb730f112fa6e6c031e69ec6cf`
- HEAD：`f595262207796dbf325cb9951ed3dc02b4887362`，仅源码存档。
- 原起点：`41c034171e60b2d4962b0adbe8f3cffbf80a0436`，未改动。
- 累计 35 文件与固定 after 字节相同；相对 R7 快照 20 文件不变，15 文件变化（11 生产、4 测试）。逐文件说明见同名 JSON。未把相对 HEAD 的差异当作累计范围。

## Standards 与 Spec

Standards：职责及路径符合 R5 合同；未发现测试绕过真实发送逻辑或重新开放真实 USB/TCP 的确定问题。测试初始化异常边界有 R8-F2。

Spec：核查精确原始 0x9F 响应、私有权威身份及票据、连接代次、请求/缓存/收包/FX隔离、USB 切换、活动 lease 等待、ACK 未知不被识别解除、CP1/CP2 底层准入和 legacy SINGLE。未发现其他确定新阻断。四分区及禁用状态主逻辑符合合同，但旧 support 文案造成 R8-F1。默认草稿/绑定保留与旧写入过滤静态保持。

辅助 Standards/Spec reader 仅辅助本 DLA 实际审阅，不是正式 high-impact fresh。

## 证据核对与局限

- 检查表绑定的 48 项证据哈希匹配；最终 05 日志八个进程退出 0，共 608 项（新增 101 + 重新执行 507）。前四次日志不资格化最终输入。
- DLA 本轮未重新编译或运行这些断言；608 项不是完整应用、完整控制器、实际交互、高 DPI 或物理设备结果。
- 根 EXECUTION_REPORT 与回执 report_sha 仍绑定冻结历史基报告；本轮执行依据是 verification 直接绑定的新报告、检查表与真实日志。
- 合成 FX 控件、票据谓词和 TextField 草稿断言不能替代真实 Inspector/Controller 生命周期、资源持久化和任务绑定的完整证明。覆盖缺口不直接判为功能故障。
- UP-01/02、来源缺失事件、RT-03、BLE 性能及完整应用缺口保留。正式 fresh、candidate、新包、固件/桥接身份和 Owner UAT 分别收口。

## 接续边界

用本轮 JSON 正式 record-check review fail / request-fix；以命令返回的实际轮次为准。DIB 仅修 R8-F1/F2，保持已完成自动准入、锁、TTL、代次、ACK隔离及其他功能不变。先 preflight 与静态 I/O 隔离检查，再运行受影响的离线回归并如实记录本轮数量，不把旧 608 当新执行。新增报告与日志，禁止追加冻结根报告。提交后回原 DLA 实际复审，通过后再走新 Preview。

本轮没有生产/测试/桥接/固件修改，没有构建、启动应用、Git 写入、Hook、设备或烧录操作；旧 Preview 不是本轮测试包。
