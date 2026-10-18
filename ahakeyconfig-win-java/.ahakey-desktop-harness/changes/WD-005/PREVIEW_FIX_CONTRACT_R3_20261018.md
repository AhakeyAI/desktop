# WD-005 revision 3 汇总修复合同增量

## 生效与责任

Owner 授权：../../evidence/20261018-wd005-consolidated-fix-owner-authorization.md。
本增量经 contract-reconcile 后生效；与历史草案冲突时仅以下明确列出的修订优先。未提及的原 CONTRACT/PROTOCOL_AND_STATE/ACCEPTANCE 和所有历史批准保留，不重新解释成全部可改。

范围属于 J005 OLED 资源上传和 J006 灯光展示的 Preview 修复及必要依赖扩展。保留 high_impact 独立实际审阅要求。Windows 本次实现按新 revision 的 IMPLEMENT/preflight/submit 路径，不沿用旧两项 preview-fix token 提交。

整体问题统一追踪，Windows、桥接、固件三端分别承担实现责任。外部待办不阻塞 Windows 无依赖项实现，也不能因 Windows 完成便关闭全部问题。DLA 只修改治理证据，不代 DIB 修改生产代码。

## 问题与交付条件

| ID | Owner 症状及修复边界 | 责任与最低证据 |
| --- | --- | --- |
| UI-01 | OLED浅底白字；局部样式修复，禁用态仍可读，不全局改label或取消禁用 | Windows；隔离FX实际样式/截图与对比度检查 |
| LOG-01 | PowerShell终端乱码；统一新配方的进程级控制台编码和Java UTF-8，涵盖stdout/stderr/JUL/文件日志 | Windows交付；真实中文样本；不改系统区域、注册表、profile，不把现有正确UTF-8文件误转码 |
| UP-01 | 首次Begin FAIL、重试成功 | 三端定位；记录entry/连接代次/offset/阶段，找出原因再定修复，不自动重试掩盖失败 |
| UP-02 | 上传中ACK超时、后续运行态受保护暂停 | Windows/传输/固件分段取证；保留未知隔离，反馈待核实/重连恢复；不得删除保护或盲目发下一包 |
| FB-01 | SINGLE未实际发送却反馈更新成功 | Windows；尊重sendRuntimeState返回值，区分接收事件/待补发/发送，不扩大成设备已显示 |
| RT-01 | 无可见任务却SINGLE反复运行/结束 | Windows；事件与会话来源关联，排除已证实后台预测/维护事件；不得屏蔽所有7/8状态或把日志时间等同身份 |
| RT-02 | MULTI槽位4误运行和旧状态重现 | Windows；严格会话身份、无cwd/project唯一兜底；持久绑定不等于当前运行事实 |
| RT-03 | 主槽无有效状态时屏幕转而跟随其他槽 | Windows保持真实foreground/valid；固件协调仅跟随明确主槽，主槽无运行态回正常默认展示，不伪造有效主槽、不清掉其他槽灯光 |
| UI-02 | OLED MULTI缺运行模式入口指引 | Windows；资源区附近轻提示“多任务展示开关位于灯光页”，不得将资源类别标签变成运行模式开关 |
| UI-03 | 灯光右侧各区关系不清 | Windows；下述已确认结构、禁用逻辑和草稿保护 |
| BLE-PERF-01 | 单帧28672字节/598包上传221.760秒 | 三端；先计时分解，再独立A/B优化；不承诺未经实测的速度，不用压缩/无ACK冒充解决 |

诊断记录仅保存工具、会话稳定ID、事件名、来源分类、匹配结果、连接代次、上传offset和时长等必要元信息，不保存完整聊天、原始stdin正文或用户敏感内容。

## 灯光 UI 有效语义

1. 顶部 AI 展示模式 SINGLE/MULTI，仍为全局运行选择；与键盘Mode 1-4分开。模式成功ACK后切换界面生效状态，失败保留原模式与错误；编辑期间不自动写其他配置。
2. 全局亮度对两种模式均适用，独立预览/保存，不随模式禁用。
3. SINGLE 区为当前键盘 Mode 的九项状态灯效；仅 SINGLE 可编辑/预览/保存。
4. MULTI 区为四任务槽、主槽摘要和原管理入口；仅 MULTI 可编辑/应用。可以查看已有摘要，禁用时不销毁绑定、不隐式发snapshot。
5. 非当前模式区浅色且禁用，文字仍可读；切换往返保留未保存草稿和本地绑定。上传锁、连接身份、未知ACK等原禁用条件继续叠加，不能模式一切就解锁危险写入。
6. OLED 的资源类别选项不改变运行模式；可准备另一模式资源，不把灯光区禁用规则错误套到OLED本地导入。
7. 不新增MULTI自定义灯效协议，不新增全局导航、云端能力表或资源分区。

## 运行态修复边界

