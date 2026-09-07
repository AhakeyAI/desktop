# HIL-V03-STUDIO-OLED C5 preflight（2026-09-07 19:12–19:25 +08）

ACK 用户 19:07 确认并开启 C5。C1–C4 accepted @ `30cfeb8`。15L `ready / C5 preflight @ 30cfeb8`。执行 owner Cursor。Agent Relay 继续暂停。未 overlay `/Applications`、未 kickstart、未刷机、未擦 EEPROM、未 push、未签名/打包/安装候选、未改业务代码。未改 `queue.md`。未伪造 Relay `review_decision`。

## 冻结候选

| 项 | 值 |
|---|---|
| 产品 commit | `30cfeb889bfea299a41224222f8a5b400df2de33` |
| 主题 | `V03 C4R14：净化审查范围，并补 MUTATING 与严格 flock 判定` |
| ReleaseIdentity | `productVersion=0.2.1`，Bundle/Team `lab.jawa.ahakeyconfig` / `P2VFVRZK7P`，Mach `lab.jawa.ahakeyconfig.runtime` |
| 本地 Release | App+Agent **adhoc**（Identifier 为产物名，Team 未设） |
| App SHA-256 | `7c14c4b1dce7df639119f6145fbd99e7fa61d7e8a9afd38cbad1dc73298d4b97` |
| Agent SHA-256 | `6837c6bd96477b4a9a6d650a44e0ffb48d4b62290bd9c91a6975b61477f2cbe3` |
| `check-release-identity.sh` | `release identity ok` |

本候选 **不是** 可安装 HIL Runtime：XPC 正向路径要求 Developer ID + identifier `lab.jawa.ahakeyconfig`。adhoc 会被 libxpc 拒绝。

## 现网只读（已安装 0.2.1 不受影响）

| 项 | 值 |
|---|---|
| `/Applications/AhaKey Studio.app` | **0.2.1 (362)** / `AhaKeyGitCommit=1ed560bb5626048926eba499efe5394fd95304d3` |
| App/Agent 签名 | identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0 |
| 唯一 Runtime owner | `lab.jawa.ahakeyconfig.agent` pid **65466** / `runs=1`；Mach `lab.jawa.ahakeyconfig.runtime` active=1 |
| HIL label | `launchctl print` rc=**113**（未加载） |
| LaunchAgent | Label exact，RunAtLoad=true，KeepAlive=true |
| Studio GUI | pid **58877** 在跑（0.2.1） |
| XPC | 既有 Developer ID `RuntimeXPCSmokeClient` → `lab.jawa.ahakeyconfig.runtime positive`：handshake + snapshot `RESULT: ok`，exit 0。**未 kickstart** |
| 设备 | 系统蓝牙 On；**AhaKey 505C** `D4:6C:50:5C:F5:C0` VID `0x07D7` 为 **Not Connected**；USB 无 AhaKey |
| 缓存 identity | `3A9D2D14-3720-2D36-18C5-84B776CC4F3E` → `4F3E` |

原始：`raw/preflight-baseline.txt`、`raw/official-agent-print.txt`、`raw/hil-agent-print.txt`、`raw/xpc-handshake.txt`、`raw/preflight-store-identity.txt`。

## 本地 Store / EEPROM 初态（只读）

设备未连接，**不能**读键盘 EEPROM。本地 Runtime store：

- 已确认资源 1 条 GIF（4402 B）
- staged：`mode0-default` 2148859 B、`mode1-default` 3872 B、`mode2-default` 122286 B（2026-08-28）
- 历史事务 8 条，全部终态失败（`failedWithPartialCommit` 3/7 或 `failedWithoutWrites` 0/7）；无 sync baseline；`runtime_page_field_baselines` = 0
- 2026-09-02 Rhino 差分曾在 Gitee Rhino + 清洁 EEPROM 上留下 A/B 图；**本机当前键盘内容未复核**

原始：`raw/preflight-sqlite.txt`。

## 三族固件来源 SHA / HEX SHA

`.frozen-sha` 与卡面冻结点一致。Rhino 以 **`obj/` HEX** 为准；`frozen-hex/*-obj_final.hex` 三份互相相同（`ada63b34…`），**不得**当作品族身份。

| 族 | 来源 SHA | 规范 HEX | HEX SHA-256 |
|---|---|---|---|
| GitHub Standard | `3e7f900ae6f5fe71d57a03da973d79356afea1b6`（unified-firmware 仓可达） | `.wbs1-baselines/github-3e7f900-a/obj/HID_Keyboard_582m_vibe_coding.hex` | `e5a336a656377454d8a4b798a9da9c7160780824f598b991e68e6ce87c19ffca` |
| Gitee Rhino | `53cd0a97e95e3b8b35cd56ed2284970d5a79d1be`（基线树 `.frozen-sha`；unified-firmware 无该 commit 对象） | `.wbs1-baselines/gitee-53cd0a97/.../obj/HID_Keyboard_582m_vibe_coding.hex` | `ace7ab3e517ec0849d4f865cdc8d33acb304fbc7b4b5dd68a1d917f8f14b1a70`（与 2026-09-02 已刷 HEX 一致） |
| Local Rhino | `00eb7efc235770d0a40e23a8c6e7449b2c010765`（基线树 `.frozen-sha`；unified-firmware 无该 commit 对象） | `.wbs1-baselines/local-00eb7efc/.../obj/HID_Keyboard_582m_vibe_coding.hex` | `7a49f36513b9dcb9cf9cdfcc4191a1e478e9351e039e5c3d3d05005d1b35ca80` |

