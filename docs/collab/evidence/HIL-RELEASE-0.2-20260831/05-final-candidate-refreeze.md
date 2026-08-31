# HIL-RELEASE-0.2 最终候选重冻结（2026-08-31 21:19–21:25 +08）

源码：detached worktree `/tmp/ahakey-hil-release-02-5c4f440` @ `5c4f440a779452dd00282cd35fe915e2642678f0`。未改业务代码、未安装、未 push。

命令：`SIGNING_IDENTITY="Developer ID Application: Xinyang Zhang (P2VFVRZK7P)" NOTARY_PROFILE=AhaKeyNotary DMG_BASENAME=AhaKey-Studio-0.2.0-HIL-RELEASE-02-5c4f440 zsh scripts/pack-release.sh`

`pack-release.sh` 在公证前与 staple 后均调用 `verify-release-dmg.sh --expect-developer-id`；两次均为 `release dmg ok`。随后独立只读挂载复核身份，`hdiutil detach rc=0`。

## 产物

| 项 | 值 |
|---|---|
| 版本 | `0.2.0` (build `359`) |
| Bundle ID | `lab.jawa.ahakeyconfig` |
| Team | `P2VFVRZK7P` |
| DMG | `AhaKey-Studio-0.2.0-HIL-RELEASE-02-5c4f440.dmg` |
| DMG SHA-256 | `9736c31c81070967875f2021f31b14e7d17bc2248f5916d55f6e245ec336ac26` |
| 公证 | `b4038a0b-eec9-4c86-ba10-45f81544261b` **Accepted** |
| Staple | 成功（`The staple and validate action worked!` / `The validate action worked!`） |
| Gatekeeper | DMG `accepted` / `Notarized Developer ID` / `Developer ID Application: Xinyang Zhang (P2VFVRZK7P)` |
| hdiutil verify | `VALID` |

冻结 requirement（生产 helper `codesign --verify "-R=<requirement>"`）：

`anchor apple generic and certificate leaf[subject.OU] = "P2VFVRZK7P" and (identifier "lab.jawa.ahakeyconfig")`

- DMG 内 App：identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0，requirement rc=0。
- DMG 内 Agent：identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0，requirement rc=0。
- 根目录恰好一个 `AhaKey Studio.app`，同级 `LaunchAgent.plist`（非 symlink）。
- companion exact：Label `lab.jawa.ahakeyconfig.agent`；`MachServices == {lab.jawa.ahakeyconfig.runtime: true}`；`ProgramArguments == [/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent, --socket, SOCKET_PATH_PLACEHOLDER]`。

build `359` ≠ 旧候选 `323`。SHA ≠ 永久禁用 `4426b3c9…ce793b`，也 ≠ 历史 `0c3ec9a6…f33618`。本候选 **未安装**，未改 `/Applications` 或登录项，未启 Studio/BLE。

原始记录：`raw/final-candidate-refreeze.txt`、`raw/pack-release-5c4f440.log`。约 13MB DMG 留在 worktree `dist/`，不入库。
