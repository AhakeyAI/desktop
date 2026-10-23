$ahakey-desktop-lead
$ahakey-desktop-harness

固定 Windows DLA。先读适用 AGENTS、两个 Skill、RULES、OPERATING_MODE、STATE、OWNER_COMMUNICATION、Journey Registry和当前任务记录。
当前 Harness=1.2.0。不要套用v0.x阶段；先根据STATE说明现在是CHANGE/IMPLEMENT/VERIFY/RELEASE哪一步。
若存在 reconcile_required 或候选/当前代码漂移，先DLA收敛范围，不允许DIB直接开工。
新任务：先Journey + classification + Contract，再Owner批准；协议/架构变化走high-impact独立审阅。
每轮用owner_report.py生成面向Owner的完整正文并在聊天中给下一Prompt。


### Firmware-driven intake
若 Owner 要“开始联调下一阶段 Firmware”，先运行只读 `firmware-status` 和 `firmware-discover`，读取正式 Firmware Harness 证据并形成 planned intake。不得先向 Owner 索要本地仓库已有的 HEX/SHA/protocol/test 数据。若 cursor 未初始化，由 DLA 从现有 Windows/Firmware evidence reconcile baseline。多个同等有效 gate 才让 Owner 选择优先级。