原始：`raw/firmware-sha.txt`、`raw/preflight-hex-release.txt`。

## 素材夹具

入库小图：`raw/c5-ident-A.png`、`c5-ident-B.png`、`c5-ident-A.jpg`、`c5-ident-anim.gif`、`c5-corrupt.jpg`。大文件只留 SHA，不入库：

| 文件 | 用途 | SHA-256 |
|---|---|---|
| `/tmp/ahakey-c5-source-2mib-121f.gif` | >2 MiB / 121 帧规范化源 | `698be1e804021875bacc04af3bd8a32c9a133ad54a5b94824fa570e4dd97f898` |
| `/tmp/ahakey-c5-oversized-20mib-plus1.bin` | 超过 20 MiB 源文件拒绝 | `a2bd6fff787fa95c1f2c3cdb310f0ef9ca91fa1598f435194c9d49fbc53d8377` |

清单：`raw/c5-fixtures.sha256`。逐项取证模板：`01-page-matrix-template.md`。

## 签名 / 安装计划（未执行）

1. 不覆盖 `/Applications` 的 0.2.1 (362)。
2. 隔离目录（例如 `/tmp/ahakey-hil-v03-30cfeb8/`）放置 Developer ID 签名的 App+Agent，identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，requirement 与 `ReleaseIdentity.json` 相同。
3. 快照后 `bootout` 正式 `lab.jawa.ahakeyconfig.agent`，bootstrap `lab.jawa.ahakeyconfig.agent.hil`，Mach 仍为 `lab.jawa.ahakeyconfig.runtime`。
4. 回滚：bootout HIL → bootstrap 正式 362。公证/staple 对隔离 HIL 非必须；覆盖安装才走 `HIL-RELEASE-0.3`。

**当前不能直接走该门**：生产 `AhaKeyReleaseFeaturePolicy.current == .v0_2` 对所有协商态关闭 default/task picture 与 resource package，Studio 只显示「需 0.3 固件」。C1–C4 的正式页面路径在测试里靠 `picturesUnrestrictedForTests` / `allowsPictureResources: true`。签名安装 `30cfeb8` 原样仍无法用正式 UI 写图。本 HIL 卡禁止改业务代码。

## 三族执行顺序（待后续门）

1. **Gitee Rhino `53cd0a97` / HEX `ace7ab3e…` 最先**：上次已刷；若重连后探测仍是该族，本族矩阵不刷机。
2. **Local Rhino `00eb7efc` / HEX `7a49f365…`**：同族小增量，单独刷机 USER-GATE。
3. **GitHub Standard `3e7f900` / HEX `e5a336a6…` 最后**：无 `0x99`、PnP 与 Rhino 不同，风险最高；单独刷机 + EEPROM 备份/擦除 USER-GATE。

键盘 `0,0` 仍记为旧 Rhino 显示限制，不以它代替 Runtime 字节进度。

## 风险 / 回滚

| 风险 | 回滚 |
|---|---|
| 隔离 HIL 抢 Mach / 双 owner | bootout HIL，bootstrap 正式 362；HIL 现未加载 |
| 覆盖 `/Applications` | **本轮禁止**；回滚 zip 仅在以后 overlay 门制作 |
| 刷错 HEX（勿用污染的 `obj_final`） | 重刷 Gitee `ace7ab3e…` |
| EEPROM 擦除 | 擦前备份；现未擦、未读键盘 |
| 本地 WAL 残留失败事务 | 不在本 preflight 清理；正式写入前另报 |

## 结论与下一精确 USER-GATE

C5 非破坏 preflight 完成。停手。

**USER-GATE-C5-POLICY**：另开最小产品切片，把生产 `AhaKeyReleaseFeaturePolicy` 增加并切换到 `.v0_3`（或等价发布通道），使正式 Studio UI 在已登记旧固件上显示并可写图片面；不改 C2 assembler 决策、不改 C3 WAL/CAS/事务转移/BLE executor、不 overlay、不签名/安装、不刷机。切片 accepted 后再请求 **USER-GATE-C5-SIGN-HIL**：Developer ID 签名 `30cfeb8`（含策略切片）隔离 Runtime、唯一 owner、XPC，仍不覆盖 `/Applications`、不刷机、不擦 EEPROM、不断电。