- 保持SINGLE九种输入、MULTI三类显示映射、0x98 set-only、0x99完整快照、0x9A ACK-only、5分钟失效/无定时保活和Quiet/Sleep优先级。
- MULTI有稳定ID时必须精确匹配；ID冲突时不能再用transcript或cwd救回。仅在无ID且已有可靠的一对一transcript绑定时可以精确路径识别。无身份/未知会话事件不改变任意槽位；Cursor禁止workspace/thread_id替代conversation身份。
- 重新打开/切模式/应用不得把磁盘上旧lastIdeState直接恢复成现在RUNNING；绑定元信息保留，运行事实必须有本进程接收到的可信事件与有效期。允许必要的在内存身份状态管理，不以文件mtime制造任务事件。
- SINGLE保持已有正常工具兼容；仅排除具有明确来源证据的后台预测/非用户任务。没有索引记录不自动等于后台，新会话索引延迟不能导致真实任务被丢弃。无需读取完整聊天或轮询所有历史日志；如来源无法可靠区分，保留诊断并回DLA，不凭字符串猜测完成修复。
- 上传期间存最新可信事件；解除租约且连接和恢复门禁有效后补发最新事实，不重播过期事件历史。多个会话交错及迟到终态必须有回归证据；若需新产品聚合规则超出最小错误归属修复，回DLA说明，不自创。
- RT-03为外部固件依赖：当前固件存在非主槽回退。Windows不能伪造valid=1、抹掉其他槽或冒称已修好；收到固件正式配对事实后验证。

## 蓝牙优化本轮范围

Windows只做分阶段计时、真实进度/耗时反馈、合并非必要的设备查询、保护上传事务与运行态补发；不能暂停断连/身份感知。桥接本地缓存查询不当作全部无线流量。保留48字节chunk、现有ACK/CRC与USB64字节报告。

桥接独立任务：先核实EXE来源，按实际MTU适配分片、有界顺序队列、每次GATT结果处理及连接代次隔离；处理并发客户端帧完整性。不默认启用无响应写。固件独立任务：资源事务专用按扇区一次擦除、按页编程、失败状态与ACK可靠性；不要全局改通用Flash驱动影响其他配置。详见 CROSS_COMPONENT_WORK_20261018.md。

MTU/高吞吐连接参数先取证，双方能力支持且符合现有协议时实现；需新增桥接控制消息或固件协议时返回DLA正式协调。压缩、大chunk、窗口ACK、新分区和CP1.5不在本轮批准内。

## Windows allowed_paths 与文件内职责

原 allowed_paths 保留，但仍受原职责限制；新增/扩展仅如下：

- InspectorPane.java、StudioController.java、style.css、messages_*.properties：上述UI、反馈、草稿/忙碌状态，禁止改按键、侧拨、语音或设备管理业务。
- AiRuntimeDisplayService.java：从仅CP2延迟补发扩展到FB-01、RT-01/02会话归属和运行事实生命周期；不任意改变主槽选择、TTL或模式语义。
- 新增允许 `src/main/java/com/example/ahakey/service/HookDispatchServer.java`：必要来源元信息传递和诊断/真实结果，不改权限allow策略、端口或用户Hook文件。
- 新增允许 `src/main/java/com/example/ahakey/service/CodexSessionDiscoveryService.java`：来源分类所需的有限只读元信息，保护会话标题/项目分组和索引优先规则，不读聊天正文。
- 新增允许 `src/main/java/com/example/ahakey/model/AiRuntimeSlotBinding.java`、`src/main/java/com/example/ahakey/util/AiRuntimeStore.java`：仅绑定与运行事实分离的兼容读写，旧用户绑定不能丢失或批量清配置。
- BleManager.java、OledUploadService.java、DisplayConfigService.java、UsbHidTransport.java：仅诊断、上传可靠性、非必要查询调度及最新事实补发；原身份准入、代次/锁顺序/ACK隔离不可削弱。
- `src/test/java/com/example/ahakey/displayconfig`：本轮确定性断言、隔离FX及受控传输测试。无新增依赖；不得调用真实应用入口、Hook安装、硬件或网络服务。
- 编码启动配方保存于新阶段报告/后续新产物配方；没有新logback/App/Main/安装器代码权限。必须扩大路径时先回DLA，不借整目录泛化。

Windows禁止触及兄弟桥接源码/包、固件、Harness核心、用户.ahakey/.codex/Cursor配置、config_server.json、历史冻结文件和Git写入。

## 验证与提交

原A01-A11保留，追加本问题表逐项证据映射；缺测试不自动等于代码故障，也不能自动豁免。修复前后的断言应接真实调用链。

- UI：正常/禁用、模式切换成功失败、草稿保留、与上传锁叠加，OLED三类局部文字，UTF-8 stdout/stderr/文件。
- 运行态：同目录不同ID、不匹配ID+相同transcript、无身份终态、后台事件、真实新会话、重启旧RUNNING、真实完成、交错会话、上传期间最新事实与恢复后补发。
- 上传：首次Begin拒绝、分块超时、Commit未知、迟到ACK/旧连接、重复点击，均无假成功/无危险重试；USB和BLE路径分别覆盖。
- 性能：既有221.760秒为历史单次基线；桥接/固件分别A/B，空白与覆盖资源、多帧、断连及输入响应，真实设备数据待Owner。
- 旧功能：0x00/0x92/0x87/0x97/0x95/0x96/0x9F与原Hook管理、会话选择器、USB/BLE偏好同步不得回归。

允许DIB离线编译及隔离测试，不自动package/启动产品/杀进程/安装Hook/设备操作。保留现有.m2repo/target和历史dirty，不mvn clean。新报告独立保存，不覆盖冻结EXECUTION_REPORT及其SHA；按正式submit接受的证据机制绑定当前结果，若工具只能绑定旧基报告则明确并使用verification追加当前证据，不能冒称旧报告是本轮执行。

独立审阅、候选、产物、固件身份、Owner实际反馈依旧分别收口。本轮仅合同修订不能标任何缺陷FIXED或UAT通过。
