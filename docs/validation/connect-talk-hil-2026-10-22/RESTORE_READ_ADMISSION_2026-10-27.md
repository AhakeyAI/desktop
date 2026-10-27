# 恢复状态只读入口的连接初始化竞争

build506，实体手动档，模式侧栏待机读回60分钟正常。展开“恢复键盘设置”，仅点“读取恢复状态”，两次均显示“BLE 数据通道还没准备好”。未选择恢复意图、未确认USB、未发起重置，原2项草稿保留。

UI反馈断言（重新定位当前控件后执行）：`var s = await studio.getAXState({disableDiffing:true,emit:false}); if(s.includes('BLE 数据通道还没准备好。') && !s.includes('按钮 (disabled) 处理中')) throw new Error('REPRODUCED_RESTORE_READ_CHANNEL_NOT_READY');`，已实际返回该错误。

特征发现后自动启动状态查询和四模式图片查询；Inspector只等待连接及特征就绪。恢复入口比普通读取多了“命令轮次必须空闲”的立即检查，因此初始化查询尚占通道时会在发送恢复状态查询之前拒绝。候选假设包括入口过早检查、租约等待缺失和固件不支持；当前代码及重复复现支持第一项，最终固件响应仍须新候选核验。

将原立即拒绝逻辑提取到生产使用的RestoreChannelAdmission后，`swift test --filter RestoreChannelAdmissionTests`实际5项、3失败；改为最多5秒按50ms观察，等待既有读取排空，再次核对连接代次、其他配置操作和原排他条件，5项通过。取消、超时、连接变化不抢占或清空原命令轮次；不添加重试恢复命令，不放宽恢复授权或状态证明。完整882项Swift回归通过。

此修复尚未安装到build506，不把隔离测试视作原UI已关闭。新候选需重复同一路径，区分实际固件支持/不支持响应；没有精确组合HEX时不刷机、不执行整机恢复。此次未增加临时调试日志。
