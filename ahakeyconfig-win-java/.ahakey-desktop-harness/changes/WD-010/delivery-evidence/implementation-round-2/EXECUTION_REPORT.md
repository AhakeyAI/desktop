# WD-010 第2轮执行报告

2026-11-05，DIB / IMPLEMENT / FIX，第2轮。修复正式审阅 FR-01、FR-02、FR-03 和本轮早期反馈 ER2-01、ER2-02，交回 DLA 审阅。以下是实现与机器检查事实，不是独立审阅、正式固件、真机或 Owner UAT 结论。

## 身份、范围与历史

工作目录：C:/Users/20825/Desktop/windows软件代码/desktop/ahakeyconfig-win-java。
HEAD：70ccc3361ecd90e6c67828bac581a6975ebdccb2；分支 codex/win-zxy-work；未执行 Git 写入，尚无 WD-010 Git candidate。
起点指纹：b184b8b7478757a45d39a65e803a677914a1ab8eb2c7d17a24704e6cedc47775。
第1轮提交指纹：fc132cf04011722017bbaa714aa8fc2e0f611f9a899fafd8243af816a52749ed。
本轮最终指纹：aeda3627d82d8d5b7c9751dfde57c366d59ed65f176018daa8e912099d0e67ef。
累计39个批准范围内变化文件，本轮相对第1轮变化12个；逐文件 SHA 与路径见 evidence/r2-IMPLEMENTATION_CODE_IDENTITY.json。沿用已批准 revision 1、J007/J017/J018/J019，未修改 Contract、Owner 批准、Harness 核心、Firmware、eternal 或既有无关 BLE bridge 脏文件。

第1轮报告、回执和提交记录原字节保存于 recovery/implementation-round-1/，Harness request-fix history 也有历史归档。第1轮报告 SHA256：0d2c3ccc454418238f951c834cc58c3b48bc63e6f841e58051fbb97dc972301a；回执 SHA256：5503d9c24c5cd0f92788fa3fc068b90b424b9516597613ccc72e4724a47f3353。原有未加 r2 前缀的日志和证据未覆盖。第1轮实现背景和旧失败对照以该归档为准，本报告取代其恢复准备行为描述。

## 修复与验证映射

### FR-01 / ER2-01：发送前本地准备失败可恢复

FactoryResetStore 增加本地准备日志，保存原 runtime 字节与原 pending；LOCAL_PREPARING 可证明尚未发送，先持久准备 SINGLE，再持久化 SENDING 后才进入启动交换。预发送阶段保留原草稿文件和 live draft；pending 隔离正常加载/保存，真正越过发送边界后才按连接代次失效 live draft。runtime 的落盘错误、SENDING 保存失败及 FX 执行失败都进入本地回滚，不制造永远等不到的下一 attempt。

本地回滚失败保留可达的“重试本地清理”，不需要连接或设备关联，也不发送查询。即使 pending 已清除而 preparation 清除失败，也保持本地保护和重试入口。启动加载器在可证明未发送的回滚失败时加载原草稿，避免默认值以后覆盖原稿；清理成功回调从恢复后的 runtime 恢复 live displayMode。真实保存/重载验证原键位仍在。

FX 等待在动作尚未开始时超时会取消排队动作，释放队列后不得迟到变更；动作已经开始则等待实际完成再报告失败或解除保护，跨30秒仍保持锁。准备日志有大小、schema、任务ID、Base64和runtime JSON边界校验。

SENDING 是保守派发边界：标记持久化与真正发送之间的崩溃无法判明是否已发，因此按未知任务隔离、只允许查询，不自动回滚或重放。旧 PREPARED、SENDING、SENT 同样不当作可证明未发送。本地原草稿在发送后继续被隔离，完整读回成功才保存替换；不能用旧草稿作为设备完成证据。

证据：RestorePreparationChecks 最终61项，真实生产 adapter、StudioStore/AiRuntime、真实原子文件和 JavaFX；传输仅内存端点。覆盖无效草稿、runtime写后异常、发送标记失败、清理日志失败、断连重试、启动顺序、live模式恢复、排队FX超时和已经开始FX跨30秒失败、发送后持久化失败不重发。RestoreChecks603、生产UI21、runtime竞态7同时通过。

### FR-02：明确开始下一张兑换码

已成功兑换后显示“兑换新码”，只有用户显式点击才清空旧码并开启下一次输入；同一窗口可连续兑换 A、B，各一次请求。进行中与未知结果仍禁用重复提交，关闭再打开不自动重发。服务端已确认成功但资料刷新401时保留终态并提示重新登录，当前失效会话不能开启新兑换。

### FR-03 / ER2-02：确认交易成功后刷新401保留终态

