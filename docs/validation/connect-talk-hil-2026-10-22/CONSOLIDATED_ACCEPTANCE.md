# 集中补验台账 — 2026-10-22

开发统一分支：connect&talk。用户要求先补已有功能验收，再继续剩余开发。首轮候选0.2.3/source5225cf3；本轮修复编辑模式交接后已更新安装0.2.3/source342e4e861929f32f3c8a9d9674cdba1380ed7ba8，Developer ID及deep/strict验证通过。

## 最新现场：36项断电保持与全部还原已完成

当前没有遗留临时灯效。第一轮中断现场先恢复并清空后，在342e4e8修复候选按Kimi→Claude→Cursor→Codex逐模式建立9项草稿、核对范围、底部统一写入并最终读回，36/36全部通过。每项临时值为原effect+1（模17），全局亮度35%、Voice/按键/Coffee未写，未确认0。

用户明确完成正常关开键盘并确认Codex Coffee图片正常。客户端随后fresh重新读取全部36项灯效＋亮度，对比v2-all36-saved.json逐项一致，36项断电保持通过。之后按Codex→Kimi→Claude→Cursor逐模式还原原始9项，分别读回一致；最后再fresh完整读取，v2-all36-final-restored.json的37项事实与light-before.json完全相同，所有草稿等于事实、未确认0。语音配置/按下策略与测试前语义一致。已退出编辑并交还Agent，实时自动档0、autoVerified=true。

全部原始快照保留本机private目录；第二轮完整矩阵仅证明当前新固件、当前Mac上的保存/范围/断电保持/还原，不代替17种灯效全部视觉效果、EEPROM失败、旧固件与无线异常的完整矩阵。

当前安装候选为ca4bed69073ae1f1fabebfaf5ad818cc06c58dba，包含模式交接修复与固件升级页可访问分组修复，签名通过；升级页已真实验证内置文件通过/错误HEX拒绝/未勾选确认时写入口禁用，未访问ISP或刷写。详细见[FIRMWARE_ENTRY.md](FIRMWARE_ENTRY.md)。语音首次短/长按用户反馈正常，但补做连续长按停顿时确认前句丢失，已暂停其他WBS优先修复，详见[VOICE_PAUSE.md](VOICE_PAUSE.md)。不上传语音全文。

## 本轮已执行

- 完整470项Swift自动测试通过；不将自动测试代替真实设备/第三方CLI/云端验收。
- 四模式九状态灯效矩阵推进到18/36：Codex（mode2）与Kimi（mode3）各九项临时改为原effect+1（17种循环），通过底部“写入键盘”串行写入，收到最终成功弹窗，九项最终读回一致。每批对比全部36灯效与亮度，只改变预期目标；亮度35%、其他模式和Voice不变，未确认0。
- Claude（mode0）的九项草稿已建立，但写入时无法取得连接；界面明确连接超时、未开始本次操作，未弹成功、草稿保留。事实与Codex/Kimi写入后的状态一致，未确认0；该批没有硬件写入。Cursor尚未进行。
- 连接丢失后fresh Agent：connected=false、physicalSwitchState不可用、effective手动、autoVerified=false。未为凑验收模拟未知状态或绕过能力门控。已请用户轻按模式键唤醒，等待恢复；没有执行Forget PC、刷机、恢复出厂或修改系统蓝牙设置。
- CUA主窗口可读，普通滚动定位动作出现windowNotFoundAtPosition；恢复主窗口并使用其公开的原生Scroll Up/AXScrollToBottom动作后，状态/灯效选择恢复。不要求用户代点或重启，不将控制服务错误记成App写入故障。
- 离线、灯效编辑可见、已建立草稿的20.02秒CPU样本：Studio平均0.05%、Agent0.25%（单核占比），RSS约47MB/13.5MB。仅是该场景短样本，不声称长时间GIF、休眠/重连或所有性能场景通过。原始样本留本机private备份。

## 中断时现场与恢复结果

中断时硬件Codex/Kimi共18项为临时灯效，Claude九项仅本地草稿。用户确认唤醒后，首次fresh Agent仍offline；App主动只读总览成功取得连接并交还后台，fresh Agent恢复connected=true。Codex和Kimi分别九项全部恢复并最终读回一致；再次对比完整37项事实与最初基线完全相同，未确认0。明确核对仅有Claude九项本轮测试草稿后，通过放弃本地灯光修改清理，再fresh读取全部36项＋亮度：37事实与基线相同、全部草稿等于事实、未确认0。没有遗留临时硬件灯效。

