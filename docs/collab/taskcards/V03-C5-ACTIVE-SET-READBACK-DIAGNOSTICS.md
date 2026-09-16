# 任务卡 V03-C5-ACTIVE-SET-READBACK-DIAGNOSTICS：用设备现有状态帧闭合 active-set 写入事实

计划/WBS：v0.3 客户端 OLED 兼容 / C5 HIL 诊断
状态：`ready / C5IR8`
执行 owner：DSH
只读固件核对：Zcode
验收：Codex
产品基线：`85e193e62fb433436a965c72d771cd6cd351af43`
前置：15K-H accepted；C5R6 配置面通过、实物面失败并已回滚 official 0.2.1 (362)

## R6 冻结事实

- schema=3 active-set-only operation `53EC5DD6…` completed 1/1；设备 ACK 前提下 Runtime 将 `screenActiveSet:0` 记为 writeConfirmed(0)。package 唯一 action 为 `0x97 mode0 set0`，零 resource，A/B digest 未变。
- Stop(5) 后实物仍为 ident-B；A→B 未执行。R6 授权已消费，official 362 已恢复。
- writeConfirmed 不是设备 readback；R6 没有保存 `0x97` ACK echo，也没有保存 `0x00` 中的 current workMode/activeSet，因此不能判定“写入 mode0、显示另一 mode”还是“active set 未落地/后来回退”。
- 用户事后补充：进入编辑页时 Studio 原为 mode2/Codex，但在写入前已从键盘手动切到 mode0/Claude Code；最终 trace/package 也精确为人类标签 Mode 1 / `modeSlot=0` / `0x97 mode0 set0`。因此误写 Codex 已排除，physical-mode mismatch 降为次级反例；首要改为核 ACK echo 与随后 0x00 activeSet readback。

## 冻结源码只读核对

Gitee Rhino `53cd0a97` 可重建源码：

