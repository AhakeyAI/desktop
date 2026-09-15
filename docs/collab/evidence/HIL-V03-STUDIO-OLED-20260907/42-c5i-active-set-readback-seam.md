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
