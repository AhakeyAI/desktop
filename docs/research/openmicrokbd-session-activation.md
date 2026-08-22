# OpenMicro 会话唤起与 AhaKey 定向语音方案调研

调研日期：2026-08-21

范围：只使用仓库源码、项目 README、OpenAI 与 Apple 官方文档。外部仓库源码固定到 `conol-ai/openmicrokbd@b6b736c9cc85189256123d543a8fb8ad44a6f046` 和 `stephenleo/OpenMicro@9371b1d844961ba9717f78b3b3bc1cdd79da8208`。

## 结论先行

用户给出的 `github.com/conol-ai/openmicrokhd` 不存在；最接近的公开仓库是 [`conol-ai/openmicrokbd`](https://github.com/conol-ai/openmicrokbd)。它能做到“按键触发 + 多会话状态灯”，但**没有根据最近待处理会话切换 Codex 窗口/会话**：`session_id` 只进入 `ActivityEvent` 和 LED 状态表，按键动作只有通用热键、打开 app/URL、命令和宏，二者之间没有路由关系。

真正包含多会话路由的是 [`stephenleo/OpenMicro`](https://github.com/stephenleo/OpenMicro)。但它有两条不同路径：

- CLI 模式是 **PTY 逻辑路由**：所有 agent 都由 OpenMicro wrapper 启动，hook 把 `session_id` 关联到 wrapper，按键字节直接写入目标 PTY；它不需要、也不会把目标 Terminal 窗口 raise 到前台。
- `codex-app` 模式才会打开桌面会话：它读取 `~/.codex/state_5.sqlite` 的 thread id，再执行 `open codex://threads/<id>`；随后用 AppleScript 激活 Codex 并注入 `Ctrl+Shift+D` 等按键。这段实现当前只是“循环会话”，并未把 hook 选出的 `focusSessionId` 连接到对应 deep link。

因此 AhaKey 不应把该能力做成固件里的复杂会话逻辑。固件只需要产生一个稳定的语义输入事件；“最近一次待批准或已完成、等待下一步的会话选择、窗口打开、语音启动和文本注入”必须由 Runtime 完成。

## 1. `conol-ai/openmicrokbd` 的实际链路与缺口

### 1.1 输入触发

固件的 `set_held` 从 flash keymap 读取 slot，生成 keyboard/consumer HID report；`tap_slot` 只是一次 press + release。它不知道应用、窗口或会话，[源码](https://github.com/conol-ai/openmicrokbd/blob/b6b736c9cc85189256123d543a8fb8ad44a6f046/fw/src/main.rs#L433-L491)。默认 Codex profile 的 13 个实体键只是 F13–F20 与 Shift+F13–F17，其中两个 `MIC` 默认也是普通 keystroke，而不是 session-aware 动作，[源码](https://github.com/conol-ai/openmicrokbd/blob/b6b736c9cc85189256123d543a8fb8ad44a6f046/app/src/config.rs#L859-L898)。

Host app 通过全局 hotkey registry 抓取这些 HID chord，再查当前 profile 的 action；注册表只保存“slot → hotkey”，没有 session target，[`Intercept::apply`](https://github.com/conol-ai/openmicrokbd/blob/b6b736c9cc85189256123d543a8fb8ad44a6f046/app/src/intercept.rs#L82-L134)。动作执行器只支持 keystroke、macro、run、open、media 和 app settings，[`run_blocking`](https://github.com/conol-ai/openmicrokbd/blob/b6b736c9cc85189256123d543a8fb8ad44a6f046/app/src/actions.rs#L43-L69)。

### 1.2 会话识别只用于状态灯

hook adapter 的 `ActivityEvent` 确实保留 `session_id`、`turn_id`、`status` 和 `begins_turn`，[源码](https://github.com/conol-ai/openmicrokbd/blob/b6b736c9cc85189256123d543a8fb8ad44a6f046/app/src/status_ipc.rs#L26-L45)。它把 `PermissionRequest` 映射为 `Attention`、`Stop` 映射为 `Success`、`SessionEnd` 映射为 `Idle`，[`status_for_hook`](https://github.com/conol-ai/openmicrokbd/blob/b6b736c9cc85189256123d543a8fb8ad44a6f046/app/src/status_ipc.rs#L192-L235)，并给不同 agent 加 namespace，[`decode_agent_hook`](https://github.com/conol-ai/openmicrokbd/blob/b6b736c9cc85189256123d543a8fb8ad44a6f046/app/src/status_ipc.rs#L322-L364)。

但是 `HostState.activities` 明确是 runtime LED activity，[字段](https://github.com/conol-ai/openmicrokbd/blob/b6b736c9cc85189256123d543a8fb8ad44a6f046/app/src/host_state.rs#L96-L101)；`handle_activity` 的副作用只有过期 timer 和 `refresh_activity_led()`，[源码](https://github.com/conol-ai/openmicrokbd/blob/b6b736c9cc85189256123d543a8fb8ad44a6f046/app/src/host_state.rs#L429-L480)。不存在 `session_id → window/thread target`，也没有 press 时查询最近 attention/success session 的逻辑。

### 1.3 语音也不是定向会话语音

项目把 macOS Dictation 映射成 consumer usage `0x00D8`，[`apply_macos`](https://github.com/conol-ai/openmicrokbd/blob/b6b736c9cc85189256123d543a8fb8ad44a6f046/app/src/behaviors.rs#L790-L832)。这只会对**当前系统焦点**启动听写，不能选择会话。`Action::Open` 也只交给 OS default handler，[`open_target`](https://github.com/conol-ai/openmicrokbd/blob/b6b736c9cc85189256123d543a8fb8ad44a6f046/app/src/actions.rs#L104-L110)，不携带 hook session id。

## 2. `stephenleo/OpenMicro` 如何完成多会话输入路由

### 2.1 hook 建立 session 身份

Codex 官方规定每个 command hook 的 stdin 都包含稳定的 `session_id`，turn-scoped hooks另有 `turn_id`；官方还明确 `PermissionRequest` 在即将请求批准时触发，[OpenAI Hooks：common fields](https://learn.chatgpt.com/docs/hooks#common-input-fields)、[PermissionRequest](https://learn.chatgpt.com/docs/hooks#permissionrequest)。

OpenMicro 安装 `UserPromptSubmit`、`PermissionRequest`、`PostToolUse`、`Stop` hooks。hook 命令把原始 JSON POST 到本机 server，并额外带 `X-Openmicro-Instance-Id: $OPENMICRO_INSTANCE_ID`，[源码](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/hooks-install.ts#L75-L92)、[Codex hook 列表](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/hooks-install.ts#L157-L160)。wrapper 创建 PTY 时把随机 wrapper id 放进子进程环境，[`spawnAgentProcess`](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/pty.ts#L36-L58)。

Server 收到 hook 后解析 `payload.session_id`，验证 wrapper 仍是 active owner，然后写入 `sessionOwners: session_id → wrapperId`；无 wrapper 身份的全局 hook 会被忽略，避免同 cwd 多会话串线，[`HostServer` 字段](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/server.ts#L60-L74)、[`handleHook`](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/server.ts#L208-L280)。这就是实现准确路由的关键：**hook 的 session id 本身不够，还要有 Runtime 可验证的 target ownership/lease**。

### 2.2 选择最近需要操作的 session

`SessionTracker` 为每次状态更新递增 `order`。`waiting/error` 里 order 最大者成为 attention target；当没有执行中 session 时，最近 `idle/complete` 且 `focusOnStop` 的会话成为 resting target，[`aggregate`](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/state.ts#L147-L184)。`nextFocus` 只让一个“新出现的 attention id”抢焦点一次，之后允许用户手动选择，避免旧批准状态反复夺焦点，[源码](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/state.ts#L42-L65)。

这与用户目标接近，但有两个语义差异：OpenMicro 将 `Stop` 归为 transient `complete`，8 秒后衰减；而用户希望“完成信息待下一步操作”保持可选。因此 AhaKey 需要持久的 `awaitingFollowup`，直到下一次 `UserPromptSubmit`、`SessionEnd`、用户显式 dismiss 或 TTL 到期。

### 2.3 输入注入：PTY 路由，不是 OS 窗口 raise

Host server 用 `instanceForSession` 把 session owner 反查到 client instance，再通过 SSE 下发 base64 key bytes，[源码](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/server.ts#L126-L149)。CLI 的 `writeToFocused` 将输入写入该 client PTY；目标为 host 自身时直接写本地 PTY，[源码](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/cli.ts#L226-L238)。`AgentPty.write` 最终调用 `node-pty` 的 `proc.write`，[源码](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/pty.ts#L61-L108)。

所以 CLI 模式的“无需找 tab”是**输入送进后台正确 PTY**，不是让用户看到对应窗口。若产品要求“打开会话并看见批准卡片/输入框”，还必须增加 terminal pane/window activation adapter，或直接走 Codex app thread navigation。

### 2.4 Codex 桌面 app 的窗口/会话打开链路

`codex-app` harness 从 `~/.codex/state_5.sqlite` 读 `threads(id,cwd,recency...)`，过滤 archived/subagent，[`scanDesktopThreads`](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/harness/codex-app.ts#L109-L155)。`focus_session` 当前只是 `cycleThread()`，然后执行 `open codex://threads/<id>`，[源码](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/harness/codex-app.ts#L295-L303)。这是对 Codex 本地数据库和未公开 deep-link contract 的经验性依赖，不是 OpenAI 文档承诺的公共 API，升级时可能变化。

语音按下/松开被解析为分别 hold/release `Ctrl+Shift+D`，[源码](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/harness/codex-app.ts#L253-L265)。执行 synthetic keystroke 前，代码先 AppleScript `activate` bundle `com.openai.codex`，延迟 150 ms，再让 System Events 发按键，[源码](https://github.com/stephenleo/OpenMicro/blob/9371b1d844961ba9717f78b3b3bc1cdd79da8208/src/harness/codex-app.ts#L314-L349)。Apple 官方将 `NSRunningApplication.activate` 定义为“请求”激活，且明确不保证一定成功，[Apple 文档](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate%28from%3Aoptions%3A%29)。

这里仍缺一段关键 join：GUI hooks 能得到 `session_id`，SQLite 能列出 `thread.id`，但当前代码没有证明二者总是同一个标识，也没有用 `focusSessionId` 直接打开对应 thread；它只是循环 catalog。因此不能照抄后宣称“最近批准会话精确唤起”已经被实现。

## 3. AhaKey 当前基础与最小改造面

现有 macOS hook 已解析 Codex stdin context，但只把 hook 映射成 LED command；`CodexHookHandler.handleState`/`handlePermissionRequest` 没有把 `session_id`、`turn_id`、`cwd` 作为 runtime 状态保存，[本地源码](../../ahakeyconfig-mac/Sources/Agent/CodexHookHandler.swift)。当前 `AhaKeyAgent` 的事实模型主要是全局 `lastSentState` 和设备状态，尚无 session registry，[本地源码](../../ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift)。

语音端已经具备可复用的 Speech pipeline 和文本注入：`NativeSpeechTranscriptionService` 使用 `SFSpeechAudioBufferRecognitionRequest`，最后备份 pasteboard、发 `⌘V`、250ms 后恢复，[本地源码](../../ahakeyconfig-mac/Sources/Utilities/NativeSpeechTranscriptionService.swift)。Apple 官方要求 Speech 与 microphone 授权，并建议录音时给出可见提示，[Speech framework](https://developer.apple.com/documentation/speech/)、[Speech authorization](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)。现有缺口不是 ASR，而是**注入前没有解析和激活目标会话**。

## 4. 推荐的 Runtime hooks / target lease 方案

### Phase 0：先定义不跨固件的语义输入

固件新增或复用一个 vendor event：

```text
VOICE_TARGETED down|up, monotonicSequence, deviceMode
```

Runtime 在线时消费并 suppress 普通 F5/F18；Runtime 不在线则 firmware 保留现有 system voice fallback。不要把 session id、窗口 id 或 app deep link 写入固件：这些都是 host 易变状态。

### Phase 1：扩充 hook envelope 与 session FSM

Hook → Runtime 的 envelope 至少保存：

```text
client, sessionId, turnId, event, cwd, occurredAt,
toolName?, lastAssistantMessage?, ownerToken?
```

使用 OpenAI 稳定字段 `session_id` / `turn_id`，不要解析官方标为不稳定的 transcript 格式。FSM 建议：

```text
UserPromptSubmit   -> working（清除 awaitingFollowup）
PermissionRequest -> awaitingApproval
PostToolUse       -> working
Stop              -> awaitingFollowup
SessionEnd        -> closed（删除 target）
```

选择优先级：`awaitingApproval > awaitingFollowup > lastFocused > mostRecentOpen`；同级按 `eventSequence/occurredAt` 最新。按键 down 时原子 snapshot 一次 target，整个语音手势持有同一个 `TargetLease`，直到 up/cancel，避免说话中途新批准事件把文本送去另一会话。

```text
TargetLease {
  leaseId, sessionId, turnId?, targetKind,
  targetHandle, acquiredAt, expiresAt, generation
}
```

所有 delayed action（打开窗口、开始录音、最终粘贴）都校验 lease generation；`SessionEnd`、目标进程退出、用户切换、Esc 或超时立即 revoke。

### Phase 2：按 target adapter 激活，而不是统一模拟点击

建议按可靠性排序：

1. **Codex app 原生 task navigation adapter**：Runtime 若运行在 Codex desktop/Codex app extension 能力边界内，优先调用 app 提供的 thread navigation；本环境已有只读 `navigate_to_codex_page(threadId)` 能力，但它是 Codex app host 能力，不是普通 hook 子进程可调用的通用 OS API。
2. **Codex deep link adapter（兼容层）**：验证 hook `session_id == thread.id` 后才允许 `open codex://threads/<id>`；每次 app/runtime 升级做 smoke test，失败时降级到只激活 app + 提示用户选择，不能盲贴。
3. **PTY adapter**：若 session 是 AhaKey Runtime 自己 wrapper 出来的，复制 OpenMicro 的 `session_id → owner lease → PTY` 设计，直接写目标 PTY；明确此模式不 raise window。
4. **Terminal adapter**：若必须可视化窗口，注册时记录 Terminal bundle/pid/window/pane token，并使用对应 terminal 的公开 automation 接口。仅有 cwd 不足以区分多个同目录会话。

macOS app activation 使用 `NSRunningApplication`/`NSWorkspace`，激活完成后必须验证 frontmost app 与目标 composer 可访问，再进入录音。不要只靠固定 sleep；OpenMicro 的 150 ms 只是经验值。

### Phase 3：语音 handoff

推荐执行顺序：

```text
hardware down
  -> selectTarget + acquireLease
  -> activateTarget
  -> verify target/session/composer
  -> start native ASR
hardware up
  -> stop ASR
  -> finalize text
  -> revalidate lease + target still focused
  -> paste/insert into target composer
  -> optional submit only when policy explicitly enables
  -> releaseLease
```

默认只填入不自动提交，避免错误 target 时产生不可逆操作。批准动作也应与语音分开：拨杆自动批准继续由 `PermissionRequest` hook decision 控制；语音键只负责打开待处理会话并输入下一步。

### Phase 4：升级 hooks 与 runtime 的兼容策略

- hook config 继续结构化 merge，只移除自身 marker；沿用当前 AhaKey 的追加策略。
- envelope 带 `protocolVersion`、`runtimeInstanceId`、`hookBuildId`；Runtime 同时接受 N/N-1 两版。
- hooks 必须 fail-open/no-op：Runtime 不在时快速退出，不阻塞 Codex。
- Runtime 自更新前先安装兼容 hooks，成功启动并 health-check 后再切换；保留上一版本 helper 回滚。
- session registry 是临时运行态，不进固件、不长期持久化。崩溃恢复后以新 hook 重建；恢复前语音键降级为当前前台语音。
- 记录不含 prompt/transcript 的诊断字段：event、session hash、target kind、lease result、activation latency、inject result。

## 5. 验收用例

1. 两个相同 cwd 的 Codex 会话分别触发批准，语音键始终打开最新一个，而不是按 cwd 猜测。
2. A 完成后、B 请求批准后，选择 B；B 处理完后 A 仍可作为 awaitingFollowup 被选择。
3. 按住语音期间 C 新出现批准，当前 lease 仍指向原会话；下一次按键才选择 C。
4. 目标会话在录音中关闭：停止并保留 transcript 到安全草稿，不粘贴到当前前台 app。
5. deep link/SQLite schema 在 Codex 升级后失效：Runtime 检测失败并降级，不向错误窗口注入。
6. Runtime 未运行：固件仍按原 system voice 行为工作。
7. Accessibility/Speech 权限缺失：只显示引导，不启动录音，不夺取或粘贴。
8. Runtime 更新跨 N/N-1 hook 版本，审批 hook 不超时，原有第三方 hook 不丢失。

## 最终判断

可直接借鉴的不是某个“窗口魔法”，而是 OpenMicro 的三个结构：`hook session_id + 可验证 owner`、按事件 recency 的 session FSM、按一次输入手势固定 target lease。窗口激活和语音注入必须作为 AhaKey Runtime 的独立 adapter 层实现。`conol-ai/openmicrokbd` 只提供前半段状态采集/LED 和普通热键基础；`stephenleo/OpenMicro` 的 PTY 路由证明了 session-aware 输入可行，但 Codex GUI 的精确“最近待操作会话”仍需要 AhaKey 把 hook session 与可导航 thread target 做可靠 join。
