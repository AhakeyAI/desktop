# 42 — C5I：用设备现有状态帧闭合 active-set 写入事实（host-only）

任务卡：`V03-C5-ACTIVE-SET-READBACK-DIAGNOSTICS`（ready / C5I）
执行 owner：DSH；只读固件核对：Zcode；验收：Codex
基线：`85e193e`（C5HR1）
日期：2026-09-14 ~ 09-15
设备写入：**无**（本卡纯 host：不签名、不进 HIL、不发命令、不改 baseline）

## 1. 结论

1. **状态帧 readback seam**：Agent 的唯一 `0x00` parser 现在解析 Gitee 扩展帧的 current active set，
   并在值域合法时经既有 `DeviceStateReducer` 单次 composition 进入 `activeTaskPictureSets[workMode]`。
   legacy/Standard 短帧、截断帧、越界字节一律**不创建、不覆盖** map。
2. **0x97 ACK echo 校验**：`status=0` 之后必须逐字节回显请求的 `[mode,set]`；缺失/截断/错 mode/错 set
   一律 fail-closed（typed error + 具名诊断 + step 不确认）。
3. **零新查询、零 baseline 变更、零文件 sink**：本卡没有新增任何主动 query opcode，
   没有调用 authority baseline readback，也没有把 `writeConfirmed` 升格为 `verified`。

## 2. 冻结源码事实（只读）

Gitee Rhino `53cd0a97` 可重建基线（firmware repo 内 `.wbs1-baselines/`，全程只读，porcelain 空）：

| 文件 | SHA-256 | 事实 |
|---|---|---|
| `APP/sub_main/command_solve.c` | `dfc42a66…718a3` | `0x97` 成功路径回 `AA BB 97 00 <mode> <currentSet> CC DD`（`ret[3]=0`、`ret[4]=d[1]`、`ret[5]=active_ai_pic_set[d[1]]%AI_OLED_SET_COUNT`）；`0x00` 的 `data[8] = active_ai_pic_set[mode_data % USER_MODE_COUNT]` |
| `APP/sub_main/main.h` | `9ebebc72…c651` | `USER_MODE_COUNT = 4`、`AI_OLED_SET_COUNT = 2` |

因此值域是确定的：`workMode ∈ 0..<4`、`activeSet ∈ 0..<2`；byte 值 `0xff` 只可能是查询哨兵/畸形，绝不是合法 set。

## 3. 状态帧 readback seam

`Sources/Shared/DeviceStateReducer.swift`：

```swift
case fullStatus(..., brightness: Int, activePictureSet: Int?)   // 原 Int，现 typed optional

// apply 内
if let activePictureSet {
    core.activeTaskPictureSets[workMode] = activePictureSet
}
```

`nil` = 该帧**未携带**扩展字节（legacy/Standard 短帧）→ 不创建、不覆盖。
（`brightness` 保持 `Int` 与既有 `-1` 语义不变：本卡交付的是 active-set readback，
改 brightness 会把 legacy 设备的 XPC 快照从 nil 变成 35%，属于本卡范围外的行为变化。）

`Sources/Agent/AhaKeyAgent.swift`：

- 新增 typed readback：`AgentActivePictureSetReadback { mode, set }`。
- 单一值域 seam：`AgentDeviceStatus.validatedActivePictureSet(workMode:activeSetByte:)`
  —— mode/set 任一越界即返回 nil。
- `parseDeviceStatus`：`payload.count >= 10` 才读 `base + 8`（cmd echo + 9 data 字节 = 扩展帧）；
  短帧保持兼容且不伪造。
- `consumeDeviceStatus`：`activePictureSet: status.activePictureSet?.set` 交给**单次** `DeviceStateReducer.apply`
  （一次状态帧 → 一次 apply → 一次 publish，无第二次 composition）。
- 状态真实变化时的日志补 `workMode=` 与（仅当 readback 存在时）`activeSet=`；不含资源内容。
- `cachedStatus()`（socket status 回包）显式 `activePictureSet: nil` —— 那不是设备 readback。

## 4. 0x97 ACK echo 校验

`Sources/Agent/AhaKeyAgent.swift`：

```swift
enum AhaKeyActiveSetAckEcho {
    static let opcode = AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet   // 0x97
    static func validate(request: Data, response: Data) throws {
        guard response.count == request.count, response.elementsEqual(request) else {
            throw AhaKeyAgentCommandError.ackEchoMismatch(
                opcode: opcode, expected: Array(request), actual: Array(response))
        }
    }
}
```

- 生产路径：`sendConfigurationCommand` 在 `guard response.status == 0` **之后**调用
  `validateActiveSetAckEchoIfNeeded`（只对 `0x97` 生效，其它 opcode 的既有语义逐字不回退）。
- 测试 `skipBLE` 路径同样调用**同一生产 seam**；hook 只提供「设备回显字节」，
  校验逻辑不在测试里自证。
- 失败落点：`AhaKeyAgentCommandError.ackEchoMismatch` →
  `mapConfigurationCommandError` → `retryable: false` + `messageCode = .configurationDeviceRejected`
  + `failureContext{failedStepID, opcode: 0x97, deviceStatus: nil}`，
  并 `emit("配置命令 0x97 ACK echo 校验失败：expected=… actual=…")`（非敏感）。
- `deviceStatus: nil` 是刻意的：echo 不一致与「设备 status≠0」是不同事实，不伪造拒绝码。
- 未新增 `AhaKeyRuntimeEventCode`（沿用既有 `configuration.device-rejected`），
  未改 waiter 的 generation/防迟到/timeout/deviceRejected 语义。

## 5. 必测与反证

`Tests/AhaKeyConfigSharedTests/DeviceStateReducerTests.swift`
- `testFullStatusWithoutActivePictureSetNeverFabricatesOrOverwrites`：nil 不建条目、不覆盖上次可信值。
- `testFullStatusWithActivePictureSetWritesOnlyItsOwnMode`：只写自己的 mode，不镜像。

`Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift`
- `testGiteeExtendedStatusProjectsCurrentActiveSetAndStaysFailClosed`：扩展帧 workMode0/set0、set1；
  workMode1 只更新 mode1 且不动 mode0；`activeSet=0xff`、`activeSet=2`、`workMode=4`、legacy 短帧、
  截断帧（缺 trailer）全部 fail-closed（不建/不覆盖）；相同扩展帧零重复事件；
  `device.state.workMode` 与 `activeTaskPictureSets[workMode]` 同源出现在同一 snapshot。

`Tests/AhaKeyAgentTests/AhaKeyAgentByteProgressTests.swift`
- `testActiveSetAckEchoValidatorRequiresExactEcho`：exact 通过；缺失/截断/多余/错 mode/错 set 全部抛 typed error。
- `testExactActiveSetAckEchoConfirmsOperation`：控制组，精确回显 → `.completed` 且 `base:mode:0` 进入 confirmed steps。
- `testActiveSetAckEchoMismatchFailsClosedWithoutConfirmingStep`：错 set → 非 completed、
  `configuration.device-rejected`、`opcode=0x97`、`deviceStatus=nil`、`failedStepID=base:mode:0`、
  event 与 snapshot 同源、WAL 记录一致，且 **`base:mode:0` 不在 confirmed steps**。

