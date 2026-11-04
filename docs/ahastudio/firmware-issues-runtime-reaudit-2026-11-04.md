# Firmware issues #10/#11/#13/#14/#15 runtime re-audit — 2026-11-04

> **同日后续实际更新**：Owner授权后已回填11单并核对GitHub结果；#11/#13/#14/#16按未确诊/职责移交关闭归档，#10/#12/#15/#17保留开放。详见[处理回执与反馈](firmware-issue-updates-2026-11-04.md)。下文保留此前只读审计阶段的结论/建议和当时边界，不代表GitHub当前仍未更新。

本轮重新从问题原文、固件生产代码、Harness 合同、既有测试和回执取证；不为先前结论辩护。未修改固件仓库 Issue、固件源或设备，未烧录、复位、断电。问题 JSON 快照 `/tmp/ahakey-fw-issue-audit-20261104/issue-N.json` 中五单 comments 均为空，开发者尚无可引用的新回复。

## 结论

| Issue | 分类 | 建议最小处理 |
|---|---|---|
| #10 | (a) 真实链路丢失、writer 取消和 INVALID 恢复已有实现及生产路径测试；(e)/(d) 保持物理连接的配置会话取消是额外合同，目前没有等效素材空闲超时 | 承认已实现部分，只保留“逻辑会话停止而链路仍 live”产品合同/客户端联调；不得把 07A8 历史实测写成 F99D 当前故障 |
| #11 | (a) 捕获动作的 UP、模式/配置切换、Sleep/断连语义已有实现及测试；(c) 失败发送和 UP 路由失败仍是条件风险 | 去掉对既有捕获释放功能缺失的暗示；仅保留实际发送失败/异常持久化后路由不可用的可达性研究，不能认定历史 Command/Siri 根因 |
| #13 | (c) 历史迁移/旧绑定观察，不是已证 F99D 回归；(a) 正常重连、Forget 保身份功能已实现 | 改为非阻断迁移文档/旧绑定复验；刷写保留/擦除行为须绑定实际工具和选项 |
| #14 | (a) 实体 GPIO 采样与快照发布已有生产代码及真实函数 host 测试；(c) 启动/唤醒首次状态差异未复现 | 作为历史观察/联合诊断；补物理位置与新鲜回包关联，不能称拨杆采样功能未实现 |
| #15 | (a) 故障拒绝、CRC、INVALID、启动清理、Restore 持久状态已有实现及多层证据；(b) Mac 状态展示/草稿保留；(e) 泛化 K1 写中断恢复违背既有 Owner 排除 | 回填已有结果，把未做的物理故障试验单列；删除重引入 CP2.6 route-save 掉电恢复保证的要求，保留 Restore 单独批准的 interruption 验收 |

## 基线和证据边界

