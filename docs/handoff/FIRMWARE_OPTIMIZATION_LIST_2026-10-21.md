# Mac 适配固件优化与协作清单

更新：2026-11-03。当前核对 `Fireware-harness@72346b001710d573980a7d398b9e0dced8ff627c`；本机为HW1 F99D，目录身份 `x1-c582-hw1-p1-1.0.1-r001`，客户端0.2.3/build539，不依赖Runtime。HW1构建源为5fc01cf；最新归档仅新增HW2修复包与HW1验收归档，HW1 APP/Profile及HEX未变。

## 追踪规则

原[Issue #7](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7)已改为归档索引。**总单Closed不代表全部条目修复或全部验收通过。** 未闭环项已拆为8个独立Issue，各自按证据关闭。历史风险、协议缺口、联合验收和正式交付依赖分别注明，不能统一当成“当前固件已复现缺陷”。

已有Harness合同和结果直接回填链接，缺项才补；不重复索取已有协议或全部Windows工程。既有架构提案#6继续独立跟踪；新FW-07追验收证据，不重复要求改用某种存储架构。

## 全量条目与去向

| 编号 | 状态/性质 | 当前事实 | 后续工作 | 追踪入口 |
| --- | --- | --- | --- | --- |
| FW-01 | P1 · 旧组合已复现／F99D待复验 | 上传取消后可能继续拒绝配置读取，旧07A8需正常重启；K1保存修复不能替代上传取消恢复。 | 独立取消/有界事务收敛、重连读取与同位置重传。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/10) |
| FW-02 | 已有实现与正常路径实测 | 逐模式Consumer/普通路由、反复恢复已接入；F99D三轮Codex往返、四模式隔离与断电读回通过。 | 原能力缺口不重提；异常释放/故障覆盖仍分别验收。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/8) |
| FW-03 | P1 · 条件性风险／待验证 | 发送结果未向上返回、普通键去重缓存提前更新；K1 UP路由读失败清捕获不发release，实际可达性/现场根因未证实。 | 发送失败、路由不可用及模式/休眠/重连的释放责任与有界恢复。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/11) |
| FW-04 | P2 · 协议容量缺口 | 当前0x87中11+动作+描述不能超过64字节；K1路由分片动作不含独立描述，不能覆盖全部按键的完整长宏事实。 | 完整动作/描述读回、快照一致性、能力探测与兼容合同。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/12) |
| FW-05 | P2 · 历史现象／待复验 | 旧升级曾持续Reconnect，Forget PC后恢复；未在本轮F99D复现该故障。 | 区分保留绑定与清DataFlash刷写，补绑定迁移/重新配对/退避及安全恢复策略。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/13) |
| FW-06 | P2 · 历史现象／待复现 | 旧唤醒曾出现读回档位与Owner理解位置不符，重新拨动后恢复；本轮F99D正常往返通过，根因仍未确认。 | GPIO/去抖/首次0x00发布与主机缓存分项核对，覆盖启动和唤醒边界。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/14) |
| FW-07 | P2 · 联合故障验收 | 正常保存/读回/断电保持不替代存储失败、校验失败、掉电、未完成素材和Restore故障矩阵。 | 优先复用现有Harness证据；逐项标明确已覆盖、缺失、失败和恢复范围，关联既有#6提案。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/15) |
| FW-08 | P1 · 正式固件交付依赖 | 工程HEX已经存在；正式schema/预算、受控验签公钥与签名目录、normal/recovery-safe资格仍需发布方闭环。 | 给出现有权威合同、批准状态和精确来源/镜像；客户端公证另由客户端发布流程负责。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/16) |
| FW-09 | 原重复恢复缺陷已有修复与实测 | 旧组合连续0→1→2恢复及完成状态保持已通过，原#9缺陷不重复提。 | F99D及断电/改路由后恢复、默认模式和故障边界归FW-07。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/9) |
| FW-10 | 镜像缺失问题已解决 | 历史6EC组合HEX已恢复，当前HW1 F99D工程HEX已取得并实刷，不再要求Owner另找同一文件。 | 正式恢复安全镜像资格不是工程文件存在的同义词，另归FW-08。 | — |
| FW-11 | P1 · 新能力开发依赖 | 任意键独立短/长按的两套动作、阈值、松开、保存和完整读回合同未确认；App按住录音不等价。 | 按模式/按键范围、互斥/持续语义、释放、迁移及能力合同，随后Mac实际接线。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/17) |
| FW-12 | 修复代码与机器证据已交付 | F99D包含BLE长回复背压后的有界续发；普通分片配置读取通过，完整压力/故障覆盖仍保留。 | 不将旧07A8缺尾自动认定为F99D仍必现；完整原包与故障边界依Harness/客户端矩阵核验。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7#issuecomment-6491156613) |
| FW-13 | 正常交互已明确／本轮短按实测通过 | Owner明确接受短按听写、长按Siri；F99D下Claude Consumer12组down/up配对、无Command，Owner确认听写/Dock正常。 | 撤销历史固定短脉冲/禁止长按Siri诉求；异常释放风险归FW-03，不重提正常长按。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7#issuecomment-6604739434) |
| FW-14 | K1保存窄缺陷修复已确认 | F99D三轮Consumer/RightAlt保存3次commit成功，14组四模式CRC快照其他模式不变，重启后16键/4路由、待机/语音平台/拨杆绑定保持通过。 | 本项通过不代表其他条目或完整故障矩阵通过；不重复要求同一保存复测。 | [查看](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7#issuecomment-6604739434) |

## 当前仍需交接的输入

- 长宏完整事实读回与独立短/长按的受支持合同或现有等价路径：分别见FW-04、FW-11。
- 素材上传取消的无需重启恢复，以及输入释放/存储/启动恢复边界：分别见FW-01、FW-03、FW-07。
- 正式固件目录、验签材料及恢复安全镜像：见FW-08；当前不缺F99D工程文件。

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
