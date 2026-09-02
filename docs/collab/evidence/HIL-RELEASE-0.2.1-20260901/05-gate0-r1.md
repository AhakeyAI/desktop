# HIL-RELEASE-0.2.1 Gate-0 R1 不可变候选（2026-09-02 19:10–19:21 +08）

产品源 `0b4b5e1`（含 V021 `88e02aa` + verifier cleanup）。Gate-0 R1 打包：detached worktree `/tmp/ahakey-hil-release-021-0b4b5e1` @ `0b4b5e148ff822454d5ff4316e624c1e1aae1c96`。版本戳仍为 `0.2.1`；build `361`（>360，且 ≠ 323/359/360）。Team/Bundle/LaunchAgent/Mach/Hook 未改。未安装、未改 `/Applications` 或登录项、未 push。

预打包门禁（worktree）：U1 copy-gate rc=0；`swift test` 737 passed / 2 skipped / 0 failed；Release `AhaKeyConfig` 与 `ahakeyconfig-agent` 通过；`check-release-identity.sh` ok；`git diff --check` 通过。

命令：`BUILD_NUMBER=361 DMG_BASENAME=AhaKey-Studio-0.2.1-HIL-RELEASE-021-0b4b5e1 zsh scripts/pack-release.sh`

`pack-release.sh` 在公证前与 staple 后均调用 `verify-release-dmg.sh --expect-developer-id`；两次均为 `release dmg ok`，可见 `detached mountpoint:`。随后独立只读挂载复核身份，`hdiutil detach rc=0`。

## 产物

| 项 | 值 |
|---|---|
| 版本 | `0.2.1` (build `361`) |
| Bundle ID | `lab.jawa.ahakeyconfig` |
| Team | `P2VFVRZK7P` |
| DMG | `AhaKey-Studio-0.2.1-HIL-RELEASE-021-0b4b5e1.dmg` |
| 路径 | `/tmp/ahakey-hil-release-021-0b4b5e1/ahakeyconfig-mac/dist/`（约 13MB，不入库） |
| DMG SHA-256 | `4662ce93dd6dfa55e7964a5db9749ab3e7e82813a9616b114c1032ce3bbe1f0d` |
| 公证 | `f2dadb61-0518-44d9-88db-db6c2f555f18` **Accepted** |
| Staple | 成功（`The staple and validate action worked!` / `The validate action worked!`） |
| Gatekeeper | DMG `accepted` / `Notarized Developer ID` / `Developer ID Application: Xinyang Zhang (P2VFVRZK7P)` |
| hdiutil verify | `VALID` |

冻结 requirement（生产 helper `codesign --verify "-R=<requirement>"`）：

`anchor apple generic and certificate leaf[subject.OU] = "P2VFVRZK7P" and (identifier "lab.jawa.ahakeyconfig")`

- DMG 内 App：identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0，requirement rc=0。
- DMG 内 Agent：identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0，requirement rc=0。
- 根目录恰好一个 `AhaKey Studio.app`，同级 `LaunchAgent.plist`（非 symlink）。
- companion exact：Label `lab.jawa.ahakeyconfig.agent`；`MachServices == {lab.jawa.ahakeyconfig.runtime: true}`；`ProgramArguments == [/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent, --socket, SOCKET_PATH_PLACEHOLDER]`。

build `361` > 360，且 ≠ 历史 `323` / `359` / `360`。SHA ≠ 永久禁用 `4426b3c9…ce793b`，≠ 0.2.1 (360) `9f109421…610b46c3`，≠ 0.2.0 `9736c31c…` / `0c3ec9a6…`。本候选 **未安装**（本机 360 调试基线未覆盖）。

原始记录：`raw/gate0-r1-verify.txt`、`raw/pack-release-0b4b5e1.txt`。
