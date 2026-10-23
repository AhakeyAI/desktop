# WD-005 R9 fresh 接入与候选准备结果

日期：2026-10-21；原 DLA。仅治理记录，没有生产/测试/固件/桥接代码或 Git 写入。

## 已完成

1. 读取独立审阅 JSON/中文分析，核对独立对话 `01a15d3c-8934-7e80-9b05-51a92fb8c518` 确已完成。其 audit-run 是 `wd005-r9-fresh-661dbf42-aca6-4120-80a3-c7eab9e3f37a`，两种标识分别保留。
2. fresh JSON SHA256=`211f858fd4bee2a52f86ae48e043fa1bab54ce16b0c24c7fd2512d87aba9c676`；canonical pack=`79b4a6d87283e22acae6b537a106a9007f426caf06fb5fcda57b15ea49074087`。35个逐文件分析/当前after匹配，22份证据哈希匹配，独立记录中的protected_baseline全部匹配。
3. 新增 `FORMAL_REVIEW_R9_20261021.json` 承接原DLA审阅并绑定fresh。没有覆盖根REVIEW、原actual review或fresh。新文件SHA256=`77f8b6efcb00badba83f3df0b8dbd200db671de1f9bd1955ba3f4335cea32049`。
4. 正式 `record-check --check review --status pass` 成功，verification.review=pass。STATE由工具转为VERIFY/CANDIDATE_PREP、next_actor=DLA、revision=87。其余real_device/owner_uat保持pending；Preview PASS未升级为UAT。
5. 固件HEX仍为FFB920修复包：`ffb9208f79084aa24a832ad2562a14dbbea5df4d114a135cb5b2eb98d4e05539`。正式CP2 gate原始SHA仍为`bf6efc5ac8380b6420c4ded17492b4bc798cad46072699c38ede41945fb5dbaa`。

Windows源码指纹仍为`98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9`；有效批准记录仍为`5ca53dc27d3bb53b05e7b48932f7a39b8db387fb730f112fa6e6c031e69ec6cf`。当前外部工作区漂移不使新固件自动获得这份批准。

## 实际命令与失败保留

- 首次record-check将fresh JSON也作为并列review evidence传入，工具把每个JSON都当完整DLA主报告校验，退出1：`Review must explicitly pass as DLA`。没有登记PASS或修改路由。随后只传完整FORMAL_REVIEW JSON与fresh中文分析；主报告通过fresh_review_record引用独立JSON，正式命令退出0。未修改规则或独立文件来迎合校验。
- 第一次candidate-plan退出1：三份`.rollback-backups/20261010T084508`恢复资料未有candidate-preserve登记，被列为未提交范围外输入。
- 按已存在的RECOVERY_EVIDENCE、20261015维护Owner授权和任务原隔离记录，通过正式candidate-preserve-foreign精确登记status-before.txt、tracked-worktree.patch、untracked-before.txt。三者SHA与原start一致，原件和内容副本保留；未忽略整个目录、未扩展allowed_paths、未提交恢复资料。
- 再次candidate-plan退出1：`Pinned reference changed/missing: CP2-UPLOAD; DLA reconcile before using old approval`。没有生成CANDIDATE_GIT_PLAN.ps1，没有候选、暂存或commit。

## 新阻塞：引用读取了变化中的固件工作区

在正式review登记通过之后的候选准备期间，固件工作区出现实际源码改动。初次报CP2-UPLOAD；随后完整12项引用检查观察到3项漂移、9项匹配：

| 引用 | 固件相对路径 | 原批准SHA256 |
| --- | --- | --- |
| CP2-PROTOCOL | APP/sub_main/command_solve.c | 968a72e823343a00ed2d82739d0faba4f1a72ac66322e5cb416b17c97c5d9dc0 |
| CP2-UPLOAD | APP/services/resource_upload_transaction.c | 3707922380c827fd0160185935faa4b8d4b0539959fb71b11a9d0763c54d6887 |
| CP2-COMMAND-HEADER | APP/sub_main/command_solve.h | d60fb7a5d6732eff46f4229cb7d09f5d3c4afe73f550efe0ac238c8443cd39eb |

08:30:12 UTC时工作区SHA：command_solve.c=`62eda392d9a668507118b068668ee5462b8bd624ecde5d21274c5c6ae7df8a77`；upload=`0c33c05b983bc290324a0501b2c1eabd31f610348b095f768515dd7e902f168f`；header=`9f0124ef969c5818385908ae1a59db2a37dc75e2ca364cc158353003eb3b9075`。工作区持续开发，这些是观察快照，不是建议追随的新批准目标。

只读git diff显示：新增resource_flash_writer状态机/延迟Chunk ACK/Flash忙准入；upload检查write回调失败；header新增command_external_flash_busy和command_storage_tick声明。这是实质代码变化，不能只更新哈希或宣称与已测固件等价。

REFERENCES记录commit为08dd24a6e8ce3526fef36661f5c97940add98a25；已测修复HEX候选为70ca334f65d73b6a2f20a0598e55c6da59f26526。两提交上述三文件Git blob内容相同，原批准字节存在换行形态差异：
- upload Git blob原始SHA与批准完全相同。
- command_solve.c Git blob原始SHA=4623ffe1f7d752a74dfd535b19af18ca2324222f5dde889dc7a61ea441aa2756，转换为CRLF后的SHA精确匹配原批准。
- header Git blob原始SHA=96a24abae870ffb31d0c086538379a0b9f487f1f3cb6ddb1e4fb895b617fd5bf。原工作区是43个CRLF和24个裸LF的混合换行，不能用全LF/全CRLF的hash直接冒称原字节匹配。只在内存移除当前diff新增的两条声明后，重建候选SHA精确为原批准d60fb7...，且归一LF内容与两固定commit一致。未写回固件或制造原始证据。

`desktop.py reference_inputs`仅按external_root/path读取当前工作区并比较SHA；revision_or_commit为必填元信息，但未用该commit取Git blob。因此固定历史配对会受后续开发工作区影响。当前helper未提供只切换为原commit读取且保持原批准身份的正式窄协调接口。

## 下一步边界

建议独立Harness维护评估“固定commit + 文件路径 + 明确字节/换行证据”的只读引用验证，保持原批准、start、pack/fresh及源码身份。必须获得Owner专项授权并走独立维护审阅；此记录不授权改规则/seal。不得伪造hash相等、静默把当前工作区改动当已批准内容，或用临时替换local固件根绕过验证。

不建议把REFERENCES直接追到最新工作区后重开产品轮次：这会把未交付的新固件混入刚测试的配对，并使当前审阅绑定失效。也不允许回退固件别人的工作。

恢复合法引用验证后再candidate-plan并审查清单。特别注意：closure_assets只递归根REVIEW的fresh指针，而本轮根REVIEW按要求保留原文；精确候选清单应额外包含FORMAL_REVIEW所引用的独立fresh JSON，不能只保存主报告/MD而漏掉机器可读依赖。可通过精确补充清单处理，不为此改历史REVIEW。

正式build/delivery、A01-A11与增量覆盖、BLE/故障/持久化缺口和最终archive/close仍分别完成。没有将风险观察升级成已确认功能故障，也没有自动豁免未覆盖项。