原始37项事实、每批快照和最终reconnected-restored-baseline.json留本机local-backups/consolidated-acceptance-20261022。原effect按状态0..8为10/16/12/1/3/6/12/5/0，四模式相同；全局亮度35%。Voice、键位和Coffee素材未写。完整矩阵的断电保持尚未开始。

## 补验发现：交接后编辑模式跳回实体模式

在原5225cf3候选真实只读复现：从Mode3浏览到Kimi/Mode4灯条编辑，点击刷新；读回回执固定为Mode4/Kimi/会话结束，但当前编辑器标签跳回Mode3。未按实体模式键、未保存配置即可复现。原因是workModeForDisplay在连接交接时由nil回到实体Codex模式，根View只为inlineKeyTarget保留上下文，没有保护灯条等其他编辑器；写入事务的捕获目标正确，问题在浏览选择被覆盖。

抽取实际调用的选择策略，先等价保留旧条件并重放“编辑Kimi→设备报告nil→2”：4项聚焦回归中的编辑保持断言失败（共13条），只读跟随与原单键固定目标已通过。随后补充编辑保护，完整474测试通过。语音/状态通知仍独立使用真实实体模式，不因用户浏览草稿改变路由。342e4e8签名候选已安装；同一路径Kimi/Mode4刷新后仍Mode4，交还后台及fresh自动审批查询后标签仍Mode4。fresh Agent connected=true、physical/effective=0、autoVerified=true；只读复测没有写入。接续四模式写入时编辑标签也均保持目标模式，未再发生跳转。完整474自动测试及两轴审查通过。

## Hook验收工具修复

原scripts/verify-codex-hook-trust.py独立Swift编译遗漏共享配置生命周期依赖，实际执行在编译阶段失败，尚未运行CLI。原因是TomlPolicyLocator与CodexConfigLeverSync共用文件，后者新增ApprovalAutomationControl后引入Cursor/Kimi配置依赖，脚本仍只列两个旧源文件。

修复6dcf229补齐五个真实生产源文件，增加参数解析及--compile-only。--help、Python语法检查及--compile-only通过；后者实际在临时目录编译并执行initial/reinstall/remove三阶段fixture，明确输出cli_executed=false。没有启动Codex或读取真实账户配置；不把该结果记为真实CLI Hook执行/重装验收。Spec和Standards窄复核均无未解决问题。原完整smoke路径保留。

## 待验证、未开发与外部条件

### 最新语音结果

当前安装f719026签名候选。VOICE-PAUSE-01已通过连续长按停顿和短按主动重复词真机复验；两段各一次粘贴，用户确认正常。首次按下至语音条展示延迟仍记VOICE-LAT-01，原因未定，用户明确要求记录后续排查，现继续其他验收。麦克风、键位、Voice策略保持原状。

| WBS范围 | 还需要什么 | 当前安排/原因 |
| --- | --- | --- |
| I01/I02a | 16键/宏范围、真实冲突与取消、旧设备矩阵 | 自动负例已覆盖；需在线键盘继续原位验收，已过的Key4描述往返不重复冒充全16键 |
| I02b-1/I02b-2a/I02b-2b | 四模式路由/短长按/处理策略及按住时切模式边界 | 核心保存和回填曾通过；重复字/偶发延迟仍开放，需实体声音与时序日志逐段比对 |
| I02d | Consumer首次退出、AhaType真实云端成功 | 当前设备状态3不能客户端恢复Consumer2；云端之前ClosedEndpoint，需实际成功复测 |
| I03/D03 | 其余18状态、全36项恢复、断电保持、存储失败与无线中断 | 36/36写入/范围/断电保持/恢复通过，37项回基线；完整视觉与故障矩阵仍待 |
| I04/D04/D05 | 19位置、最大8/12帧、错误素材/中断/恢复 | JPEG/3帧/取消恢复曾过；保留Coffee位置8，不将元数据核对当完整图像/容量验证 |
| D02 | 真实任务来源、App直连、前台/静默/休眠/OLED | 固定三色和并发曾过；App直连/可靠前台仍有待实现，不能先标验收通过 |
| H02/Q01 | Claude/Cursor/Kimi真实安装重装、会话重载、异常退出收回 | 自动fixtures部分过；本轮仅修复并验证Codex生成工具，不触碰正在使用的CLI配置 |
| L02/Q04 | 宏/语音/睡眠交接、长时GIF/CPU、电量/灵动岛、覆盖安装/旧固件 | 短样本不代替长时及旧设备实测；需在线设备继续 |
| G52/L03 | HEX/目标错误拦截、失败恢复与刷后只读验证 | 升级入口/内置文件/错误HEX拒绝已补验，未实际烧录；目录候选UX和正式镜像组合仍依赖开发/发布材料 |
| I07/Q05 | 全用户链路与完整矩阵 | 汇总以上，不能单独用470项自动测试关闭 |
| V10/I02c | 分模式Consumer与普通绑定混用 | 最新固件未改变，仍需固件Issue8的分发/持久化/释放合同与可验收HEX |
| D05-CP3 | WS3资源工厂恢复 | 最新EXECUTION的WS3 CP3仍为refinement_required_before_start；不同于已实现0x8D单位置解除引用 |
| G40/G50/G51/G53/G54 | WS4/5治理、目录信任、候选/恢复/发行组合 | 最新Architecture为stage_b_input_draft_not_accepted；schema/签名/缓存/兼容验收等未冻结，当前不能实测“官方稳定目录” |
| R50/KLP01 | 整机出厂恢复、独立短长按 | 需各自实际固件合同与读回；不把WS3资源恢复或Host语音短长按误认为已完成这些能力 |
| I05/I06 | 模式/拨杆高级区/待机迁回右侧、删除重复页 | 明确待开发，依用户要求在可执行的现有功能验收之后推进 |
| Q03 | Windows/Mac交替配置 | 可选，需另一端候选及协作 |

