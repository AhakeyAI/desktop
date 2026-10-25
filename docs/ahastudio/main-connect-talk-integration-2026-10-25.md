# main 与 connect&talk 整合方案及确认记录

当前状态（2026-10-25）：用户在逐项确认后最新指示“阅读下固件最新代码现状，如果确实不行就先安装现状执行客户端适配和整合”。已重新拉取固件仍为0a055ba，重复恢复缺口提交固件Issue #9；现开始按已确认规则适配和整合。下文“待确认/未实施”均为原审查时的历史状态；未取得新HEX、不对当前键盘执行恢复，安装将在候选验证后进行。

## 冻结依据

| 项目 | 本轮基线 |
| --- | --- |
| 客户端仓库 | AhakeyAI/desktop |
| 最新main | 0ddab17fc8128d4090a5f1963354be666771f6f3，含PR179 Windows Java整合，以及最近macOS修复 |
| connect&talk | 2b6941850c84fed81d1e439b0a7ccb4700360914 |
| 共同祖先 | 1b8882a5c7f546e60a1b868c16edbab46104184f |
| 分叉 | main独有82提交；connect&talk独有256提交，不等于82/256个功能 |
| 文件范围 | main较祖先492文件（其中Mac40）；适配分支396文件（其中Mac270）；双方共同修改26文件 |
| 模拟合并 | Git merge-tree发现20个冲突文件；未改工作区/索引或提交实际合并 |
| 正在安装运行的版本 | 0.2.3/build376，e3e210a；不是当前分支最新源码，也不是最新main |
| 固件接入基线 | harness/x1-refactor-main/0a055ba，独立于客户端main |

最初CPU/BLE/Hook的runtime提交37697fb、8ab1278、d9d117c、53c2220本身不在两条客户端分支的直接祖先链，但其旧版迁移提交8015307（PR76/857d415）及后续bfa8896均是main和connect&talk的共同祖先。因此不能用旧SHA未出现认定修复丢失，也不用再把原runtime改动重迁一次。后续冲突仍可能重新破坏这些行为，需要保留回归。

## 已执行的验证

- main固定0ddab17：隔离工作区执行完整Swift测试179项，零失败。
- main：完成arm64 release App＋Agent组装及ad-hoc深度严格签名验证。只生成本地审查产物，没有安装、启动、公证或发布，不作为正式签名包。
- main远端CI40071191416成功；connect&talk最近完整本地测试715项通过。两个基线单独通过，不证明合并后通过；没有运行带20处冲突的合并树。
- 根据当前ApprovalBindingPolicy.effectiveSwitchState原函数构造隔离JSON探针：正常0/true返回自动；switchState及physicalSwitchState为false仍返回自动；approvalAutoVerified为数字1仍返回自动；0.5返回手动。只执行纯函数，无Agent/socket/实际授权/用户配置写入。
- 自动合并后的CI文件已同时保留Windows Java任务及适配分支Mac安装包／发布守卫，仍需在最终整合提交上实际运行。

## 推荐整合路线

把最新main合入现有connect&talk，在这条统一分支保留适配历史、导入main修复，并按功能解决冲突。整合后HEAD必须包含冻结main作为祖先。保留main为上游发布基线，当前不直接提交main，不rebase已共享的256项历史、不force push，也不把整批提交逐个cherry-pick后再维护第二条长期分支。

这条路线符合“基于最新main整合”和此前“只维护connect&talk”的决定。main源代码中Windows及其他平台文件按其上游结果保留，本轮不改写跨平台产品实现。先冻结安全回退点；在用户确认后才执行实际merge。若实施时main已前进，先更新差异和验证范围，不默默沿用本报告旧结论。

## 全量已识别风险及处理决定

以下区分实际缺口、已复现问题、两边重叠实现和合并后仍待验证项；不是承诺静态分析能穷尽所有真机故障。

