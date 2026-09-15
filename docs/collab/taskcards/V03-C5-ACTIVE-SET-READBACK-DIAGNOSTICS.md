# 任务卡 V03-C5-ACTIVE-SET-READBACK-DIAGNOSTICS：用设备现有状态帧闭合 active-set 写入事实

计划/WBS：v0.3 客户端 OLED 兼容 / C5 HIL 诊断
状态：`ready / C5I`
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

- **范围（host-only，零设备）**：`Sources/Agent/AhaKeyAgent.swift`（+126/-8 区间）+ `Sources/Shared/DeviceStateReducer.swift`（+11/-1）+ 三个既有测试文件（+73/+83/+52）；未改 assembler/Facade/Studio/View/C3/ReleaseIdentity/安装器/固件/HIL driver。
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
