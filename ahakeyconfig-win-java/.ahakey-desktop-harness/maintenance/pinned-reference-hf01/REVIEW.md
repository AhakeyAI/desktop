# WD-005 固定引用窄维护独立审阅

结论：**PASS，未发现阻断问题。** 本结论只针对下述精确维护工件，不是产品 UAT、安装回执、固件批准或新协议批准。

审阅日期：2026-10-21。
独立审阅 Agent ID：`01a15daf-a2dc-77f2-acd2-7702fda66b45`，来自本次执行环境的 `CODEX_THREAD_ID`。本轮角色为独立 Harness 窄维护审阅者，非产品 DIB。

## 授权与工件

已阅读根 AGENTS、Harness SKILL、route-hf01/PLAN 先例、本维护 PLAN 及 Owner 授权原话。审阅目标是保留批准与历史，固定读取 WD-005 已批准固件版本，不降低门禁。

已逐段审阅 prepare.py、候选 desktop.py 相对现运行版本的精确差异、pinned_references.py、精确清单、九份 approved-bytes、BASELINE、安装器、隔离用例及现有测试结果。REVIEW.json 的 files 绑定安装器 artifacts() 定义的全部 **19** 个文件及 SHA256；通过解析函数并独立读取哈希取得清单，没有执行安装器或测试模块。

## 实际分析

1. **精确差异与默认严格行为。** 完整字节比较确认 desktop.py 仅有 reference_inputs 的两个差异块。非 WD-005 返回空映射；WD-005 必须匹配 revision 5、approval canonical SHA、原 REFERENCES SHA、Owner SHA 和完整九条 reference。三个未映射引用 CP2-ARCH、CP2-EXECUTION、CP2-GATE 仍逐字节核验原路径 SHA；原字段、重复 ID、协议要求校验保留。
2. **固定身份链。** 九项均独立核对完整 commit `08dd24a6e8ce3526fef36661f5c97940add98a25`、literal path、普通文件模式、blob OID 和 SHA256。九份副本 SHA 全等于原 REFERENCES，且仅替换 CRLF 为 LF 后与原 blob 字节全等。不解码历史注释，不修剪空白，不接纳新内容。混合换行 header 明确为重建字节；即使 prepare.py 采用删除当前 header 两行的重建方法，也必须匹配原批准 SHA 和固定 blob 等价链。
3. **seal 与路径。** WD-005 解析前验证 policy。新 helper 和清单由现有 .agents 治理快照覆盖；副本虽不直接入 seal，但每次按被 seal 固定的原始 SHA 校验。缺清单、缺副本、缺对象、映射或批准变化均拒绝，不回退到工作区。child 拒绝链接/reparse/越界，Git tree 拒绝符号链接和子模块。
4. **受控安装。** 安装前精确绑定审阅工件、授权、旧 helper/seal、固定三个运行目标、生产指纹和保护文件；正式写锁内再次校验，先保存旧原字节，再逐文件原子写入。治理差异必须恰为三个运行目标；更新 seal 后继续校验 policy 和保护文件。try 内异常恢复原 helper/seal 并删除新增文件。不修改任务路由、批准、产品或固件。
5. **真实基线核对。** 当前 helper、seal、Owner 授权及原批准/REFERENCES 与记录匹配。BASELINE 的 5086 个保护文件全部匹配；按现运行规则独立计算的 94 个生产输入指纹仍为 `98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9`。seal 的 54 个既有条目哈希全部一致。两个新增运行目标均不存在，维护尚未安装。
6. **网络与 Git。** 候选 Git 调用只有 rev-parse、ls-tree、cat-file，不调用过滤器、hooks、checkout 或 fetch；环境禁用 optional locks、replace objects、lazy fetch 和终端提示。本机 Git 为 2.54.0.windows.1。本轮独立核对还显式禁用全部 Git 传输协议，只读固定固件对象，未做 Git 写入。

## 测试与限制

- 现有记录为 25 项隔离检查通过，0 failures、0 errors。日志 SHA256 独立核对为 `3e4402395762f52c55eb8678c71f048ed79cf9595d851537ce15d8721493cda4`。本轮未重跑测试，未改写日志和既有失败历史；范围外的两次历史失败日志未另行审阅。
- 解析隔离测试 mock policy/Git 读取，安装隔离测试 mock artifacts；已通过的故障用例证明其记录中的安装后异常恢复路径，不等于所有故障点或真实安装已验证。
- 安装是正式写锁下的逐文件原子替换加异常回滚，不是断电或强制终止条件下的跨文件原子事务。此类中断需依据原字节备份人工检查恢复，安装器不会盲目重试。
- 未运行安装器（包括 dry-run）、产品构建、应用、Hook、桥接、设备测试、烧录或发布。仅新增本目录 REVIEW.json 与 REVIEW.md；运行 .agents、seal、STATE、任务历史和候选实现均未修改。

## 下一步

由原 Harness 维护对话接收精确审阅工件，在原授权范围内处理受控安装。安装器必须重新通过全部前置门禁；任何漂移需停止并重新审阅，不重写旧批准、旧测试或产品历史。本审阅不替代后续原 DLA 的正式 candidate-plan、产品审阅或 UAT；Git 操作仍交 Owner。
