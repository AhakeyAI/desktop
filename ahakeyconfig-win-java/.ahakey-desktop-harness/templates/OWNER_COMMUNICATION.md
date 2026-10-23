# Owner 交互与进度交付约定 — OI-02（v1.2）

这是所有 DLA / DIB / Harness 对 Owner 的强制交互规则。它不改变业务批准、代码权限或测试真相。

## 1. Owner-facing 默认语言：中文

- 所有面向 Owner 的自然语言说明、结论、风险、问题、建议、测试步骤和接力说明，默认必须使用中文。
- 允许保留英文/代码形式的：类名、函数名、协议名、路径、命令、SHA256、状态枚举、错误原文、文件名。
- 禁止“标题中文、正文大段英文”。如引用工具英文错误，先给中文解释，再附必要原文。
- `owner_report.py` 会对关键叙述字段执行中文内容检查；这只是结构检查，不证明事实正确。

## 2. 不要求定时心跳；只在有意义的节点汇报

- 不再要求“每 3–5 分钟”定时进度。Owner 不需要工作直播。
- 仅在以下情况主动插入简短中文更新：发现会改变下一步的 blocker、需要 Owner 决策、阶段发生切换、或本轮工作完成。
- 普通连续工具调用可安静完成；最终回复必须完整说明结果、缺口和下一步。
- `owner_report.py progress` 保留为可选工具，不是门禁，也不是强制节奏。

## 3. 每轮最终回复必须直接交付

1. **进度与结论**：第一屏用中文说明当前 CHANGE / IMPLEMENT / VERIFY / RELEASE 的位置、本轮结论、能否开工/测试。
2. **完成与缺口**：只写实际结果与影响，不用“读了很多文件”代替结论。
3. **Owner 行动**：分开写“产品/范围决策”“操作”“真实测试”。复制提示词/切换对话也算操作。
4. **下一步**：明确角色、对话、任务、模式、目标。普通同角色连续工作不要求 Owner 反复确认。
5. **完整接力 Prompt**：跨对话时必须在聊天正文完整展示；文件只归档，不能让 Owner 去文件末尾找。

## 4. DLA 的产品职责不能被 Firmware intake 代替

Firmware 仓解决“底层能力/协议/真实状态怎么工作”；Windows DLA 仍负责桌面端产品设计与 Grill。
新功能在 DIB 开工前，DLA 必须：
- 主动读取现有 Windows UI/用户动线/状态代码；
- 识别 Firmware 已经定义的事实与 Windows 仍需决定的产品问题；
- 对真正有歧义的 UI、用户旅程、状态 ownership、读写时机、异常行为与 UAT 方式进行 Grill / Owner 对齐；
- 没有产品歧义时可以明确说明“无需再问 Owner”，但不能只检查资料齐全就跳过 DLA 产品判断。

## 5. Contract revision 是正常流程

Owner 在 IMPLEMENT 中修正产品语义时：
- DIB 必须暂停受影响实现并交回 DLA；
- DLA 记录 Contract revision / alignment，Owner 只确认变化部分；
- 历史 Contract 与旧批准保留，不要求回退旧 Contract hash；
- 通过正式 `contract-reconcile` 生成新的 effective approval / dispatch 后再回 DIB；
- 不把合法产品修正误判成必须寻找旧 start-fingerprint 原字节。

## 6. 文件和脚本职责

- `owner_report.py render`：生成最终中文 Owner 汇报。
- `owner_report.py progress`：可选的中途中文更新；不要求定时调用。
- `owner_report.py check`：检查拟发送正文是否完整、中文叙述是否满足要求。
- 脚本只检查结构/文本，不认证代码、测试、Owner 身份或事实真假。
