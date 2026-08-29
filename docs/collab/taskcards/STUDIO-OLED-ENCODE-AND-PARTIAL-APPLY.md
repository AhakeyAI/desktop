# 任务卡 STUDIO-OLED-ENCODE-AND-PARTIAL-APPLY：受理前编码 + 只提交当前编辑项

计划/WBS：HIL-CONFIG C1 暴露的产品缺口（不在 HIL 卡内施工）  
状态：`ready / E-1`（Cursor ACK 后翻 active；与 Zcode WBS 1.5 路径隔离）  
提出：Cursor（用户 2026-08-28 12:20 明确要求下一轮实现）  
执行 owner：Cursor（Codex 验收）  
基线：`feat/unified-client` 产品 `3bc52b2b6bc33b1fd483e6db7377a27dde389af7`；调度文档 `90b472831433f02740749f915ad993fcf3a058a7`

## 用户要求（冻结意图，细节待 Codex 裁切白名单）

1. **源图先缩放到 160×80（并按设备容量抽帧）再受理**  
   与现有 `OLEDFrameEncoder` / `AhaKeyOLEDFrameEncoderCore` 及 Studio 文案（源文件 ≤20 MB、自动缩放/抽帧）对齐。不得再拿未编码的大 GIF 去撞 planner 的 2 MiB / 30 帧 / 16 MiB 解码预算，导致出厂 `claude_0.gif` 整包 `applyRejected`。
2. **只改一项图就只提交当前编辑项**  
   不受其他模式草稿牵连；只关心当前模式、当前槽位/状态的内容。不得再因 Kimi Downloads 残留图或 Claude 出厂 GIF 让 Cursor 写入失败。空槽保持不上传。

## HIL 现场对照（2026-08-28）

- 组装器错误 2：`Downloads` 不可读路径仍带 URL、元数据为空。
- 组装器错误 3：idle 与 default/done 不同文件。
- Apply 错误 3：`claude_0.gif` 2.05 MiB / 120 帧 / 1024×576，CAS 源图受理失败（编码器未跑）。
- 用户清掉其它模式后只写 Cursor `cursor.gif`：operation `49A143EC-6931-475B-AC36-FD26E8830412` **failedWithPartialCommit** 3/7 步（已确认 `mode1-default`、`mode1-set0-working`、`mode1-set0-waiting`），无 sync baseline；Studio 显示「部分完成（—）」因为 `messageCode` 为 nil。
- 不在 `HIL-CONFIG-TRANSACTIONS` 内改业务代码。

## 用户续报（2026-08-28 13:39，待 Codex 裁切是否并入本卡）

现场仍部分完成。去掉 base 步 0x98 后，`E3669637`/`FC7DE8E7` 卡在 **0x97 status=3**，0x04 未跑。用户要求记入下一轮：

3. **关机再开机图消失** — 与未 save、无 baseline 一致；不能当已通过的断电恢复。
4. **写入慢** — 整包 7 步；用户曾取消 0/7。
5. **任务状态切换时屏幕不显示 `uploading pic`** — apply 期间 Agent 仍发 0x90。
6. **`uploading pic` 字节恒为 0,0**，不随进度，最后一次性刷掉。

## 建议完成定义（供 Codex 修订后生效）

1. 选 ≤20 MB 的 JPEG/PNG/GIF，受理与设备写入使用编码后的 160×80 RGB565 预算，不再因源图像素/帧数在 accept 被拒。
2. 「写入键盘」在用户只编辑某一模式某一 OLED 槽时，包内只含该变更所需资源与该模式必要配置，其它模式未改槽位不因本地草稿脏图 fail-fast。
3. 定向测试：超大源图可受理；单槽写入不读取其它模式无效路径；idle/default 规则若仍冻结须在 UI 拦截并说清，不得只丢 NSError 序号。
4. 不改 wire v1.1、正式 plist、固件、安装器；HIL 环境与 Agent PID 76134 由 HIL 卡保留。

## Codex 请确认

- 是否立卡并插入 `queue.md`（建议紧挨 HIL-CONFIG，不并行改 HIL 执行纪律）。
- 白名单与是否包含「失败码展示 messageCode」一并修。
- HIL C1 在本卡 accepted 前是否保持阻塞（当前建议：是）。

## Codex 调度裁决：E-1 开工范围（2026-08-29 15:31）

### 目标

交付一个端到端最小切片：用户在当前模式编辑 OLED 图片后点击写入，系统必须在 `ingestResources/apply` 前完成设备规格预检（160×80、按本次 0x99 容量得出的最大帧数均匀抽帧），且本次包只读取、组装和提交当前编辑模式；其它模式的脏草稿、失效路径或超限源图不得阻塞本次写入。

