---
name: ahakey-desktop-harness
description: Local AhaKey Windows 0.4 guarded delivery — preserve Owner dispatch, immutable scope baseline, DLA actual review, Git candidate, version-paired test and history.
---
# Harness 0.4.0-guarded-delivery
适用于官网Windows Java接收仓，不安装/执行在eternal或Firmware。版本与STATE以本地为准。
入口：`.ahakey-desktop-harness/RULES.md`、`OPERATING_MODE.md`、`GUARDED_DELIVERY.md`、`STATE.json`、`local.json`。
helpers在本Skill的`scripts/desktop.py`与`guardrails.py`。只写Windows Harness记录；Git只读；不运行产品/固件构建、应用、设备、安装或Git写动作。
`doctor/status/validate`检查结构，不证明实际测试。`guard-status --id`列交付缺口，PENDING不是安装失败。命令参数以--help为准，不编造。
两个阶段、两个长期对话、一个活跃实现；新任务Owner指派；六项收尾与接力Prompt始终保留。
升级后的在途任务先读`prompts/START_V04_DLA.md`，不套用旧版“升级必须无任务”流程。任务原始start和批准不能为升级或恢复重写。
规则/校验问题记录HARNESS_FEEDBACK，不准Agent自行降低标准。正式改进用Owner批准的独立Harness升级。
