# HIL-CONFIG 2026-08-27 — 基线与 XPC smoke

时间：2026-08-27 20:41–20:47 +08

## 基线（登记前）

- 客户端 HEAD：`ca3184b`（`docs(collab): transfer HIL-CONFIG to Cursor`）
- 固件仓：`9135183867a693dbab81aac3b9d4a1b172c34860`，工作树 clean
- 已安装 App：`/Applications/AhaKey Studio.app`（2026-08-21 14:58，version 0.1.0 build 70，Developer ID `P2VFVRZK7P` / `lab.jawa.ahakeyconfig`）
- 正式 LaunchAgent：`~/Library/LaunchAgents/lab.jawa.ahakeyconfig.agent.plist`（874B，**无 MachServices**，KeepAlive+RunAtLoad）
  - Program：`/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent --socket …/ahakey.sock`
  - 备份：`raw/official-agent.plist`（sha256 `61da75e0ece09f3bf422770aa707b7cb99af865ff4d004e2b1e1da9d84055804`，与现盘文件一致）
- 正式 agent PID 29085 当时持有 `ble-owner.lock`；Studio GUI PID 56036
- 无残留 `lab.jawa.ahakeyconfig.agent.hil`
- 持久化：`~/Library/Application Support/AhaKeyConfig`（61M）；`runtime-store/resources` 空；WAL 存在
- 设备身份缓存：`3A9D2D14-3720-2D36-18C5-84B776CC4F3E` → `4F3E`
- 系统蓝牙：On；Connected：`AhaKey X1`（BLE HID）。USB 跳过。
- 原始转储：`raw/preflight-baseline.txt`、`raw/preflight-detail.txt`

## 临时登记（可回滚）

1. 退出已安装 Studio GUI；`launchctl bootout gui/$(id -u)/lab.jawa.ahakeyconfig.agent`（**未改、未删正式 plist**）。
2. 首次从 Documents 下 `.build/release` 启动时，launchd 进程卡在 dyld `open`（RSS≈80KB）。改为把同 sha256 二进制复制到 `/tmp/ahakey-hil-bin/ahakeyconfig-agent` 再登记。
3. 写入 `~/Library/LaunchAgents/lab.jawa.ahakeyconfig.agent.hil.plist`（源：`raw/lab.jawa.ahakeyconfig.agent.hil.plist`），`MachServices` = `lab.jawa.ahakeyconfig.runtime`，`NSUnbufferedIO=YES`。
4. `launchctl bootstrap` + `kickstart`。PID 10092；endpoint `lab.jawa.ahakeyconfig.runtime` active=1。
5. 日志：`raw/agent-hil.log`（已监听 Unix/Hook/XPC）。

## XPC smoke（不碰供电/蓝牙开关）

客户端：`RuntimeXPCSmokeClient`，Developer ID + identifier `lab.jawa.ahakeyconfig`（未纳入 git，体积大）。

- 正向 `lab.jawa.ahakeyconfig.runtime positive`：handshake + snapshot，exit 0。
  - runtime `0.1.0(development)`，interface `1.1`，schema=`[1]`，capabilities=`configuration, diagnostics, event-replay, snapshot`
  - `RESULT: ok`
- 负向 ad-hoc 签名同一二进制：`RESULT: rejected`，exit 3（libxpc 在业务前拒绝）。
- 完整输出：`raw/xpc-smoke.txt`

未在本步对真机 apply 配置包（避免误写入）；最小合法包与 `resourceByteCountMismatch` 归 C1/C2。

## 当前环境注意

- HIL agent 日志出现 `LED 状态 2: 未连接`：正式 agent 已停，Runtime 尚未 attach 键盘。C1 前需要 Agent 重新持有 BLE，**不要**关蓝牙或拔电。
- 已安装 Studio 仍是 8/21 旧包，C1 将使用仓库当前 5.7 Studio，不覆盖 `/Applications`。
