# WD-007 整体拒收并恢复 WD-006

Owner 于 2026-11-01 明确要求整体代码回退，并将 WD-007 全部验收不通过。授权原文见 ../../evidence/20261101-owner-reject-wd007-rollback-wd006.md。

结论：OWNER_REJECTED / owner_uat FAIL；正式 helper 已将 WD-007 suspend 为 PAUSED，根 STATE 进入 CHANGE / WAIT_OWNER_TASK，无活跃实现。PAUSED 是本版 Harness 可用的保存状态，不表示 Owner 接受或等待自动修复。没有调用 close 伪造验收通过，也不自动重启 WD-006。

产品代码目标为 9365911b2ea5cfa88203aa0985b7a6f2fadae38f。163 个当前产品文件逐字节匹配该 Git 快照；与原 R13 安装包构建输入 target/wd006-r13-source-1.0.12 比较也无实质差异（只存在 UTF-8 文本 CRLF/LF 差异）。31 个 WD-007 新增生产/测试/构建文件已在备份验证后移出当前产品目录。修改清单和哈希在 rollback-20261101/PLAN.json。

回退前 WD-007 当前代码已保存为本地调试提交 f5ad2893（Owner 拒收，不是稳定候选），另有 rollback-20261101/before 原字节备份。历史 R0–R6 实现、构建、审阅、失败证据保留；以前离线 PASS 不改写为未运行，本轮 FAIL 是 Owner 整体拒收，不声称所有真机用例逐项执行失败。

target 中旧 classes、test-classes、generated-sources、generated-test-sources、maven-status 与顶层 JAR 已移入 rollback-20261101/build-cache，避免后续增量编译混入 WD-007 类。未运行产品构建、应用、安装或设备操作。

原 WD006-R13-LocalModel-1.0.12 安装包未改，实测 SHA256 为 21de9ab7c4e5c5b915cbd92c7f0f3d62b003ef90f9df20ceb962b46ae0b36af7。用户 .ahakey、已安装软件、Hook 配置、Firmware、并列平台、旧安装包、Harness 核心及其他在途历史不回退。

备份暂存时 git diff --cached --check 在原始 ACTUAL_DIFF.txt 内报告 327 处历史空白；生产文件的同项检查为 0。未改写原始 diff 以消除告警，该原始输出保存在 rollback-20261101/savepoint-whitespace-check.log；调试保存并非质量通过。

后续以 WD-006 代码为起点。未来若要重新引入 WD-007 的某项改动，必须由 Owner 重新明确范围，不能自动恢复本次已拒收增量。旧版对 HW1/HW2 1.0.1 的限制也随真实回退恢复，没有暗中保留 R6 兼容补丁。
