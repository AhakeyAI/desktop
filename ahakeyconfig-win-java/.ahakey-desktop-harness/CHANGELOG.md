## 1.3.0
- 修复 v1.2 governance snapshot 漏掉 OWNER_PREVIEW/EVIDENCE_STREAMS/PRESERVED_FOREIGN 导致的假 PROTECTED_GOVERNANCE_CHANGED。
- 新增 Preview defect fast loop：preview-request-fix / preview-fix-submit / preview-fix-review；原 Contract 内小 Bug 不重走 Product Grill、Fresh Review、Formal Candidate。
- Preview FIX 使用独立 evidence stream，不回写 frozen EXECUTION_REPORT。
- Preview 可反复 build/test；Preview 稳定后再统一 formal candidate/build/UAT。
- 取消按时间定期进度要求，仅事件型汇报。

# v0.2.0-pilot 相对 v0.1-alpha1

继承：Java Preserve First、DLA/DIB、一次Baseline+两个日常阶段、UI Placement、跨端交接、八份历史代码调查。

改为：Grill贯穿Contract；真实局部预览先于入口批准；产品以后台、配置排障为主；固件工作区整体只读；共享协议按版本只读引用固件侧，不用旧Desktop快照充当正式定义；明确旧版兼容/未知状态；两个本地文档协作的固定对话；单活跃实现；DIB连续执行；mock/真机分别记；核心旅程先团队确认、相关证据渐进补齐。

工程实现：补齐三份Skill的name/description front matter与显式调用元数据；状态使用标准库JSON；加入默认预检、白名单/哈希校验/冲突备份的安装器；不自动Git提交；保留活动记录；批准输入指纹与单活跃检查；首轮Prompt明确只做DLA调查。没有引入新产品代码/框架/协议。

旧八份调查原文中的软件版本、类名、命令和视觉顺序都是待复核线索；没有宣称本地线上源码/真机已通过。历史canonical快照仅在legacy目录保留。旧pycache不再打包。

<!-- AHAKEY-V03-CHANGELOG:BEGIN -->
## 0.3.0-owner-driven / 2026-09-27
- Owner 指派驱动；无任务 WAIT_OWNER_TASK，迁移清单不自动执行。
- 全局产品基线门禁改为任务级范围/现有行为保护，不自动修改 baseline 的批准值。
- UI 分为 none / existing / minimal / formal；简化联调入口，不削弱协议与真实测试。
- 三工作区只读/写边界；双对话、本地交接、单一活跃实现。
- 新增 Owner 指派、只读调查状态、最小范围批准即激活、按构建/固件身份测试及收尾等待。
- 脚本核验文件哈希、证据新鲜度和生产改动范围；不能验证身份/测试真实性或提供 OS 隔离。
- 0.2 原地升级：默认预检、全 Harness 备份、运行数据保留、空闲路由迁移、冲突停止、受保护回滚。
<!-- AHAKEY-V03-CHANGELOG:END -->

<!-- AHAKEY-V04-CHANGELOG:BEGIN -->
## 0.4.0-guarded-delivery
支持显式指定已submit活跃任务的原地升级；原起点/记录保留；实际diff与结构化review、Git候选和存档、运行产物manifest、固件配对、追加式历史与pause/resume保护。schema4仅状态层升级；现有change schema2与批准签名输入不变。
<!-- AHAKEY-V04-CHANGELOG:END -->


## 0.5.0-distribution-handoff
新增发行观察、正式Firmware Gate补充、验收映射、中文Owner简报、逐步骤真实结果和Owner驱动双版批次；保留HF01路径规范化和v0.4审阅/Git/原始基线。升级保留在途OWNER_TEST，不回放初始化、不修改产物。

## 1.0.0
- Unified CHANGE→IMPLEMENT→VERIFY runtime gates; Journey/classification/high-impact review; truthful fail evidence; launch recipe binding; Owner-selected release variants and batch reminder.


## 1.0.1
- Firmware-driven intake: DLA discovers formal Firmware gates/artifacts/protocol/tests from the bound read-only Firmware repo.
- Added Windows-side firmware sync cursor and planned intake evidence binding.
- Owner is no longer asked to manually transcribe local gate/HEX/SHA/protocol/test facts.
- Existing v1 task/history/recovery records remain preserved.


## 1.2.0
- 所有 Owner-facing 长叙述默认中文，owner_report 增加中文检查。
- 长任务增加约3–5分钟/关键节点中文进度更新规则与 progress renderer。
- DLA 明确承担 Firmware intake 后的 Windows Product/UX Grill，不允许仅因资料齐全直接跳 DIB。
- 新增 first-class `contract-reconcile`：保存 Contract revision history、重新绑定 effective approval/dispatch，并支持显式 Owner 授权的旧 guard-origin 引用修复。
- Contract reconcile 采用先校验后事务写入；取代会半写失败的临时 route 修复方式。
- Skill 卡片显示版本统一为 v1.2，不再显示 v0.5。


## 1.2.0
- 新增 Owner Preview Build/Test：DLA actual diff review pass 后可先出可测包，formal fresh review/candidate/delivery 并行继续。
- 新增 phase-scoped evidence：submit 冻结 IMPLEMENTATION_RECEIPT；BUILD_ONLY 改用独立 BUILD_REPORT/BUILD_RECEIPT，避免小 Markdown 追加让 review/candidate 反向 stale。
- 新增仓内 preserved foreign candidate 机制，历史 dirty 不再要求 Owner restore/stash/commit。
- candidate 成立后验证 immutable commit，不再要求当前 working-copy governance 文档永远等于 candidate 时字节。
- 移除“每 3–5 分钟”定时汇报要求，只保留 blocker/Owner决策/阶段切换/完成时汇报。
