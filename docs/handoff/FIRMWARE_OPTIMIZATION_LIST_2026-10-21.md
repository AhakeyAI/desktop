# Mac 适配固件优化与协作清单

更新：2026-11-04。当前核对 `Fireware-harness@72346b001710d573980a7d398b9e0dced8ff627c`；本机为HW1 F99D，目录身份 `x1-c582-hw1-p1-1.0.1-r001`，客户端0.2.3/build548，不依赖Runtime。HW1构建源为5fc01cf；最新归档仅新增HW2修复包与HW1验收归档，HW1 APP/Profile及HEX未变。

## 2026-11-04口径更正

本表是**固件/客户端联调、历史观察、能力扩展及发布协作清单，不是8个最新固件未修复Bug**。本轮重读Issue原文、Harness批准合同、Owner决定、生产代码和已有测试后，应先复用现有实现/证据。特别纠正：

- #15不得重新引入Owner已于2026-10-24取消的K1路由写中断旧值恢复保证；正常保存后的读回/普通重启保持仍要求，Restore中断恢复另按其合同。
- #16的发行目录/信任策略属于客户端与发布协作；固件身份、工程HEX、源码/哈希和机器结果已有，不能统一当作固件未交付。恢复候选可资格确认现有稳定镜像，不要求为了文件数量另编一份HEX。
- #10已实现物理owner loss恢复；Mac本地取消而HID物理链路保留是额外体验/联调问题。#11/#13/#14不能从静态分支或旧现象升级为F99D确诊Bug。
- #12是超出CP4D单报告上限的协议扩展请求；#17是已实现短长按安全底座之外的可配置闭环，均不应说原机制整体没做。

详见[逐条重审](../ahastudio/firmware-issue-classification-review-2026-11-04.md)与[运行路径复核](../ahastudio/firmware-issues-runtime-reaudit-2026-11-04.md)。Owner后续已授权并执行GitHub更新：#11/#13/#14/#16关闭归档（not_planned），#10/#12/#15/#17保留开放，#8/#9补最新限定证据、#7更新索引；11单正文/评论/状态均已回读核对。[实际处理与反馈链接](../ahastudio/firmware-issue-updates-2026-11-04.md)。

## 追踪规则

