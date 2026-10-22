# WS3 App直连实时来源（开发中）

D02的一个已确认缺口：AgentManager将连接交给App时卸载Agent LaunchJob；原任务概览只支持后台socket，不能作为App直连的实时来源。新入口必须来自真实Hook事件，不能重放current-ide-state旧快照，也不能按cwd/命令文本猜会话。

本批先完成共同底座：AgentPresentationSession迁到Shared的WS3PresentationSession，Agent保留typealias；原激活证明、串行ACK/50ms事件合并、300秒任务过期、模式切换、退出清理逻辑不变。App下一步复用同一协调器，避免两套时序分叉。

HookSupport在原IPC前尝试发布独立实时事件，只处理带合法真实会话元数据的state/state_with_reset/permission；没有活跃App reader时不写事件，也不改变原审批返回/策略。落盘仅包含客户端、SHA256会话引用、事件名、状态和单调时间，不包含原始session、提示词、工具参数、识别文字或凭据。

WS3LiveTaskJournal由显式App连接创建UUID nonce，环形尾部最多64条/64KiB，只接纳5秒内事件；进程退出或新连接不能重放旧nonce。生产者使用非阻塞flock，争用时放弃这次辅助显示事件，原Hook IPC继续；这是best-effort实时显示，不是可靠消息队列，也不作为审批事实。App消费需按sequence去重，发现溢出缺口时清理旧任务并提示快照可能不完整。

退出时先无锁删除nonce专属lease文件，再尽力清理共享指针/事件；争锁不能丢失撤销，旧finally不能删除新nonce。源已关闭时即使App进程还活着，后续事件也会拒绝。注册、断连、Quiet/Sleep、配置交接和模式变化的消费者接线仍待后续批次，未将这份底座记为D02完整实现。

新增4项真实临时目录测试：隐私字段、活跃租约、断连代次/旧finally、64条上限、非法事件、非阻塞锁及争锁下撤销；连同原Agent协调器和任务注册表共21项相关测试通过。两轴审查中发现的撤销争锁问题已用专属lease文件修复并复核通过。没有读取真实用户任务，也没有安装/连接或写入键盘。

可靠前台身份仍需可证明的会话/窗口来源，不能用最近事件或仅前台App名称冒充具体会话。App直连补齐与前台/静默/休眠/OLED矩阵仍在总WBS，不缩减目标。
