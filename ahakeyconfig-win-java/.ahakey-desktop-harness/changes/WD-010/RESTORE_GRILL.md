# WD010 设备恢复子阶段：固件事实与逐项 Grill

日期：2026-11-04。状态：CHANGE，Q1至Q6及主流程整体已确认；Owner随后要求继续细化UI内容及实现异常场景，接续详细GRILL，尚未批准完整实施；无生产实现/设备操作。
授权：`.ahakey-desktop-harness/evidence/20261104-wd010-restore-owner-intake.md`。

## 已查明的事实

1. Windows 右上更多菜单已有“恢复当前模式默认值”。TopBar.java:267 调用 StudioState.restoreCurrentModeDefaults（:520），只修改当前模式草稿并提示等待保存；不是整机恢复。
2. 固件当前 APP/sub_main/command_solve.c:493 的 command_k1_restore_handle 使用 0x9E 的 0x30 查询、0x31 发起/手动重试。旧 docs/investigation 中 0x96 A5 5A 是历史信息，不能作为当前实现依据；当前 0x96 另有 onboarding 语义。
3. 当前协议：查询 `AA BB 9E 01 30 <nonce:u32_le> CC DD`；发起采用支持重复恢复的 v2：`AA BB 9E 02 31 <nonce:u32_le> <expected_next_attempt:u32_le> CC DD`。17字节回复包含 result/version/sub/nonce/state/attempt。expected_next_attempt 必须是已读取 durable attempt + 1，拒绝重复/过期/超前值。result=0 本身不是最终完成证据；必须匹配请求和 attempt，确认 COMPLETE 及设备实际配置回读。
4. USB 或 BLE 配置通道可发起，但必须有 USB 外部供电（充电线供电 + BLE 也可）。活跃上传、写配置、恢复进行中等条件拒绝；不能自动中止其它写操作来强行恢复。
5. 恢复范围：四模式键位/宏/描述（Mode4为空）、拨杆、语音引导和绑定默认值、待机、灯光、显示/GIF选择及19条用户资源 metadata；回 Mode1/SINGLE，清临时预览与任务状态。仅将用户资源标记为无效/空，不要求物理擦除全部资源数据，不宣称安全擦除。
6. 保留：固件版本、设备身份/名称、蓝牙配对及关联、制造校准信息、工厂资源和保留字段。不能将恢复等同于 Forget Computer 或清除蓝牙身份。电脑云端账号不是此固件操作的范围。
7. 一旦 durable IN_PROGRESS 已写入，关闭桌面软件或断开通信不会取消恢复；没有取消命令。丢回复仅查询状态，不自动重新发起。失败/断电可能进入 INCOMPLETE，限制正常输入/配置；需用户明确手动重试。成功后桌面端丢弃恢复前设备草稿，重新读取设备，不能自动写回旧配置或旧 MULTI 状态。

## 正式记录及证据局限

只读根：C:/Users/20825/Desktop/vibe-code；观察 HEAD 24f72d3e0301aa6bb2fa9e1b99337033bb801a4d。已运行 Windows firmware-status / firmware-discover；cursor 已初始化，未推进消费游标。
WS45 STATE.yaml 显示 WS45_CP1_RESTORE_INITIALIZATION accepted_with_debt；2026-10-30 closure.md 记录旧硬件范围 PASS_WITH_DEBT，候选 ed426c97d4aad9a20c1585d6b15125252b6caa49、HEX SHA256 07A8DF32F86BD0B74C62F1C52D4217EFE77AD9821D02B355CB96E163D1CD271A，Owner 确认重复恢复和重启场景。
该记录保留真实断电、存储擦除边界、硬件矩阵等 NOT_VERIFIED 债务；不能转述为全硬件/正式发布安全通过。
本轮可直接读到的 Restore formal receipts 为 20261024T154509、20261025T095317、20261025T133952；最后一个绑定旧候选 292a49f3 / 6EC0413C...。closure 引用的 20261027T203634 receipt 在当前绑定根的 evidence 搜索中未找到，且 closure 已声明正式 HEX 路径缺失、另有 SHA相同副本。不得拿 10/25 的 v1 receipt 冒充 10/27 v2 的交测绑定。后续正式交测前应继续核验原身份/确切产物，不要求 Owner 手工搬运已存在资料，也不自行重建 Firmware receipt。
当前全局 Firmware 已推进到 HW1_RESPONSIVE_OFF，其 PASS 不自动重新验收 Restore，当前源码存在不证明当前设备安装版本匹配。本次只作产品 Grill 与证据准备，不制造 firmware-intake 的合格 gate 绑定。