- `command_solve.c` SHA-256 `dfc42a66…718a3`：`0x97` 成功路径先更新 `active_ai_pic_set[mode]`、持久化，失败返回 status3；成功 ACK 回显 `[mode,currentActiveSet]`。当目标 mode 等于当前 `running_data.mode_data` 且 OLED active 时，清帧索引并投递 `MCT_PIC_DISPLAY`。
- `main.c` SHA-256 `bd19e99b…4d59`：`0x90 state=5` 映射 DONE；`update_claude_oled()` 设 active、清帧索引并投递 `MCT_PIC_DISPLAY`。因此“0x97 只在资源写时重绘”与“Stop 不触发任务图重绘”均被源码否定。
- Agent `sendConfigurationCommand` 等待匹配 generation/opcode 的 `0x97` 固件 ACK status0 后才返回，operation completed 不只是 CoreBluetooth didWrite；但 ACK payload `[mode,set]` 当前被丢弃，未与请求交叉验证。
- Gitee 周期 `0x00` 状态本来包含 battery/signal/fw/workMode/light/switch/brightness/**当前 mode activeSet**；Agent parser 只读到 switch，主动丢弃 brightness/activeSet。Runtime contract/reducer 已有 `activeTaskPictureSets` typed 投影，只是 Agent 没填。

## 红色反馈环

Codex 以临时测试注入 Gitee exact 扩展状态帧（随后删除临时代码，测试文件恢复干净）：

```text
swift test --filter AhaKeyAgentRuntimeEndpointTests.testDiagnosticExtendedStatusProjectsCurrentActiveSet
Executed 1 test, with 1 failure
XCTAssertEqual failed: nil != Optional(0)
Gitee extended status 已携带当前 mode 的 active set，Runtime 不得丢弃
```

该 0.38s loop 精确证明只读归因 seam 缺失；物理画面矛盾本身仍需下一次设备只读观察，host 不作伪复现。

## 完成定义

1. 扩展 Agent 的唯一 `0x00` parser：短 legacy/Standard 帧保持兼容；仅当扩展字段完整且 `workMode`、activeSet 值域合法时，才把 current mode active set 送入现有 `DeviceStateReducer.activePictureSet`/等价单次 reducer composition。畸形、截断、0xff/越界不得创建或覆盖 map。
2. 同一次状态帧只发布一次 deviceChanged；相同 frame 零重复事件/日志。XPC snapshot `device.state.workMode` 与 `activeTaskPictureSets[workMode]` 同源出现。只作为设备状态/诊断投影，**本卡不得调用 authority baseline readback、不得把 writeConfirmed 升 verified**。
3. 日志在状态真实变化时记录非敏感 `workMode` 与 `activeSet`；不得记录资源内容。`ble-verbose.log`/文件 sink 不在本卡范围。
4. `0x97` command ACK 必须校验 payload 精确回显请求的 `[mode,set]`；status0 但 echo 缺失/截断/错 mode/错 set 时 step fail-closed，不确认 WAL/baseline，并留具名诊断。合法 Gitee/Rhino/current ACK 继续通过；Standard 不产生 0x97。
5. ACK 校验使用单一 typed parser/seam；不得只在测试模拟 transport 中自证。现有 generation/peripheral waiter、防迟到、timeout/deviceRejected 语义不回退。

## 必测

- 注入 Gitee exact 0x00：workMode0/activeSet0 与 workMode0/activeSet1 均进入 snapshot map；相同帧零重复。workMode1 则只更新 mode1，不镜像 mode0。
- legacy 短帧不伪造 active set；截断扩展、activeSet=0xff/2、workMode 越界 fail-closed 且不覆盖上次可信 map。
- 0x97 ACK table：exact `[mode,set]` success；missing/extra/wrong-mode/wrong-set/status-nonzero/stale-generation 均不确认 step。断言 operation/baseline 零错误推进。
- 生产静态/接口门证明没有新增查询 opcode、没有 page baseline authority 调用、没有 View/Studio 消费绕路。

## 白名单与门禁

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- 现有 Shared parser/reducer 文件仅在确需 typed optional/组合 seam 时最小修改；优先复用已有 `activePictureSet` event 与 Runtime state contract
- Agent endpoint/page execution、DeviceStateReducer/contract 精确测试
- 本任务卡、当轮 evidence、`docs/collab/board.md` DSH append-only
- 定向、全量 Swift、App+Agent Release、identity、增量与 `5d1fe1d` 全范围 diff-check 全绿；提交白名单后停手提审。

## 非目标

不改 assembler/Facade/Studio/View、C3 Store/WAL/CAS、ReleaseIdentity、安装器、固件或 HIL driver；不新增主动 query，不更新/伪造 baseline，不签名/安装/HIL/设备写/刷机/EEPROM/断电/push。C5I accepted 后只能另请纯只读 R7 USER-GATE。

## 执行记录（append-only）

### [2026-09-14 18:00] Codex：R6 停点 accepted；源码否定 redraw/Stop 假设，开放 host-only C5I readback seam

- R6 配置面 accepted、实物面 failed；停止/回滚成立，授权已消费。A→B 不得补做。
- 源码证明 0x97 成功会 ACK并条件重绘，Stop(5) 会 DONE重绘；Agent 等设备 ACK但丢弃 echo，且丢弃现有 0x00 activeSet 字段。最可能分叉为 physical workMode mismatch，其次为 ACK echo/实际 set 不一致。
- 临时 0x00→snapshot 红测稳定失败并已清理。仅开放 C5I：解析现有只读状态+验证未来 ACK echo；零新查询、零设备写、零 baseline 变更。
- 用户补充又证明写入前已物理切到 mode0，且 package 也是 mode0；误写 Codex 排除。C5I 首要核 ACK echo/readback，mode mismatch 仅保留为需状态帧证伪的次级反例。
- 15L=`blocked / awaiting C5I`；C5I accepted 后另请 read-only R7 gate。
- 需要回复：是（@DSH ACK 后仅执行 C5I，完成停手提审）

### [2026-09-15 10:30] DSH：C5I 完成，停手提审

- **范围（host-only，零设备）**：逐文件 numstat（`git show --numstat fbc3b77` 原文）——`Sources/Agent/AhaKeyAgent.swift` **+118/−8**、`Sources/Shared/DeviceStateReducer.swift` **+9/−2**、`Tests/AhaKeyAgentTests/AhaKeyAgentByteProgressTests.swift` **+88/−0**、`Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift` **+91/−0**、`Tests/AhaKeyConfigSharedTests/DeviceStateReducerTests.swift` **+52/−0**、evidence **+141/−0**、本卡 **+90/−0**（合计 +589/−10）；未改 assembler/Facade/Studio/View/C3/ReleaseIdentity/安装器/固件/HIL driver。**机械更正**：原条目写的 `+126/−8`、`+11/−1`、`+73/+83` 是估算值，已按 numstat 原文修正。
- **状态帧 readback seam（完成定义 1）**：`DeviceStateEvent.fullStatus.activePictureSet` 改为 **typed optional**——`nil` = 该帧未携带扩展字节（legacy/Standard 短帧），**不创建、不覆盖** `activeTaskPictureSets[mode]`；`apply` 内 `if let` 才落 map。Agent 侧新增 typed `AgentActivePictureSetReadback` 与单一值域 seam `validatedActivePictureSet(workMode:activeSetByte:)`（固件 `USER_MODE_COUNT=4`、`AI_OLED_SET_COUNT=2`，Gitee `53cd0a97` `main.h` SHA `9ebebc72…c651`）；`parseDeviceStatus` 仅当 `payload.count >= 10` 才读 `base+8`，越界/截断即 nil。`cachedStatus()`（socket status 回包）显式 `activePictureSet: nil`，不当设备 readback。
  - `brightness` 保持既有 `Int` 与 `-1` 语义不动：本卡交付 active-set readback；改 brightness 会把 legacy 设备 XPC 快照从 nil 变 35%，属范围外行为变化。此决定请 Codex 复核。
- **单次 composition（完成定义 2）**：一次状态帧仍只走**一次** `DeviceStateReducer.apply` → 一次 publish；相同帧零事件/零常规日志（新测试与既有 dedup 测试同时覆盖）。XPC snapshot 的 `device.state.workMode` 与 `activeTaskPictureSets[workMode]` 同源出现在同一 snapshot（测试直接断言同一份 projection）。
- **日志（完成定义 3）**：状态真实变化时补 `workMode=` 与（仅 readback 存在时）`activeSet=`，仅非敏感标量，无资源内容；未新增文件 sink。
- **0x97 ACK echo 校验（完成定义 4）**：Gitee 成功路径回 `AA BB 97 00 <mode> <currentSet> CC DD`（`command_solve.c` SHA `dfc42a66…718a3`，已只读复核），故 `status=0` 后必须逐字节等于请求 `[mode,set]`。单一 typed seam `AhaKeyActiveSetAckEcho.validate(request:response:)`；缺失/截断/多余/错 mode/错 set 一律抛 `AhaKeyAgentCommandError.ackEchoMismatch` → `retryable:false` + `.configurationDeviceRejected` + `failureContext{failedStepID, opcode:0x97, deviceStatus:nil}` + 具名 `emit`。生产路径与 `skipBLE` 测试路径调用**同一** seam（hook 只提供设备回显字节）。合法 Gitee/Rhino/current ACK 不回退；Standard 不产生 0x97；waiter 的 generation/防迟到/timeout/deviceRejected 语义未动。未新增 `AhaKeyRuntimeEventCode`。
- **红色反馈环**：临时 endpoint 红测（Codex 已删除）的等价断言已永久化；另外三条反证补丁均实测变红——A `?? 0` 伪造 set0（4 failures）、B 去掉值域门（3 failures）、C echo 校验 no-op（9 failures，含反例 operation 变 completed 的假绿暴露）；每次补丁经 sha256 备份还原复核。
- **门禁**：定向 17 类 **422/422**；全量最终树第 2 次 **1220 / 2 skipped / 0 failures**（第 1 次仅命中既有 Agent concurrency flake；首版树第 1 次亦全绿 1220/0）；App+Agent Release rc=0；identity ok；增量 `85e193e` 与全范围 `5d1fe1d` diff-check 通过。
- 未新增主动 query、未调用 authority baseline readback、未升格 `writeConfirmed`、未伪造 whole-object；未签名/安装/HIL/设备写/刷机/EEPROM/断电/push；固件基线只读（firmware repo porcelain 空）；R6 保留的 `/tmp/ahakey-c5r6-*` 未复用未删除。提交只含白名单文件，不含 `board.md`/`queue.md` 既有他人 diff。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/42-c5i-active-set-readback-seam.md`
- 需要回复：是（@Codex 复核 C5I：状态帧 readback seam 的 nil/值域语义、0x97 ACK echo fail-closed 与 step 不确认、单次 composition 与同源 snapshot、三组反证、定向 422/422 与全量绿；并请裁定 `brightness` 是否留待后续卡）

### [2026-09-15 10:40] Codex：产品主语义与 brightness 边界通过；ACK/边界必测未完整，退 tests-only C5IR1

- 固定范围 `85e193e...fbc3b77`。Standards 轴 0 findings；Spec 轴 2×P1 + 1×P2。独立定向抽样 **175/175**、range diff-check 通过；最终全量 **1220 / 2 skipped / 0** 有效。
- 产品 accepted/frozen：activeSet typed optional、短帧 nil 不创建/覆盖、Gitee base+8 + mode/set 值域、单次 reducer/publish、XPC 同源 map、生产/skipBLE 共用 0x97 echo seam、mismatch nonretryable且不确认 step。无 query/authority/baseline/file sink。`brightness` 保持既有 `Int/-1` 是正确范围控制，**不另开卡、不在 C5IR1 修改**。
- **P1 ACK operation matrix**：missing/extra/wrong-mode 目前只测 pure validator，只有 wrong-set 进入真实 executor/WAL。任务卡要求 exact/missing/extra/wrong-mode/wrong-set/status-nonzero/stale-generation 每行都证明真实 step/operation/baseline 不推进。C5IR1 用同一 page/base execution fixture 表驱动全部失败行：终态非 completed、对应 0x97 step 不在 confirmed、page baseline/operation projection 不误进成功；status-nonzero 保留 deviceStatus，echo mismatch 为 nil；stale generation 不得借当前 waiter确认。
- **P1 production boundary gate**：补永久静态/接口测试，证明 C5I 范围没有新增 query opcode/主动查询调用、没有 `applyAuthoritativeFieldReadback`/baseline authority 调用、没有 View/Studio 消费旁路；测试必须精确扫描目标函数/文件，不得用会误匹配注释/evidence 的全仓 substring。
- **P2 log dedup**：扩展状态首个真实变化只产生一条含 `workMode=`/`activeSet=` 的 status log；相同帧重放零 status log。现有测试只锁了零 event，未锁零日志。
- **P3 evidence numstat**：任务卡执行记录的逐文件 numstat 与 git 实际不一致（实际 Sources `+118/-8`、`+9/-2`；tests `+88/+91/+52`）。C5IR1 evidence/append 需机械更正，不改历史提交。
- **仅开放 C5IR1（tests/docs-only）**：产品 `AhaKeyAgent.swift` / `DeviceStateReducer.swift` 零改；只改上述三个既有测试、evidence/任务卡/board append。复跑定向/全量/双 Release/identity/full diff-check，白名单提交后停手。
- 15L 保持 `blocked / awaiting C5IR1`；R7 USER-GATE 不建立、不授权。
- 需要回复：是（@DSH ACK 后仅执行 tests/docs-only C5IR1）

### [2026-09-15 11:35] DSH：C5IR1 完成，停手提审（tests/docs-only）

- **零改产品**：`git status --porcelain -- ahakeyconfig-mac/Sources` 为空——`AhaKeyAgent.swift`、`DeviceStateReducer.swift` 一字未动；改动仅测试 + evidence + 本卡。
- **P1 ACK 失败矩阵逐行走真实 executor/WAL**：新增 `testActiveSetAckFailureMatrixFailsClosedThroughRealExecutor`，`missing` / `extra` / `wrong-mode` / `wrong-set` / `status-nonzero` 五行各自 fresh agent + 真实 runner/Store/executor（`skipBLE` 只跳过外设写出，不跳过 ACK seam 与 WAL），逐行断言：operation 不 completed、`messageCode=configuration.device-rejected`、`failureContext.opcode=0x97`/`failedStepID=base:mode:0`（echo 行 `deviceStatus=nil`、status 行 `=3`）、**`base:mode:0` 不在 confirmedSteps**、**`syncBaseline==nil` 且 `pageFieldBaselines` 为空**、具名诊断（echo 行恰好一条 `expected=[0, 0] actual=…`；status 行走既有拒绝点且不误报 echo）。控制组补 `syncBaseline != nil`（成功路径确实推进 revision），使「零推进」断言非空转。
- **P1 永久 production boundary gate**：新增 `testC5IAgentBoundaryGateStaysFreeOfQueryAuthorityAndStudioBypass`，只读扫描 Agent + reducer 源码：无 `cmdReadTaskPicState`(0x94)/`cmdReadTaskPicSet`(0x96) 新查询；无 `AhaKeyRuntimePageBaseAuthority`/`pageBaseAuthoritySnapshot(`/`writeConfirmed`；Agent 的 `store.pageFieldBaselines(` 读取点**冻结在既有 2 处**；无 `AhaKeyStudioView`/`PackageAssembler`/`RuntimeFacade`/`PageCommitCoordinator` 旁路；正向断言 0x97 走 `AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet`、echo 走 `AhaKeyActiveSetAckEcho.validate(`、值域走 `validatedActivePictureSet(`。
- **P2 状态日志**：首帧必须恰好一条 `← status …` 且含 `workMode=0`/`activeSet=0`；相同扩展帧除零 event 外必须零 `← status` 日志。
- **反证（sha256 备份还原复核 `9ed68b63…f7a4`）**：D echo 校验 no-op → 矩阵 8 failures（operation 变 completed、step 被确认、`syncBaseline` 变 `revision:1/904 bytes`、诊断缺席）；E 注入 `AhaKeyRuntimePageBaseAuthority` 注释 → boundary gate 1 failure；F 生产日志去掉 `workMode=` → 首帧日志断言 1 failure。
- **stale-generation 闭合位置（请裁定）**：代际判定已在生产 `DeviceWaiterRegistry` 永久化——新增 `DeviceCommandSequencerTests.testResolve_staleGenerationNeverConfirmsZeroNineSevenAck`（0x97 精确字节：当前代际 `.response`；代际推进 → `generationInvalidated` 强败，同字节 ACK 无法复活，且无残留 waiter）。**executor 级 stale 注入在本卡不可达**：Agent 唯一 ACK ingress 是 CoreBluetooth delegate，现有 seam 只覆盖 OLED 协商帧，非 `skipBLE` 路径因 `commandChar/peripheral==nil` 直接 `.disconnected`；要灌入 stale ACK 必须**新增产品测试 seam**（改 `AhaKeyAgent.swift`），而 C5IR1 禁止产品改动。故本卡采用分层闭合，不声称已做到 executor 级 stale 注入——若需该粒度请显式授权最小产品 seam 卡。
- **机械更正**：C5I 条目原写的 `+126/−8`、`+11/−1`、`+73/+83` 是估算值，已按 `git show --numstat fbc3b77` 原文改为 `+118/−8`、`+9/−2`、`+88`、`+91`（evidence §6 同步给出 numstat 代码块）。
- **门禁**：见提审条目（定向、全量、双 Release、identity、diff-check）。未签名/安装/HIL/设备写/刷机/EEPROM/断电/push；R7 未建立未授权。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/42-c5i-active-set-readback-seam.md` §8
- 需要回复：是（@Codex 复核 C5IR1：五行矩阵三元闭环、boundary gate 与反向活性、P2 日志、numstat 更正；并裁定 stale-generation 分层闭合是否接受，或授权最小产品 seam 卡）

### [2026-09-15 11:50] Codex：五行矩阵/log 通过；旧 callback 可借当前 waiter，boundary gate 失真，退 C5IR2

- 固定范围 `fbc3b77...541742f`。Standards 轴 1×P1；Spec 轴 2×P1。五行 executor/WAL 失败矩阵、成功 baseline 控制、首帧唯一日志/重放零日志、tests/docs-only product-zero、numstat修正与最终全量 1223/0 均成立。
- **P1 stale callback source identity**：现测试只在 `DeviceWaiterRegistry` 上解析已 invalid 的旧 requestID；生产 `didUpdateValueFor` 却从当前 `inFlightCommand` 与当前 `configOperationWaiters[rid]` 选 waiter，再由 DeviceTransportCore补当前 generation。N 的旧 characteristic callback 若与 N+1 当前请求同 opcode、同 `[mode,set]`，仍可能借用 N+1 waiter完成。C1 的 callback association 已冻结 generation/peripheral，但目前只用于 0x99/0x94 negotiation，业务 ACK 分支未核 source。
- **仅开放 C5IR2 产品最小修复**：复用 callback 对象上已绑定的 source，抽一个不依赖 negotiation in-flight 的 current-source gate（source generation==当前、peripheralID==当前）；所有非 negotiation 的配置 ACK 在读取 current head/rid、解析状态、推进队列或恢复 continuation之前先过该门。unknown/ambiguous/invalid/旧代/异 peripheral callback 全部零 waiter/queue/WAL/baseline变化；当前 source exact ACK 正常完成。不得从 current head/global generation反推 callback source。
- **必测生产形状**：同 UUID N旧 callback对象；N+1 新连接/新 callback进入相同 0x97 waiter且请求/ACK字节完全相同。注入 N ACK必须零完成、零 confirmed step、零 baseline；注入 N+1 ACK才完成。另覆盖异 peripheral、unknown/ambiguous/invalid，及旧 0x00 扩展状态不得改 active-set map。测试 seam须把 callback object交给与生产 `didUpdateValueFor` 相同的 dispatcher，不得直接传 generation/requestID。
- **P1 boundary gate**：现 scanner会因注释假红，又漏过真实 `sendDirectCommandFrame(0x94/0x96)` literal。改为 comment-aware + 精确目标函数/callsite inventory：冻结既有 legacy probe 0x94 恰一处、0x96 零处，以及 authority/pageFieldBaseline/View旁路的真实调用点；不得以注释 mutant证明活性。
- **C5IR1 已通过项冻结**：五行 echo/status executor矩阵与 baseline零推进、状态日志、C5I optional readback/ACK echo主语义。brightness保持原状，不另开卡。
- C5IR2 白名单：`AhaKeyAgent.swift` 仅 callback source gate/test seam所需最小修改，endpoint/byte/page/sequencer精确测试、evidence/本卡/board。不得改 Reducer、Studio/View/Facade/assembler/C3 Store/schema或固件。
- 15L 保持 `blocked / awaiting C5IR2`；R7 USER-GATE不建立、不授权。完成提交、全门禁后停手提审。
- 需要回复：是（@DSH ACK 后仅执行 C5IR2）

### [2026-09-15 15:30] DSH：C5IR2 完成，停手提审

- **产品最小改动（仅 `AhaKeyAgent.swift`）**：新增唯一配置 ACK ingress `consumeConfigurationCommandAck(_:callbackIdentity:)`——形状校验后**先核 callback 冻结身份**，再读当前 head/rid、resolve、续 continuation、advanceQueue（顺序不可交换，失败路径零状态变化）。gate 谓词 `isCurrentConfigurationAckSource` 复用 C1 既有 callback object association（`commandChar`/`notifyChar` 在 `didDiscoverCharacteristicsFor` 已分别绑定），要求 `generation == oledConnectionGeneration` 且 `peripheralID == currentOLEDPeripheralID()`；unknown/ambiguous/invalid 由既有状态机天然判 false。**无新增账本/状态/第二套 association**。
- **单一实现**：提取 `enqueueConfigurationCommand` / `awaitRegisteredConfigurationAck` / `finishConfigurationCommand`，生产路径与测试 seam 共用同一注册与收尾逻辑（不复制粘贴）。测试 seam 只吃 callback 对象（`consumeConfigurationCommandAckForTesting`、`isCurrentConfigurationAckSourceForTesting`、`configurationWaiterCountForTesting` + hook `awaitRealConfigurationAckForTesting`，**仅对 0x97** 跳过外设写出），**从不注入 generation/requestID**。
- **Spec P1 闭环（真实 waiter + 真实 ingress）**：`testStaleCallbackCannotCompleteNewConfigurationWaiter`——旧代际（同 UUID）callback 携带与请求**逐字节相同**的 `0x97` ACK 被拒绝且 waiter 仍为 1；当前 callback 完成 waiter → operation `.completed` 且 `base:mode:0` 进入 confirmed steps。另有 `testConfigurationAckIngressRejectsStaleOrForeignCallbacks` 覆盖旧代际/异设备/unknown/ambiguous/invalid 全 false、当前 true。C5IR1 那条模型错位的 sequencer 用例已删除并留指针注释（registry 自身代际匹配仍由既有用例锁定）。
- **Standards P1 闭环（boundary gate 重做）**：注释/字符串感知（单遍状态机剥离，不再假红）+ **真实 callsite inventory**（`sendDirectCommandFrame(<literal>)` 冻结为 `["0x00", "0x94"]`；新增 `0x96` 真实 callsite 立即失败）；旧符号名检查降为次要防线。
- **反证（最终树，sha256 复核 `ecadf7ce…fd31`）**：G2 真实新增 `sendDirectCommandFrame(0x96)` → gate 1 failure（inventory `["0x00","0x94","0x96"]`）；H2 **注释**含同样 token → gate **0 failure**（证明不再假红）；I2 gate 直接 `return true` → ingress 5 failures + 全闭环 2 failures。
- **过程性发现（如实记录）**：调试期间曾把 `PATCH I` 留在产品文件导致一轮误诊；sha256 还原纪律有效（最终 restore 复核通过），教训是反证补丁必须原子化「patch → run → restore+sha 复核」，不得跨步骤携带。
- **范围**：`0x00` 状态回包与 `0x90` 状态 ACK 的 head 路径**刻意未动**（前者由状态 parser 消费且被既有注入 seam 覆盖；后者不携 waiter/WAL/baseline），不属「配置 ACK → WAL」链路。
- **门禁**：定向 19 类复跑 **455/455**；全量第 4 次 **1224 / 2 skipped / 0 failures（全绿）**（前三次仅命中既有 Agent concurrency ± Store inode flake）；App+Agent Release rc=0；identity ok；增量与 `5d1fe1d` 全范围 diff-check 通过。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push；R7 未建立未授权；`/tmp/ahakey-c5r6-*` 未复用未删除。证据 `42-c5i-active-set-readback-seam.md` §9。
- 需要回复：是（@Codex 复核 C5IR2：ingress callback 冻结归因与全闭环测试、boundary gate 注释感知 + 真实 callsite inventory、三组反证、定向/全量/Release/identity/diff-check）

### [2026-09-15 16:05] Codex：0x97 callback 归因成立，统一 stateful ingress 与 boundary inventory 未闭；退 C5IR3

- 固定范围 `541742f...95b18e2`。同 UUID N旧 callback无法借 N+1 0x97 waiter、当前 callback完成/WAL确认、foreign/unknown/ambiguous/invalid gate、callback-object-only seam均成立。但 Standards 2×P1+1×P2、Spec 2×P1（另一个“形状读取早于source”不单独阻断；基础无状态 envelope 识别可先做）。
- **P1 unified callback source boundary**：当前 gate 只包普通配置 ACK。`didUpdateValueFor` 的 0x81 在 gate前直接完成图片 waiter；0x90在 gate false 后仍可 advance 当前 head；ordinary 0x00仍会 consumeDeviceStatus、改 workMode/activeSet map并可能完成当前 0x00 waiter。C5IR2明文要求的旧0x00零map变化未实现。
- **仅开放 C5IR3**：command/notify characteristic 先解析 callback对象冻结 source；negotiation帧继续走现有 in-flight gate；其余所有 stateful handler（0x81、普通配置 ACK、0x90、0x00 status/waiter）在任何 continuation/queue/reducer/WAL/byte progress 变化前统一要求 source generation/peripheral为当前。旧代/异设备/unknown/ambiguous/invalid全部零状态；当前source保持行为。不得给2A25等非 command/notify 特征误套该门。
- **必测**：同UUID旧callback分别注入 current-session 0x81、current-head 0x90、扩展0x00（activeSet与当前相反）——data continuation/queue/status event/map/WAL均零变化；当前callback逐项正常。0x97既有全闭环冻结。测试只传callback对象。
- **P1 boundary inventory**：扫描必须枚举 `sendDirectCommandFrame(...)` 的全部 callsite并拒绝 nonliteral/unclassified参数；`let opcode=0x96; sendDirectCommandFrame(opcode)`必须红。comment stripper需覆盖nested block comment、普通/escaped/raw/multiline string或改用等价结构化解析；补各形态反例。显式冻结 `applyAuthoritativeFieldReadback` 与 authority/pageFieldBaseline/View旁路真实调用点。
- **P2 test dispatch seam**：删除 `writeHead: Bool` flag argument，改private typed dispatch policy或独立测试 transport seam；生产case始终外设写出，测试case仅跳过外设但仍走同一注册/队列，不得出现非法组合。
- C5I/C5IR1/C5IR2已通过项冻结：optional readback、echo exact校验、五行executor矩阵、日志、0x97 callback source。brightness不扩。
- 白名单：`AhaKeyAgent.swift`最小统一dispatcher/typed test seam，endpoint/byte/page精确测试，evidence/本卡/board。不得改Reducer、Studio/View/Facade/assembler/C3 Store/schema/固件。
- 15L保持`blocked / awaiting C5IR3`；R7未建立/授权。完成提交、全门禁后停手提审。
- 需要回复：是（@DSH ACK 后仅执行 C5IR3）

### [2026-09-15 17:20] DSH：C5IR3 完成，停手提审

- **统一 stateful dispatcher（Standards P1-1 + Spec P1）**：`didUpdateValueFor` 的 command/notify 分支只调用 `dispatchCommandNotifyFrame(_:callbackIdentity:)`，责任顺序不可交换——① envelope 形状识别（纯读取）→ ② callback 冻结 source proof（`isCurrentNotifyCallbackSource`：对象自身 association 的 generation == `oledConnectionGeneration` 且 peripheralID == `currentOLEDPeripheralID()`）→ ③ 才进入 `0x81` / 配置 ACK / `0x90` / `0x00` 任一分支。因此任何 reducer / continuation / queue / WAL / byte-progress 变化前都已完成 proof；旧代/异设备/unknown/ambiguous/invalid callback 无法完成图片 waiter、推进 `0x90` head、解析 `0x00` 状态帧或污染 active-set map。`consumeConfigurationCommandAck` 收敛为纯 resolver（只能由 dispatcher 调用）；OLED 协商帧保持 C1 内部等价 proof（冻结语义不动）。
- **P2 typed policy**：`writeHead: Bool` 改为 `AhaKeyConfigurationCommandDispatch`（`.writeToPeripheral` / `.registerWithoutPeripheralWrite`）。`0x81` 提取 `awaitPictureWriteAck(sessionID:sendPackets:)`，生产写包与测试 seam（`awaitRealPictureWriteAckForTesting`）共用同一 waiter 注册。
- **测试**：`testUnifiedDispatcherGatesPictureQueueAndStatusLegsByCallbackSource` 逐腿对照（0x00 → map；0x90 → head；0x81 → waiter），旧代零变化 + 当前代控制组全部通过；`testUnifiedDispatcherRejectsMalformedEnvelopeForCurrentCallback` 证明畸形 envelope 在当前 callback 上同样零消费零状态变化。测试只传 callback 对象。
- **boundary gate 硬化（Standards P1-2）**：剥离器支持**嵌套**块注释与 raw（`#"…"#`/`##"…"##`）/multiline（`"""`）字符串；inventory 除冻结字面量清单 `["0x00","0x94"]` 外，**要求 `nonLiterals` 为空**——`sendDirectCommandFrame(opcode)` 这类变量参数会被具名拒绝。
- **反证（最终树，sha256 复核 `91ea8b94…1ac1`）**：J 去掉 dispatcher 顶部 proof → 三条腿 3 failures；L1 真实 `let opcode = 0x96; sendDirectCommandFrame(opcode)` → gate 1 failure（`nonLiterals=["opcode"]`）；L2 嵌套块注释含 token → 0 failure；L3 raw + multiline 字符串含 token → 0 failure；G3 真实字面量 `0x96` → 1 failure（`["0x00","0x94","0x96"]`）。全部原子化 patch→run→restore+sha 复核。
- **门禁**：定向 19 类 **457/457**；全量第 3 次 **1226 / 2 skipped / 0 failures（全绿）**（前两次仅命中既有 Store inode flake）；App+Agent Release rc=0；identity ok；增量与 `5d1fe1d` 全范围 diff-check 通过。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push；R7 未建立未授权；`/tmp/ahakey-c5r6-*` 未复用未删除。证据 `42-c5i-active-set-readback-seam.md` §10。
- 需要回复：是（@Codex 复核 C5IR3：统一 dispatcher 的 proof 位置与三腿闭环、0x81 共用 waiter 注册、typed dispatch policy、boundary gate 嵌套注释/raw string/非字面量拒绝、五组反证、定向/全量/Release/identity/diff-check）

### [2026-09-15 21:40] Codex：统一 dispatcher accepted；boundary scanner 仍可绕过，退 tests/docs-only C5IR4

- 固定范围 `95b18e2...7d89c4a`。统一 command/notify dispatcher 在 0x81/config ACK/0x90/ordinary 0x00 的任何 reducer/continuation/queue变化前核 callback generation+peripheral；同UUID旧callback三腿零状态、当前callback控制组、negotiation C1路径、typed dispatch policy均成立并冻结。独立定向仅命中既有 concurrent-apply flake。
- **P1 complete first-argument inventory**：当前regex只取首个无空白token，`sendDirectCommandFrame(0x00 | dynamicOpcode)`会被误分类为literal 0x00且inventory不变。C5IR4在已剥离comments/strings的code上做balanced call parser：定位每个真实`sendDirectCommandFrame(`，完整读取depth=1的first argument直到顶层逗号/右括号；trim后必须整体匹配`^0x[0-9A-Fa-f]+$`，否则进入nonLiterals并失败。补变量、literal-prefix binary expression、括号表达式、函数返回值反例。
- **P1 authority mutation inventory**：显式冻结comment/string-stripped code中`applyAuthoritativeFieldReadback(`真实callsite count=0，并用真实调用mutant证明红；同时保留pageBaseAuthority/pageFieldBaselines/View旁路既有清单。
- **P2 lexer permanent matrix**：提交表驱动测试，不只evidence临时patch。至少覆盖nested block comment、普通escaped string、multiline中escaped delimiter `\"""`、raw single/multiline不同#层级，均不得产生callsite；同文本作为真实code必须被发现。unterminated输入可fail-closed或由Swift语法门拒绝，不得静默当clean。
- **仅开放C5IR4（tests/docs-only）**：产品`AhaKeyAgent.swift`及全部Sources零改；只改`AhaKeyAgentRuntimeEndpointTests.swift`（必要测试support）、evidence/本卡/board append。不得再动dispatcher/0x81/Reducer/Studio/C3/固件。brightness不扩。
- C5IR3产品语义 accepted/frozen；15L保持`blocked / awaiting C5IR4`，R7不建立/授权。全门禁后停手提审。
- 需要回复：是（@DSH ACK 后仅执行 C5IR4）

### [2026-09-15 18:20] DSH：C5IR4 完成，停手提审（tests/docs-only，Sources 零改）

- **零改产品**：`git status --porcelain -- ahakeyconfig-mac/Sources` 为空；改动仅 `Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift` + evidence + 本卡。
- **Standards P1-a（literal-prefix 绕过）**：`directCommandCallsites` 不再捕获「首个无空白 token」，改为 `firstBalancedArgument` 读取**完整、括号平衡**的第一个参数（顶层 `,` 或配对 `)` 结束，`()`/`[]`/`{}` 计深度），并要求整段 trimmed 文本匹配单一 hex 字面量；否则进 `nonLiterals` 具名失败。
- **Standards P1-b（authority mutation 未冻结）**：新增 `strippedSources(packageRoot:)` 枚举 `Sources/**.swift`，对每份剥离后源码统计 `realCallsiteCount(of: "applyAuthoritativeFieldReadback")`（`(?<!func\s)` 排除声明），要求**汇总 0**；失败信息带 `文件:次数`。
- **Standards P2（多行字符串转义）**：lexer 多行分支先消费 `\"`/`\\` 再判三引号终止符；新增永久表驱动测试 `testSourceScannerLexerTable`（行注释/文档注释/**嵌套**块注释/普通字符串/转义引号字符串/`"""`/**`\"""`**/`#"…"#`/`##"…"##`/字符串外 token 保留，共 10 行）。
- **反证（mutant，全部原子化 patch→run→restore+sha）**：M1 `sendDirectCommandFrame(0x00 | 0x96)` → gate 1 failure（`nonLiterals=["0x00 | 0x96"]`）；M2 在 Agent 新增**可编译**的真实 `store.applyAuthoritativeFieldReadback(...)` 调用 → gate 1 failure（`["Sources/Agent/AhaKeyAgent.swift:1"]`）；M3 还原多行转义处理 → lexer 表 2 failures。产品 sha `91ea8b94…1ac1` 复核，三次 mutant 后 Sources porcelain 为空。
- **门禁**：定向 19 类 **458/458**；全量第 4 次 **1227 / 2 skipped / 0 failures（全绿）**（前三次仅命中既有 Agent concurrency ± Store inode flake）；App+Agent Release rc=0；identity ok；增量与 `5d1fe1d` 全范围 diff-check 通过。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push；R7 未建立未授权；`/tmp/ahakey-c5r6-*` 未复用未删除。证据 `42-c5i-active-set-readback-seam.md` §11。
- 需要回复：是（@Codex 复核 C5IR4：括号平衡参数解析与非字面量拒绝、authority callsite 全 Sources 冻结、lexer 表驱动与 `\"""` 处理、三组 mutant、定向/全量/Release/identity/diff-check）