### 反证（有 assert 保护的还原，非仅声称）

| 补丁 | 结果 |
|---|---|
| A：Agent 用 `?? 0` 伪造 set0 | 端点测试 **4 failures**（越界覆盖、越界 workMode 建条目、legacy 伪造） |
| B：去掉 `validatedActivePictureSet` 值域门 | 端点测试 **3 failures**（0xff/2/越界 workMode 落入 map） |
| C：`AhaKeyActiveSetAckEcho.validate` 改为 no-op | validator 表 5 项全红 + 反例测试 operation 变 completed（**假绿暴露**），共 **9 failures** |

每次补丁都经 sha256 备份还原并复核（`683dcf4f…7069`）。

## 6. 门禁

| 项 | 结果 |
|---|---|
| 定向（17 类：Agent 6 类 + DeviceStateReducer + Studio/Runtime 10 类） | **422 / 422，0 失败** |
| 全量 Swift 第 1 次（首版代码树） | **1220 / 2 skipped / 0 failures（全绿）** |
| 全量 Swift 第 2 次 | 1220 / 2 skipped / **2 failures** —— 两个已登记 flake（Agent concurrency + Store inode），与 C5HR1 轮次同一清单 |
| 全量 Swift 最终树第 1 次 | 1220 / 2 skipped / **1 failure** —— 同一 Agent concurrency flake |
| 全量 Swift 最终树第 2 次 | **1220 / 2 skipped / 0 failures（全绿）** |
| `swift build -c release --product AhaKeyConfig` | rc=0 |
| `swift build -c release --product ahakeyconfig-agent` | rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| 增量 `git diff --check 85e193e -- ahakeyconfig-mac` | 通过 |
| 全范围 `git diff --check 5d1fe1d`（整仓 + `ahakeyconfig-mac`） | 通过 |

### 逐文件 numstat（`fbc3b77` 提交原文，机械更正）

```
118   8   ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift
  9   2   ahakeyconfig-mac/Sources/Shared/DeviceStateReducer.swift
 88   0   ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentByteProgressTests.swift
 91   0   ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift
 52   0   ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/DeviceStateReducerTests.swift
141   0   docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/42-c5i-active-set-readback-seam.md
 90   0   docs/collab/taskcards/V03-C5-ACTIVE-SET-READBACK-DIAGNOSTICS.md
```

C5I 任务卡条目原写的 `+126/−8`、`+11/−1`、`+73/+83` 为估算值，已在 C5IR1 按上表原文更正
（合计仍为 **+589/−10**）。

首轮定向曾出现 1 处失败但当时用 `tail` 截断未保存日志、无法指名；随后连续两次 422/422 全绿。
**过程性教训：门禁输出必须整份 tee 落盘，不得只 tail。**

## 7. 边界与冻结

- 白名单实际改动：`Sources/Agent/AhaKeyAgent.swift`、`Sources/Shared/DeviceStateReducer.swift`
  + 三个既有测试文件 + 本卡 + evidence + board append。
- 未改：assembler / Facade / Studio / View / C3 Store-WAL-CAS / ReleaseIdentity / 安装器 / 固件 / HIL driver。
- 未新增主动 query、未调用 authority baseline readback、未升格 `writeConfirmed`、未新增文件 sink。
- 未签名、未安装、未进 HIL、未写设备、未刷机、未擦 EEPROM、未断电、未 push。
- 固件基线仅只读引用（firmware repo porcelain 空）；R6 保留的 `/tmp/ahakey-c5r6-*` 未复用、未删除。

## 8. C5IR1（tests/docs-only 补强）

C5I 产品主语义 accepted；本段记录 `C5IR1` 的测试/文档补强。**`AhaKeyAgent.swift` 与
`DeviceStateReducer.swift` 产品代码零改**（`git status --porcelain -- ahakeyconfig-mac/Sources` 为空）。

### 8.1 P1：ACK 失败矩阵逐行走真实 executor/WAL

`AhaKeyAgentByteProgressTests.testActiveSetAckFailureMatrixFailsClosedThroughRealExecutor`
表驱动 5 行（`missing` / `extra` / `wrong-mode` / `wrong-set` / `status-nonzero`），每行都用
**fresh agent + 真实 runner/Store/executor**（`skipBLE` 仅跳过 BLE 外设写出，不跳过 ACK seam 与 WAL）：

| 每行断言 | 说明 |
|---|---|
| operation 不 completed | `state != .completed`，`messageCode = configuration.device-rejected` |
| 失败上下文 | `opcode = 0x97`、`failedStepID = base:mode:0`；echo 行 `deviceStatus = nil`、status 行 `= 3` |
| 0x97 step 不 confirmed | `base:mode:0` 不在 `confirmedSteps` |
| baseline 零推进 | `syncBaseline(for:) == nil` **且** `pageFieldBaselines` 为空 |
| 具名诊断 | echo 行恰好一条 `ACK echo 校验失败：expected=[0, 0] actual=[…]`；status 行走既有「被设备拒绝 status=3」且不误报 echo |

控制组 `testExactActiveSetAckEchoConfirmsOperation` 补 **`syncBaseline != nil`**，证明成功路径
确实推进会话 baseline——使上表的「零推进」断言非空转（反证 D 实测：校验 no-op 时该行报
`revision: 1 ... 904 bytes`，即 baseline 真的被推进）。

### 8.2 P1：永久 production boundary gate

`AhaKeyAgentRuntimeEndpointTests.testC5IAgentBoundaryGateStaysFreeOfQueryAuthorityAndStudioBypass`
只读扫描 `Sources/Agent/AhaKeyAgent.swift` 与 `Sources/Shared/DeviceStateReducer.swift`：

- 无新增 query：两份源码都不得出现 `cmdReadTaskPicState`(0x94) / `cmdReadTaskPicSet`(0x96)；
- 无 authority readback：不得出现 `AhaKeyRuntimePageBaseAuthority` / `pageBaseAuthoritySnapshot(` / `writeConfirmed`；
  Agent 的 `store.pageFieldBaselines(` 读取点**冻结在既有 2 处**（page preconditions + snapshot 投影），新增即失败；
- 无 View/Studio 旁路：不得出现 `AhaKeyStudioView` / `AhaKeyStudioPackageAssembler` / `AhaKeyStudioRuntimeFacade` / `AhaKeyStudioPageCommitCoordinator`；
- 正向：`AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet`（0x97 必须走共享 opcode 常量）、`AhaKeyActiveSetAckEcho.validate(`、`validatedActivePictureSet(` 必须在场。

