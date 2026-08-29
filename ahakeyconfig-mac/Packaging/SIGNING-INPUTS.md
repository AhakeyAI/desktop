# WBS 5.9A 签名输入清单

本卡只冻结输入，不实际使用 Developer ID 签名。HIL-RELEASE-0.2 在 USER-GATE 下使用同一份清单签名。

| 字段 | 冻结值 |
|---|---|
| 产品版本 | `0.2.0` |
| Bundle ID | `lab.jawa.ahakeyconfig` |
| Signing ID | `lab.jawa.ahakeyconfig` |
| Team ID | `P2VFVRZK7P` |
| 应用包名 | `AhaKey Studio.app` |
| 可执行文件 | `AhaKeyConfig` |
| Runtime helper | `Contents/MacOS/ahakeyconfig-agent` |
| launchd Label | `lab.jawa.ahakeyconfig.agent` |
| Mach service | `lab.jawa.ahakeyconfig.runtime` |
| 最低系统 | macOS 13.0（Darwin 22）；macOS 12 必须拒绝 |
| codesign requirement | `anchor apple generic and certificate leaf[subject.OU] = "P2VFVRZK7P" and (identifier "lab.jawa.ahakeyconfig")` |

HIL 签名时：

1. 以 `scripts/pack-unsigned-candidate.sh` 产出的候选为输入。
2. `codesign --sign "Developer ID Application: … (P2VFVRZK7P)" --timestamp --options runtime` 分别签 agent 与 `.app`。
3. 公证与 staple 只在 USER-GATE 执行。
4. 不得改 Bundle ID / Team ID / Mach service。
