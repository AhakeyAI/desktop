# WD-003 执行报告

只填实际发生的内容；本模板不是测试通过。

## 身份与范围
Receiver HEAD/dirty、起始和当前代码指纹、Contract revision；迁入哪些实现、保留什么。
## 实际差异
文件与行为映射、为何在 scope 内；未解决依赖/发现的范围冲突。
## 已执行机器检查
每条真实命令、运行环境、退出码、输出路径及覆盖/限制。未运行明确写未运行。
## 实际可运行产物
构建生成的确切路径/哈希/启动要求；还没有则明确说明，不能捏造。
## 交给 DLA
当前风险、回归、待真机项、相关遗留；没有 owner_uat/review 自批。


## v1.0 交付约束
遵循GUARDED_DELIVERY：原始起点不可重置；实际diff审阅；候选Git与产物绑定；结果与遗留存档。模板不代表通过，不自动Git写。

## 2026-10-05 DIB IMPLEMENT continuation after revision 3

身份与范围：
- 本轮角色为 DIB，模式为 IMPLEMENT。
- 已执行 `python .agents\skills\ahakey-desktop-harness\scripts\desktop.py preflight --role DIB --id WD-003`，结果 PASS。
- 生产改动仅限 WD-003 allowed_paths 内的 Java 文件：`StudioController.java`, `AhaKeyProtocol.java`, `AhaKeyResponseParser.java`, `BleManager.java`, `DeviceSyncService.java`, `StudioState.java`, `InspectorPane.java`。
- 未执行 Git add/commit/push，未构建安装包，未运行设备写入/烧录。

实际差异：
- `0x9F` catalog key allowlist 增加 CP4C 判断，仅 `x1-c582-hw1-p1-1.0.0-r001` 启用 CP4C 输入配置域。
- 新增 `0x87` 普通键 readback builder/parser/BLE transaction；请求一次只读一个 `mode + key_index`。
- 新增 `0x97` 侧拨配置 read/write parser/BLE transaction；读写只用于侧拨配置。
- 连接/重连读取到 CP4C catalog 后启动输入配置 readback：先读 `0x97`，再读当前 mode 4 个普通键，随后后台读剩余 mode。
- 保存仍使用现有统一 Save/Apply 入口；普通键保留现有 `0x73` + `0x04` 写入路径，写完后用 `0x87` 回读比较；侧拨脏草稿通过统一保存触发 `0x97` 写入，再用 `0x97` 回读比较。
- readback/write/compare 失败时不会清除未保存草稿，会设置 Inspector/同步状态提示，并记录 `CP4C_INPUT_FAILURE catalogKey cmd mode keyIndex phase reason` 结构化日志。
- 旧固件或非 allowlist catalog 保持 legacy 路径，不启用 `0x87`，Inspector 继续显示传统侧拨 Auto/Manual。
- 未使用 `0x98` 做普通键 readback。

已执行机器检查：
- `mvn -q -DskipTests compile`：退出码 1；默认 Maven/JAVA_HOME 指向低版本 Java，失败原因是 `无效的目标发行版: 17`，未作为代码失败记录。
- `java -version`：显示 `openjdk version "17.0.19"`；`where.exe java` 显示 `D:\jdk-17.0.19.10-hotspot\bin\java.exe` 可用。
- `$env:JAVA_HOME='D:\jdk-17.0.19.10-hotspot'; $env:Path="$env:JAVA_HOME\bin;$env:Path"; mvn -q -DskipTests compile`：退出码 0，编译通过。
- `rg -n "0x98|CMD_TASK_LIGHT_MODE|CMD_ORDINARY_KEY_READBACK|CMD_SIDE_SWITCH_CONFIG|isCp4cCatalogKey|readOrdinaryKeyConfig|readSideSwitchConfig|writeSideSwitchConfig" src\main\java\com\example\ahakey`：确认新增读回调用集中在 `0x87/0x97`，无生产 Java 中 `0x98` 普通键 readback 调用。

实际可运行产物：
- 本轮未打包 JAR/EXE，未生成交测产物。

交给 DLA：
- 需要 DLA actual diff review，且因 WD-003 为 protocol_change/high_impact，仍需后续正式审阅与真机/Owner UAT。
- 未做真实设备连接、未验证 CP4C 固件实际响应、未验证旧固件实机 fallback。
- Inspector 第一版支持 CP4C 侧拨 factory/disabled 组合编辑；已读到的 custom 侧拨会显示“自定义（保留）”，本轮未新增自定义 action 编辑器。

