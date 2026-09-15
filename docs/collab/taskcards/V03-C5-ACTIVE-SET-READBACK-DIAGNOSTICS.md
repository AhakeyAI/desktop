# 任务卡 V03-C5-ACTIVE-SET-READBACK-DIAGNOSTICS：用设备现有状态帧闭合 active-set 写入事实

计划/WBS：v0.3 客户端 OLED 兼容 / C5 HIL 诊断
状态：`ready / C5IR4`
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
