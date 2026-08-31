# HIL-RELEASE-0.2 重新冻结候选（2026-08-31 12:11–12:15 +08）

源码：detached worktree `/tmp/ahakey-hil-release-02-3b287be` @ `3b287beecf34c3f2d433631610f8e8c8f85c9149`。未改业务代码、未安装、未 push。

命令：`SIGNING_IDENTITY="Developer ID Application: Xinyang Zhang (P2VFVRZK7P)" NOTARY_PROFILE=AhaKeyNotary DMG_BASENAME=AhaKey-Studio-0.2.0-HIL-RELEASE-02-3b287be zsh scripts/pack-release.sh`

`pack-release.sh` 在公证前与 staple 后均调用 `verify-release-dmg.sh --expect-developer-id`；两次均为 `release dmg ok`。随后只读挂载复核身份，trap detach `rc=0`。

## 产物

| 项 | 值 |
|---|---|
| 版本 | `0.2.0` (build `323`) |
| Bundle ID | `lab.jawa.ahakeyconfig` |
| Team | `P2VFVRZK7P` |
| DMG | `AhaKey-Studio-0.2.0-HIL-RELEASE-02-3b287be.dmg` |
| DMG SHA-256 | `0c3ec9a6f5031e2497be786d32a4d5ba4d02bd474e5b7e124f04201b92f33618` |
| 公证 | `bbf43bac-3a71-4b57-bfbb-87554a2de96f` **Accepted** |
| Staple | 成功（`The staple and validate action worked!` / `The validate action worked!`） |
| Gatekeeper | DMG `accepted` / `Notarized Developer ID` / `Developer ID Application: Xinyang Zhang (P2VFVRZK7P)` |

冻结 requirement（生产 helper `codesign --verify "-R=<requirement>"`）：

`anchor apple generic and certificate leaf[subject.OU] = "P2VFVRZK7P" and (identifier "lab.jawa.ahakeyconfig")`

- DMG 内 App：identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0，requirement rc=0。
- DMG 内 Agent：identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0，requirement rc=0。
- 根目录恰好一个 `AhaKey Studio.app`，同级 `LaunchAgent.plist`（非 symlink）。
- companion exact：Label `lab.jawa.ahakeyconfig.agent`；`MachServices == {lab.jawa.ahakeyconfig.runtime: true}`；`ProgramArguments == [/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent, --socket, SOCKET_PATH_PLACEHOLDER]`。

旧 SHA `4426b3c9924fe83e83f4b2ffb7a4025b53e2786fc42f6c7fc2c1ff02ffce793b` 未复用，仍不得安装。本候选 **未安装**，未改 `/Applications` 或登录项。

原始记录：`raw/pack-release.log`、`raw/refreeze-candidate.txt`。约 13MB DMG 留在 worktree `dist/`，不入库。
