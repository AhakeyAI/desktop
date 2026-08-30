# HIL-RELEASE-0.2 冻结候选（2026-08-30 23:41–23:53 +08）

源码：detached worktree `/tmp/ahakey-hil-release-02-6649834` @ `6649834602536fe1199960effa6121fdcb4a3739`。未改业务代码、未安装、未 push。

命令：`SIGNING_IDENTITY="Developer ID Application: Xinyang Zhang (P2VFVRZK7P)" NOTARY_PROFILE=AhaKeyNotary DMG_BASENAME=AhaKey-Studio-0.2.0-HIL-RELEASE-02-6649834 zsh scripts/pack-release.sh`

## 产物

| 项 | 值 |
|---|---|
| 版本 | `0.2.0` (build `304`) |
| Bundle ID | `lab.jawa.ahakeyconfig` |
| Team | `P2VFVRZK7P` |
| DMG | `AhaKey-Studio-0.2.0-HIL-RELEASE-02-6649834.dmg` |
| DMG SHA-256 | `4426b3c9924fe83e83f4b2ffb7a4025b53e2786fc42f6c7fc2c1ff02ffce793b` |
| 公证 | `9133cb9a-0b09-47a3-9946-acaa228d0b05` **Accepted** |
| Staple | 成功（`The staple and validate action worked!`） |
| Gatekeeper | DMG/App `accepted` / `Notarized Developer ID` |

冻结 requirement：

`anchor apple generic and certificate leaf[subject.OU] = "P2VFVRZK7P" and identifier "lab.jawa.ahakeyconfig"`

- `dist/AhaKey Studio.app`（`build.sh` 直出）：App 与 Agent **均满足**。Agent identifier = `lab.jawa.ahakeyconfig`。
- DMG 内 App：**满足**。identifier = `lab.jawa.ahakeyconfig`。
- DMG 内 Agent：**不满足**（`codesign -R` rc=3）。identifier = `ahakeyconfig-agent`。

原因：`package_dmg.sh` 在 Finder 布局后重签挂载 App/Agent 时未传 `--identifier lab.jawa.ahakeyconfig`，Agent 回落到二进制文件名。这是 6649834 打包脚本行为，不是本卡改出来的。

## P0（只记录，本卡不改代码）

**DMG 嵌套 Agent 丢失冻结 signing identifier。** 与 `SIGNING-INPUTS.md` / `ReleaseIdentity.json` 冲突；XPC peer 策略只接受 `lab.jawa.ahakeyconfig`。此 DMG **不得进入安装矩阵**。

返工方向（另开卡）：`package_dmg.sh` 重签必须带 `--identifier "$SIGNING_IDENTIFIER"`，与 `build.sh` 一致；再出公证 DMG。

原始记录：`raw/pack-release.log`、`raw/freeze-candidate.txt`。14MB DMG 副本留在 `raw/`，不入库。