## 读取的正式及源码依据

- .ahakey-harness/project-state.yaml
- .ahakey-harness/workstreams/X1-PLATFORMIZATION-RELEASE-COMPOSITION/{STATE.yaml,PRD.md,ARCHITECTURE.md}；Architecture 的 Restore product scope / wire allocation
- .ahakey-harness/evidence/checkpoints/X1-PLATFORMIZATION-RELEASE-COMPOSITION/WS45_CP1_RESTORE_INITIALIZATION/checkpoint-review/20261030-oldline-close/closure.md
- .ahakey-harness/evidence/stage-b/WS45-20261026-repeat-restore-after-complete-amendment.md，结合 STATE 的 accepted amendment 判断，不把旧 draft 尾注当最新路由
- APP/sub_main/command_solve.c、APP/sub_main/main.c:883
- APP/services/restore_initialization.{c,h}、APP/services/k1_restore_store.h
- tests/host/restore_initialization 下的单元/生产旅程测试源（只读，不执行 Firmware 脚本）

## 逐项 Grill

Q1 已确认：Owner 要求把现有“恢复当前模式默认值”改名为“恢复出厂设置”，同一位置接入整机恢复；删除原仅恢复当前模式草稿的功能。此前推荐的“新增并保留旧项”未获采纳，不得沿用。原话存于 evidence/20261104-wd010-restore-q1-owner-decision.md（Harness 根）。
Q2 已确认：一次明确确认弹窗列出目标设备、恢复范围、配对保留、USB供电要求和不可撤销说明，默认聚焦取消，点击“确认恢复出厂设置”才发起。不要求输入文字。原话存于 evidence/20261104-wd010-restore-q2-owner-decision.md（Harness 根）。
Q3 已确认：同一弹窗说明未保存的设备配置也将丢弃，确认即丢弃并恢复，取消原样保留；恢复后以设备读回值为准，旧草稿不自动写回。原话存于 evidence/20261104-wd010-restore-q3-owner-decision.md（Harness 根）。仅涉及目标设备配置草稿，不删除账号或无关本地文件。
Q4 已确认：入口始终可见可点击，未连接/不支持/已知忙碌时明确解释原因，不发起恢复。证据见 evidence/20261104-wd010-restore-q4-owner-decision.md（Harness根）。无法提前判断的USB供电等条件由固件最终裁决；result=1通用拒绝不作为确切原因证明，不通过试发恢复探测支持能力。
Q5 已确认：采用独立进度和结果窗口，显示正在恢复、正在读取配置、完成或需处理等真实阶段，不造百分比。证据见 evidence/20261104-wd010-restore-q5-owner-decision.md（Harness根）。防重复提交、等待设备状态、失败不自动重试、完整读回后才显示成功等约束保留。
Q6 已确认：允许关闭进度窗口，明确标注“关闭窗口不会停止设备恢复”；当前应用继续查询，再点菜单打开同一进度/结果，不重发恢复。证据见 evidence/20261104-wd010-restore-q6-owner-decision.md（Harness根）。关闭整个应用也不取消固件，重启后仅查询状态，不自动发起/续跑。
主流程方案：RESTORE_PRODUCT_SCOPE.md；Owner已确认主流程，随后指出具体UI及异常分支不足。详细草案见 RESTORE_UI_CASES_DRAFT.md，继续逐项讨论实际窗口内容，不重复Q1至Q6。固件事实继续自行查证；不要求Owner手工搬运。
Grill 完成并经 Owner 确认共识后再收敛 Contract、正式批准及 DIB；原云端账号/AhaType/兑换充值范围保留。