| 编号/优先级 | 当前证据与风险 | 推荐处理及验收 |
| --- | --- | --- |
| R01/P0 分支与文件覆盖 | 20文件文本/二进制冲突；AhaKeyStudioView、Agent、BLE、云端、语音均重叠。整文件选择main会失去适配，整文件选当前会丢main修复 | 按下述功能批次手工整合；逐项建立main修复→整合实现→测试映射。禁止只按“ours/theirs”批量选边 |
| R02/P0 异常值误批准（已复现） | main AHK-053新增严格JSON类型；当前实际审批入口在共享ApprovalBindingPolicy，仍以as? Int/Bool接收JSON桥接值，纯函数已复现false/数字1被接受。HookSupport即使自动合入严格辅助函数，也不会自动修复这条入口 | 在共享实际授权边界统一严格整数0/1及真正布尔；四CLI均补相同负例。无授权继续原链路，不能借修复重新返回deny |
| R03/P0 Agent/socket所有权（缺口） | main AHK-015有进程存活期flock、并发接收、读超时和仅删除死socket；当前startSocketListener仍使用connect探测、listen(5)、无该实例锁 | 引入main锁和接收改进，保留当前BLE所有权、代际、Codex恢复日志及主队列可变状态。验证慢连接/双Agent/退出再启不抢socket、不误撤或误批 |
| R04/P0 Codex权限语义冲突 | main SessionStart/PermissionRequest会调用默认config策略同步；当前已按用户授权改为原桌面会话下一轮同步、精确持有者读回和恢复，不默认改config.toml | 保留当前新授权/原会话/journal流程；导入main严格解析和Hook配置保真修复，改造旧policySink测试以验证新需求，不能恢复默认策略硬改或假称本轮立即生效 |
| R05/P0 Kimi产品策略冲突 | main AHK-049对原生Kimi写default_permission_mode（自动yolo/手动manual），只影响新建会话；当前明确保留原版终端、状态Hook，不接管其权限，等待运行中原会话接口 | 用户本轮明确要求保留main现有默认权限控制，并在此基础上完善；同时核查Desktop/TUI原会话接口，保留9项原生观察事件。区分当前会话、同TUI的/new与重启CLI，不能因原会话外部附着未验就删掉已有能力 |
| R06/P0 草稿/确认基线（缺口） | main AHK-021新增loadSynced/saveSynced；当前没有同等整份持久化。main只在旧“全部写入”路径更新，自动合入模型函数也无法覆盖当前每组件提交 | 接入当前单键/Voice/灯条/屏幕/待机/拨杆每条成功路径，只有确认的组件更新基线。区分本地Host偏好、键盘事实、设备与连接；保留当前2项草稿，迁移不能把整份草稿当已写入，也不能单组件保存清除全部草稿 |
| R07/P0 新旧固件路由 | 新固件9E与旧固件共用同目录key；main仍是旧键位/全局语音链。新固件K1由route store决定，旧73/96路径的ACK/普通键读回不证明实际Voice路由改变 | 保留当前CP2.6随机nonce挑战、版本/子命令/整记录CRC、同连接证明和当前模式事务；旧ACK只证明不支持新路由。不能恢复全局覆盖或把“无法恢复Consumer”提示套到所有设备 |
| R08/P1 BLE中断/晚ACK（重叠） | main AHK-061/022/064/065等新增等待任务、特征身份、断连收尾、失败阶段和旧OLED重试；当前已有单命令ticket/代际/超时污染后断连及CP2上传事务 | 保留一个串行等待/撤销机制，迁移main失败阶段和遗漏边界，不并存两套waiter。旧80/81重试不直接复制到8A/8B/8C或9E提交；分别验证超时/取消/断连/旧ACK/重复点击 |
| R09/P1 电量与真实连接 | main 9dbb89b避免OLED隔离误屏蔽电量/设备信息；当前已有0电量来源、断连未知状态修复 | 分离遥测读取与写入ACK接纳，校验当前peripheral/特征/代际；写入失败不能卡死全部遥测，旧回调也不能把断开设备显示成已连接或旧自动档 |
| R10/P1 图片/GIF损坏与容量（部分重叠） | main AHK-063增加惰性解码的dataProvider验证，当前有自动缩图抽帧和单帧失败停止，但不等同该验证；main沿旧版源文件/帧数链路 | 合并损坏帧校验与错误位置提示，保留当前自动缩图、抽帧、8/12帧/19位置隔离和CPU缓存。正常黑图必须通过，损坏PNG/GIF必须拒绝，不能把用户重新赶回手工压缩或旧70帧分区 |
| R11/P1 云端账号竞态（部分重叠） | main #127/89abb0e在回调和请求token上隔离旧会话；当前请求边界已比对token并重定向登录，但旧请求网络失败/状态回调仍需合并检查 | 同时保留当前可注入URLSession、旧token防注销和main回调保护。隔离测试旧登录/刷新/兑换/订单响应，不让旧响应覆盖新账户、配额、错误或busy状态 |
| R12/P1 权益与登录混淆（缺口） | main #161不再用登录JWT.exp推算订阅权益；当前仍有jwtExpirationString回填，也把权益到期视为登录失效 | 使用服务端权益字段；登录无效→登录入口，权益到期/无权益→续费或服务状态，不能反复退出有效账号。保留用户登录和AhaType总开关，分别测null/到期/坏日期/401/非JSON |
| R13/P1 云端失败反馈与语音回归 | main #157返回结构化failureReason并显示原文回退；当前只有超时专门告警，其余失败可能被成功HUD覆盖。整段采用main又会丢当前8秒预算、首次启动反馈、停顿分段/去重/只回填一次及按压配对 | 合并结果类型和所有调用点，保留当前录音策略快照/8秒回退/登录重定向/语音算法；闭端点、业务错误、登录失效均显示真实回退原因，不重新引入首次无响应或前半句丢失 |
| R14/P1 改名与设备信息接口 | main AHK-016同时改变changeDeviceName返回Result及UTF-8字节校验；协议构包可自动合并，BLE和DeviceInfo发生冲突 | 成对迁移校验与UI反馈，检查新能力写入门和设备确认；不能只改函数签名或提示“已改名”却未发送。保留名称/Appearance与身份，不让恢复测试改配对 |
| R15/P1 多语言与侧栏产品布局 | UTF-16中英文资源均冲突；生成器和大View也冲突，main有完整修复文案、当前有新语音/屏幕/更新/审批文案 | 合并键集合并人工检查同键不同语义，保留编码、去重、格式占位；保留虚拟组件→修改→侧栏、底部唯一“写入键盘”、成功选择、地球icon入口。不能恢复独立键盘设置页或旧全量保存 |
| R16/P1 CI/其他平台/发行 | main新增Windows Java任务及跨平台源码，当前新增App/Agent组成校验和发布守卫；模拟CI可同时保留，但双方绿不代表整合绿。build号/同0.2.3版本/源SHA容易混淆 | 保留两边CI及main非Mac内容，运行整合提交完整流水线；候选记录App+Agent同源SHA、唯一build、架构、签名及安装来源。当前产物不作正式公证发布，也不替换用户运行包 |
| R17/P1 新固件交付与回滚边界 | 组合候选只有路径与SHA记录，本分支未含HEX字节；旧安装包回滚不能自动恢复已写Flash、Consumer路由或已清素材元数据。旧main客户端在新固件上可能显示保存成功而实际路由未变 | 代码整合与刷机分开；取得精确HEX并核验后才联合验收。备份可读配置和原素材文件，说明不可导出字节的限制；保护Coffee、Voice、配对，未确认不执行Restore/全局初始化 |
| R18/P2 验收、发布和剩余需求 | 当前Consumer接线未真机；独立长按、宏完整读回、缺记录初始化、Restore、Kimi接口、正式目录/密钥及发布材料仍有未闭环项。合并不消灭这些缺口 | 更新WBS逐项映射证据，已有179/715测试不作全量HIL证明；旧/新固件、全组件、生命周期、GIF/CPU/睡眠和最终签名包仍分别验收，实体操作按用户要求最后集中 |

