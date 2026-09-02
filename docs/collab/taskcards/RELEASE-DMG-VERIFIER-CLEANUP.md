# 任务卡 RELEASE-DMG-VERIFIER-CLEANUP：DMG verifier 失败路径卸载收口

计划/WBS：release tooling hygiene
状态：`ready / implementation`
执行 owner：Cursor（Codex 验收）
基线：`1c024c5`

## 问题

`verify-release-dmg.sh` 对合法候选的成功路径能正常 detach，但验证失败时的 cleanup 使用 `hdiutil detach ... || true`，且不校验挂载终态。Swift 负向 DMG fixture 因此留下多个只读挂载。该问题不影响 v0.2.1 build 360 候选身份，但必须在下一次候选重冻结前修复。

## 允许范围

- `ahakeyconfig-mac/scripts/verify-release-dmg.sh`
- 对应 packaging script tests
- 本卡、queue 与 append-only board 记录

## 完成定义

1. 成功和失败路径共用一个幂等 cleanup，detach 失败不得被静默吞掉；保留原始验证错误同时记录 cleanup 错误。
2. 真实空/缺 companion DMG 负向案前后，`hdiutil info`/挂载集合完全一致，临时 mountpoint 不存在；连续运行两次仍一致。
3. 正向 Developer ID DMG verifier 仍通过且 detach 终态可见。
4. 只卸载确认属于 `ahakey-dmg-verify.*` 测试 fixture 的历史挂载，记录前后清单；不卸载其它磁盘。
5. packaging 定向测试、全量 Swift、Release build 与 `git diff --check` 通过。

## 禁止

- 不修改已公证 v0.2.1 build 360 DMG，不重冻结候选。
- 不安装、不刷固件、不 reboot/logout、不 push。

## 执行记录（append-only）

### [2026-09-02 10:51] Codex：建卡，排在 v0.2.1 Gate-1 之后

- Gate-0 终裁确认候选成功路径不泄漏挂载；本卡仅收口失败路径和历史测试 fixture 卫生。
- 本卡不阻断 build 360 Gate-1，但阻断下一次 DMG 候选重冻结。

### [2026-09-02 17:01] Codex：V021 R1 产品 accepted，本卡开放 implementation

- `V021-BLE-WAKE-RECOVERY` 产品 `88e02aa` accepted。本卡现在是 Cursor 唯一 ready 卡。
- 只修 `verify-release-dmg.sh` 失败路径 detach 与负向 fixture 卫生；不改已公证 360 DMG，不覆盖安装，不打 361，不刷机，不 push。
- 需要回复：是（@Cursor ACK 后仅执行本卡）
