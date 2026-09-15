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

首轮定向曾出现 1 处失败但当时用 `tail` 截断未保存日志、无法指名；随后连续两次 422/422 全绿。
**过程性教训：门禁输出必须整份 tee 落盘，不得只 tail。**

## 7. 边界与冻结

- 白名单实际改动：`Sources/Agent/AhaKeyAgent.swift`、`Sources/Shared/DeviceStateReducer.swift`
  + 三个既有测试文件 + 本卡 + evidence + board append。
- 未改：assembler / Facade / Studio / View / C3 Store-WAL-CAS / ReleaseIdentity / 安装器 / 固件 / HIL driver。
- 未新增主动 query、未调用 authority baseline readback、未升格 `writeConfirmed`、未新增文件 sink。
- 未签名、未安装、未进 HIL、未写设备、未刷机、未擦 EEPROM、未断电、未 push。
- 固件基线仅只读引用（firmware repo porcelain 空）；R6 保留的 `/tmp/ahakey-c5r6-*` 未复用、未删除。