## 实施批次与顺序（确认后）

1. **M0 冻结/保护**：记录两个最新SHA、当前安装包来源、用户2项草稿和应用/Agent状态；备份本地偏好、当前确认基线、Voice与授权、CLI自有配置及恢复日志。私密内容留本机，不推仓库。准备可撤销的源码/安装包回退点。
2. **M1 上游合入骨架**：在connect&talk合入main，保留历史及上游其他平台文件，生成20冲突的功能归属清单。此阶段不安装、不新建长期远程分支、不发main PR。
3. **M2 最高优先安全闭环**：Agent实例锁/IPC调度与当前生命周期合并；严格类型实际授权入口；Codex Hook保真与原会话授权/恢复；Kimi按讨论确认的策略接入。先验证异常输入、双实例、卸载重装、离线与退出行为。
4. **M3 数据和云端**：每组件已确认基线持久化；账号请求隔离、真实权益日期、认证失效分类；AhaType结构化回退结果与当前8秒/录音算法合并。保留所有现有草稿和有效登录。
5. **M4 通道和产品链路**：BLE/图片损坏/晚ACK/遥测/改名/本地化整合，保留侧栏与9E事务、单组件范围、自动压缩。新旧协议分层运行必要的故障fixture。
6. **M5 完整自动验证**：汇合两边测试及本次语义差异回归；逐条确认main新修复被保留，不删除不兼容测试来凑绿；运行Swift完整测试/构建、SDK、Windows原有CI、组成/发布/安装守卫及中英文校验。检查最终HEAD包含选定main，私密配置零提交，生产工作区无冲突标记。
7. **M6 继续剩余开发**：恢复初始化状态机/产品入口、缺记录四模式显式初始化、长宏未知描述事实处理等继续按最新WBS；只把确实依赖固件/官方接口/正式发布输入的项列依赖，不把现成协议重新列未提供。
8. **M7 候选与集中真机**：自动项完成后再生成同源App/Agent候选，核验签名与版本；取得精确新固件镜像，明确素材/配置影响。最后一次集中语音短长按、实体拨杆、重启/屏幕、断连和旧/新设备矩阵。通过后再讨论最终发行/PR，仍以此前约定的connect&talk为开发整合分支。