AhaTypeService 为同一原始会话的服务端过期保留受控交付关联。CloudAccountManager 以带 delivery Session 的 OperationResult 返回交易终态；兑换成功和已支付不会被随后刷新401吞掉，并使主账号页回到登录。另一并发请求先触发401时仍可沿同一原始会话交付终态。显式退出、新登录及取消认证操作切断关联，旧终态不能更新新账号。订单轮询代次和窗口关闭取消继续生效。

证据：CloudTransactionUiChecks47项，真实 FX 事件、账号/兑换窗口与二维码窗口逻辑、本地 HTTP Server；包括新码、未知结果、兑换/支付确认后401、另一请求先401、显式退出/换号隔离。DLA最后指出的更早时序也已用阻塞兑换/order-status成功响应→另一请求401→释放成功响应覆盖，两种交易均显示成功终态；主动换号对照抑制旧响应。核对发现对应生产分支已使用operationDelivery，因此最后仅补测试，没有再次修改产品。CloudChecks52、CloudUiChecks7通过。

## 实际检查与证据

环境 Java 17.0.19.10、Maven本地缓存 .m2repo。最新编译命令为 mvn -Dmaven.repo.local=.m2repo -DskipTests test-compile，r2-compile-07.log 为 BUILD SUCCESS；102个产品源码、44个测试源码。compile05至compile07仅增加已经开始FX超时及更早401时序测试，无产品改动。

完整命令、各自隔离 home、退出状态、日志 SHA 与范围见 evidence/r2-EXECUTION_EVIDENCE.json；27份本轮日志/截图的哈希见 evidence/r2-LOG_MANIFEST.json。11个套件通过，10个有计数的套件合计931项，DeviceMaintenanceChecks另为无计数套件：

| 套件 | 通过项数 | 最终日志 |
|---|---:|---|
| RestorePreparationChecks | 61 | r2-RestorePreparationChecks-04.log |
| CloudTransactionUiChecks | 47 | r2-CloudTransactionUiChecks-03.log |
| CloudChecks | 52 | r2-CloudChecks-01.log |
| VoiceFinalChecks | 32 | r2-VoiceFinalChecks-01.log |
| RestoreChecks | 603 | r2-RestoreChecks-01.log |
| RestoreProductionUiChecks | 21 | r2-RestoreProductionUiChecks-01.log |
| CloudUiChecks | 7 | r2-CloudUiChecks-01.log |
| RuntimeRestoreRaceChecks | 7 | r2-RuntimeRestoreRaceChecks-01.log |
| SpeechLifecycleCheck | 37 | r2-SpeechLifecycleCheck-01.log |
| DeviceMaintenanceChecks | 套件通过 | r2-DeviceMaintenanceChecks-01.log |
| DisplayConfigIsolationChecks | 64 | r2-DisplayConfigIsolationChecks-01.log |

核心回归记录绑定最后3个相关既有套件；专项/模拟记录绑定前8个WD-010套件。git diff --check -- src/main pom.xml src/test/java/com/example/ahakey/wd010 退出0；只出现已有LF/CRLF提示。未扩展无新失败或未解决问题的测试。

r2-compile-06 因PowerShell拆分未引号包裹的Maven属性参数，在编译前以未知lifecycle phase退出1；保留日志，compile07使用正确引号退出0。

本轮最初 RestorePreparationChecks-01 失败为测试夹具添加了既有 AiRuntimeStore 不接受的 customPreserved 字段，启动变为 SINGLE 默认值；保留该 exit1 日志。夹具改为既有支持的 codexDataDir，未放宽产品解析器；最终61项通过。第1轮 DisplayConfigCapabilityChecks 与 K1RouteEditorChecks 的历史失败及旧1.0.19成品对照继续保留，未改写为PASS，本轮未重跑这两个额外诊断。

## 交付状态与接续

本轮仅有编译class和机器证据，没有新JAR、EXE、安装包或Git candidate；没有执行真实账号/兑换/付款、麦克风/模型推理/SendInput、真实设备恢复/断电、安装/驱动/Hook、kill、模型下载、烧录或发布。mock和本地FX测试不等于真实后端、真机或安装包PASS。正式恢复v2固件Gate/Artifact仍需DLA只读发现和绑定。

本轮完成 record-check 后 submit 至 VERIFY / DLA_REVIEW，由原 DLA 自动读取本聊天与冻结回执，核验最终身份并继续实际/独立审阅。Owner不需要复制转交、切换聊天、付款、刷机或测试。审阅通过后沿既有授权继续完整 local-model EXE；构建阶段用最终包自己的runtime跑关键套件与现有 SpeechNativeCheck 公共WAV。构建和测试写各自阶段记录，不修改本次冻结报告。DIB不自填review、real_device、owner_uat。