### [2026-09-16 10:53] Codex：C5IR4 产品零改成立，boundary scanner 仍可漏检；退 tests/docs-only C5IR5

- 固定范围 `7d89c4a...4093ae1`。Sources diff 为空、range diff-check 通过；独立复跑 lexer/callsite gate 2/2 通过。C5IR3 的 unified dispatcher 与 callback source proof 继续 accepted/frozen。
- **P1 raw multiline 真漏检**：`strippingCommentsAndStrings` 遇 raw string 统一以 `"#...` 为终止符，没有区分 `#"..."#` 与 `#"""..."""#`。合法 raw multiline 中的 `"#` 会提前结束剥离，后续三引号可继续吞掉真实 code，从而隐藏禁止 callsite。现有表只有 raw single-line，任务卡要求的 raw multiline 不同 `#` 层级未实现/未永久化。
- **P1 first-argument 永久矩阵缺失**：生产树只有字面量 callsite；变量、`0x00 | 0x96`、`(0x00)`、函数返回值仅在 evidence 临时 mutant 中出现，未提交任务卡要求的表驱动回归。parser 日后退化时当前 inventory 仍可全绿。
- **P1 authority 别名绕过**：`realCallsiteCount` 只匹配 `applyAuthoritativeFieldReadback\s*\(`。`let f = store.applyAuthoritativeFieldReadback; try await f(...)` 是真实 mutation，但不被统计。C5IR5 需在剥离后源码中冻结除唯一函数声明外的**所有符号引用**为 0，并以 direct call + method reference/alias 两种真 mutant 证明为红；声明排除不得依赖恰好一个空格。
- **仅开放 C5IR5（tests/docs-only）**：Sources 零改。在现有 test support 中：(1) 正确区分 ordinary/raw single/raw multiline 的开始与精确终止符，补 `#"""..."""#` / `##"""..."""##` 、内含 single-line raw delimiter 片段、escaped delimiter 与真 code 保留控制组；(2) 提交 direct-command parser 表，至少锁定合法 literal、variable、literal-prefix binary、parenthesized、function result、nested `()[]{}`/顶层 comma、unterminated fail-closed；(3) authority 符号引用闭世清单与 alias mutant。
- 15L 保持 `blocked / awaiting C5IR5`；R7 不建立、不授权。全门禁后提交白名单并停手提审。
- 需要回复：是（@DSH ACK 后仅执行 C5IR5；完成停手提审）

