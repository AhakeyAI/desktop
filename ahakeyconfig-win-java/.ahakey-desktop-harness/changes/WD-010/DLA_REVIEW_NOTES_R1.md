# WD-010 DLA 实际累计差异审阅，第1轮

审阅会话：01a1a594-ba84-7a33-bd03-48125a887c69。Builder：01a1a968-73d2-7cc3-84e1-0487f363f991。
Pack：251455d9e58d17bc8e54bbd2115b2532f7ac1b9e5a1f6467941591b4d6bafead。
代码：fc132cf04011722017bbaa714aa8fc2e0f611f9a899fafd8243af816a52749ed。
本轮实际逐段阅读2298行累计diff和对应生产上下文，覆盖37个文件；不存在缺失起点字节。尚未登记PASS。

## 逐文件语义

- pom.xml：加入二维码ZXing依赖，离线构建和包内依赖需由最终EXE验证。
- StudioController：真实菜单服务接线、恢复生命周期、维护写入阻断、关闭释放。
- DeviceMaintenanceCoordinator：恢复专用只读/启动权限、连接代次及普通事务互斥。
- DeviceStatus：读回待机值。
- DisplayConfigState：恢复清空及真实读回状态。
- FactoryResetState：进度、待核实、只读及忙状态。
- StudioState：全部模式草稿清理及实际图片选择映射。
- WindowsCredentialStore：用户级DPAPI封装，凭据不明文持久化。
- FactoryResetProtocol：v1查询、v2 expected-next启动、nonce和17字节响应严格校验。
- K1RouteProtocol：空路由有效读回判断，不将缺失响应伪装成功。
- AhaTypeConfig：账号存储及旧明文凭据迁移、严格损坏处理。
- AhaTypeService：兼容旧响应、真实最终文字接口、20秒超时、会话世代、有效期和额度、单次输出delivery guard。
- AiRuntimeDisplayService：恢复期间清除旧运行偏好，真实发送监视器内检查维护epoch。
- BleManager：帧重组、原设备身份、恢复边界权限及专用catalog读回。
- CloudAccountManager：登录注册、账号刷新、兑换和原充值顺序；写请求绑定点击时会话。
- FactoryResetService：确认、持久化意图、一次启动、仅查询恢复、完整读回和重连隔离。发起前本地失败路径存在阻塞问题，见下文。
- FactoryResetStore：严格记录及原子持久化、连接/设备身份判定。
- K1RouteService：完整读回能力判断。
- UsbHidTransport：固定17字节二进制恢复响应，不按payload内尾字节提前截断。
- VoiceInputManager：最终识别后异步整理、一次输出、录音世代/取消与账号guard。
- StudioStore：严格存取、pending时不载入/保存旧草稿；删除与后续失败必须修复事务边界。
- CanvasController、CanvasPane、InspectorPane：目标只读时禁止编辑和写入入口。
- CloudAccountDialog：单实例窗口、输入保留、登录态刷新、兑换/充值真实handler。成功后的新兑换和会话失效反馈存在缺陷。
- FactoryResetDialog：默认取消的一次确认、进度窗口关闭不取消、人工关联仅查询。
- FloatingVoiceNotification：显示真实整理等待提示。
- TopBar：云账号/刷新和恢复入口、待核实banner、旧模式恢复移除。
- messages_en.properties、messages_zh.properties：菜单标题统一。
- CheckProcess：隔离进程测试执行器，不作为产品入口。
- CloudChecks：DPAPI/loopback/真实20秒超时及历史schema；未执行真实账号交易。
- CloudUiChecks：真实JavaFX handler、401回登录、失败输入保留及排队兑换的账号隔离。
- RestoreChecks：帧全部拆分、权限及确定性失败状态机；当前未覆盖意图存储后、发命令前的本地准备失败。
- RestoreProductionUiChecks：真实controller和恢复生产适配器、全字段读回及末尾metadata失败；内存USB不是硬件通过。
- RuntimeRestoreRaceChecks：真实worker卡在transport monitor后跨恢复epoch放行，旧MULTI不能迟到写入。
- VoiceFinalChecks：真实AhaType→VoiceInputManager、捕获输出、取消/新录音/退出后禁止迟到文本。

## 阻塞发现

1. FactoryResetService.confirm先保存expected-next的PREPARED记录，随后生产discardDraft先删除studio-draft，再调用可能因runtime偏好保存/strictSnapshot失败而抛错的factoryResetStarted。此时还未发送start，却被归为UNKNOWN；原设备attempt仍是旧值，后续query一直不匹配且锁无法解除。草稿可能已删。必须修复已知未发送的本地准备失败，保持草稿且零恢复写入，不能把这条路径作为固件结果未知处理。真实发送/回复丢失的未知仍应保持仅查询，不得自动重发。
2. CloudAccountDialog成功兑换后永久禁用submit，后续同会话复用同窗口，无明确新兑换入口。要保留本次结果和防重复，同时允许用户显式开始新码。
3. 兑换/支付已收到成功后刷新资料遇到401时，服务使会话失效；完成回调及UI旧会话检查会吞掉已确认成功，窗口可能停留在处理中。必须将该次已确认成功和权益刷新失败分别表达，同时仍阻止结果污染主动切换后的新账号。

独立最终报告提供复现与正式发现编号；三项汇总路由同一次FIX。未修复前不得preview/build通过。

## 保留行为与限制

旧系统Win+H路径、hook/BLE桥与安装脚本不在本次生产修改内；相关回归已有记录。DisplayConfigCapabilityChecks和K1RouteEditorChecks同点失败已在实际1.0.19旧包复现，不能计为通过也不扩大本次范围修旧断言。
Harness最后正式关闭baseline仍为WD-005；Owner对1.0.19实际通过的反馈是本轮最近体验依据，不伪造新的formal闭环。原始start及批准保持不变。
本次涉及protocol，风险high，需不同于DLA/DIB的独立最终审阅绑定新pack。Firmware v2源码依据已审；匹配正式receipt及HEX缺失，故不能宣称正式设备配对UAT通过。线上模型效果、真实付款/兑换、真机恢复与安装尚未测试。