本轮重新读取固件076382b的WS3/WS4/5 EXECUTION与WS4/5 PRD：WS3 CP3仍待细化；WS4/5仍为Stage B输入草案、全部检查点refinement_required_before_start，catalog格式/签名/缓存/发行归档/兼容门槛仍开放。文档描述的未来目标不当作当前固件已具备能力。以上是外部合同现状，不是要求用户重复批准已授权的客户端工作。


## 2026-10-23 自动回归后发现 H02-KIMI2（未修复）

567项Swift及9项发布守卫通过后，继续核对真实CLI版本发现：本机Claude Code 2.1.299、Cursor Agent 2026.10.19-6bbf2c4、Kimi Code 2.3.0。不能将旧Kimi Python补丁或fixture通过等同为当前原生二进制兼容。

已在临时KIMI_CODE_HOME复现，无真实配置/凭证/模型服务参与：原生kimi doctor读取指定临时config.toml；同环境编译执行实际KimiConfigPolicySync.productionConfigURL结果不匹配，进程退出1；原生doctor对default_yolo明确输出“Unknown top-level key ignored by the v2 engine: default_yolo”，而default_permission_mode=manual无警告。日志在本机`/tmp/ahakey-kimi-v2-path-repro.log`。这个忽略行为不能只用doctor退出0判为成功。