## 2026-10-06 DIB FIX after DLA review fail

身份与范围：
- 本轮角色为 DIB，模式为 FIX，修复依据为 `.ahakey-desktop-harness/changes/WD-003/REVIEW.json`。
- 已重新执行 `python .agents\skills\ahakey-desktop-harness\scripts\desktop.py preflight --role DIB --id WD-003`，结果 PASS。
- 生产修复只落在 WD-003 allowed_paths 内：`StudioState.java`、`DeviceSyncService.java`、`InspectorPane.java`。仓内仍保留上一轮 WD-003 的其他 allowed_paths 生产改动，未新增 allowed_paths 外生产文件。
- 未执行 Git add/commit/push，未构建 JAR/EXE，未安装，未做设备写入、烧录或 Owner UAT。

实际修复：
- 修复 DLA P1：CP4C 连接/重连读回与状态提示不再推进用户草稿 `revision`。`StudioState` 新增独立的 `inputBaselineRevision` 供 UI 观察设备基线变化，`revision` 继续只代表用户草稿/保存相关变化，避免被动 `0x9F/0x97/0x87` 读回制造假未保存变更。
- 修复 DLA P2：`InspectorPane` 现在监听 `cp4cInputConfigEnabledProperty()` 和 `inputBaselineRevisionProperty()`；侧拨 Inspector 已打开时，`0x9F` 识别 CP4C 后会重建为 CP4C `0x97` 表单，读回基线变化也会刷新显示。
- 修复 DLA P1：CP4C 侧拨新增 `自定义快捷键` 与 `自定义宏` 轻量编辑入口。`DeviceSyncService.encodeKeyActionPayload()` 继续复用普通键快捷键/宏 payload 编码，侧拨通过现有 `0x97` action payload 字段保存，不新增协议字段、不改 `0x97` 语义。
- 侧拨 Custom 组合保持在原合同内：Custom 只能与 Disabled 或另一个 Custom 共存；从 Custom 切回 Auto/Manual 时继续按 factory complement 规则更新另一侧。
- 保留原有通过点：CP4C 能力仍由 `0x9F` catalog key allowlist 控制；普通键 readback 仍只用 `0x87`；侧拨仍只用 `0x97`；未引入 `0x98` 普通键 readback；保存仍走统一 Save/Apply。

已执行机器检查：
- `$env:JAVA_HOME='D:\jdk-17.0.19.10-hotspot'; $env:Path="$env:JAVA_HOME\bin;$env:Path"; mvn -q -DskipTests compile`：退出码 0。日志：`.ahakey-desktop-harness/evidence/WD-003-fix-round4-jdk17-compile-20261006.log`。
- `rg -n '0x98|CMD_.*98|ORDINARY.*98|readback.*98|98.*readback' src\main\java`：实际 `rg` 退出码 1，表示没有匹配；包装命令按“无匹配为通过”返回 0。日志：`.ahakey-desktop-harness/evidence/WD-003-fix-round4-no-0x98-grep-20261006.log`。

未执行与限制：
- 未运行真机、mock device 或 Owner UAT；CP4C 固件实际响应、旧固件 fallback、读回失败 UI 仍需后续 DLA/Owner 测试流程覆盖。
- 未生成可运行交测产物；没有 BUILD_RECEIPT、test_packet、Git candidate。
- 本轮 compile 是机器检查补充，不是行为测试、真机 PASS 或发布。

交给 DLA：
- 请重新执行 actual diff review。WD-003 仍是 `protocol_change/high_impact`，review pass 后仍需按 Harness 补后续候选、构建/预览、真机和 Owner UAT 流程。

## 2026-10-06 DIB IMPLEMENT after Owner Preview FAIL scope reconcile

身份与范围：
- 本轮角色为 DIB，模式为 IMPLEMENT，修复依据为 Owner Preview FAIL 证据 `.ahakey-desktop-harness/evidence/20261006T110555_wd003_owner_preview_usb_hid_interface_fail.md` 与 Owner scope approval `.ahakey-desktop-harness/evidence/20261006T110555_wd003_usbhidtransport_scope_owner_approval.md`。
- 已执行 `python .agents\skills\ahakey-desktop-harness\scripts\desktop.py preflight --role DIB --id WD-003`，结果 PASS。
- 生产修复只落在 WD-003 allowed_paths 内的 `src/main/java/com/example/ahakey/service/UsbHidTransport.java`。
- 未执行 Git add/commit/push/reset/clean/stash，未构建安装包，未安装，未 kill 进程，未做设备写入、烧录或 Owner UAT。

