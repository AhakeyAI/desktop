# HIL-RELEASE-0.2 Gate-0（2026-08-30 23:11–23:16 +08）

只读预检。未签名、未安装、未改 `/Applications`、未 bootout、未刷机、未 push。

## 通过

- Detached worktree `/tmp/ahakey-hil-release-02-6649834` @ `6649834602536fe1199960effa6121fdcb4a3739`，工作树 clean，`check-release-identity.sh` 通过。
- 兼容策略提交 `d9d2cbb` 存在。
- `ReleaseIdentity.json`：version `0.2.0`，Team `P2VFVRZK7P`，Bundle/Signing `lab.jawa.ahakeyconfig`。
- Developer ID 在钥匙串：`Developer ID Application: Xinyang Zhang (P2VFVRZK7P)`（`9E44F53DE4B97D256AC7DA1F5DA893DEED48B270`）。
- 系统蓝牙 On。已连接 **AhaKey 515C** `D4:6C:51:5C:F5:B4`，VID `0x07D7`，HID UsagePage=1 Usage=6（键盘）。无 USB AhaKey。

## 环境原状（已快照，未改动）

- `/Applications/AhaKey Studio.app`：0.1.0 (70)，mtime Aug 21 14:58。App 外层 Developer ID `P2VFVRZK7P`；内嵌 Agent 为 **ad-hoc** 且 bundle 密封已坏（多份 `ahakeyconfig-agent.ahk-bak*` 与 backup）。`codesign --verify --deep --strict` / `spctl` 失败。
- 正式 LaunchAgent plist 仍在，`launchctl` 显示 `lab.jawa.ahakeyconfig.agent` **disabled**，`print` 找不到服务。
- HIL 残留：`lab.jawa.ahakeyconfig.agent.hil` 已登记、未运行；占用 Mach `lab.jawa.ahakeyconfig.runtime`；二进制 `/tmp/ahakey-hil-bin/ahakeyconfig-agent`。
- 先前冻结的 **AhaKey X1** `D4:6C:50:5C:F5:C0` / PID `0x501A` 当前 Not Connected。

## 回滚快照

| 对象 | sha256 |
|---|---|
| 正式 plist | `61da75e0ece09f3bf422770aa707b7cb99af865ff4d004e2b1e1da9d84055804` |
| HIL plist | `bb8df32368e672103e1632b74fbf14d36124eeaef5b61f77ac7709003f6ed923` |
| App 可执行 | `577b0d49c6dce8dedac2b7462842e3cbe68231b69f9aa9539fa88bacc7c8f919` |
| Agent 可执行 | `d75e828ea8c11e845e7b2fcd90b401ba3afaf44ea392f4cb2283ecce90e73df8` |

副本：`raw/official-agent.plist`、`raw/hil-agent.plist`、`raw/gate0-preflight.txt`、`raw/gate0-snapshot.txt`。本机另有 17MB App zip（不入库）。

## Gate-0 结论

源码/身份/Developer ID/BLE 键盘在场 → **Gate-0 预检完成**。

进入冻结候选前 **blocked**：

1. **无 notarytool keychain profile**（`notarytool` / `AC_PASSWORD` 均不存在）。调度要求公证 DMG，不能在缺凭据时伪造公证。
2. HIL 残留占用 `lab.jawa.ahakeyconfig.runtime`；安装矩阵开始前必须先按快照回滚 HIL label（尚未执行）。
3. 当前连接键盘是 515C，不是先前 HIL 冻结的 X1 地址。若本卡必须用 X1，需用户改连。

未进入步骤 2 签名/公证/DMG。
