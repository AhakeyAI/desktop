# Rhino 旧客户端 vs Runtime OLED 同机差分验证计划

状态：待执行 / USER-GATE  
日期：2026-09-02  
目标设备：AhaKey X1 `D4:6C:50:5C:F5:C0`

## 1. 要回答的问题

在**同一台键盘、同一份固件、同一组图片和同一断电流程**下：

1. 旧 Rhino 直连客户端能否完成图片上传、逐步进度、立即显示和断电保存？
2. 新 Runtime 事务路径是否在相同输入下失败；若失败，第一处分歧发生在哪个 opcode、payload、ACK/status 或命令顺序？
3. `0x97 status=3` 是所有客户端都能触发的固件故障，还是只由 Runtime 的能力协商、planner、命令顺序或成功判据触发？

在差分完成前，项目口径保持：Runtime—固件兼容/时序回归，根因未定；不得把旧固件 journal 单独宣布为唯一根因。

## 2. 已冻结的历史材料

### 2.1 首选黄金源码对

仓库：`/Users/heartline/Documents/Codex/ahakeyconfig-latest-task-gif`  
提交：`53cd0a97e95e3b8b35cd56ed2284970d5a79d1be`  
提交说明：`fix: make Rhino four-state image uploads reliable`

该提交同时修改了固件上传/持久化路径与 macOS 直连客户端，因此客户端和固件必须从**同一 clean worktree**构建，不能拿当前 dirty `rhino` 工作树拼装。

注意：该提交中跟踪的 `obj_final/HID_Keyboard_582m_vibe_coding.hex` SHA-256 为 `ada63b348b55f87c0848cf0b506a90ff56508e7dedd021152c6b9506f487f830`，但历史审计已证明多个提交复用了同一个 `obj_final` blob。它不能替代从冻结源码 clean build 得到的黄金 HEX。

### 2.2 只作历史参考的现成产物

- 客户端 DMG：`/Users/heartline/Documents/Codex/ahakeyconfig-main/dist/AhaKey-Studio-task-gif-release-20260623-225936.dmg`
- SHA-256：`965c37718bcbe7e153ee100485499191673b24147b4b44ed861f177a79bbcccd`
- 签名：Developer ID `P2VFVRZK7P`，Bundle ID `lab.jawa.ahakeyconfig`，版本 `0.1.0 (1)`，strict verify 通过。

该 DMG 早于 2026-07-29 的可靠上传提交，只能用于界面/启动侦察，不能作为差分金标准。

- 历史固件：`AhaKey-independent-upload-20260624.hex`。历史文档记录它与当时配套客户端能上传并显示双套任务图，仅剩顶部条纹问题；它可作备选复现材料，但不与上述 6 月 23 日 DMG 声称为精确配对。

## 3. 单变量执行顺序

### Phase 0：冻结现场，不写键盘

1. 先停止或完成当前 `HIL-RELEASE-0.2.1` Gate-1 R1；两个会话不得同时占用同一键盘、Runtime label 或 BLE。
2. 记录当前安装客户端 `0.2.1 (361)`、DMG SHA、App/Agent 签名、LaunchAgent plist、唯一 owner、XPC、Hook 配置 SHA。
3. 固定一组测试图片：同一个 mode/set/state、相同原始文件与期望帧数；为旧客户端和 Runtime 保存编码后帧数、总字节数与内容 SHA。
4. 记录当前固件 `0x99` 原始响应、协议版本、slot 边界、active set 和 binding 查询结果。
5. 本阶段不 bootout、不安装旧客户端、不进 ISP、不刷机。

### Phase A：旧 Rhino 客户端 + 当前固件（核心差分，先做）

1. 从 `53cd0a97...` 创建 clean detached worktree，在隔离输出目录构建并签名旧 Rhino 客户端。
2. 因新旧客户端 Bundle ID 相同，**不覆盖 `/Applications/AhaKey Studio.app`，不使用 LaunchServices `open`，不注册登录项，不安装旧 Agent/Hook**。
3. 先保存 official Runtime 状态，再执行一次可审计 bootout，让旧直连客户端成为唯一 BLE owner。
4. 用绝对路径启动旧客户端可执行文件；设置隔离的 `HOME`/`CFFIXED_USER_HOME`，防止改写 v0.2.1 的 preferences/Application Support。若系统权限模型不接受隔离 home，则停下，改为先备份偏好，不得直接继续。
5. 写入固定图片，采集：
   - `0x80` header 或其它 prepare；
   - 每块数据长度与累计确认字节；
   - `0x81`；
   - `0x95/0x96/0x97/0x98/0x99` 的 payload、顺序、ACK/status；
   - 客户端进度、键盘 OLED 进度、立即显示结果；
   - 写入后 binding/active-set 查询。
