# 日常入口
先读适用AGENTS、当前角色Skill、RULES、GUARDED_DELIVERY、STATE、任务change.json/Contract/REFERENCES/verification与最新交接。
- 安装和结构：`python .agents/skills/ahakey-desktop-harness/scripts/desktop.py doctor`，`status`，`validate`。
- 本任务交付缺口：`... desktop.py guard-status --id WD-001`。这是清单；PENDING是尚未完成，不是自动授权或假PASS。
- DLA审阅：`review-pack --id WD-001 --role DLA`，查看输出实际diff，填写本项REVIEW.json，再用原`record-check --check review`附JSON和必要Markdown。
- Git：`candidate-plan`只生成需Owner审核的精确暂存计划；不自动执行。Owner提交后`candidate-check --commit HEAD --owner-record <实际Owner记录>`。
- 可运行产物：DIB按已授权范围`build-open`，运行核验过的构建命令，`build-finish`列全runtime目录/依赖、日志和入口。详见GUARDED_DELIVERY。
- 交测：完成OWNER_TEST.md/JSON、Firmware身份JSON，`request-test`；Owner反馈后如实record-check real_device/owner_uat，失败request-fix。
- 收口：archive-plan / Owner存档 / archive-check / close；结束WAIT_OWNER_TASK。
不需要每轮read-only调查new任务或Git。模板不是完成记录。CLI帮助是参数合同：`... desktop.py <command> --help`。
