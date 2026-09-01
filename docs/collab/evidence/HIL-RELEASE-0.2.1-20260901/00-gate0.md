# HIL-RELEASE-0.2.1 Gate-0 不可变候选（2026-09-01 21:56–22:05 +08）

U2 产品基线 `95b775d`。Gate-0 打包源码：detached worktree `/tmp/ahakey-hil-release-021-1c024c5` @ `1c024c54167e64194c57434fb452f258103d1977`（仅 `productVersion` 0.2.0→0.2.1 戳记，Team/Bundle/LaunchAgent/Mach/Hook 未改）。未安装、未改 `/Applications` 或登录项、未 push。

预打包门禁（worktree）：U1 copy-gate rc=0；`swift test` 722 passed / 2 skipped / 0 failed；Release `AhaKeyConfig` 与 `ahakeyconfig-agent` 通过；`check-release-identity.sh` ok；`git diff --check` 通过。

命令：`BUILD_NUMBER=360 DMG_BASENAME=AhaKey-Studio-0.2.1-HIL-RELEASE-021-1c024c5 zsh scripts/pack-release.sh`

`pack-release.sh` 在公证前与 staple 后均调用 `verify-release-dmg.sh --expect-developer-id`；两次均为 `release dmg ok`。随后独立只读挂载复核身份，`hdiutil detach rc=0`。

## 产物

| 项 | 值 |
|---|---|
| 版本 | `0.2.1` (build `360`) |
| Bundle ID | `lab.jawa.ahakeyconfig` |
| Team | `P2VFVRZK7P` |
| DMG | `AhaKey-Studio-0.2.1-HIL-RELEASE-021-1c024c5.dmg` |
| 路径 | `/tmp/ahakey-hil-release-021-1c024c5/ahakeyconfig-mac/dist/`（约 13MB，不入库） |
| DMG SHA-256 | `9f109421531b196c9378abb2c0d2b1f5b52f62c902d6796ae37ee720610b46c3` |
| 公证 | `4c2e56d7-22c6-46d5-adc1-9a77d57971e8` **Accepted** |
| Staple | 成功（`The staple and validate action worked!` / `The validate action worked!`） |
| Gatekeeper | DMG `accepted` / `Notarized Developer ID` / `Developer ID Application: Xinyang Zhang (P2VFVRZK7P)` |
| hdiutil verify | `VALID` |

冻结 requirement（生产 helper `codesign --verify "-R=<requirement>"`）：

`anchor apple generic and certificate leaf[subject.OU] = "P2VFVRZK7P" and (identifier "lab.jawa.ahakeyconfig")`

- DMG 内 App：identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0，requirement rc=0。
- DMG 内 Agent：identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0，requirement rc=0。
- 根目录恰好一个 `AhaKey Studio.app`，同级 `LaunchAgent.plist`（非 symlink）。
- companion exact：Label `lab.jawa.ahakeyconfig.agent`；`MachServices == {lab.jawa.ahakeyconfig.runtime: true}`；`ProgramArguments == [/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent, --socket, SOCKET_PATH_PLACEHOLDER]`。

build `360` > 359，且 ≠ 历史 `323`。SHA ≠ 永久禁用 `4426b3c9…ce793b`，也 ≠ 0.2.0 `9736c31c…ac26` / `0c3ec9a6…f33618`。本候选 **未安装**。

原始记录：`raw/gate0-mount.txt`、`raw/pack-release-1c024c5.txt`。