6. 键盘关机再开机，复查图片、binding、active set。至少重复两次。
7. 退出旧客户端，确认进程完全不存在；不要立即恢复 Runtime，先封存本轮日志。

判定：若 Phase A 完全成功，已直接证明当前固件具备旧路径可用性，进入 Phase B；此时不得先刷旧固件。

### Phase B：新 Runtime + 同一当前固件

1. 恢复 official Runtime 或使用已有签名 HIL Runtime label；只能有一个 BLE owner。
2. v0.2.1 正式 UI 的 OLED 被发布策略隐藏，因此使用冻结的 HIL 配置事务入口驱动真实 Runtime planner/executor；不得临时打开正式版隐藏 UI 后声称是发布行为。
3. 输入必须与 Phase A 相同：相同源文件、mode/set/state、编码帧数、槽位范围。
4. 捕获与 Phase A 相同的逐帧时间线和查询结果；WAL 步骤进度与 confirmed bytes 分开记录。
5. 失败时停止在第一处分歧，不先修改代码，不继续 C2–C6。

核心判定：

| Phase A | Phase B | 结论 |
|---|---|---|
| 成功 | 失败 | 优先归 Runtime planner/顺序/能力协商/成功判据回归 |
| 失败 | 失败 | 当前固件、设备持久状态或共同协议仍可疑；进入 Phase C |
| 成功 | 成功 | 旧失败可能依赖历史 journal/设备状态；需恢复原状态才能继续归因 |
| 失败 | 成功 | 旧客户端/构建配对或旧协议路径有问题，不支持固件根因结论 |

### Phase C：黄金 Rhino 客户端 + 黄金 Rhino 固件（仅在需要时）

这是刷机 USER-GATE，必须由用户在新会话中再次明确确认。

1. 进入 ISP 后先执行只读识别：对已知当前候选 HEX 逐一 `wchisp verify`。如果没有任何候选匹配，说明当前 code flash 没有可恢复的精确镜像；**默认停止，不刷机**，直到用户接受无法恢复当前未知固件的风险。
2. `wchisp eeprom dump` 保存完整 EEPROM，记录 SHA-256；不先 erase EEPROM。
3. 从 `53cd0a97...` clean worktree 使用固定 xPack 13.2.0 + ch583sdk clean build Rhino HEX，记录源码提交、工具链/SDK pin、HEX SHA、Flash 范围。
4. 用户操作 ISP：键盘断电，按住语音键，插 USB-C，保持约 5 秒后松开。
5. 依次执行：`wchisp flash --no-reset <golden.hex>`、`wchisp verify <golden.hex>`、`wchisp reset`。任一步失败立即停止。
6. 只运行同提交构建的旧 Rhino 客户端，重复 Phase A；建立黄金绿基线。
7. 再换到新 Runtime，保持黄金固件和测试图片不变，重复 Phase B。
8. 完成后按识别到的精确当前 HEX 恢复固件，并视验证目标决定是否恢复 EEPROM；恢复前必须再次向用户说明会覆盖哪份状态。

## 4. 每一步必须留的证据

- 客户端/Runtime/固件的 commit、产物路径、SHA-256、签名与进程 PID。
- 固件 `0x99` 原始 bytes，不只记录解析后的 `current/legacy`。
- 单调时间戳的 TX/RX：opcode、payload 长度、payload SHA/摘要、status、重试次数。
- 三种进度分别记录：客户端 UI、Runtime WAL/confirmed bytes、键盘 OLED。
- 写后立即查询、关机后查询、屏幕照片/短视频。
- 每个阶段的 BLE 唯一 owner 证明；禁止旧客户端和 Runtime 同时连接。
- 所有作废样本必须保留并标记原因，不能覆盖为成功结果。

## 5. 通过与停止条件

Phase A 通过需要同时满足：上传完成、进度非恒定 `0/0`、目标图立即显示、查询一致、两次关机后仍保持。

Phase B 通过使用同样的设备结果判据；WAL completed 只是附加条件，不能替代屏幕与断电保持。

立即停止条件：

- 当前 firmware 无精确可恢复 HEX；
- EEPROM dump 失败；
- 同时出现两个 BLE owner；
- 客户端/Runtime 修改了非隔离配置或 Hook；
- flash/verify 任一步非零；
- 测试输入的编码帧数或 SHA 在两条路径间不一致；
- 发生 Agent 崩溃、设备身份变化或不可解释的协议重连。

## 6. 本轮明确不做

- 不在验证过程中修 Runtime 或固件。
- 不把 6 月 23 日 DMG 与 7 月 29 日固件伪称为精确配对。
- 不使用当前 dirty Rhino 工作树构建黄金产物。
- 不并行执行 v0.2.1 Gate-1、HIL-CONFIG 或其它会占用该键盘的测试。
- 不 push、不发布、不量产切换。