（门自身活性由反证 E 证明：注入一行 `AhaKeyRuntimePageBaseAuthority` 注释即 1 failure。）

### 8.3 P2：状态日志

- 首帧：恰好一条 `← status …`，且必须含 `workMode=0` 与 `activeSet=0`；
- 相同扩展帧：除零 event 外，`← status` 日志必须为零。

（活性由反证 F 证明：移除生产日志里的 `workMode=` 后该断言 1 failure。）

### 8.4 stale-generation 的闭合位置（请 Codex 裁定）

- **代际判定层（已永久化）**：`DeviceCommandSequencerTests.testResolve_staleGenerationNeverConfirmsZeroNineSevenAck`
  用生产 `DeviceWaiterRegistry` + `0x97` 精确字节：当前代际精确回显 → `.response`；
  代际推进 → 在飞 `0x97` waiter 被 `generationInvalidated` 强败，**同字节 ACK 也无法复活**，且无残留 waiter。
- **executor 层（本卡不可达，如实说明）**：Agent 唯一 ACK ingress 是 CoreBluetooth delegate
  `didUpdateValueFor`；现有测试 seam 只覆盖 OLED 协商帧（`ingestOLEDNegotiationNotifyForTesting` /
  `handleOLEDNotifyFrameForTesting`），**没有**通用命令 ACK 注入 seam，且非 `skipBLE` 路径会因
  `commandChar/peripheral == nil` 直接 `.disconnected`。因此「把 stale 0x97 ACK 灌进真实 executor」
  需要一个**新的产品测试 seam**（改 `AhaKeyAgent.swift`），而 C5IR1 明确禁止产品改动。
- 本卡采取的分层闭合：代际判定由生产 sequencer 永久锁定；「未解析 → step 不确认 → baseline 零推进」
  由 §8.1 的同一条 runner/WAL 契约（非 `.success` 即不确认）与 §8.1 的 status-nonzero 行共同覆盖。
  DSH 不声称已做到 executor 级 stale 注入；若 Codex 要求该粒度，请显式授权一个最小产品 seam 卡。

### 8.5 C5IR1 反证（有 assert 保护的还原，产品文件 sha256 复核 `9ed68b63…f7a4`）

| 补丁 | 结果 |
|---|---|
| D：`AhaKeyActiveSetAckEcho.validate` no-op | 矩阵 **8 failures**：operation 变 `completed`、`base:mode:0` 进入 confirmed steps、`syncBaseline` 变成 `revision:1 / 904 bytes`、具名诊断缺席 |
| E：在 Agent 注入一行 `AhaKeyRuntimePageBaseAuthority` 注释 | boundary gate **1 failure**（门自身活性） |
| F：生产 status 日志移除 `workMode=` | 首帧日志断言 **1 failure**（P2 断言活性） |

每次补丁均以 sha256 备份还原并复核；`git status --porcelain -- ahakeyconfig-mac/Sources` 在全部反证后为空。

### 8.6 C5IR1 门禁

| 项 | 结果 |
|---|---|
| 定向（19 类：Agent 6 + DeviceStateReducer + DeviceCommandSequencer + DeviceTransportCore + Studio/Runtime 10） | **454 / 454，0 失败** |
| 全量 Swift 第 1 次（最终树） | **1223 / 2 skipped / 0 failures（全绿）** |
| `swift build -c release --product AhaKeyConfig` | rc=0 |
| `swift build -c release --product ahakeyconfig-agent` | rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| 增量 `git diff --check fbc3b77 -- ahakeyconfig-mac` | 通过 |
| 全范围 `git diff --check 5d1fe1d` | 通过 |

## 9. C5IR2（最小产品改动：配置 ACK ingress 的 callback 冻结归因 + boundary gate 重做）

C5IR1 被退两条 P1；本段记录 `C5IR2`。产品改动仅 `Sources/Agent/AhaKeyAgent.swift`（最小）。

### 9.1 问题（Codex Spec P1）

生产 ingress 从**当前** `inFlightCommand`/current rid 反推 waiter 与代际；同 UUID 旧 characteristic
callback（代际 N）只要携带与 N+1 请求**逐字节相同**的 `0x97` ACK，就会被当前 head/rid 认领并误完成新 waiter。
C5IR1 的 sequencer 用例把迟到 ACK 送给**已作废的旧 requestID**，没有建模这条真实路径。

### 9.2 修复

- 新增唯一 ingress `consumeConfigurationCommandAck(_ data: Data, callbackIdentity: AnyObject) -> Bool`：
  形状校验 → **先核 callback 冻结身份** → 再读当前 head/rid → resolve → 续 continuation → advanceQueue。
  顺序不可交换；失败路径零状态变化。
- gate 谓词 `isCurrentConfigurationAckSource(_:)`：复用 C1 既有 callback object association
  （`resolveOLEDNotifySource(attachedTo:)`；`commandChar`/`notifyChar` 在 `didDiscoverCharacteristicsFor`
  已分别 `bindOLEDNotifySource`），要求 `generation == oledConnectionGeneration` **且**
  `peripheralID == currentOLEDPeripheralID()`。unknown / ambiguous / invalid 由既有状态机天然返回 nil。
  **没有新增账本**、没有新状态、没有第二套 association。
- 提取 `enqueueConfigurationCommand` / `awaitRegisteredConfigurationAck` / `finishConfigurationCommand`，
  使生产路径与 C5IR2 测试 seam **共用同一注册与收尾实现**（不复制粘贴）。
- 测试 seam（只吃 callback 对象，测试从不注入 generation/requestID）：
  `consumeConfigurationCommandAckForTesting(_:callbackIdentity:)`、
  `isCurrentConfigurationAckSourceForTesting(_:)`、`configurationWaiterCountForTesting()`，
  以及 hook `awaitRealConfigurationAckForTesting`（**仅对 `0x97`** 跳过 BLE 外设写出，
  其余命令仍走既有模拟路径，因此资源/绑定步不受影响）。
- 明确不在本卡范围：`0x00` 状态回包与 `0x90` 状态 ACK 的 head 路径维持原状——
  `0x00` 由状态 parser 消费且被既有注入 seam 覆盖，`0x90` 不携 waiter/WAL/baseline；
  两者都不属于「配置 ACK → WAL」链路。

### 9.3 测试重做

| 测试 | 内容 |
|---|---|
| `AhaKeyAgentRuntimeEndpointTests.testConfigurationAckIngressRejectsStaleOrForeignCallbacks` | 真实 callback 对象 + 真实代际：旧代际（同 UUID）/ 异设备 / unknown / ambiguous / invalid → gate+ingress 全 false；当前 callback → gate true |
| `AhaKeyAgentByteProgressTests.testStaleCallbackCannotCompleteNewConfigurationWaiter` | **全闭环**：真实在飞 `0x97` waiter + 真实 ingress。旧 callback 携带**相同** ACK → 拒绝且 waiter 仍为 1；当前 callback → 完成 waiter → operation `.completed` 且 `base:mode:0` 进入 confirmed steps |
| `DeviceCommandSequencerTests` | 删除 C5IR1 那条「把迟到 ACK 送给旧 requestID」的用例（模型错位），保留指针注释指向上述 ingress 测试；registry 自身的代际/设备匹配仍由既有 `testResolve_staleTransportGeneration_doesNotComplete` 等锁定 |