官方来源：[配置合同](https://moonshotai.github.io/kimi-code/en/configuration/config-files.html)、[Hooks合同](https://moonshotai.github.io/kimi-code/en/customization/hooks)、[权限交互](https://moonshotai.github.io/kimi-code/en/guides/interaction.html)。新目录为.kimi-code/config.toml，显式重定位变量KIMI_CODE_HOME；默认权限字段为default_permission_mode（manual/yolo/auto），与旧default_yolo布尔不同。当前preTool Hook不得因为写盘成功就声称活跃会话已切档，原生2.3也不能应用旧Python源码补丁。

下一步需以版本/安装类型区分旧、新Kimi，统一App/Agent检测、Hook安装移除、诊断和策略所有权；使用隔离配置验证实际Hook和运行时权限行为，再明确动态切档能否通过官方接口实现。保留旧版兼容及用户未托管策略，不把新版仅不报错当成接管成功。ce615c9签名候选尚未安装，仍为开发验收候选，不能宣称最终用户版已齐。


### H02-KIMI2 阶段修复与严格剩余范围

实现提交 ca6a1c4。App/Agent使用同一版本位置选择，支持.kimi-code及显式KIMI_CODE_HOME；生成Hook时固定布局/根目录，旧Python不被新默认PATH误导，新版不执行Python补丁。Hook改由字面POSIX命令调用绝对agent，省去登录shell；词法识别只清除真实托管argv和语句，保留其后provider、用户Hook、带marker文本的多行prompt。重装幂等，未托管坏配置不阻止撤销自己的策略，坏租约仍报错。

原生版只同步任务状态，PreToolUse不查审批、不写权限、不输出放行，也不写旧调试链路；界面明确范围。公开policy入口对原生版返回unsupportedRuntime，避免创建无法即时撤回的自动会话。新权限字段解析/所有权模型仅供受控事务与fixture，不能据此声称原生实时接管完成。旧Python接管保持原流程。登记受控配置路径，停止/卸载可清理不同CLI home中的自有策略，保留用户改成Never Ask的值；重复状态不重写登记文件。

50项跨Kimi/Codex/Cursor策略局部回归通过，两轴代码审查及窄复核通过。`python3 ahakeyconfig-mac/scripts/verify-kimi-native-hooks.py` 实际运行本机原生2.3.0，临时home下安装8条/重装8条/移除后1条用户Hook；自己的SessionStart/UserPromptSubmit真实执行，保留用户阻断Hook并验证CLI明确报告该阻断，模型请求计数始终0。另断言生产路径和原生CLI home解析符号链接后相同、公有同步不改权限。/var与/private/var是同一实际目录，测试按实际文件比较。没有更改真实Kimi配置、账号或二进制，也没有替换当前Studio。

交互对照使用隔离TUI和本机假模型（仅写临时marker）：manual基线请求批准；Hook返回allow仍请求批准；只改默认字段仍请求批准；空闲时服务profile更新可在下一次用户输入后重新载入；工具调用前从Hook调用profile切manual虽code=0，该TUI当前工具仍执行。由此保留“当前运行会话随拨杆即时切档”未完成，不能将HTTP成功或无交互自动执行当成接管证明。原生CLI、临时服务及假模型已退出，含临时认证值的文件已清理。

后续继续调查原生运行时扩展点。官方公开仓库MoonshotAI/kimi-code包含v2.3.0源码及权限/反向RPC组件，尚未据此证明可以加载AhaKey的可靠接管扩展；不得把“暂未找到接口”直接当成无需开发。原生完整支持仍在总WBS，四组固件合同依赖也未变。


### 2026-10-23 JSON Hook生命周期与配置保留

实现cf718cf已推送connect&talk。Claude/Cursor旧子串卸载误删先复现两处失败；生产共用编辑器改按字面argv归属、保留用户Hook及其他配置、损坏结构拒写。22项相关Swift回归通过，规范与需求两轴复核无问题。Claude 2.1.299真实生命周期12/12/1全部通过，用户阻止Hook仍执行且模型请求0；Kimi 2.3.0真实8/8/1同步通过。收据见hook-lifecycle-2026-10-23.json。

Cursor 2026.10.19-6bbf2c4补验仍为部分：其CURSOR_CONFIG_DIR只重定位CLI配置，钩子loader仍固定os.homedir下.cursor/.claude。隔离探针仅在该测试Node进程替换homedir并设置临时config/data/store，使用本机虚构账号/元数据端点；真实sessionStart/sessionEnd已经执行，但完整会话需Agent流协议，当前假端点返回协议错误，尚未执行用户beforeSubmitPrompt阻止Hook。不能将这次退出1或SessionEnd有记录标为完整生命周期通过。探针与其临时语言服务均已确认退出，未修改真实CLI设置/账号/实体配置。

Kimi进一步核验的[官方SDK实现](https://github.com/MoonshotAI/kimi-code/blob/b5e28fd6beac752a2cdcc0ff2f5fdf40e6494fbb/packages/node-sdk/src/sdk-rpc-client-v2.ts)中setPermission能作用于本进程agentFacade；[官方TUI入口](https://github.com/MoonshotAI/kimi-code/blob/b5e28fd6beac752a2cdcc0ff2f5fdf40e6494fbb/apps/kimi-code/src/cli/run-shell.ts)直接创建自己的harness，SDK传输在该路径是内存连接。这说明SDK存在权限方法，并不证明另一个外部Studio进程可连接已运行TUI。实时接管仍待开发，不回退到无效的写默认字段或REST成功判定。


### Cursor启动/退出补验与遗漏状态路由修复

新收据cursor-state-routing-2026-10-23.json覆盖本批。生产安装的beforeSubmitPrompt/beforeReadFile此前未映射到HookClient及WS3TaskMetadata，回归先红后绿，现为仅状态running事件。15项相关Swift通过，拒绝将敏感内容、假会话或权限决定混入状态请求。

实际Cursor CLI三阶段为10/10/1；sessionStart/sessionEnd与保留用户Hook执行，移除后只有用户Hook。此阶段使用无服务端Agent流的离线夹具，预期退出1/Protocol error是明确边界，不能按整条工具生命周期验收完成。测试进程的os.homedir隔离和回环伪造元数据不修改真实CLI。新增真实子进程回归修复父已退出时漏清子进程的问题，CI将执行该检查。双轴复核中的P2已关闭；修复后原三阶段复跑通过，确认无临时进程残留。


### Claude同会话Hook重载与CI夹具修复

新增可重复命令 `python3 scripts/verify-claude-hooks.py --live-reload`。实际Claude 2.1.299同一常驻stream-json进程完成旧命令→含空格/单引号的新路径→移除；每轮用户阻断Hook都实际执行、所有阶段进程保持同一个、模型请求0。文件更新使用生产编辑器及原子写入，写后留出稳定期。早期探针中用户阻断太快可能取消并行的托管Hook，已让阻断等待短暂时间再完成；不将早期漏记事件诊断为客户端缺陷。受保护的最终版本已通过，见claude-live-reload-2026-10-23.json。范围仅是Hook配置，未据此宣称权限策略/实体拨杆即时重载。

[官方设置文档](https://code.claude.com/docs/en/settings#when-edits-take-effect)说明设置文件变更会重载；[官方受管设置文档](https://code.claude.com/docs/en/managed-settings)说明managed来源不因settingSources缩小而关闭。审查因此补了两种模式共同的系统策略隔离前置检查：系统managed文件/目录/断链、偏好域存在或无法确认均拒绝启动CLI，不打印策略值。两轴复核P2已关闭。

b223860的CI在新增子进程回归处失败：远端macOS对已结束的孤儿进程组的killpg(...,0)返回EPERM。夹具现在核对精确PGID的非Z成员，无活进程才视为结束；有活成员仍失败。新增可确定复现该返回值的测试，连同原真实子进程和策略隔离共5项通过。此处是夹具兼容修复；CI重跑前不声称b223860全绿。


### H02-CODEX-LIVE：活动会话撤回缺口与修复

真实CLI0.162.1已复现旧实现“文件回到on-request、活动会话仍bypassPermissions”的失败。新实现不再产生持久never；自动由当前PermissionRequest授权，手动/离线/暂停交回原生。旧bypass/未知模式在每次工具前重新验证，没有实时自动证明即deny，要求恢复原生审批或新建原生审批会话；不能把显式CLI bypass/GUI Full Access的阻止伪装成已经显示原生审批框。详见 `../../ahastudio/codex-hook-managed-approval-2026-10-23.md`。

代码/配置反例44项通过，包括真实Handler路径、默认会话无额外BLE查询、大输入不误挡、暂停和不完整证明、旧租约升级/丢失文件/损坏所有权；最终完整Swift601项零失败，发布守卫9项零失败，两轴复核和最终文案澄清均通过。

真实原生CLI两类会话各5状态（自动→手动→离线→暂停→恢复自动）均通过：原生会话的三个非自动阶段确实发起native approval，夹具拒绝后不执行标记；旧bypass三个阶段直接阻止，恢复有效自动才执行。6个Hook受信启用，代码来自实际共享生产策略/输出模块，配置确认是回环provider，目标仅临时文件。使用合成档位事实而非实际BLE，不宣称真实硬件端到端完成。生产生成的Codex Hook生命周期7/7/1同步复验通过，用户Hook保留并执行。

收据codex-live-approval-2026-10-23.json绑定本批源文件摘要、红例/最终两类会话与生命周期结果。当前已安装客户端、真实配置与语音素材未修改；签名候选与实体验收随后进行。总WBS新增此P0子项后为29行（父子项不能相加成独立功能数）。


### CI完整安装包补齐

此前绿色CI（run39839656358/a2cbe4c）归档实查缺后台Agent、来源SHA和AppleEvents说明、最低系统12.0错误；未安装/运行该归档。现在CI复用完整打包入口，组成门在上传前核对主程序/Agent、来源/权限/语言/最低系统。5项反例通过；实际本地arm64完整出包（0.2.3，底层源码8e13aac＋打包补丁）双执行文件齐全、min13.0、来源SHA正确、两语言资源齐全，深度严格ad-hoc签名通过，未安装未发布。两轴复核通过，正式发布签名公证门未放宽。收据ci-app-composition-2026-10-23.json记录原包反例和本地原型边界，提交后产物与正式测试候选另核验。
