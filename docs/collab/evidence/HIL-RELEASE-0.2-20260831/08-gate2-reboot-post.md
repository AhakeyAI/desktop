# HIL-RELEASE-0.2 Gate-2 重启 POST（2026-08-31 22:35 +08）

用户授权采集整机重启 POST。Codex Gate-2 same-session accepted @ `58c4d7f` / 证据 `c082ecd`。本轮不重做卸载或故障注入，不覆盖 `/Applications` 359，不刷机、不 push。

## 判定：POST 未发生

本机**没有**在 PRE（22:15）之后重启，因此不能把当前现场当作重启后保活证据。

| 项 | PRE（22:15） | 授权采集时（22:35） |
|---|---|---|
| `kern.boottime` | （当时 uptime 已是多日） | **Sat Aug 29 08:26:09 2026** |
| `uptime` | — | 2 days, 14:09 |
| `last reboot` | — | Sat Aug 29 08:26 |
| official Agent pid | **77220** | **77220**（未换 pid） |
| launchd `runs` | 1 | 1 |
| last exit | never exited | never exited |

Agent 仍是 Gate-2 重装后的同一进程。KeepAlive 同会话杀进程拉起已在 `07-gate2-keepalive-rollback-uninstall.md` 验收；那不是整机 reboot。

未执行 `reboot`/`shutdown`/`logout`（会打断 Cursor 与桌面）。未伪造 POST。

## 仍待用户重启后采集

重启并登录后应核对：0.2.0 (359)、App/Agent strict 签名、唯一 `lab.jawa.ahakeyconfig.agent` 且 pid ≠ 77220、HIL rc=113、XPC handshake+snapshot、登录项、plist `KeepAlive`+`RunAtLoad`、无 staging/backup。

原始：`raw/gate2-reboot-pre.txt`。本文件不把重启保活判绿。