### 9.4 boundary gate 重做（Codex Standards P1）

- **注释/字符串感知**：单遍状态机剥离 `//`、`/* */` 与字符串字面量后再匹配——注释不再假红。
- **真实 callsite inventory**：正则收集 `sendDirectCommandFrame(<literal>)` 的 opcode 字面量并冻结为
  `["0x00", "0x94"]`；新增 `sendDirectCommandFrame(0x96)` 这类**真实 callsite** 立刻失败。
  旧 gate 只查不存在的符号名（`cmdReadTaskPicState/cmdReadTaskPicSet`），现已降为次要防线。

### 9.5 反证（均在最终树上，sha256 还原复核 `ecadf7ce…fd31`）

| 补丁 | 结果 |
|---|---|
| G2：真实新增 `sendDirectCommandFrame(0x96)` callsite | boundary gate **1 failure**，实得 inventory `["0x00", "0x94", "0x96"]` |
| H2：**注释**里写 `sendDirectCommandFrame(0x96)` + `AhaKeyRuntimePageBaseAuthority` | gate **0 failure**（证明不再因注释假红） |
| I2：`isCurrentConfigurationAckSource` 直接 `return true` | ingress 测试 **5 failures** + 全闭环测试 **2 failures**（旧代际被接受、waiter 被完成） |

### 9.6 过程性发现（如实记录）

调试全闭环测试时我一度把 `PATCH I`（gate 直接返回 true）留在产品文件里，导致「stale callback 被接受」
的假象并浪费一轮诊断。**sha256 备份还原纪律本身是有效的**（最终 restore 校验通过），
但教训是：**每个反证补丁必须在同一步内立即还原并复核**，不能跨步骤携带；
后续所有补丁均按「patch → run → restore+sha 复核」原子化执行。

### 9.7 C5IR2 门禁

| 项 | 结果 |
|---|---|
| 定向（19 类：Agent 6 + DeviceStateReducer + DeviceCommandSequencer + DeviceTransportCore + Studio/Runtime 10） | 首跑命中既有 Agent concurrency flake；复跑 **455 / 455，0 失败** |
| 全量 Swift | 第 1–3 次仅命中两个已登记 flake（Agent concurrency ± Store inode）；**第 4 次 1224 / 2 skipped / 0 failures（全绿）** |
| `swift build -c release --product AhaKeyConfig` / `ahakeyconfig-agent` | rc=0 / rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| 增量 `541742f` 与全范围 `5d1fe1d` `git diff --check` | 均通过 |

## 10. C5IR3（source proof 上提到统一 stateful dispatcher + boundary gate 硬化）

### 10.1 问题

- **Standards P1-1**：C5IR2 的 source proof 只在配置 ACK 分支内。`0x81` 在它**之前**被直接消费；
  `0x90` 与 ordinary `0x00` 在它返回 false 后**继续**处理。旧 callback 因此仍能完成图片 waiter、
  推进 `0x90` head、或污染 active-set map / 状态 waiter。
- **Standards P1-2**：callsite inventory 只认字面量参数，`sendDirectCommandFrame(opcode)` 可绕过；
  且剥离器不支持 Swift 嵌套块注释与 raw/multiline string。
- **Standards P2**：`writeHead: Bool` 把「生产写外设」与「测试不写」揉进一个 flag argument。
- **Spec P1**：任务卡要求的「旧扩展 `0x00` 零 active-set map 变化」未实现；`0x81`/`0x90` 同源风险未闭合。

### 10.2 修复：统一 stateful dispatcher

`didUpdateValueFor` 的 command/notify 分支现在只调用
`dispatchCommandNotifyFrame(_ data: Data, callbackIdentity: AnyObject) -> Bool`，责任顺序**不可交换**：

1. **envelope 形状识别**（`AA BB … CC DD`，count ≥ 6）——纯读取，零副作用；
2. **callback 冻结 source proof**（`isCurrentNotifyCallbackSource`：对象自身 association 的
   generation == `oledConnectionGeneration` 且 peripheralID == `currentOLEDPeripheralID()`）；
3. proof 通过后才进入 `0x81` / 配置 ACK / `0x90` / `0x00` 任意分支——即任何
   reducer / continuation / queue / WAL / byte-progress 变化之前。

- `consumeConfigurationCommandAck` 收敛为纯 resolver（不再自带 gate），并在文档中写明
  「只能由 dispatcher 调用」。
- OLED 协商帧仍在 dispatcher 之前走 `ingestOLEDNegotiationNotify`：C1 已在该 handler 内部
  做等价的 generation/peripheral/in-flight proof（保持 C1 冻结语义不变）。
- **P2**：`writeHead: Bool` 改为 typed `AhaKeyConfigurationCommandDispatch`
  （`.writeToPeripheral` / `.registerWithoutPeripheralWrite`）。
- `0x81` 也改为共用实现：提取 `awaitPictureWriteAck(sessionID:sendPackets:)`，
  生产写包路径与 C5IR3 测试 seam（`awaitRealPictureWriteAckForTesting`）共用同一 waiter 注册。
- 测试 seam（全部只吃 callback 对象）：`dispatchCommandNotifyFrameForTesting(_:callbackIdentity:)`、
  `isCurrentNotifyCallbackSourceForTesting(_:)`、`inFlightCommandOpcodeForTesting()`、
  `pictureWriteWaiterPendingForTesting()`、`activeUploadSessionIDForTesting()`。

### 10.3 测试

| 测试 | 内容 |
|---|---|
| `AhaKeyAgentByteProgressTests.testUnifiedDispatcherGatesPictureQueueAndStatusLegsByCallbackSource` | 三条腿逐条对照：**0x00** 旧 callback → dispatcher 丢弃且 `activeTaskPictureSets` 零变化、当前 callback → 正常投影；**0x90** 旧 callback → 丢弃且 `0x90` head 仍在飞、当前 callback → head 被推进；**0x81** 旧 callback → 丢弃且图片 waiter 仍待、当前 callback → waiter 完成。全部用真实 waiter/真实 head |
| `AhaKeyAgentRuntimeEndpointTests.testUnifiedDispatcherRejectsMalformedEnvelopeForCurrentCallback` | 即使当前 callback，短帧 / trailer 错 / header 错一律不被消费，且 active-set map 仍为空 |
| `AhaKeyAgentRuntimeEndpointTests.testC5IAgentBoundaryGateInventoryStaysFrozen`（硬化） | 嵌套块注释 + raw/multiline string 感知；**非字面量 callsite 必须为空**；字面量清单冻结 `["0x00","0x94"]` |