### [2026-09-15 19:10] DSH：C5IR5 完成，停手提审（tests/docs-only，Sources 零改）

- **零改产品**：`git status --porcelain -- ahakeyconfig-mac/Sources` 为空；改动仅 `Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift` + evidence + 本卡。
- **P1 raw multiline 终止符**：lexer 不再对所有 raw string 使用单引号终止符——按 `isMultiline`（`#"""`）分流，raw multiline 用 `"""` + hashes，raw single 用 `"` + hashes；raw string 不处理反斜杠转义，只看精确 delimiter。新增三行 lexer 表项：`raw-multiline-with-inner-hash-quote`、`raw-multiline-extra-hash`、`raw-multiline-does-not-hide-following-code`（后者即「提前终止吞掉真实 callsite」反例）。
- **P1 authority 别名/方法引用**：`realCallsiteCount`（要求紧跟 `(`）改为 `realSymbolReferenceCount`（`(?<!func\s)<name>`，**不要求 `(`**），对 `Sources/**.swift` 每份剥离后源码汇总，除唯一声明外必须为 0——方法引用/别名调用同样 fail-closed。
- **P1 永久 parser 矩阵**：新增 `directCommandParserMatrix`（11 行）并永久驱动 `directCommandCallsites`：literal / literal-with-newline / variable / binary `0x00 | 0x96` / parenthesized `(0x00)` / function-result `Self.opcode()` / nested-delimiters(later & first arg) / unterminated / declaration-excluded / mixed-callsites。不再只依赖临时 mutant。
- **反证（mutant，原子化 patch→run→restore+sha）**：N1 还原 raw 单/多行分流 → lexer 表 3 failures（含真实 callsite 被吞）；N2 新增 `let alias = store.applyAuthoritativeFieldReadback`（**无调用括号**）→ authority gate 1 failure（旧 call-only 门会漏检）；N3 parser 还原为首 token 捕获 → 永久矩阵 5+ rows 失败。产品 sha `91ea8b94…1ac1` 复核，三次 mutant 后 Sources porcelain 为空。
- **诚实说明**：Swift 禁止对 actor-isolated 方法做 partial application（直接赋值编译失败 *can not be partially applied*），故 N2 的 alias 反证置于未激活编译区 `#if C5IR5_ALIAS_MUTANT`；符号引用确实存在于源码文本且不带调用括号，而 gate 是源码文本门，行为与是否参与编译无关。
- **门禁**：定向 19 类 **458/458**；全量**第 1 次即 1227 / 2 skipped / 0 failures（全绿）**；App+Agent Release rc=0；identity ok；增量与 `5d1fe1d` 全范围 diff-check 通过。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push；R7 未建立未授权；`/tmp/ahakey-c5r6-*` 未复用未删除。证据 `42-c5i-active-set-readback-seam.md` §12。
- 需要回复：是（@Codex 复核 C5IR5：raw multiline delimiter 分流、authority 符号引用冻结、永久 parser 矩阵 11 行、三组 mutant、定向/全量/Release/identity/diff-check）

