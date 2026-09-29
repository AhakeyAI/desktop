# 旧版客户端本地安装与修复验证

日期：2026-09-29。基线：GitHub main `f9a690a`。

代码候选：`2857542`，本地版本 `0.2.2`。包含 CPU、Codex 策略修复、覆盖安装时 LaunchAgent 参数迁移、历史 Agent 状态轮询，以及用户追加的灵动岛精确 hover/抖动修复。

## 安装和代码检查

- macOS 全量测试：98 项通过；VibeBar 独立测试：7 项通过。
- App 与 Agent 的 arm64、x86_64 Release 构建用于 universal 签名包。
- Developer ID 签名、公证、staple、DMG checksum 和 Gatekeeper 检查通过后，从 DMG 覆盖安装；内嵌 AhaKeyGitCommit 用于核对安装来源。
- 覆盖前备份了原 App、LaunchAgent plist、应用偏好、Application Support 与 Codex config，备份仅保存在本机，未入库。
- 首轮安装发现旧 LaunchAgent 保留 Application Support socket 参数，而 main 的 GUI/Hook 使用 `/tmp/ahakey.sock`。`7e60c66` 补齐自动启动前迁移；真实安装已验证参数重写、Agent 启动、socket 回包和 App→Agent 交接。
- `fb05139` 补齐历史去重方案依赖的 1.5 秒 Agent 状态查询；相同状态不重复写 JSON，30 秒按需刷新 mtime，断开后停止轮询并重置去重基线。

## 真实键盘与 CPU

AhaKey 505C 通过 BLE 连接；GUI 直接读取电量 63–64%、固件 1.0，并观察到用户的真实 Mode 切换。以下 CPU 数据来自 `proc_pid_rusage` 的 CPU 时间差分，为单核百分比；每阶段采样约 60 秒。

| 场景 | Studio 平均 CPU | Agent 平均 CPU | 常规 BLE 日志新增 |
| --- | ---: | ---: | --- |
| 真实连接、GUI 持有 BLE、前台（7e60c66） | 0.230% | 未运行 | 326B，来自实际 Mode/电量变化 |
| 真实连接、Agent 持有 BLE、隐藏（fb05139） | 0.019% | 0.007% | 0B |
| 真实连接、Agent 持有 BLE、主窗口关闭（fb05139） | 0.019% | 0.008% | 0B |

关窗后 Studio 与 Agent 进程继续运行，socket 仍返回真实自动档 `0`。这些不是完整十分钟/三十分钟内存 soak 数据。测试期间真实 Codex 工具 Hook 仍产生事件性 stateValue/stateTs 写入，因此整体 JSON hash 改变不等于相同 BLE 轮询重复落盘；去重回归和零常规 BLE 日志已分别验证。

GUI 的 Agent-only 冷启动电量显示仍受 main 既有缓存限制（可显示 0%）；真实电量值以上述 GUI 直接连接读取为准。本次未扩展 Agent 电量/设备名协议。

## Codex 参数与实体拨杆

- 本机 `codex-cli 0.153.4` 的隔离 CODEX_HOME 实测：untrusted 导致 app-server 初始化失败；on-request 与 never 均成功。
- 生产 TOML 写入器在临时配置中将 untrusted 修为 on-request，并保留注释。
- 用户切实体拨杆到手动，Agent 返回 `1`；安装版 CodexPermissionRequest 不输出 allow，实际用户配置写为 on-request。
- 用户切回自动，安装版 CodexSessionStart 与 CodexPermissionRequest 均正常退出；后者输出 `decision.behavior=allow`，配置为 never。
- 自动档测试结束后，用户 Codex config 与安装前备份逐字节一致。
- Hook 验证只产生协议结果，没有执行被批准的工具命令。公开证据 JSON 使用测试 session 标识，未包含用户配置、凭据或原始诊断日志。

## 灵动岛热区与抖动

- 旧代码固定 440×58 热区；边界外测试实际失败（返回屏幕索引 0）。新代码依据实际 SwiftUI 渲染 frame 和锁定的 NotchShape 轮廓判断。
- 回归覆盖四侧、透明圆角、负坐标屏幕、未测量 frame、拖窗鼠标按下状态，以及 22pt 菜单栏。
- 删除 50ms 轮询，改为鼠标事件触发并合并重复更新；收起时窗口穿透鼠标事件，移除重复 compact onHover 入口与库 hover 阴影，避免透明区捕获拖窗或触发动画。
- 原生预览用户确认：“边界外不展开、移入才展开”；修复抖动后再次确认“不抖了，进到可见区域才展开”。预览采用静态状态；调试日志已从产品源码清除。
- Standards/Spec 独立审查完成；短菜单栏曲线差异发现项已修复并复核。

## 验证范围

本轮覆盖三组修复与新增 hover 要求的构建、安装、正常使用路径；不包含固件烧录、OLED 写入、完整 USB/多显示器真机矩阵或长时间 soak。代码中的非运行时显示问题不据此宣称全部消除。
