# 固件 Issue #10–#17 重新核对与建议修订

日期：2026-11-04。根据固件开发者“多数已解决，可能未读到实现位置”的反馈，重新读取8单完整原文、#7/#9历史评论、最新远端分支、Harness合同/Owner决定、生产代码和既有测试。**固件仓库Issue/代码本轮只读：新8单当前均无评论，未把开发者尚未发表的逐条回复编造为结论；未修改、评论或关闭任何Issue。** 本轮只更新客户端仓库的核对文档与WBS，没有改固件、刷机或调整用户配置。

## 结论先行

之前把“未闭环事项”统一称为“未修复固件问题”，口径需要纠正。8单不能算8个F99D确诊Bug：

- **5项主要应归已有实现/条件风险/历史观察/联合验收/发布协作**：#11、#13、#14、#15、#16。
- **1项是现有断连恢复之外的体验扩展**：#10，Mac逻辑取消而HID物理链路仍在的情形。
- **2项是明确的用户配置/协议能力扩展或接线请求**：#12、#17；既有CP4D单报告读回和CP2短长按底座本身已实现，不能把整个功能说成没做。

这不等于“8项都已完整实物验收”，也不等于“对方必须按8个Bug返工”。先承认已有实现并复用既有证据，只对具体缺口或复现失败提出新动作。

## 本轮范围

固件基线：`Fireware-harness@72346b001710d573980a7d398b9e0dced8ff627c`；该Git生产树与HW1 F99D manifest所记源5fc01cf的APP/Profile一致。最新原始HW1/HW2交付见[FIRMWARE_INDEX](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/FIRMWARE_INDEX.md)。不拿旧工作目录、eternal-dev1.4.8或HW2产物代替本机HW1基线。

代码/合同核对不等于重建每个HEX字节或重新做硬件故障注入。既有回执按原范围引用；本轮仅额外在临时导出目录执行既有resource_display_config host测试，PASS。五项运行路径的完整来源见[独立复核笔记](firmware-issues-runtime-reaudit-2026-11-04.md)。

## 逐条处理