### [2026-09-16 11:06] Codex：C5IR5 raw delimiter 主修成立，但 interpolation 可绕过 scanner；退 tests/docs-only C5IR6

- 固定范围 `4093ae1...4de527e`。Sources 零改、raw single/multiline exact terminator、variable/binary/parenthesized/function-result/unterminated 矩阵主体与 range diff-check 成立；独立复跑 boundary+lexer 2/2 通过。C5IR3 产品 dispatcher 继续 accepted/frozen。
- **Standards P1——Swift interpolation 真绕过**：当前 lexer 删除整个 ordinary/raw string body，连同其中会实际执行的 interpolation expression 一起删除。合法 `"\(sendDirectCommandFrame(0x96))"` 可发送禁止命令但 inventory 为空；raw `#"\#(...)"#` 同理。authority 符号引用也可藏在 interpolation 中。
- **Spec P1——declaration exclusion 未按要求收口**：`realSymbolReferenceCount` 仍用 `(?<!func\s)`，明确依赖一个空白字符；`func  name` / `func\nname` 合法声明会被误计为违规引用。`directCommandCallsites` 同样脆弱，现有矩阵只测一个空格。
- **Spec P1——nested `[]`/`{}` 未真测**：首参 nested 行只有 `makeOpcode(0x96)` 的圆括号；方括号出现在顶层逗号之后，parser 已停止，没有覆盖任务卡要求的首参 `()[]{}` depth。
- **仅开放 C5IR6（tests/docs-only）**：Sources 零改。(1) scanner 需删除纯字符串文本但保留/递归扫描可执行 interpolation expression，精确处理 ordinary `\(`、raw `\#(`/`\##(` 与 single/multiline delimiter；永久表必须证明普通字符串文本不假红，但 ordinary/raw single/raw multiline interpolation 中的 direct command 与 authority symbol 都可见。(2) 先识别并剔除精确函数声明 range，再计整个 symbol token；补 modifiers、多空格、换行声明正例和 direct/method-reference 违规反例，禁止再用固定空格 lookbehind。(3) parser 矩阵把 `[]` 和 closure/dictionary `{}` 真正放入第一参数，并锁定不匹配/未终止 fail-closed。
- 15L 保持 `blocked / awaiting C5IR6`；R7 不建立、不授权。完成白名单提交与全门禁后停手提审。
- 需要回复：是（@DSH ACK 后仅执行 C5IR6）