成功标准：最新main的新增修复有覆盖证据；已确认的新产品/权限语义不回退；用户草稿、Voice和账号保留；新固件能力按真实挑战读回；完整自动CI通过；真机及发行项没有被误标完成。正式实施前不承诺当前两边代码机械拼接即可达标。

## 需要讨论确认的两点

- 推荐按“main合入connect&talk、保留当前侧栏/新固件/原会话权限架构、逐项补入main修复”推进，保持统一分支、不重写共享历史。
- Kimi原“仅状态同步”建议已由用户本轮要求修正：保留main现有默认权限控制并完善，同时调查Desktop和CLI原会话接口；具体接入、权限映射和授权边界仍逐项讨论，不默认为整个整合方案已获执行许可。

本方案待确认。此时不执行实际merge、生产修复、覆盖安装或刷机。

## 附录：模拟合并的20个冲突文件

- `ahakeyconfig-mac/Resources/en.lproj/Localizable.strings`
- `ahakeyconfig-mac/Resources/zh-Hans.lproj/Localizable.strings`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Agent/ClaudeHookHandler.swift`
- `ahakeyconfig-mac/Sources/Agent/CodexHookHandler.swift`
- `ahakeyconfig-mac/Sources/Agent/CursorHookHandler.swift`
- `ahakeyconfig-mac/Sources/Agent/KimiConfigDiagnostic.swift`
- `ahakeyconfig-mac/Sources/Agent/KimiConfigLeverSync.swift`
- `ahakeyconfig-mac/Sources/Agent/KimiHookHandler.swift`
- `ahakeyconfig-mac/Sources/BLE/AhaKeyBLEManager.swift`
- `ahakeyconfig-mac/Sources/Utilities/AgentManager.swift`
- `ahakeyconfig-mac/Sources/Utilities/AhaTypeTextOptimizer.swift`
- `ahakeyconfig-mac/Sources/Utilities/CloudAccountManager.swift`
- `ahakeyconfig-mac/Sources/Utilities/NativeSpeechTranscriptionService.swift`
- `ahakeyconfig-mac/Sources/Utilities/OLEDFrameEncoder.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Sources/Views/DeviceInfoView.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/ClaudeHookHandlerTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigTests/AhaKeyBLEManagerTests.swift`
- `ahakeyconfig-mac/scripts/generate_localizations.py`

## 逐项Grill确认记录
- 第1项已确认：保留既定产品方案，在connect&talk迁入main的修复效果；按组件保存等产品语义不回退。此项仅确认整合原则，不构成完整方案实施授权。

- 第2项用户指示：先调查Kimi Desktop和CLI TUI控制对话权限的接口；main已有能力必须保留并在此基础上完善。已完成官方文档/源码阶段调查，接口存在与可外部附着原进程分别记录；尚未确认完整实施方案。

- 第2项产品范围已确认：普通Kimi桌面版、Kimi Code Desktop、官方CLI TUI全部纳入；分别核验会话权限接口，main现有能力保留。此项不等于具体权限映射或整个整合方案已获执行许可。


### 2026-10-25 第2项阶段确认

Kimi范围：普通Kimi/Work、Kimi Code Desktop、官方CLI TUI均包括。用户选择自动档“完全自动、不再询问”，Code目标auto/Never Ask；main默认权限同步能力保留并完善，其yolo映射需按新目标调整。已在独立临时配置复现main auto→manual→自动档回到yolo；未读写用户配置。管理会话范围与权限生命周期尚待逐项讨论，未授权实施整体整合。

Kimi会话范围追加确认：全部已明确授权接管的会话（含后台）；未授权的不变，不可控制的独立提示。断连/暂停/退出后的权限处理尚待讨论。

Kimi生命周期追加确认：断连/暂停/退出恢复接管前设置，保留用户新修改；原本完全自动仍可恢复完全自动。三端原会话控制与异常退出恢复尚待技术核验，不能报已完成。


### 第3项已确认：登录与权益分离（2026-10-25）

会员到期/额度不足时保留登录，提示原因并回填本地识别原文；只有明确未登录或Token无效才回登录入口。不能使用JWT过期时间推断会员到期，不能将未知权益或空到期时间伪造成到期。旧账号请求晚到不能更新新账号资料或清掉新登录。

本轮隔离探针原样抽取两分支错误分类器，未发网络请求：HTTP200/code500/data401/无msg：current=false、main=true；HTTP200/仅msg=Token无效：current=true、main=false；包含完整未登录文字及data401两者true；额度不足403两者false。整合需合并识别覆盖，不能任选其一覆盖。探针文件 `/tmp/ahakey-cloud-classifier-integration-probe-20261025.swift`。


### 第4项已确认：无历史基线保留未知（2026-10-25）

升级时旧草稿全部保留；缺少成功写入记录的组件显示尚未核对，读取键盘后才确认同步状态。不自动写入，不用旧本地草稿构造虚假的已同步事实。main 77b1281/AHK-021的持久化修复需保留，但其无旧基线时回退当前草稿的策略按本项确认替换；继续只提交当前组件，成功后只更新该范围记录。已有草稿不因只读核对被替换；设备身份/素材元数据不足以证明字节相同时，维持未知而非假定一致。


### 第5项与执行指示（2026-10-25）

重复恢复问题已按用户明确要求提交 [固件Issue #9](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/9)。重新fetch最新固件仍为0a055ba；host原有suite通过，新增隔离探针首恢复成功、模拟重启后第二次失败，state=COMPLETE/attempt=1。不是键盘无法开机。客户端按现状能力接入，不把反复恢复出厂标为已完成；最新用户指示已授权开始客户端适配和main整合。完整真机与正式发布门槛不因此取消。