审计使用 `git show/grep origin/Fireware-harness`，固定 commit `72346b001710d573980a7d398b9e0dced8ff627c`，没有读取固件工作目录的旧分支作为生产结论。`git diff 5fc01cf43990743051bbc68c9381c9a44441b1d8 72346b0 -- APP Profile` 无差异。交付 manifest 明确 `git_head_at_build=5fc01cf...`、catalog key `x1-c582-hw1-p1-1.0.1-r001`、F99D 完整 HEX SHA256；HW2 不在此推论范围。[F99D manifest](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/evidence/builds/hw1-k1-save-fix-20261102/save-fix-build-manifest.json#L154)

注意：manifest 是原构建方 provenance，不能把它改写为此次完全重建验证。抽查其 136 个 source hashes，许多 raw blob 与 Windows checkout 行尾不同；按全文件 LF/CRLF 尝试仍有 16 文件不匹配（含 keyboard.c、psk_hid.c），构建脚本以 `hashlib.sha256(p.read_bytes())` 对当时工作目录原始字节取 hash（[实现](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/tools/harness/build-hw1-k1-save-fix.ps1#L10)），并校验构建期间不变；不是 Git blob hash。这些差异本轮未定位，不能据此断言语义代码有变化。command_solve.c、psk_multi_button.c、k1_restore_store.c 可按行尾形式匹配。因生产 Git tree 在 5fc01cf 与 72346b0 一致，下面可靠说明该源码线行为；不能由此声称已完全重建并验证每个 HEX 字节。

另核对 `origin/eternal-dev=bc4f6e40dc11b486af9cedba528d24844e6225a9`、`origin/harness/x1-refactor-main=efecc471376f99ce6753e257933bfba287937bb4`。eternal-dev 仍有旧 GPIO 采样路径，但不是 HW1 F99D 的归因基线；refactor-main 仍包含 resource upload loss cleanup，未见可替代此处逻辑会话取消的 resource timeout。没有借用这些分支宣布当前 HW1 已修复。

机器 PASS 表示相应 host/static/production-function 检查，不等于 macOS 实际动作、控制器交付、真机故障注入或所有启动时序 PASS。反过来，缺少额外 HIL 不能抹去已有实现。

## #10：不能再泛称“取消与恢复未实现”

`command_process_losses()` 依据 owner transport/handle/generation 判定死连接，取消 active/busy writer，或调用 `resource_upload_abort_invalid()`；后者清 active、设置 pending-mask 并尝试持久 INVALID。`command_recovery_tick()` 每秒重试 pending invalid；启动 sanitize 也处理 WRITING/不一致元数据。已提交且 publication 先于 loss 的资源保留，不是随断连无条件清掉。[command loss / retry](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/sub_main/command_solve.c#L728) [resource transaction implementation](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/services/resource_upload_transaction.c#L54)

既有 `test_production_paths.c::disconnect_tests` D1-D7 覆盖 queued Begin/Chunk/Commit 丢失、同 handle 重连、IO 中 loss、提交发布前后、无关链路/重复 loss、失败 INVALID 校验、无重连定时恢复、多位置 boot sanitize。存档 stdout 七项 PASS，已经直接反驳“没有 writer/loss/INVALID 恢复实现”的笼统说法。[production disconnect tests D1-D7](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/tests/host/ai_presentation/test_production_paths.c#L120) [stored D1-D7 PASS](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/evidence/checkpoints/X1-AI-WORKFLOW-PRESENTATION/CP2/20261018T171958/CP2_UPLOAD_DISCONNECT_OWNER_TESTS.stdout.log#L1)

但问题原文特定前提“macOS 仍可能保留键盘 HID 物理连接”非常关键：现合同只把真实 USB/GAP loss 认作 owner loss，明确 Windows 关闭但 USB 仍枚举不构成 loss。active upload 只允许 Chunk/Commit/0x00，0x83/0x9F 返回失败符合这份旧合同。资源事务结构无 clock/last_activity；30 秒超时属于 **K1 route temporary transaction**，不是素材上传。没有发现无需物理断连即可取消一个仍 live 上传的专用合同/通用闲置超时。[physical loss contract](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/workstreams/X1-AI-WORKFLOW-PRESENTATION/ARCHITECTURE.md#L1189) [30s K1 timeout, resource pending retry](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/sub_main/command_solve.c#L794)

因此“提供……显式取消或有界空闲恢复合同”是对已实现物理 owner-loss 之外的新增产品需要；可以跟踪，但不能把现成部分重新作为固件欠实现。0x8D 不是 abort 的判断正确。不要用畸形 chunk 当公开 abort API：现代码虽可能触发 invalid，但不构成受支持的会话取消合同。

建议替换：**“物理 owner loss + writer drain + INVALID 定时恢复已有实现和 D1-D7 证据。仅待确认 Mac 本地取消保留物理连接时的会话结束合同及 F99D 联调；若能保证真实 owner loss，先按现合同验证，不要求新增 opcode。旧 07A8 重启恢复不证明 F99D 当前缺陷。”**

## #11：既有捕获释放不可忽略；两个窄风险不能推导历史根因

代码捕获 DOWN 时的 route kind/action/usage/mode，UP 使用捕获内容，Sleep 显式正常释放；真实 disconnect 清状态，禁止把旧 release 发到新连接。这是合同明确选择，不是“断连没有发送 release 所以漏实现”。生产 TU 测试真实调 `key44callback`，证明 mode 从 0 改 1、在线 route 被替换后仍释放原 Consumer；另证明 disconnect 无迟到 release，Sleep 释放普通动作。20261030 followup 已修复重复离线 USB polling 误清 BLE capture；回执绑定特定 candidate，17 required checks PASS，明确 Owner UAT pending。[capture/sleep/disconnect](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/hardware/psk_multi_button.c#L257) [actual production TU assertions](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/tests/host/input_control/test_k1_production_tu.c#L120) [20261030 followup result](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/evidence/checkpoints/X1-INPUT-CONTROL/CP2.6_K1_CAPTURE_RELEASE_FOLLOWUP/regate-20261030/handoff.md#L1)

问题两个具体观察在源码上成立：普通键去重 cache 在 void 封装发送前更新；封装忽略 HidDev_Report 返回值。不能把 Consumer 的直接发送与普通键 cache 混成同一因果链。尚未证明实际发送失败被永久抑制或它就是历史 Command 卡住根因。[keyboard cache-before-send](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/hid_dev/keyboard.c#L106) [void HID wrapper](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/hid_dev/psk_hid.c#L432)

`input_control_k1_route_event(PRESS_UP)` 读 route 失败会 `finish(0)`，但 `k1_restore_store_read` 使用 cached `s_current`；不是每次 UP 都重新读 EEPROM。普通 mode/config 变化已被测试反例覆盖。路由不可用通常来自 unusable store 或 Restore IN_PROGRESS/INCOMPLETE；Restore reset 路径还有显式释放。所以必须展示“已 DOWN、之后异常 store 状态使 read 失败、且其他 cleanup 未释放”这条生产序列，才有实际 defect。错误 mode、强制改内存、孤立调用失败分支不能代替可达性证明。[cached route read](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/services/k1_restore_store.c#L314) [reset release](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/sub_main/main.c#L883)

建议替换：**“捕获释放、模式/配置切换、Sleep 和真实断连清理已实现。剩余两项为条件风险：HID 实际失败如何恢复，以及异常 store 状态导致 UP route 失败是否可达。只有证明真实失败序列再定修复；不据此归因已通过的正常短按或历史 Siri/Command。”** 不要求全面新 fault matrix 才承认功能已实现。

## #13：旧绑定观察与现成恢复策略须分别说

`connectivity_identity` 已把 remembered-host reconnect/open pairing/Forget-hosts-preserve-identity 分为明确 API；测试也验证边界。WS1 FINAL closure 接受 CP1/CP2/CP3/CP3A，并把 post-Forget pairing recovery 列为已关闭阻断项。与此同时，它明确保留 `WS1-CP2-STALE-HOST-LOCAL-BOND-SECURITY-FAIL` 非阻断观察：主机陈旧记录+键盘旧 bond 可能短连后安全/HID 失败。不能说所有旧绑定场景均已解决，也不能把它重新包装成 F99D 新增 P2 defect。[identity APIs](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/services/connectivity_identity.c#L6) [WS1 closure and carried debt](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/evidence/workstream-closures/WS1-FINAL-CLOSURE-20260930.md#L80)

“升级”包含实际烧录器是否擦 DataFlash、主机是否忘记配对、BLE 地址是否改变等外部条件。源代码无法替代烧录工具实际选项；“所有旧/新 HEX 矩阵完成才关闭”是新增 qualification 需求。

建议替换：**“历史旧绑定/升级流程观察，F99D 未复现；正常重连与 Forget 保身份恢复已有实现。回填实际烧录保留/擦除策略及预期重新配对指引。若同一身份、保留绑定升级仍可复现，再附 GAP/security reason 建具体缺陷。”** 可移非阻断文档/联合验证，不要求无提示清配对。

## #14：GPIO 与发布功能已存在，首包时序另说

`main.c::read_sw_state` 实际切换 PB5 并两次读 PB4 得到 0/1/2；与 static last_state 比较后 `sw_state_change` 更新 `running_data.sw_state`、SDK lever event、`command_side_snapshot()`，然后执行物理拨杆动作门。MCT_key_scan 定时执行采样，配置绑定与物理 sw_state 是不同数据。这里没有证据表明需要软件反转方向。[physical GPIO sampling + snapshot](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/sub_main/main.c#L1140) [periodic production scan](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/sub_main/main.c#L1320)

更强的反例：`test_cp2_5_production_paths_adapter.c` R2 通过真实 main scan→GPIO→callback，把 physical_switch 依次置 0/1/2，并验证三份 immutable snapshots 的 0/1/2。它不是镜像重写算法；runner 从 production source 提取真实函数。它不能证明首次 0x00 一定晚于首采样，也不能证明实际硬件去抖/启动电平，但足以承认采样/发布实现存在。[actual main/GPIO R2 oracle](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/tests/host/ai_presentation/test_cp2_5_production_paths_adapter.c#L422) [production extraction runner](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/tests/host/ai_presentation/run_production_paths.py#L1)

建议替换：**“实体采样和发布已有实现/host 证据，F99D 正常拨动 Owner 已通过。旧唤醒差异无 GPIO 时序证据，列为观察；只在可重复的新鲜回包与实际位置不一致时升为固件缺陷。启动首包、host 缓存、物理方向逐项区分。”**

## #15：主要是证据索引/联合验收，且部分要求已经明确不在承诺内

素材 `begin` 验证范围/长度、持久 WRITING；chunk 检查序号/长度并在失败时 invalid；commit 要求完整字节数及 CRC，并验证 VALID 元数据发布；发布失败补偿 INVALID，失败时 pending quarantine 和定时 retry，不假成功。D1-D7 和 host transaction tests 已覆盖大量所列场景，不能只提“正常保存或几次重启不足”而漏掉已存在的失败注入。[resource transaction implementation](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/APP/services/resource_upload_transaction.c#L54) [production disconnect tests D1-D7](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/tests/host/ai_presentation/test_production_paths.c#L120) [transaction host tests](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/tests/host/ai_presentation/test_resource_display_config.c#L114)

共享 K1/Restore store 测试覆盖 v1→v2 deliberate-write migration、corrupt committed record fail-closed、generation ambiguity；Restore production journey 覆盖 refusal、持久 incomplete、boot/reconnect 不自动继续、显式 retry、重复 COMPLETE attempt token 等。检查并不等于真机 erase adjacency 或物理掉电验证；剩余项宜标精确 NOT_VERIFIED，不能声称已全硬件验收。[shared store tests](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/tests/host/input_control/test_k1_route_store.c#L45) [Restore production journey](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/tests/host/restore_initialization/test_restore_production_journey.c#L92)

关键范围纠正：20261024 Owner 决定明确移除 CP2.6 route-store 写中断时恢复可信旧 K1 路由的保证及专门 power-interruption test；无有效路由时 K1 暂不发送、K2-K4 可用，完成保存仍须读回和普通重启保持。当前 PRD/EXECUTION 继续保留这个选择；Restore 的 durable IN_PROGRESS/INCOMPLETE 及中断验收是独立要求。故原文“配置/素材写入各关键阶段掉电或重启”如泛化为所有配置的原子回滚保证，将重引入已撤销范围。[explicit Owner removal of route power-cut recovery](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/evidence/owner-decisions/X1-INPUT-CONTROL-CP2_6-POWER-LOSS-RECOVERY-REMOVED-OWNER-DECISION-20261024.md#L11) [current PRD scope distinction](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/.ahakey-harness/workstreams/X1-INPUT-CONTROL/PRD.md#L286)

“Mac侧……显示失败/未确认/恢复状态并保留草稿”属于客户端职责；没有这些 UX 不能证明固件实现缺失。建议把本单改为跨端证据索引，分别列 已有 host/生产路径 PASS、已做特定 HEX HIL、未做物理故障 qualification；删除所有配置必须掉电回滚的暗示。正常重复 Restore 已修复的结论应保留，不再次索要同一缺陷实现。

## 本轮实际验证

把固定 ref 的源文件导出 `/tmp/ahakey-runtime-72346`，仅在临时目录用 clang 编译并运行现有 `tests/host/ai_presentation/test_resource_display_config.c` + `APP/services/resource_map.c` + `APP/services/resource_upload_transaction.c`，使用仓库 runner 同样的 `-std=c99 -Wall -Wextra -Werror`，结果 **PASS: resource display config host tests**。没有新增仿真镜像测试；该运行只支持资源事务/容量/fail-closed 单元范围，不支持 BLE/Mac 真机、真实 Flash 故障或 HIL。完整 production-path runner 依赖 Windows WCH SDK 路径，本轮没有改它或伪称重新跑过 D1-D7；D1-D7 引用的是仓库原回执。