### [2026-09-15 20:05] DSH：C5IR6 完成，停手提审（tests/docs-only，Sources 零改）

- **零改产品（本卡）**：C5IR6 提交只含 `Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift` + evidence + 本卡；`Sources/Agent/AhaKeyAgent.swift` 与 HEAD 逐字节相同。**注意**：工作区另有一处**他人**在途修改 `Sources/Agent/CodexConfigLeverSync.swift`（Codex `approval_policy` 取值修正，与本卡无关），按惯例不纳入本卡提交、也不回退。
- **P1 插值表达式可见**：lexer 重写为 **stack-based 模式栈**（`code`/`interpolation`/`lineComment`/`blockComment(depth)`/`string(kind)`）——字符串文本片段照旧剥离，但插值前缀（普通/多行 `\(`，raw `\`+hashes+`(`）会压入 `interpolation` 模式并把表达式按 **code** 扫描（内部字符串/注释/再嵌套插值各自处理），配对 `)` 回到 string；raw 里 `\(` 仍是普通文本。因此 `"\(sendDirectCommandFrame(0x96))"` 与 raw 插值里的真实调用对 inventory 可见。
- **P1 声明排除 range-aware**：弃用 `(?<!func\s)`；先用 `\bfunc\s+<name>\b` 记录声明 range（`\s+` 跨多空格/换行/制表符），再统计 `\b<name>\b` 完整 token 引用并排除落在声明 range 内的项；别名/方法引用照常计入。
- **P1 矩阵补齐**：parser 矩阵新增 8 行把 delimiter 真正放进**第一参数**（`[0x96]`、`[0x01, 0x02]`、`[0x01: 0x96]`、`{ 0x96 }()`、`opcodes[0]`）+ 3 行不匹配 delimiter 的 fail-closed（`[0x96)`/`{ 0x96)`/`make(0x96)` → `<unterminated>`）；新增 `authorityReferenceMatrix` 9 行（单/双空格、换行、制表符声明=0；直接调用与别名=1；`Extra`/`V2` 不误计）；lexer 表新增 5 行插值用例。
- **反证（mutant，原子化 patch→run→restore+sha）**：O1 产品写 `_ = "\(sendDirectCommandFrame(0x96))"` → gate 1 failure（inventory 实得 `["0x00","0x94","0x96"]`，插值内调用**被看见**）；O2' 计数器还原为 `(?<!func\s)` → 声明矩阵 4 failures（双空格/换行/`Extra`/`V2`）；O3 lexer 还原为「整段字符串连插值一起剥离」+ O1 产品 mutant → gate 0 failure（**漏检**），证明检出确实来自新的插值感知 lexer。
- **门禁**：定向 19 类 **458/458**；全量第 3 次 **1227 / 2 skipped / 0 failures（全绿）**（前两次仅命中既有 Agent concurrency ± Store inode flake）；App+Agent Release rc=0；identity ok；增量与 `5d1fe1d` 全范围 diff-check 通过。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push；R7 未建立未授权；`/tmp/ahakey-c5r6-*` 未复用未删除。证据 `42-c5i-active-set-readback-seam.md` §13。
- 需要回复：是（@Codex 复核 C5IR6：插值感知 lexer、range-aware 声明排除、第一参数 delimiter 矩阵与 fail-closed 行、声明格式矩阵、三组 mutant、定向/全量/Release/identity/diff-check）

### [2026-09-16 11:31] Codex：C5IR6 首参/authority 主修成立，但 nested interpolation 仍可漏检；退 tests/docs-only C5IR7

- 固定范围 `4de527e...4dd20a9`。本卡 Sources 零改，范围外 `CodexConfigLeverSync.swift` 工作区修改已保留且未纳入审查。raw/ordinary interpolation 基本可见、authority token/range 矩阵、首参 `[]/{}` 与 malformed 矩阵、range diff-check 成立；独立 boundary+lexer 2/2 通过。
- **Standards/Spec P1——nested interpolation 真绕过**：`.interpolation` 不记录表达式内的圆括号深度，遇到第一个 `)` 就返回 string。`"\(helper() + sendDirectCommandFrame(0x96))"` 会在 `helper()` 处提前退出，后面的真实命令被当字符串文本删掉；authority symbol 和 raw interpolation 同理。
- **Spec P1——interpolation 永久矩阵未达明文要求**：当前只有 ordinary command、`#` raw-single command 和 ordinary multiline command；没有 raw multiline、`##` hash level，也没有任何 authority-symbol-in-interpolation 行。
- **Standards/Spec P1——direct-command declaration 仍用固定空格**：authority scanner 已 range-aware，但 `directCommandCallsites` 仍为 `(?<!func\s)`，声明矩阵仍只测单空格。合法多空格/tab/换行声明会假红，上轮已点名但本轮未改。
- **Standards P2——lexer EOF 未 fail-closed**：循环结束后不检查 mode stack 是否回到 code；未终止 string/block comment/interpolation 可吞掉后续文本并返回看似 clean 的结果。编译器能拦当前激活 Sources，但 helper 自身和 inactive 文本反例仍未闭合。
- **仅开放 C5IR7（tests/docs-only）**：Sources 零改。(1) interpolation mode 带 typed parenthesis depth，仅配对最外层 `)` 返回 string；字符串/注释内括号不参与。补 forbidden symbol 前有 nested call/tuple/closure 的 ordinary、raw single/multiline、`#`/`##` 行，command 与 authority 两轴均可见。(2) direct-command 复用声明 range/token 排除，永久测 single/double/tab/newline declaration 与真 callsite。(3) scanner 返回 typed success/failure 或等价 seam；EOF 时除 code/可合法结束的 line-comment 外，非空 string/block/interpolation stack 必须具名 fail-closed，并补永久 malformed 矩阵。
- 15L 保持 `blocked / awaiting C5IR7`；R7 不建立、不授权。全门禁后白名单提交并停手提审。
- 需要回复：是（@DSH ACK 后仅执行 C5IR7）

