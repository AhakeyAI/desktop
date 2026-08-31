# HIL-RELEASE-0.2 Gate-1 fail-forward：enable + bootstrap（2026-08-31 14:04–14:05 +08）

用户 14:03 明确授权 Codex 12:45 最小现场恢复。只做 official `enable` + 当前正式 plist `bootstrap` + 唯一 owner + XPC handshake/snapshot。未删 backup/zip，未注册登录项，未启动 Studio，未测 BLE，未卸载，未回灌，未刷机，未 push。未改业务代码。

## 恢复前（只读）

- `/Applications/AhaKey Studio.app`：0.2.0 (323)，`codesign --verify --strict` rc=0。
- `/Applications/AhaKey Studio.app.ahakey-backup`：仍在；0.1.0 密封仍坏（rc=1）。
- `launchctl print-disabled gui/501`：`lab.jawa.ahakeyconfig.agent` => **disabled**。
- official / HIL `launchctl print` 均为 rc=113（零 owner）。
- 正式 plist 已含 MachServices `lab.jawa.ahakeyconfig.runtime`；ProgramArguments 指向 `/Applications/.../ahakeyconfig-agent`。
- 登录项：Typeless / QoderWork / BaiduNetdisk（无 Studio）。

## 命令与结果

```
CMD: launchctl enable gui/501/lab.jawa.ahakeyconfig.agent
enable_rc=0
print-disabled: "lab.jawa.ahakeyconfig.agent" => enabled

CMD: launchctl bootstrap gui/501 ~/Library/LaunchAgents/lab.jawa.ahakeyconfig.agent.plist
bootstrap_rc=0
```

未重试。bootstrap 一次成功。

## 唯一 Runtime owner

| 检查 | 结果 |
|---|---|
| `launchctl list` | 仅 `6602  0  lab.jawa.ahakeyconfig.agent` |
| official print | rc=0，state=running，pid=6602，program=`/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent`，Mach `lab.jawa.ahakeyconfig.runtime` managed |
| HIL print | rc=113，not found |
| Studio GUI | 未启动（仅 Agent 进程） |
| 登录项 | 未增加 Studio |
| backup / zip | 仍在；zip `/tmp/ahakey-hil-gate1-rollback/AhaKey-Studio-pre-gate1.zip` |

## XPC

生产客户端 `docs/collab/evidence/HIL-CONFIG-20260827/raw/RuntimeXPCSmokeClient`：identifier `lab.jawa.ahakeyconfig`，Developer ID `Xinyang Zhang (P2VFVRZK7P)`，`--verify --strict` rc=0。未从当前脏树 `swift build`。

```
CMD: RuntimeXPCSmokeClient lab.jawa.ahakeyconfig.runtime positive
HANDSHAKE: runtime=AhaKeyRuntimeVersion(major: 0, minor: 1, patch: 0, buildMetadata: Optional("development")) interface=AhaKeyRuntimeInterfaceVersion(major: 1, minor: 1) schema=[1] capabilities=["configuration", "diagnostics", "event-replay", "snapshot"]
RESULT: ok
xpc_positive_rc=0
```

未跑负向 ad-hoc（本轮未要求）。未开 Studio，未测 BLE。

## 结论

Fail-forward **完成**：official disabled override 已 enable；0.2 Agent 已 bootstrap 且为唯一 Runtime owner；XPC handshake+snapshot exit 0。机器仍保留损坏 0.1 backup 与 Gate-1 zip，登录项未登记 Studio。Gate-1 安装器路径仍未成功；本步只恢复 Runtime，不视为安装器验收通过。

停手提审。15F2 R1 产品改动保持未提交。

原始：`raw/gate1-failforward.txt`。
