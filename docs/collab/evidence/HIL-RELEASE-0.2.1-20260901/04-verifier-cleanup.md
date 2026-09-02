# RELEASE-DMG-VERIFIER-CLEANUP：失败路径 detach 收口（产品，非 HIL / 非 361）

日期：2026-09-02 17:59–18:06 +08
ACK Codex `718dd3a`。未 overlay `/Applications`、未改已公证 0.2.1 (360) DMG、未打 build 361、未 HIL、未刷机、未 push。

## 行为

- `verify-release-dmg.sh` 成功/失败路径共用 `shared_cleanup`：只 detach 本进程 `ahakey-dmg-verify.*` mountpoint，校验挂载消失后再 `rmdir`。
- `hdiutil detach` 失败不再 `>/dev/null 2>&1 || true`。验证失败时保留原 rc，并在 cleanup 也失败时打印 `cleanup error`。
- `--print-fixture-mounts` / `--detach-stale-fixtures` 只操作确认属于 `ahakey-dmg-verify.*` 的 fixture；系统卷与其它磁盘不动。

## 卫生

- 本机残留 **34** 个 `/private/tmp/ahakey-dmg-verify.*` 只读挂载（Swift `ahakey-verify-*.dmg` fixture，不是 360 候选）。清单 `raw/verifier-fixtures-before.txt`。
- `--detach-stale-fixtures` 后 fixture 挂载 **0**；另两枚 2026-09-01 空目录（未挂载）已 `rmdir`。系统卷仍在。终态 `raw/verifier-mounts-after-stale-detach.txt`。

## 正向 360

只读复跑既有候选，未修改文件：

- SHA-256 `9f109421531b196c9378abb2c0d2b1f5b52f62c902d6796ae37ee720610b46c3`
- `verify-release-dmg.sh --expect-developer-id` → `release dmg ok`，可见 `disk ejected` / `detached mountpoint:`
- 前后 `/sbin/mount` 一致，无 fixture 残留
- 记录 `raw/verifier-360-positive.txt`

## 门禁

- packaging 定向：`AhaKeyReleasePackagingScriptTests` **28 / 0 failures**（含空 DMG / 缺 companion 各跑两次、stale fixture 只卸本前缀、成功路径 detach 可见）。
- 全量 `swift test`：**737 tests / 2 skipped / 0 failures**。
- Release：`AhaKeyConfig` 与 `ahakeyconfig-agent` complete。
- 本卡 `git diff --check` 通过。

## 工作区既有 dirty（未纳入）

modified：`DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

verifier 失败路径与历史 fixture 卫生完成，停手提审。含 V021 的下一张候选 DMG（build >360）等 Codex accepted 本卡后再冻结；本机 360 不覆盖。