### 10.4 反证（最终树，sha256 复核 `91ea8b94…1ac1`）

| 补丁 | 结果 |
|---|---|
| J：去掉 dispatcher 顶部的 source proof | 三条腿全部 **3 failures**（0x00/0x90/0x81 旧 callback 全部被错误接受） |
| L1：真实 `let opcode = 0x96; sendDirectCommandFrame(opcode)` | gate **1 failure**，实得 `nonLiterals=["opcode"]`（变量绕过被拒） |
| L2：`/* outer /* inner */ sendDirectCommandFrame(0x96) AhaKeyRuntimePageBaseAuthority */` | gate **0 failure**（证明支持**嵌套**块注释，且注释不假红） |
| L3：`#"sendDirectCommandFrame(0x96)"#` + `"""…"""` 多行字符串 | gate **0 failure**（raw/multiline string 被正确剥离） |
| G3：真实 `sendDirectCommandFrame(0x96)` 字面量 | gate **1 failure**，实得 `["0x00","0x94","0x96"]` |

每次补丁均原子化「patch → run → restore+sha 复核」，最终 restore 通过。

### 10.5 C5IR3 门禁

| 项 | 结果 |
|---|---|
| 定向（19 类：Agent 6 + DeviceStateReducer + DeviceCommandSequencer + DeviceTransportCore + Studio/Runtime 10） | **457 / 457，0 失败** |
| 全量 Swift | 第 1–2 次仅命中既有 Store inode flake；**第 3 次 1226 / 2 skipped / 0 failures（全绿）** |
| `swift build -c release --product AhaKeyConfig` / `ahakeyconfig-agent` | rc=0 / rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| 增量 `95b18e2` 与全范围 `5d1fe1d` `git diff --check` | 均通过 |

## 11. C5IR4（tests/docs-only：callsite parser 收紧、authority callsite 冻结、lexer 表驱动）

C5IR3 产品 dispatcher 已 accepted/frozen；本段为 `C5IR4`，**Sources 零改**（`git status --porcelain -- ahakeyconfig-mac/Sources` 为空）。

### 11.1 P1：callsite parser 会接受 literal-prefix 表达式

原实现用 `([^,)\s]*)` 只捕获首个无空白 token，因此
`sendDirectCommandFrame(0x00 | 0x96)` 会被归为合法字面量 `0x00`。
现改为**读取完整、括号平衡的第一个参数**（`firstBalancedArgument`：到顶层 `,` 或与调用括号配对的 `)`
为止，`()`/`[]`/`{}` 均计深度），并要求**整段 trimmed 文本**匹配单一 hex 字面量；
否则进 `nonLiterals` 并具名失败。传入文本已剥离注释/字符串，故无需再处理引号。

### 11.2 P1：authority mutation API 未被显式冻结

原 gate 只查类型名 / `writeConfirmed` / `pageFieldBaselines`，新增
`store.applyAuthoritativeFieldReadback(` 这类**真实调用**不会触发任何断言。
现在 gate 会枚举 `Sources/**.swift`（`strippedSources`），对每份剥离后的源码统计
`realCallsiteCount(of: "applyAuthoritativeFieldReadback")`（`(?<!func\s)` 排除声明本身），
要求**汇总为 0**；任何文件出现真实 callsite 都会带着 `文件:次数` 失败。

### 11.3 P2：多行字符串转义三元引号

原 lexer 在 `"""` 内不处理 `\` 转义，`\"""` 会被误判为结束符。
现在多行分支先消费 `\"` / `\\` 转义再检查三引号终止符；
并把 lexer 行为固化为**永久表驱动测试** `testSourceScannerLexerTable`：
行注释 / 文档注释 / **嵌套**块注释 / 普通字符串 / 转义引号字符串 / `"""` / **`\"""`** /
`#"…"#` / `##"…"##` / 字符串外 token 保留，共 10 行。

### 11.4 反证（mutant，全部原子化 patch→run→restore+sha）

| 补丁 | 结果 |
|---|---|
| M1：`sendDirectCommandFrame(0x00 \| 0x96)`（literal-prefix 表达式） | gate **1 failure**，实得 `nonLiterals=["0x00 \| 0x96"]` |
| M2：在 Agent 新增**可编译**的真实 `store.applyAuthoritativeFieldReadback(...)` 调用 | gate **1 failure**，实得 `["Sources/Agent/AhaKeyAgent.swift:1"]` |
| M3：还原多行字符串转义处理 | lexer 表测试 **2 failures**（`multiline-string-escaped-triple-quote` 行 token 未被剥离） |

产品文件 sha256：`91ea8b94…1ac1`；测试文件 sha256：`c5ir4-tests` 备份复核通过；
三次 mutant 后 `git status --porcelain -- ahakeyconfig-mac/Sources` 为空。

### 11.5 C5IR4 门禁

| 项 | 结果 |
|---|---|
| Sources 改动 | **零**（`git status --porcelain -- ahakeyconfig-mac/Sources` 为空） |
| 定向（19 类） | **458 / 458，0 失败** |
| 全量 Swift | 第 1–3 次仅命中两个已登记 flake（Agent concurrency ± Store inode）；**第 4 次 1227 / 2 skipped / 0 failures（全绿）** |
| `swift build -c release --product AhaKeyConfig` / `ahakeyconfig-agent` | rc=0 / rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| 增量 `7d89c4a` 与全范围 `5d1fe1d` `git diff --check` | 均通过 |

## 12. C5IR5（tests/docs-only：raw multiline 分流、authority 符号引用冻结、永久 parser 矩阵）

`C5IR3` 的 unified dispatcher / callback source proof 继续 accepted/frozen；本段为 `C5IR5`，
**Sources 零改**。

### 12.1 P1：raw multiline 终止符解析

原实现对**所有** raw string 都用单引号终止符 `"` + hashes，把 `#""" … """#`（raw multiline）
当成 raw single-line，于是体内合法的 `"#` 会提前结束剥离，随后的 `"""` 又会开启一段吞掉真实代码的
字符串——被吞掉的 callsite 对 gate 不可见。

现在按 **raw single / raw multiline 的实际 delimiter 分流**：

```swift
let isMultiline = start.quoteIndex + 2 < chars.count
    && chars[start.quoteIndex + 1] == "\"" && chars[start.quoteIndex + 2] == "\""