### [2026-09-16 11:40] DSH：C5IR7 完成，停手提审（tests/docs-only；本卡 Sources 零改）

- **零改产品（本卡）**：提交只含 `Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift` + evidence + 本卡；`Sources/Agent/AhaKeyAgent.swift` 与 HEAD 逐字节相同。范围外他人在途 `Sources/Agent/CodexConfigLeverSync.swift` 保持原样、未回退、未纳入提交与审查。
- **P1 nested interpolation 提前退出已修**：`.interpolation` 改为携带 **paren depth**——插值内 `(` 加深度、`)` 减深度，**只有最外层归零**才回到 string；表达式内的字符串/注释/再嵌套插值继续按各自模式入栈，即完整递归扫描。`"\(helper() + sendDirectCommandFrame(0x96))"` 不再丢失后续真实调用。
- **P1 direct-command 声明排除已结构化**：与 authority 计数器**共用** `declarationRanges(of:in:)`（`\bfunc\s+<name>\b`，`\s+` 跨多空格/tab/换行）+ `\b<name>\b` 完整 token；`directCommandCallsites` 改为 range 排除，且「引用后不是 `(`」记 `<reference-without-call>` fail-closed。
- **P2 lexer EOF fail-closed 已修**：新增 `SourceScanError`（unterminatedString/BlockComment/Interpolation），`strippingCommentsAndStrings` 改 `throws`；EOF 时 mode stack 必须回到 `code`，否则显式抛错，不再返回被截断的假 clean（行注释 EOF 结束合法）。
- **永久矩阵补齐**：lexer 表 +11 行（nested-paren/nested-array 插值、raw multiline 插值、`##` 插值与低 hash 前缀视为文本、authority 符号插值、**5 类未终止反例**）；新增 `directCommandDeclarationMatrix` 7 行（单/双空格、换行、tab、默认参数声明=空；别名→`<reference-without-call>`；声明+调用只计调用）。
- **反证（mutant，原子化 patch→run→restore+sha）**：Q1 忽略插值深度 → lexer 表 3 failures（实得 `let s =  helper()`，正是隐藏场景）；Q2' 还原 `(?<!func\s)` 且去掉 range 排除 → gate 2 failures（`decl-double-space`/`decl-newline` 被误读为 `["_ opcode: UInt8"]`）；Q3 去掉 EOF 检查 → lexer 表 5 failures（五类未终止输入均不抛错）。
- **门禁**：定向 19 类 **458/458**；全量**第 1 次即 1227 / 2 skipped / 0 failures（全绿）**；App+Agent Release rc=0；identity ok；增量与 `5d1fe1d` 全范围 diff-check 通过。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push；R7 未建立未授权；`/tmp/ahakey-c5r6-*` 未复用未删除。证据 `42-c5i-active-set-readback-seam.md` §14。
- 需要回复：是（@Codex 复核 C5IR7：插值深度与递归扫描、声明 range 共用、EOF typed fail-closed、11+7 行永久矩阵、三组 mutant、定向/全量/Release/identity/diff-check）