原[Issue #7](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7)已改为归档索引。**总单Closed不代表全部条目修复或全部验收通过。** 未闭环项已拆为8个独立Issue，各自按证据关闭。历史风险、协议缺口、联合验收和正式交付依赖分别注明，不能统一当成“当前固件已复现缺陷”。

已有Harness合同和结果直接回填链接，缺项才补；不重复索取已有协议或全部Windows工程。既有架构提案#6继续独立跟踪；新FW-07追验收证据，不重复要求改用某种存储架构。

## 全量条目与去向

| 编号 | 状态/性质 | 当前事实 | 后续工作 | 追踪入口 |
| --- | --- | --- | --- | --- |
| FW-01 | 体验优化/联调，非F99D确诊Bug | 物理owner断连、writer取消、INVALID重试和启动清理已有实现及D1-D7证据；旧07A8取消后需重启不能推定F99D当前失败。 | 仅核对Mac取消但HID链路仍live的会话结束体验；优先复用现合同，不强求新opcode。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/10) |
| FW-02 | 已有实现与正常路径实测 | 逐模式Consumer/普通路由、反复恢复已接入；F99D三轮Codex往返、四模式隔离与断电读回通过。 | 原能力缺口不重提；异常释放/故障覆盖仍分别验收。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/8) |
| FW-03 | 已关闭归档，未确诊风险 | UP/模式/配置切换、Sleep和真实断连收尾已有生产TU测试；发送失败和UP读路由失败尚未建立真实可达故障序列。 | 有真实生产可达失败序列时重开；不以静态分支归因历史Siri/Command，不重做已有机制。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/11) |
| FW-04 | 协议扩展请求，现CP4D行为符合合同 | CP4D明确单报告64字节、动作加描述最多53字节、超长TOO_LARGE且不分片；K1路由分片不含全部键位描述。 | 若完整旧长宏需更大事实读回，指出/补受支持接口；不称普通宏保存功能未实现。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/12) |
| FW-05 | 已关闭归档，升级流程转客户端 | 正常重连与Forget保身份已有实现；WS1已有旧bond非阻断记录，F99D未复现该旧问题。Mac build548已区分默认保留DataFlash与显式清空；真实保持仍待验。 | 核对实际刷写保留/擦除、主机记录和身份；有同组合可复现及GAP原因后再提固件缺陷。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/13) |
| FW-06 | 已关闭归档，历史差异未复现 | GPIO采样/0-1-2快照已有生产路径和R2测试，F99D正常实体往返已过；旧唤醒差异缺GPIO时序证据。 | 仅针对可重复实际位置/新鲜回包差异补诊断，不视为采样功能欠实现。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/14) |
| FW-07 | 复用已有证据的联合验收 | CRC/INVALID/定时重试、共享store及Restore故障已有代码和host测试；不能因Mac未补验就抹去。K1写中断恢复旧值保证已被Owner排除。 | 仅保留已批准范围内物理擦除/Restore中断等NOT_VERIFIED项；删除所有配置必须掉电回滚的泛化条件。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/15) |
| FW-08 | 已移交客户端发布并归档 | PRD/Architecture已有逻辑合同及职责；固件身份、工程HEX/来源/哈希/机器结果已有。发行目录、校验/签名策略与客户端公证属发布流程。 | 复用现有交付，联合确认最终发布schema、预算和恢复候选资格；客户端承担目录/信任与公证/发布环境。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/16) |
| FW-09 | 原重复恢复缺陷已有修复与实测 | 旧组合连续0→1→2恢复及完成状态保持已通过，原#9缺陷不重复提。 | F99D及断电/改路由后恢复、默认模式和故障边界归FW-07。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/9) |
| FW-10 | 镜像缺失问题已解决 | 历史6EC组合HEX已恢复，当前HW1 F99D工程HEX已取得并实刷，不再要求Owner另找同一文件。 | 正式恢复安全镜像资格不是工程文件存在的同义词，另归FW-08。 | — |
| FW-11 | 已有安全底座；用户配置闭环需求 | CP2已实现短长按内部安全机制且明确不含Desktop写协议；当前load_policy仍镜像同一动作。 | 对方若已有两套动作配置/保存/读回入口，只需指出；否则按阶段扩展推进，不称短长按机制没做。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/17) |
| FW-12 | 修复代码与机器证据已交付 | F99D包含BLE长回复背压后的有界续发；普通分片配置读取通过，完整压力/故障覆盖仍保留。 | 不将旧07A8缺尾自动认定为F99D仍必现；完整原包与故障边界依Harness/客户端矩阵核验。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7#issuecomment-6491156613) |
| FW-13 | 正常交互已明确／本轮短按实测通过 | Owner明确接受短按听写、长按Siri；F99D下Claude Consumer12组down/up配对、无Command，Owner确认听写/Dock正常。 | 撤销历史固定短脉冲/禁止长按Siri诉求；异常释放风险归FW-03，不重提正常长按。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7#issuecomment-6604739434) |
| FW-14 | K1保存窄缺陷修复已确认 | F99D三轮Consumer/RightAlt保存3次commit成功，14组四模式CRC快照其他模式不变，重启后16键/4路由、待机/语音平台/拨杆绑定保持通过。 | 本项通过不代表其他条目或完整故障矩阵通过；不重复要求同一保存复测。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7#issuecomment-6604739434) |

## 当前实际协作项

- #12/#17：长宏完整读回扩展及独立短长按用户配置闭环，先指出已有受支持入口，确实缺少再补。
- #10：Mac逻辑取消保留物理链路的体验合同，承认既有物理owner loss实现。
- #15：保留合同范围内物理联合验收；复用已有机器/生产测试，不重新引入已排除要求。#11/#13/#14已按未确诊/历史观察归档，有新的可复现证据时重开。
- #16已移交客户端WBS G40/G50–G54/G53并关闭归档；正式发布尚未完成，固件已给身份/HEX/机器证据不再重复索要。

## 已明确的产品与证据边界

- F5备选按Owner决定暂缓；Consumer长按Siri为正常交互，不发出“必须固定短脉冲”的新要求。
- 19素材位置、默认8帧/其他12帧、10fps与0x8D停用自定义素材已有合同，不重复索要；0x8D不等于abort、找回旧图或安全擦除。
- 上传取消在旧07A8上失败、重启后恢复通过；F99D尚未做同一取消故障复验。
- 正常Consumer、K1保存、原会话拨杆与断电保持的已过子项保留；不能据此关闭整套故障/长期/多硬件覆盖。
- HW1结果不套用独立HW2候选。Mac高CPU、Hook参数、编辑锁定和取消提示等客户端修复不列作固件新缺陷。
- 本清单及Issue拆分未修改或刷写固件，没有新增硬件UAT结论。

## 证据入口

- [最新归档及HW1同源核验](../validation/connect-talk-hil-2026-10-22/firmware-72346b-archive-sync-2026-11-03.json)
- [F99D三轮保存与断电保持](../validation/connect-talk-hil-2026-10-22/hw1-save-fix-hil-2026-11-03.json)
- [Consumer定向HID及Owner结果](../validation/connect-talk-hil-2026-10-22/f99d-consumer-hid-build539-2026-11-03.json)
- [旧上传取消/恢复记录](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7#issuecomment-6519589952)
- [原提醒清单](./FIRMWARE_FOLLOW_UP_2026-10-09.md)及Git历史保存最初描述；当前状态以本表和独立Issue为准。
