# AhaKey 固件与客户端冻结基线

状态：WBS 0.1 完成；WBS 0.2 部分完成，Flash 布局与 HIL 待验证

冻结时间：2026-08-22（Asia/Singapore）

## 1. 可复现基线

| 来源 | 分支 | 冻结 SHA | 远端复核 | 用途 |
|---|---|---|---|---|
| GitHub `AhakeyAI/AhaKey-X1-hardware-source` | `dev` | `3e7f900ae6f5fe71d57a03da973d79356afea1b6` | `git ls-remote` 已确认 | 统一固件主线 |
| Gitee `anpx/ahakeyconfig` | `rhino` | `53cd0a97e95e3b8b35cd56ed2284970d5a79d1be` | `git ls-remote` 已确认 | Rhino 资源/可靠性来源 |
| 本地桌面仓库 | `rhino` | `00eb7efc235770d0a40e23a8c6e7449b2c010765` | 本地 worktree 已确认 | Gitee Rhino 之后的硬件修复来源 |
| GitHub `AhakeyAI/desktop` | `main-anpx` | `0da59ce3a058fc19c8abe1de4fa019bae6d1f2b4` | `git ls-remote` 已确认 | current-only USB 客户端参考 |
| 当前统一实施分支 | `feat/unified-client` | `fbb8e14e9924a913bc2d445d379f8b794b3774eb` | 本地 HEAD | 唯一集成入口 |

Gitee 的完整 `git fetch --all` 本次等待超时后被中止，但单独的 `ls-remote` 已确认远端 Rhino SHA 未变化。GitHub hardware `dev` 已浅克隆并与本地 Rhino 固件做逐文件静态比较。

## 2. 分支关系结论

- GitHub hardware `dev` 与 Gitee Rhino 不是可安全直接合并的同一仓库历史。
- `gitee/rhino` 与当前桌面主线也没有共同 merge-base；禁止目录级合并。
- 本地 `rhino` 在 Gitee 冻结点后包含五个明确相关提交：Agent task lease/设备身份、macOS USB 枚举、VBUS 传输切换、客户端身份兼容、固件 v11 启动采样。
- `origin/main-anpx` 相对共同基线包含 18 个提交；只有 `0da59ce` 的 current USB 行为进入本次移植候选，其他 UI、插件、Windows Rust 和文件删除不得捎带合并。

## 3. 固件静态差异矩阵（WBS 0.2 部分产物）

“已发现”只表示源码存在，不代表已经通过真实键盘 HIL。

本轮已完成行为和协议入口的静态比较；尚未取得三个基线各自的 linker map、Flash 分区地址、区域大小及实际占用，因此不能把 WBS 0.2 标为完成。完整 Flash 布局矩阵必须在可重复构建三套固件后补齐。

| 能力 | GitHub hardware `dev` | Gitee/本地 Rhino | 统一版决定 |
|---|---|---|---|
| SDK bridge | `APP/sdk_bridge` 完整存在，默认关闭 | 不存在 | 保留 GitHub 实现及关闭默认值 |
| 自动关机/AI 状态 | 存在，含可配置分钟与 SDK AI 回调 | 存在较早实现 | 以 GitHub 行为为主，移植 Rhino 稳定性时不得回退 |
| 四状态、双套任务图 | 基础 AI 状态 | `0x95-0x98`、双套 binding 完整 | 逐命令移植到统一协议模块 |
| 能力协商 | GitHub 有 `0x99` 入口 | Rhino 返回 factory 状态、用户槽边界等扩展 | 冻结为 protocol v4 capability TLV，禁止继续扩展固定位置包 |
| 事务化出厂资源 | 无 | `factory_assets.c/.h`、trigger、manifest、journal | 作为独立 FactoryAssetModule 移植 |
| 图片槽位保护/恢复 | 基础写入 | 用户区边界、override journal、写入超时和恢复 | 移植并补断电 HIL |
| SDK/工厂命令空间 | SDK 声明 `0xF0-0xFF` 保留 | Rhino 使用 `0x95-0x99` | v4 冻结前做 opcode 冲突检查 |
| USB 配置通道 | A1 command、A2 data | 同类通道并有后续身份修复 | 统一 64-byte framing；current-only 才开放写入 |
| USB/BLE 设备身份 | 基础/旧身份 | 本地 v11 使用 `07D7:501A`、稳定 serial、BLE PnP 对齐 | 采用稳定身份，但同时兼容已出货 `413C:2107` |
| VBUS 切换 | GitHub 路径 | 本地 v9/v11：插线复位、拔线安全关机、首个 1s tick 采样 | 作为硬件风险项单独 HIL，不盲目复制 |
| 构建与量产变体 | GitHub 工程 | Rhino Makefile、factory manifest | 单源码，两份资源 pack；业务代码不设 Rhino 分叉 |

## 4. macOS `main-anpx` USB 移植清单

只移植行为，不 cherry-pick 整体提交：

1. 双 VID/PID 与 vendor usage page `0xFF00` 匹配。
2. IOHID manager/device 正确 schedule、unschedule、重新枚举和有界重试。
3. A1/A2 64-byte framing 和 command/data 大小限制。
4. 能力协商确认 current 以前禁止业务写入。
5. 稳定设备身份、USB/BLE 身份 join 与 transport generation。
6. USB 迟到回包不得完成 BLE waiter。

明确拒绝移植 `main-anpx` 的现状：Studio 与 Agent 各自拥有一个 USB transport，再通过 start/stop 交接。这违反 Runtime 唯一设备所有权，只能作为协议/IOKit 参考。

## 5. 尚未关闭的 WBS 0 风险

- Fn/Globe 在 macOS USB/BLE 上的真实 HID 报告与可配置性。
- Windows USB `0xEE` 平台信号和枚举缓存。
- BLE 首次连接无法可靠推断操作系统时的设备端选择流程。
- protocol v4 的 opcode、BLE MTU、EEPROM/Flash/RAM 预算。
- VBUS v11 在插线、拔线、充电器、Hub、睡眠唤醒场景的 HIL。
- Codex hook session id 到桌面 thread/navigation target 的 join 稳定性。

这些项目未通过前，WBS 1 只能做隔离原型和内部构建，不能切换量产主线。