| Issue | 当前已有实现/正确边界 | 建议修订，而非要求重新实现 |
|---|---|---|
| [#10 上传取消恢复](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/10) | owner真正断连后，排空/取消writer、INVALID持久化失败重试、启动清理已有实现；D1–D7已有PASS。Mac取消本地连接但保留HID物理链路不等于该owner已丢失。 | 标题改为“Mac逻辑取消但物理链路保留时的恢复体验”。承认现成断连恢复；只协商逻辑会话结束/有界闲置优化，不能用旧07A8故障宣称F99D未修复，也不强制指定新opcode。 |
| [#11 HID释放](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/11) | 捕获DOWN动作并在UP释放，跨模式/改路由、Sleep、真实断连收尾已有生产TU测试。普通键发送前更新cache/void结果封装、UP路由失败分支是静态条件观察，未建立现场可达故障序列。 | 改“发送失败/异常路由的可达性诊断”。不重提捕获释放整体缺失，不据此定历史Command/Siri根因；有可复现生产调用链再定具体Bug。 |
| [#12 长宏读回](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/12) | CP4D明确规定64字节响应、动作+描述最多53字节，超长返回TOO_LARGE，不做分片。当前实现符合此合同，普通宏读写不能被称为没实现。 | 改“超出CP4D单报告容量的完整读回扩展需求”。若Mac完整旧功能需要更长动作+描述，请先指出现成可用入口；没有则另冻结扩展合同。保留需求，不把合同内拒绝算Bug。 |
| [#13 重连/旧绑定](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/13) | 正常重连、Forget保身份API已有；WS1已把stale-host/local-bond安全失败列为非阻断观察。F99D无本单新的确诊复现。 | 转历史观察/升级引导，先核对实际擦除、保留和主机旧记录。只有同一精确组合复现并有GAP/security证据时再提具体固件缺陷。 |
| [#14 拨杆首报](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/14) | GPIO0/1/2采样、状态更新和不可变快照已有生产路径与R2测试；F99D实体正常往返已通过。 | 保留首包/唤醒差异诊断，不称采样功能未实现。先区分Host缓存、真实物理方向及新鲜回包时序。 |
| [#15 故障矩阵](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/15) | 资源CRC/INVALID/重试、共享store及Restore故障已有大量host/生产路径证据。Owner已明确撤除CP2.6 K1路由写中断恢复旧值保证。 | 改已有证据索引和批准范围内联合验收。删除“所有配置阶段掉电都应恢复旧值”的泛化暗示；K1正常完成保存后读回/普通重启保持仍要求，Restore中断恢复单独保留。 |
| [#16 发布交付](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/16) | 逻辑字段/职责已有PRD/Architecture，固件key、工程HEX、源/哈希和机器记录已交。Release catalog在合同里属于Desktop/release operations。 | 移客户端/发布协作，复用已有固件材料。具体schema文件、校验/签名策略、公证和GitHub发布环境由对应发布方落地；恢复候选可选择已有稳定HEX，不要求为数量另编固件。正式发布尚未完成不等于固件功能Bug。 |
| [#17 独立短长按](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/17) | CP2已实现mirrored/distinct动作的安全底座，且明确Desktop写协议不在该CP2交付范围；当前生产load_policy把两者映射到同一份绑定。 | 改“在已有安全底座上补两套动作配置/持久化/读回闭环”。若已存在配置入口，只需对方给函数/字段/命令位置，Mac据此接；否则按后续阶段能力推进，不称短长按机制整体没做。 |

## 三处需要明确改正的证据

### 1. #15不能重引入已撤销的要求

[2026-10-24 Owner决定](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/evidence/owner-decisions/X1-INPUT-CONTROL-CP2_6-POWER-LOSS-RECOVERY-REMOVED-OWNER-DECISION-20261024.md#L11)明确移除K1路由写中断时恢复完整可信旧配置的保证及专门power-interruption测试。无有效路由时K1暂不发送、K2–4可用；正常完成保存仍须读回和普通重启保持。当前架构1025行仍保持此决定。Restore的durable incomplete/显式重试不因此取消。

因此原单“配置/素材写入各关键阶段掉电”过宽，必须按模块合同拆开。不能要求新做完整泛化矩阵后才承认已有实现。

### 2. #13必须先检查客户端刷写策略

[FIRMWARE_INDEX当前指引](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/FIRMWARE_INDEX.md)要求对应硬件手动刷写保留DataFlash，不整片擦除。Mac当前[AhaKeyFirmwareFlasher.swift](../../ahakeyconfig-mac/Sources/Utilities/AhaKeyFirmwareFlasher.swift)会依次执行`--usb eeprom erase`、`--usb erase`、`flash --no-erase`，界面也明确让用户确认清空。此前测试清空经过单次明确授权，不能倒改成“未授权擦除”；但普通升级/高级清空恢复与最新交付指引的适用范围，应由客户端先核对对齐。

这里仅证明策略差异，**没有证明清DataFlash就是历史Reconnect的唯一根因**，也未证明DataFlash等于蓝牙bond区域。还要按实际工具和布局区分CodeFlash/SNV/bond。不能把该责任直接推给固件配对功能。

### 3. #16应按已有职责协作，不把客户端发布工作全推给固件

[WS4/5 PRD](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/workstreams/X1-PLATFORMIZATION-RELEASE-COMPOSITION/PRD.md#L135)明确catalog属于Desktop/release operations，不存在设备里；[Architecture职责表](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/workstreams/X1-PLATFORMIZATION-RELEASE-COMPOSITION/ARCHITECTURE.md#L57)区分固件key和桌面目录/验签/候选/刷后验证。

PRD的信任文字是version+checksum/signature，Stage B open decisions仍列具体文件格式和signing/checksum机制；不能称某个特定签名算法/公钥已经是固件欠交的已冻结合同。客户端已实现的签名目录是我方设计选择，应在发布协作里确认。

PRD381行明确recovery-safe候选可以是之前稳定版、当前最稳定版或专用恢复版。需要资格和证据，不强制normal和recovery必须是两个新编译的不同字节文件。当前工程文件已交，不再重复要求Owner找HEX。

## #12/#17为何仍保留为对接需求

[CP4D合同](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/workstreams/X1-INPUT-CONTROL/ARCHITECTURE.md#L891)直接定义53字节上限；源码command_solve.c1037行执行同一规则。K1 `0x9E/0x10`只分块返回route kind/length/action，不包含全部16键的独立描述。

[CP2合同](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/workstreams/X1-INPUT-CONTROL/ARCHITECTURE.md#L434)明确内部短长按底座已做，Desktop写协议不在CP2范围；生产psk_multi_button.c343行的load_policy把short和long都指向`user_key_bind[mode][key_index]`。因此“两个机制都没做”的说法错误；需要核对的是超长完整读回和两套动作的用户配置闭环。这些需求仍服务Owner已确认的完整客户端目标，没有被本次审计删除。

## 可以发给对方的简短说明（草稿，未发送）

> 已重新核对，之前把已有实现待Mac复验、历史观察、新能力和发布协作混称为“未修复”，口径不准。已有断连恢复、捕获释放、GPIO快照及故障测试我们会直接复用；K1写入掉电旧值恢复的已撤销要求会删掉。目录/签名策略/公证等按客户端发布职责处理。接下来只请你帮忙指出#12长宏完整读回、#17两套动作配置的现有入口；#10则单独确认Mac逻辑取消而物理HID还在时是否需要体验扩展，不要求重做已有机制。

## 本轮处理边界

更新本地WBS/协作清单与此建议稿；GitHub原单尚未修改、关闭或新增评论。对方今天逐条回复后，应把其给出的具体路径补到同一张表，有现成接口就由Mac继续接线，而不是继续索要整套重复证明。未作破坏性设备验证，也不因为这份纸面核对宣称完整硬件验收通过。
