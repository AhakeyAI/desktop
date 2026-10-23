# WD-001 执行报告

只填实际发生的内容；本模板不是测试通过。

## 身份与范围
Receiver HEAD/dirty、起始和当前代码指纹、Contract revision；迁入哪些实现、保留什么。

Role: DIB. Task: WD-001. Contract revision: 1. Preflight passed before implementation.

Implemented only the approved CP3A Windows sleep wait time integration. Firmware and eternal were not modified.

## 实际差异
文件与行为映射、为何在 scope 内；未解决依赖/发现的范围冲突。

- `src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java`: added `0x95` command constant plus query/set frame builders for supported values `0/30/60/120`.
- `src/main/java/com/example/ahakey/protocol/AhaKeyResponseParser.java`: added sleep wait time response parsing.
- `src/main/java/com/example/ahakey/service/BleManager.java`: added read and set-then-query-verify APIs. Save path sends `0x95` set, waits for `0x95`, then sends `0x95` query and checks readback.
- `src/main/java/com/example/ahakey/view/TopBar.java`: added the minimal control inside the existing device info card in the More dialog.
- `src/main/resources/messages_zh.properties` and `src/main/resources/messages_en.properties`: added UI strings.

No scope expansion was needed. The new sleep wait time path does not send `0x04 save_config`.

## 已执行机器检查
每条真实命令、运行环境、退出码、输出路径及覆盖/限制。未运行明确写未运行。

- `python .agents/skills/ahakey-desktop-harness/scripts/desktop.py preflight --role DIB --id WD-001`: PASS.
- `$env:JAVA_HOME='D:\jdk-17.0.19.10-hotspot'; $env:Path="$env:JAVA_HOME\bin;$env:Path"; mvn -q -DskipTests compile`: PASS, exit code 0.
- Static search over the six allowed paths checked `0x95` usage, UI placement, and absence of `saveConfig()` in the sleep wait time save path: PASS.

Evidence:
- `.ahakey-desktop-harness/evidence/WD-001-machine-compile.md`
- `.ahakey-desktop-harness/evidence/WD-001-static-regression.md`

## 实际可运行产物
构建生成的确切路径/哈希/启动要求；还没有则明确说明，不能捏造。

No runnable product package was created in this DIB pass. The approved machine check was Java compilation only.

## 交给 DLA
当前风险、回归、待真机项、相关遗留；没有 owner_uat/review 自批。

Ready for DLA review.

Pending outside DIB:
- DLA review.
- Real device / Owner UAT against the specified CP3A HEX.
- Illegal-value protocol test is not exposed in normal UI because UI only offers legal values.