“先编码再受理”冻结为行为而不是指定存储格式：允许 CAS 继续保存受控的源图片，但 Runtime 受理前必须已实际跑过与 Agent 同源的编码核心，包内帧数/尺寸/预算必须来自该规范化结果，不能相信源文件元数据或仅把限制调大。不得把未验证的 1024×576 / 120 帧元数据提交给 planner。

### 路径白名单

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPackageAssembler.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioRuntimeFacade.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyOLEDFrameEncoderCore.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`
- `ahakeyconfig-mac/Sources/Utilities/OLEDFrameEncoder.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- 上述模块对应的 `ahakeyconfig-mac/Tests/**`；本卡与 append-only board

### 禁止事项

- 不改 Agent 执行器、WAL、XPC/wire v1.1、planner 全局配额、固件、HIL 环境、安装器或 `/Applications`。
- 不以提高 2 MiB 上限、伪造 160×80 元数据或跳过实际解码来制造假绿。
- 不把整份 draft 再过滤成“看起来像当前模式”；API 必须显式接收 scoped mode/编辑范围，且空范围 fail-closed。
- 不改变 idle/default 镜像规则、双套图语义、0x97 必须成功语义；不实现已拒绝的 A/B 双绑绕行。
- 不刷机、不安装、不 push、不恢复 HIL C1。

### 完成定义

1. 选择 JPEG/PNG/GIF 后，在任何 Runtime ingest/apply 前实际调用同源编码核心；结果固定 160×80 RGB565，帧数按设备容量/当前包资源预算均匀抽取，零帧、不可读或编码失败在 Studio 本地给出可理解错误。
2. package 的 declared frame count、width/height 与实际规范化结果一致；源图可以大于旧 2 MiB planner 源文件阈值，但必须满足 Studio 20 MiB 输入上限及编码后设备预算。若现有 wire 只能传源图，需用测试证明 Agent 二次编码与预检所选帧数/输出预算一致。
3. `applyDraft`/facade 的生产入口显式携带当前 `modeSlot`（以及必要的当前 set/state 作用域）；只读取该范围引用的文件，只组装该模式需要的 desired config 与资源。另一个模式的不存在路径、超大 GIF、空元数据不得被访问，也不得导致当前模式失败。
4. 当前模式自身存在任何无效资源时仍 fail-closed；不得静默遗漏本次编辑范围内的失败项。成功后只推进已提交范围的同步 baseline，不得把其它未提交草稿标成已同步。
5. 测试至少覆盖：1024×576/120 帧 GIF 预检后 160×80 且容量内；静态 PNG/JPEG；另一模式不可读路径不被 loader 访问；当前模式不可读仍失败；仅当前模式出现在 canonical package/resources；baseline 只更新当前范围；ingest/apply 在预检失败时调用次数均为 0。
6. 定向测试、全量 `swift test`、App+Agent Release、`git diff --check` 全绿。完成后提交一个产品 commit，写回证据并停手提审；不得自行进入 E-2 或 HIL。

- 需要回复：是（@Cursor ACK 后仅执行 E-1；ACK 时核对产品基线 `3bc52b2` 与白名单）

## 执行记录（append-only）

### E-1 执行（2026-08-29 15:51，停手提审）

Cursor ACK 后仅执行 E-1。未改任务卡状态字段。未改 Agent/WAL/wire/planner 全局配额、固件或 HIL。未安装、未 HIL、未刷机、未 push。未进入 E-2，未启动 WBS 5.8。

1. **受理前真实预检**：`AhaKeyOLEDFrameEncoderCore.normalize` 实际跑 160×80 RGB565 编码，并按 `AhaKeyDeviceLayoutPolicy().framesPerSlot`（30）均匀抽帧，写出可供 CAS 受理的规范化 GIF。申报宽高/帧数来自该结果，不抄源文件元数据，不放宽 planner 2 MiB。
2. **显式当前模式 scope**：生产 `apply(modes:scope:)` / `applyDraft(_:scope:)` 必须带 `modeSlot`；空范围 fail-closed。store 只组装 `draft(for: modeSlot).packageInput()`，不扫描其它模式。其它模式失效路径不会被 normalizer/loader 打开。
3. **baseline 只推进本次范围**：写入 completed 后用 `mergingSubmittedMode` 合并当前模式，其它未提交草稿保持未同步。

门禁：定向 OLED 预检/facade/assembler/encoder/baseline **35/35**；全量 `swift test` **565 执行 / 0 失败**（2 skip）；App+Agent Release 与 `git diff --check` 通过。产品 commit **`b10a3b7`**。

- 需要回复：是（@Codex 按 `3bc52b2...b10a3b7` 验收 E-1）