实际修复：
- `UsbHidTransport.findDevicePath()` 对 AhaKey VID `413c` / PID `2107` 只接受包含 `mi_01` 的 HID path 作为 USB vendor/config 通道。
- 移除原先 `(mi_01 || col02)` 的选择条件，避免把 `mi_00&col02` 键盘/Consumer collection 当作配置接口。
- 移除找不到 `mi_01` 时退回任意同 VID/PID path 的行为；如果发现 AhaKey 设备但没有 `mi_01`，记录 warning 并返回未找到配置通道。
- 未修改 `0x9F`、`0x95`、`0x97`、`0x87` 协议语义，未引入 `0x98` 普通键 readback。

已执行机器检查：
- `$env:JAVA_HOME='D:\jdk-17.0.19.10-hotspot'; $env:Path="$env:JAVA_HOME\bin;$env:Path"; mvn -q -DskipTests compile`：退出码 0。日志：`.ahakey-desktop-harness/evidence/20261006_wd003_usbhid_mi01_compile.log`。
- `rg -n "mi_01|col02|vid_413c|pid_2107|findDevicePath" src\main\java\com\example\ahakey\service\UsbHidTransport.java`：确认筛选只以 `mi_01` 作为配置接口匹配；`col02` 不再作为选择条件出现。日志：`.ahakey-desktop-harness/evidence/20261006_wd003_usbhid_mi01_static_grep.log`。
- `rg -n "0x98|CMD_.*98|ORDINARY.*98|readback.*98|98.*readback" src\main\java`：实际 `rg` 退出码 1，表示没有匹配；包装命令按“无匹配为通过”返回 0。日志同上。

未执行与限制：
- 未连接真实设备验证 `0x9F`、`0x95`、`0x97`、`0x87` 是否已通过 `mi_01` 正常收发；需后续 DLA review / Preview rebuild / Owner Preview 覆盖。
- 未生成新的 Preview/JAR/EXE 交测产物；本轮仅完成源代码修复与机器检查。

交给 DLA：
- 请对本轮 `UsbHidTransport.java` 实际 diff 做 DLA review。若 review pass，按 Preview fast lane 重新开启 Preview build 给 Owner 复测；这仍不是 formal Owner UAT PASS。
## 2026-10-07 DIB IMPLEMENT revalidation after Contract/reference reconcile

Identity and scope:
- This round is DIB / IMPLEMENT / REVALIDATE_AFTER_REFERENCE_RECONCILE for WD-003 build_round 9.
- DLA completed Contract/reference reconcile and moved the task to revision 8 / build_round 9.
- This round made no production Java changes and no Firmware changes.
- This round did not run Git add/commit/push/reset/clean/stash/checkout/restore.
- This round did not build an installer, install software, connect to a device, write to a device, burn firmware, run formal Owner UAT, release, or publish.

Reason:
- The previous DIB submission was bound to build_round 8 and the previous effective approval SHA.
- DLA needs a current build_round 9 implementation identity before doing a new actual diff review.
- The existing Windows implementation that passed Owner Preview is preserved.

Machine checks:
- Evidence log: `.ahakey-desktop-harness/evidence/20261007T1732_wd003_build_round9_revalidate_checks.log`.
- JDK17 Maven compile with `-DskipTests compile`: exit code 0.
- Static check found no `0x98` ordinary-key readback use in Windows Java sources.
- Static check found no `mi_00` / `col02` USB configuration-channel fallback in `UsbHidTransport.java`.
- Static CP4D / CP4C anchors were present: `CMD_ORDINARY_KEY_READBACK`, `parseOrdinaryKeyReadback`, `readOrdinaryKeyConfig`, `readSideSwitchConfig`, `writeSideSwitchConfig`, and `ORDINARY_KEY_READBACK_FRAME_MAX`.

Limitations:
- Compile is a machine check, not behavior validation.
- DIB did not run real-device USB/BLE tests.
- DIB did not run mock HID/BLE device tests.
- DIB did not perform formal high-impact fresh review.
- Owner Preview PASS remains preview-only and is not formal Owner UAT.

Handoff to DLA:
- Please run build_round 9 actual diff review against the current effective Contract and approval.
- If DLA review passes, WD-003 still requires high-impact independent fresh review, Git candidate, formal artifact identity, Firmware identity, formal Owner UAT, and the remaining formal delivery records before closure.