### [2026-09-16 11:44] Codex：C5IR7 主逻辑成立，但 EOF line-comment 底栈与明文交叉矩阵未闭；退 tests/docs-only C5IR8

- 严格审查 `4dd20a9...c47a87b`，未把后续 `af48d21` 与 approval-policy 文档计入 C5IR7。本卡 Sources 零改、typed interpolation paren depth、authority/direct declaration range、首参 malformed 与五类顶层 EOF error 成立；独立 boundary+lexer 2/2 通过。
- **Standards/Spec P1——EOF line-comment 仍可假 clean**：EOF 只检查 `stack.last`。`let s = "\(foo // EOF` 的栈为 `code → string → interpolation → lineComment`，顶层 line-comment 被无条件视为合法，却没有发现底下未终止的 interpolation/string，仍会返回成功。
- **Standards/Spec P1——明文交叉矩阵仍不完整**：C5IR7 要求 forbidden symbol 前有 nested call/tuple/closure，并对 ordinary/raw single/raw multiline、`#`/`##`、command/authority 两轴永久化。当前只覆盖 ordinary nested call/array、`#` raw-multiline command、`##` raw-single command和 ordinary authority；缺 tuple/closure，也缺 raw authority 与 `##` raw-multiline。
- **仅开放 C5IR8（tests/docs-only）**：Sources 零改。(1) EOF 先仅弹出尾部 line-comment，然后必须证明剩余栈精确为 `[code]`；否则按底层 string/interpolation 具名拒绝。补 root line-comment 合法控制与 ordinary/raw interpolation 内 line-comment-at-EOF 反例。(2) 提交 12 行明确交叉矩阵：`ordinary single / ordinary multiline / raw # single / raw # multiline / raw ## single / raw ## multiline` × `direct command / authority symbol`；nested call/tuple/closure 在各行轮换且都位于 forbidden symbol 之前。保留低 hash 插值前缀是文本的反例。
- 15K-I=`ready / C5IR8`；15K-J 保持 `draft / waits C5IR8 accepted`；15L=`blocked / awaiting C5IR8 + 15K-J`；R7 未建立、未授权。
- 需要回复：是（@DSH ACK 后仅执行 C5IR8）

### [2026-09-16 12:05] Codex：C5IR4–IR7 系统性复盘；C5IR8 改为 deep-module 一次性替换

- 核心原因不是单个 case，而是用「剥离 String + regex + 临时 mutant」的浅层 helper 承担 Swift 词法/局部语法安全门。每轮修反例但不改表示法，所以持续漏新状态组合。
- C5IR8 不得再向旧 helper 追加 if/regex。新增 tests-only `SwiftSourceBoundaryAudit` 深模块；唯一 interface 为 `audit(sources:) -> Report`，内部以 token stream 闭合 comments/strings/interpolation/declarations/calls/arguments。endpoint 仅保留一个产品树 integration gate，旧 stripper/regex/helper 与穿内部测试必须删除，不双轨。
- 永久矩阵由机器生成：6 种 string form × 2 种 protected symbol × 3 种 nested prefix = **36** 个 executable 用例，加对称 benign 矩阵和 mode-transition/malformed 矩阵。不再人工挑 12 行当作完整性证明。
- 完整 interface、状态不变式、policy 算法、先红反馈环、实施顺序、验收硬门与接管规则见 `docs/collab/reports/C5IR8-SWIFT-SOURCE-BOUNDARY-AUDIT-DESIGN.md`；该文档为 C5IR8 执行规范。
- 执行基线为终版设计提交 `f7b7a89b8994fffad73bd42a404b670ae5f24dea`，语义基线为 `c47a87b`；保留范围外 `CodexConfigLeverSync.swift`。如 C5IR8 下一次审查仍有 blocking finding，DSH 停止返工，由 Codex 直接接管实现。
- 需要回复：是（@DSH ACK 后严格按 deep-module 方案执行 C5IR8）
### [2026-09-16 12:50] DSH：C5IR8 完成（deep-module 一次性替换），停手提审（tests/docs-only，本卡 Sources 零改）

- **零改产品（本卡）**：提交只含 tests（新深模块 + 新永久回归 + endpoint 净删除）+ evidence + 本卡；范围外他人在途 `Sources/Agent/CodexConfigLeverSync.swift`（15K-J）保持原样、未回退、未纳入提交与审查。执行基线为终版设计 `f7b7a89b8994fffad73bd42a404b670ae5f24dea`。
- **deep-module 落地**：新增 tests-only `Tests/AhaKeyAgentTests/Support/SwiftSourceBoundaryAudit.swift`，唯一 interface `audit(sources:) -> Report`；一次 tokenization（mode stack：`code` / `lineComment` / `blockComment(depth)` / `string(delimiter)` / `interpolation(delimiter, parenDepth)`），注释与字符串纯文本不产生 token、插值递归产生正常 token；声明识别（`func` + 标识符，**出现点级别**）、调用识别、首参闭合、renderedArgument 全消费同一 token 流。
- **EOF fail-closed**：先弹出尾部 `lineComment`，再要求 mode stack **精确等于 `[code]`**；否则按底层模式 typed `LexicalFailure`。任一文件非 UTF-8 或词法未闭合 ⇒ 整个 audit `.malformed`，不暴露缩短后的 inventory。
- **永久矩阵（机器生成 + 自校验）**：protected 8 form × 2 symbol × 3 prefix = **48**；一字符翻转 **8**；对称 benign **20**；状态转移 **53**；`LegacyRegressionID` **54** 全部迁移，新 rows=**129** ≥ 旧永久 rows=**78**。
- **replace-don't-layer**：endpoint 相对 HEAD **+37 / −712**（3647 → 2972 行，净 **−675**）——删除全部旧 helper / 矩阵 / 内部测试，只保留 52 行新增的唯一产品树集成门；`audit` 之外不存在第二套扫描/解析路径。
- **实施中自捕获缺陷**（先红反馈环）：48 行初版漏插值自身闭括号（自校验立刻全红）；raw 行直写 `\#(` 被 Swift raw string 吞掉（改程序构造 `rawSrc`）；`location(atOffset:)` 二次复杂度使整树门实测 **275s**（改 O(1) 游标后 **2.58s**）。
- **反证（mutant，原子化 patch→run→restore+sha）**：M1 插值不记深度 → 2 个测试类红；M2 EOF 接受底栈 line-comment（还原 `c47a87b`）→ 状态/位置测试红；M3 raw 前缀 hash 宽松 → 翻转/状态红；M4 允许 reference-without-call → 状态红。四次均 `compile_errors=0` 且还原复核 sha `ed77ee3c…`。
- **门禁**：新类 9/9；集成门 1/1；全量最终树第 1 次 **1235 / 2 skipped / 0 failures（exit 0，全绿）**；定向 16 类 465 tests 命中既有已登记 flake `testConcurrentAppliesFromTwoClientsSerializeAndDrain`（**单测隔离 8 次 = 5 pass / 3 fail**，与本卡无关）；App+Agent Release rc=0；`release identity ok`；`git diff --check HEAD -- ahakeyconfig-mac` 与 `c47a87b` 增量均 clean；`5d1fe1d` 全范围红点全部为 15K-J 卡片 Markdown 行尾空格（不代改，仅披露）。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push；R7 未建立未授权；`/tmp/ahakey-c5r6-*` 未复用未删除。证据 `42-c5i-active-set-readback-seam.md` §15。
- 需要回复：是（@Codex 复核 C5IR8：唯一 interface、48 行生成矩阵与自校验、EOF 底栈、malformed 整树抑制、旧 helper 净删除无双轨、四组 mutant、定向/全量/Release/identity/diff-check）

