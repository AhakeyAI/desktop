# 固件 Issue 最新反馈与关闭记录

2026-11-04，Owner明确授权“已验证内容回填、该关闭的关闭”后执行。读取全部原文/评论，重新fetch确认固件仍为Fireware-harness@72346b0；每次写入前核对正文/标题/状态/评论未被他人修改。更新后再次通过GitHub API核对全部11个正文、标题、评论及状态。未新增硬件试验或固件代码变更。

## 实际处理

- 关闭归档4项：#11、#13、#14、#16，GitHub state_reason均为not_planned。原因分别是未形成可复现缺陷、历史观察或职责移交，不能改写为所有故障/硬件矩阵已修复验收。
- 保留开放4项：#10逻辑取消体验扩展、#12长宏完整读回扩展、#15合同范围内物理联合验收、#17独立两套动作配置闭环。
- #8/#9保持原关闭状态，补准确的组合和已通过范围；#7仍为归档索引，更新实际去向。
- 其他贡献者的#6提案不在本次范围；已再次核对其正文、标题和开放状态未改动。
- 各正文保留折叠历史原文，顶部最新结论明确覆盖旧要求；没有删除旧证据，没有把尚未公开的开发者回复编造为结论。

| Issue | 更新后状态 | 反馈 |
|---|---|---|
| [#7](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7) | closed | [本次反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7#issuecomment-6622090314) |
| [#8](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/8) | closed | [本次反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/8#issuecomment-6622084268) |
| [#9](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/9) | closed | [本次反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/9#issuecomment-6622086753) |
| [#10](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/10) | open | [本次反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/10#issuecomment-6622058745) |
| [#11](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/11) | closed（未确诊/职责归档） | [本次反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/11#issuecomment-6622061916) |
| [#12](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/12) | open | [本次反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/12#issuecomment-6622064154) |
| [#13](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/13) | closed（未确诊/职责归档） | [本次反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/13#issuecomment-6622066739) |
| [#14](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/14) | closed（未确诊/职责归档） | [本次反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/14#issuecomment-6622069434) |
| [#15](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/15) | open | [本次反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/15#issuecomment-6622072572) |
| [#16](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/16) | closed（未确诊/职责归档） | [本次反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/16#issuecomment-6622076109) |
| [#17](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/17) | open | [本次反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/17#issuecomment-6622080755) |

## 核心更正

承认已有物理owner-loss恢复、捕获释放、GPIO快照、CRC/INVALID/store/Restore测试。K1写中断恢复旧值的Owner排除决定继续生效；Restore中断合同独立保留。正式catalog/信任/公证等转客户端发布WBS，不要求无必要的第二份新HEX。

F99D/build537三轮Codex路由保存、14组四模式隔离及正常重启读回，build539 Claude Consumer 12组HID及Owner听写/Dock确认，按原证据范围回填。连续两次Restore是07A8/build522的结果，未冒称F99D新做了破坏试验；默认模式观察与未做物理故障保留在#15。

客户端build548默认保留DataFlash升级/显式清空已补齐；真实保留升级兼容与绑定保持仍待集中HIL，未据此确定历史Reconnect唯一根因。客户端完整验收8组及3类开发依赖未因关闭这些归档单而消失。

[原始合同/代码复核](firmware-issue-classification-review-2026-11-04.md) · [运行路径复核](firmware-issues-runtime-reaudit-2026-11-04.md) · [WBS](mac-adaptation-master-wbs-2026-10-22.md) · [API复核回执](../validation/connect-talk-hil-2026-10-22/firmware-issue-feedback-2026-11-04.json)
