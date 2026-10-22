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