let term = Array((isMultiline ? "\"\"\"" : "\"") + String(repeating: "#", count: start.hashes))
var j = start.quoteIndex + (isMultiline ? 3 : 1)
```

raw string 不处理反斜杠转义，终止只看精确 delimiter。

### 12.2 P1：authority 别名/方法引用可绕过

原 gate 只统计「紧跟 `(` 的直接调用」，`let f = store.applyAuthoritativeFieldReadback` 这类
方法引用/别名会执行同一 mutation 却计数为 0。现改为 **符号引用计数**
`realSymbolReferenceCount(of:in:)`（pattern `(?<!func\s)<name>`，**不再要求 `(`**），
对 `Sources/**.swift` 每份剥离后的源码汇总，除唯一 `func` 声明外必须为 0。

### 12.3 P1：永久 parser 回归矩阵

新增 `directCommandParserMatrix`（11 行）并**永久驱动** `directCommandCallsites`：
literal / literal-with-newline / variable / binary-expression `0x00 | 0x96` /
parenthesized-expression `(0x00)` / function-result `Self.opcode()` /
nested-delimiters-in-later-argument / nested-delimiters-in-first-argument / unterminated /
declaration-excluded / mixed-callsites。矩阵在生产源码形态之外独立锁定 parser 行为，
不再只依赖临时 mutant。

同时给 lexer 表补三行 raw multiline：`raw-multiline-with-inner-hash-quote`、
`raw-multiline-extra-hash`、`raw-multiline-does-not-hide-following-code`
（后者正是「提前终止导致吞掉真实 callsite」的反例）。

### 12.4 反证（mutant，全部原子化 patch→run→restore+sha）

| 补丁 | 结果 |
|---|---|
| N1：还原 raw string 单/多行分流 | lexer 表 **3 failures**，含 `raw-multiline-does-not-hide-following-code`（真实 callsite 被吞） |
| N2：新增 `let alias = store.applyAuthoritativeFieldReadback`（**无**调用括号） | authority gate **1 failure**（`["Sources/Agent/AhaKeyAgent.swift:1"]`）——旧的 call-only 门会漏检 |
| N3：把 parser 还原为「首个无空白 token」 | 永久矩阵 **5+ rows 失败**（binary / parenthesized / function-result / nested-first-arg 全部误判） |

**说明（诚实记录）**：Swift 禁止对 actor-isolated 方法做 partial application
（`store.applyAuthoritativeFieldReadback` 直接赋值会编译失败：*can not be partially applied*），
因此 N2 的 alias 反证放在**未激活编译区** `#if C5IR5_ALIAS_MUTANT`：符号引用真实存在于源码文本中
且不带调用括号——gate 是源码文本门，其行为与是否参与编译无关。

产品 sha256 `91ea8b94…1ac1`；测试文件 sha256 备份复核；三次 mutant 后
`git status --porcelain -- ahakeyconfig-mac/Sources` 为空。

### 12.5 C5IR5 门禁

| 项 | 结果 |
|---|---|
| Sources 改动 | **零**（`git status --porcelain -- ahakeyconfig-mac/Sources` 为空） |
| 定向（19 类） | **458 / 458，0 失败** |
| 全量 Swift | **第 1 次即 1227 / 2 skipped / 0 failures（全绿）** |
| `swift build -c release --product AhaKeyConfig` / `ahakeyconfig-agent` | rc=0 / rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| 增量 `4093ae1` 与全范围 `5d1fe1d` `git diff --check` | 均通过 |

## 13. C5IR6（tests/docs-only：插值表达式可见、声明排除 range-aware、矩阵补齐）

**Sources 零改**；`C5IR3` unified dispatcher / `C5IR5` raw multiline 主修继续 accepted/frozen。

### 13.1 P1：字符串插值里的真实调用被整段剥离

`"\(sendDirectCommandFrame(0x96))"` 与 raw `#"\#(…)"#` 中的 interpolation expression 是**可执行代码**，
但原实现把整个字符串体一起删除，调用对 inventory 不可见。
现在 lexer 改为 **stack-based 模式栈**（`code` / `interpolation` / `lineComment` /
`blockComment(depth)` / `string(kind)`）：

- 字符串**文本片段**照旧剥离；
- 命中插值前缀（普通/多行 `\(`；raw 为 `\` + hashes + `(`）时压入 `interpolation` 模式，
  表达式内容按 **code** 继续扫描（其内部字符串/注释/再嵌套插值同样按各自规则处理），
  遇到配对的 `)` 回到 string 模式；
- raw string 里 `\(` 仍是普通文本（只有 `\#(` 才是插值），因此 raw 反例不会被误收。

### 13.2 P1：声明排除改为 range-aware

`(?<!func\s)` 只能处理「恰好一个空白」，`func  name` / `func\n name` / `func\tname` 都会被误计为引用；
同时它没有 token 边界，`applyAuthoritativeFieldReadbackExtra` 也会被误计。
现在：

1. 用 `\bfunc\s+<name>\b` 匹配声明（`\s+` 天然跨多空格/换行/制表符），记录声明 range；
2. 统计 `\b<name>\b` 的**完整 token** 引用；
3. 落在任一声明 range 内的引用被排除；别名/方法引用（无调用括号）照常计入。

### 13.3 P1：永久矩阵补齐

- **parser 矩阵**新增 8 行，把 delimiter 真正放进**第一参数**：
  `[0x96]`、`[0x01, 0x02]`、`[0x01: 0x96]`、`{ 0x96 }()`、`opcodes[0]`，
  以及三条不匹配 delimiter 的 fail-closed 行 `[0x96)` / `{ 0x96)` / `make(0x96)` → `<unterminated>`。
- **声明格式矩阵** `authorityReferenceMatrix`（9 行）：单/双空格、换行、制表符声明均为 0；
  直接调用与别名引用为 1；`Extra` / `V2` 后缀名不再误计。
- **lexer 表**新增 5 行插值用例：普通插值可见、文本片段剥离、raw 插值可见、多行插值可见、
  插值内嵌套字符串被剥离。

### 13.4 反证（mutant，原子化 patch→run→restore+sha）

| 补丁 | 结果 |
|---|---|
| O1：产品里写 `_ = "\(sendDirectCommandFrame(0x96))"` | gate **1 failure**，inventory 实得 `["0x00","0x94","0x96"]` → 插值内调用**被看见** |
| O2'：把计数器还原为 `(?<!func\s)` | 声明矩阵 **4 failures**（双空格、换行、`Extra`、`V2` 全部误判） |
| O3：lexer 还原为「整段字符串连插值一起剥离」+ O1 的产品 mutant | gate **0 failure**（**漏检**）→ 证明 O1 的检出确实来自新的插值感知 lexer |

产品 sha256 `91ea8b94…1ac1`；测试文件 sha 备份复核；三次 mutant 后 Sources porcelain 为空。

### 13.5 C5IR6 门禁

| 项 | 结果 |
|---|---|
| C5IR6 自身 Sources 改动 | **零**（本卡提交只含测试 + evidence + 本卡；`AhaKeyAgent.swift` 与 HEAD 逐字节相同） |
| 工作区他人在途修改 | `Sources/Agent/CodexConfigLeverSync.swift`（他人改动 Codex `approval_policy` 取值，与本卡无关）——**未纳入本卡提交**，如同 `board.md`/`queue.md` 既有 diff 的处置 |
| 定向（19 类） | **458 / 458，0 失败** |
| 全量 Swift | 第 1–2 次仅命中两个已登记 flake（Agent concurrency ± Store inode）；**第 3 次 1227 / 2 skipped / 0 failures（全绿）** |
| `swift build -c release --product AhaKeyConfig` / `ahakeyconfig-agent` | rc=0 / rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| 增量 `4de527e` 与全范围 `5d1fe1d` `git diff --check` | 均通过 |

## 14. C5IR7（tests/docs-only：插值深度、声明 range 共用、EOF fail-closed）

**本卡 Sources 零改**；范围外他人在途 `Sources/Agent/CodexConfigLeverSync.swift` 未回退、未纳入审查。

### 14.1 P1：nested interpolation 提前退出

`.interpolation` 原来遇任意 `)` 立即回到 string，没有括号深度。
`"\(helper() + sendDirectCommandFrame(0x96))"` 中 `helper()` 的 `)` 会提前结束插值，
其后的真实调用被当作文本删除。现在 `.interpolation(depth:)` **携带 paren depth**：

- 插值内 `(` → depth + 1；
- `)` → depth − 1，**只有 depth 归零**才回到 string；
- 表达式内的字符串/注释/再嵌套插值继续按各自模式入栈，因此是**完整递归扫描**。

### 14.2 P1：direct-command 声明排除仍固定空格

`directCommandCallsites` 原来用 `(?<!func\s)`。现在与 authority 计数器**共用**同一套机制：

```swift
static func declarationRanges(of name: String, in code: String) -> [NSRange]   // \bfunc\s+<name>\b
static func realSymbolReferenceCount(of name: String, in code: String) -> Int  // \b<name>\b 去掉声明 range
```

`directCommandCallsites` 改为 `\bsendDirectCommandFrame\b` + 声明 range 结构化排除；
若引用后（跳过空白）不是 `(`，也记 `<reference-without-call>` 并 fail-closed。

### 14.3 P2：lexer EOF fail-closed

新增 `SourceScanError`（`unterminatedString(kind:)` / `unterminatedBlockComment(depth:)` /
`unterminatedInterpolation(depth:)`），`strippingCommentsAndStrings` 改为 `throws`：
扫描到 EOF 时 mode stack 必须回到 `code`，否则**显式抛错**。`strippedSources` 与 gate 因此
在遇到未终止字符串/块注释/插值时直接失败，而不是返回被截断的假 clean。
（行注释在 EOF 结束合法。）

### 14.4 永久矩阵补齐

- lexer 表新增 11 行：`nested-paren-interpolation-keeps-later-call`、
  `nested-array-interpolation-keeps-call`、raw multiline 插值、`##` raw 插值、
  `##` 下 `\(`/`\#(` 视为文本、authority 符号插值可见，以及
  **5 行未终止反例**（ordinary/multiline/raw 字符串、块注释、插值）各自断言 typed error。
- 新增 `directCommandDeclarationMatrix`（7 行）：单/双空格、换行、tab、带默认参数声明 = 空清单；
  别名引用 → `<reference-without-call>`；声明 + 调用只计调用。

### 14.5 反证（mutant，原子化 patch→run→restore+sha）

| 补丁 | 结果 |
|---|---|
| Q1：`.interpolation` 忽略深度、遇首个 `)` 退出 | lexer 表 **3 failures**（nested-paren / nested-array / unterminated 深度），实得 `let s =  helper()` —— 正是 Codex 指出的隐藏场景 |
| Q2'：direct-command 还原为 `(?<!func\s)` **且**去掉声明 range 排除 | gate **2 failures**（`decl-double-space` / `decl-newline` 被误读为 `["_ opcode: UInt8"]`） |
| Q3：去掉 EOF fail-closed 检查 | lexer 表 **5 failures**（五类未终止输入均不再抛错） |

产品 sha256 `91ea8b94…1ac1`（`AhaKeyAgent.swift` 与 HEAD 逐字节相同）；测试文件 sha 复核；
三次 mutant 后 Sources 仅剩范围外的他人在途文件。

### 14.6 C5IR7 门禁

| 项 | 结果 |
|---|---|
| C5IR7 自身 Sources 改动 | **零**（提交只含测试 + evidence + 本卡；`AhaKeyAgent.swift` 与 HEAD 逐字节相同） |
| 工作区他人在途修改 | `Sources/Agent/CodexConfigLeverSync.swift`（与本卡无关）——未回退、未纳入提交与审查 |
| 定向（19 类） | **458 / 458，0 失败** |
| 全量 Swift | **第 1 次即 1227 / 2 skipped / 0 failures（全绿）** |
| `swift build -c release --product AhaKeyConfig` / `ahakeyconfig-agent` | rc=0 / rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| 增量 `4dd20a9` 与全范围 `5d1fe1d` `git diff --check` | 均通过 |

## 15. C5IR8（tests/docs-only：deep-module 一次性替换 + EOF 底栈校验 + 48 行机器生成矩阵）

**本卡 Sources 零改**；范围外他人在途 `Sources/Agent/CodexConfigLeverSync.swift`（15K-J 归属）未回退、未纳入提交与审查。
执行基线为冻结设计 `f7b7a89b8994fffad73bd42a404b670ae5f24dea`；不再向旧 endpoint helper 追加 if/regex。

### 15.1 根因：浅层「剥离 + regex」表示法

C5IR3–C5IR7 连续漏检的共同原因不是单个 case：`strippingCommentsAndStrings` + regex 无法表示
「字符串文本 / 插值表达式 / 声明 / 调用参数」的状态组合。C5IR8 改为 tests-only 深模块
`Support/SwiftSourceBoundaryAudit.swift`，唯一 interface `audit(sources:) -> Report`，内部一次
tokenization：注释与字符串纯文本不产生 token，interpolation expression 递归产生正常 token，
声明识别、调用识别、参数闭合全部消费同一 token 流。

### 15.2 P1（Codex 点名）：EOF 只检查栈顶 → 行注释掩盖未闭合底栈

`let s = "\(foo // EOF` 的栈为 `code → string → interpolation → lineComment`；旧实现只看 `stack.last`
且把 lineComment 无条件视为合法，于是返回成功、掩盖其下未闭合的 string/interpolation。
现在：先弹出**尾部 lineComment**（行注释在 EOF 结束合法），再要求剩余 mode stack **精确等于 `[code]`**；
否则按底层未闭合模式抛 typed `LexicalFailure`（string / blockComment(depth) / interpolation(depth)）。

### 15.3 P1（Codex 点名）：明文交叉矩阵不完整

旧树只有 ordinary nested call/array、`#` raw-multiline command、`##` raw-single command、ordinary authority，
缺 tuple/closure、raw authority 与 `##` raw-multiline。现在按冻结设计改为**机器生成**且带生成器自校验：
**8 种 string form × 2 种 protected symbol × 3 种 nested prefix = 48 行**
（8 form = ordinary single/multiline + raw1/raw2/raw3 single/multiline；prefix = nested-call/tuple/closure）。

### 15.4 永久矩阵（新模块）

| 矩阵 | 行数 | 断言 |
|---|---|---|
| protected interpolation（8 form × 2 symbol × 3 prefix） | 48 | command 轴恰 1 calls、opcode=0x96、零 violation；authority 轴恰 1 violation |
| 一字符翻转 protected→benign | 8 | protected 先证明可见；翻转后整份 clean（无空转变异） |
| 对称 benign（8 form × 2 symbol 纯文本 + line/nested-block 注释 2×2） | 20 | 全 clean，且 id/source 唯一 |
| 状态转移 | 53 | EOF、注释深度、字符串终止、raw hash 精确/低/高频前缀、参数 trivia、越界 opcode、声明 trivia、authority 命名边界 |
| 旧回归迁移账本 | 54 ID | `LegacyRegressionID` 每个 ID 在新用例中真实存在；新 rows=129 ≥ 旧永久 rows=78 |
| 产品树集成门（endpoint 唯一保留） | 1 | 全 `Sources/**` ⇒ `.complete`、violations 空、`opcodeMultiset == [0x00, 0x94]` |

旧永久 rows=78 的机械计数（删除前的工作树实测）：lexer `Row(name:` 31（HEAD 29 + 本卡草稿 2）
+ `DirectCommandParserRow` 26 + `AuthorityReferenceRow` 9 + `InterpolationCrossRow` 12 = 78。

### 15.5 replace-don't-layer（净删除，无双轨）

`AhaKeyAgentRuntimeEndpointTests.swift` 相对 HEAD `git diff --numstat` = **+37 / −712**（净 **−675**，
3647 → 2972 行）：新增唯一产品树集成门 52 行，旧 helper / 矩阵 / 内部驱动测试 **712 行**全部删除
（草稿阶段先删 829 行，其中含本卡草稿自己加的 2 行 lexer + 12 行交叉矩阵）。不再存在 `strippingCommentsAndStrings`、`SourceScanError`、
`directCommandCallsites`、`firstBalancedArgument`、`realSymbolReferenceCount`、`declarationRanges`、
`strippedSources`、`directCommandCallsites`、`directCommandParserMatrix`、`authorityReferenceMatrix`、
`directCommandDeclarationMatrix`、`interpolationCrossMatrix`，以及 `testSourceScannerLexerTable`、
`testSourceScannerInterpolationCrossMatrix`、`testC5IAgentBoundaryGateInventoryStaysFrozen`。

### 15.6 实施中自捕获的三处缺陷（先红反馈环）

1. **生成器缺插值闭括号**：初版 48 行 body 只写 `\(<prefix><symbol>`，漏掉插值自身 `)`，全部 fixture
   退化为「未闭合字符串」。生成器自校验「每行恰一条可观测结果」立刻全红。已补 `interpolationClose`。
2. **行数据静默失义**：raw hash 行若在 Swift `#"…"#` 里直写 `\#(`，会被宿主语言定界符规则吞掉、测试
   实际测了别的东西。改为程序构造 `rawSrc(hashes:markerHashes:body:)`，并保留「低 hash 前缀是文本、
   精确 hash 才可见」反例。
3. **二次复杂度**：`location(atOffset:)` 对每个 token 重算 `units[..<offset]`，整树审计实测 **275s**。
   改为消费 `advance` 维护的 O(1) 游标后同一集成门 **2.58s**；顺带删除两处死代码。

另有一处实现语义修正：声明排除从「名字集合」（会把同名成员调用一起白名单掉）改为
**出现点级别**（仅 `func` 紧邻的标识符是声明点）。

### 15.7 反证（mutant，原子化 patch→run→restore+sha）

| 补丁 | 结果 |
|---|---|
| M1：插值 `)` 不记深度（遇到首个 `)` 即回到 string） | protected 矩阵 + 状态矩阵 **2 个测试类红** |
| M2：EOF 接受底层 line-comment（还原 `c47a87b` 行为） | 状态矩阵 + 位置可追溯测试红 —— 正是本轮被点名的掩盖场景 |
| M3：raw 前缀只要求 marker hash ≤ delimiter hash | 一字符翻转矩阵 + 状态矩阵红（低 hash 前缀不再安全） |
| M4：允许 reference-without-call | 状态矩阵红（`direct.reference-without-call`） |

四次变异均 `compile_errors=0`，每次都从备份还原并复核 sha256 与 clean 拷贝逐字节一致
（`ed77ee3c…`）。

### 15.8 C5IR8 门禁

| 项 | 结果 |
|---|---|
| C5IR8 自身 Sources 改动 | **零**（`git diff --stat HEAD -- ahakeyconfig-mac/Sources` 仅有范围外 15K-J 的 `CodexConfigLeverSync.swift`） |
| 新类 `SwiftSourceBoundaryAuditTests` | **9 / 9，0 失败**（0.017s） |
| 产品树集成门（唯一保留） | **1 / 1**（2.58s；旧 helper 版同门为 275s） |
| 定向（16 类 C5I 域：Agent 6 + Store + Studio/Runtime 8 + 本卡新类） | 465 tests，**1 failure = 已登记 flake** `testConcurrentAppliesFromTwoClientsSerializeAndDrain`（复跑同样命中）；**单测隔离 8 次 = 5 pass / 3 fail** ⇒ 与 C5IR8 无关（隔离运行不执行本卡任何测试） |
| 全量 Swift（最终树第 1 次） | **1235 tests / 2 skipped / 0 failures（exit 0，全绿）** |
| `swift build -c release --product AhaKeyConfig` / `ahakeyconfig-agent` | rc=0 / rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| `git diff --check HEAD -- ahakeyconfig-mac`（工作区） | 通过 |
| `git diff --check c47a87b -- ahakeyconfig-mac`（C5IR8 增量，含工作区） | 通过 |
| `git diff --check 5d1fe1d`（全仓历史范围） | **红点全部为他方提交**：`docs/collab/taskcards/V03-CODEX-APPROVAL-POLICY-COMPATIBILITY.md`（`af48d21` 引入的 Markdown 行尾硬换行双空格，15K-J 卡片）。DSH 未修改该文件、不代改，仅披露 |

固化制品 sha256：`Support/SwiftSourceBoundaryAudit.swift` = `ed77ee3cb8d231317a7c25fbb588f55935ced63e4a3b897d056472d43f39e36e`；
`SwiftSourceBoundaryAuditTests.swift` = `53428d81bb20907a7ea460931b14e65529a5b103698196a581fc2c13fea582c1`；
endpoint blob = `d740aced51d36de9bc6f268b2a8f6fc66679bb83`。

未签名 / 未安装 / 未 HIL / 未设备写 / 未刷机 / 未 EEPROM / 未断电 / 未 push；R7 未建立未授权；
`/tmp/ahakey-c5r6-*` 未复用未删除。
