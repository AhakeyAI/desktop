# WD-005 固定引用维护与候选准备结果

日期：2026-10-21。DLA 接续 Owner 专项授权，未执行产品、固件、桥接或 Git 写入。

## 维护完成

- 独立维护包：`.ahakey-desktop-harness/maintenance/pinned-reference-hf01`。
- 25项隔离维护测试实际通过；两次沙箱权限失败原日志保留。这不是产品656项重跑，也不是硬件测试。
- 独立审阅者：`01a15daf-a2dc-77f2-acd2-7702fda66b45`，结论PASS。REVIEW.json SHA256=`c741a581b3d7ba4566d0bec91a853690d9d203b83e206c37f0ec22fd506bc3e6`，绑定19项精确工件。
- 受控安装于2026-10-21T09:11:27+00:00完成，原helper/seal有原字节备份及INSTALL_RECEIPT。更新3个运行工件及正式印章；没有手改路由。安装前后5086项既有任务文件及产品指纹一致。
- 九个已批准源码引用固定到原提交`08dd24a6e8ce3526fef36661f5c97940add98a25`，原始批准SHA与固定Git blob分别验证，只容许精确绑定的CRLF/LF字节等价。三个未映射gate引用仍按原路径原SHA检查。不追随固件工作区新功能，不修改REFERENCES、批准、pack或fresh。
- Windows指纹仍为`98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9`。已测JAR仍为`97a5ae072c18a0ed229538fee7766426bd9f6c8ba807607aee10f141efa3052b`，HEX仍为`ffb9208f79084aa24a832ad2562a14dbbea5df4d114a135cb5b2eb98d4e05539`。

## 正式接续结果

`desktop.py candidate-plan --id WD-005 --role DLA`退出0，生成原44项计划。
工具将STATE推进为VERIFY/CANDIDATE_GIT、revision88、next_actor=Owner、GIT_SAVE。
随后guard-status确认immutable origin/scope/governance、builder submission、actual DLA review均PASS。原固件引用漂移阻塞已解除。

原生成计划未自动包含FORMAL_REVIEW间接引用的fresh JSON，不能据此省略。
新增 `CANDIDATE_REVIEWED_PLAN.ps1` 与 `CANDIDATE_REVIEWED_INPUTS.json`：原44项加9项精确记录，共53项，其中生产/测试18项；其余代码已在原HEAD保存。九项为当前change/verification、固定PACK/fresh JSON、第9轮报告/检查表/隔离说明、原DLA实际审阅JSON/MD。
已解析PowerShell语法、逐项核对53个SHA、核对全部不受gitignore排除。清单不含桥接、本机config_server、旧恢复备份或全目录暂存。脚本先检查HEAD和空索引及全部输入哈希，随后仅暂存精确路径并展示统计，不自动commit/push。脚本未执行。
Harness窄维护工件/安装备份在本地保留，不能宣称已经Git存档；后续结果归档阶段另列精确治理存档清单，不把它混成WD-005生产改动。原本忽略的日志/印章不通过全目录force-add纳入候选。

## 后续门禁

1. Owner审查53项清单并执行候选提交，或明确授权Agent执行这一精确Git写入。当前授权未覆盖Git写入。
2. DLA核对真实HEAD与提交差异，创建真实Owner commit evidence，运行candidate-check。源代码savepoint不能代替候选。
3. 正式产物回执、test_packet、交付配置、固件准入、A01-A11及增量覆盖/Owner结果仍未完成。优先复用适用真实证据，只列新差额；不把Preview回执改名，不自动将Preview PASS视为正式UAT，不无理由重测整套。
4. BLE桥接源码到现场EXE绑定及性能、上传故障注入/历史根因、RT-03外部闭环、持久化/完整UI等范围按原合同和真实反馈分层收口；本轮没有自动豁免。
5. 完成适用门禁后archive-plan、Owner结果存档、archive-check、close。维护通过不是WD-005已CLOSED。
