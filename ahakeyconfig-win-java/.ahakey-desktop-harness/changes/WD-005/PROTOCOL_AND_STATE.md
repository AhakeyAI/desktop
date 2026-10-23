# CP2 协议映射和状态责任

来源：只读固件 APP/sub_main/command_solve.c:625..760、services/resource_map.h、
resource_upload_transaction.c、display_config_store.c、display_preview.c 以及当前 ARCHITECTURE。
正式文件hash、commit和成熟度见 REFERENCES.json；本页不定义新固件协议。

## 字节合同

逻辑包为 AA BB <body> CC DD。以下写 body；多字节整数 LE，像素 RGB565 为 BE。
所有写ACK body=[opcode,status]，status仅00成功/01失败；全包6字节。

| 操作 | 请求body | 成功回复body / 长度含包头尾 |
|---|---|---|
| 持久亮度 | 88 00 | 88 00 00 brightness / 8 |
| SINGLE灯效 | 88 01 mode ai_state | 88 00 01 mode ai_state effect / 10 |
| 资源BASIC | 88 02 entry | 88 00 02 entry valid write_state / 10 |
| 资源INTEGRITY | 88 03 entry | 88 00 03 entry frames:u16 bytes:u32 crc:u32 / 18 |
| 亮度预览 | 89 00 brightness | 普通ACK |
| 灯效预览 | 89 01 effect brightness | 普通ACK |
| STOP | 89 02 | 普通ACK；离开页面不调用 |
| Begin | 8A entry bytes:u32 frames:u16 crc:u32 | 普通ACK；body12/全包16 |
| Chunk | 8B entry offset:u32 length:u8 data[length] | 普通ACK；全包11+length |
| Commit | 8C entry | 普通ACK |
| 保存亮度 | 8E 00 brightness | 普通ACK |
| 保存SINGLE灯效 | 8E 01 mode ai_state effect | 普通ACK |

0x8D设备清除、0x8F保留不用于本任务。Fail回复可能仅6字节，不能硬等成功长度。
0x88需同时验证opcode/status/read_kind/selector/字段长度；迟到或错目标回复不能更新当前格。
USB单命令容纳62字节，最大Chunk全包59字节，无需旧raw data通道。
BLE逻辑包沿用现有命令通道，分片/合包按完整结构重组；任何二进制字段中的AA BB/CC DD均为数据。
0x88 INTEGRITY也有任意CRC字节，USB extractFrame和BLE findFrameEnd都须定长识别CP2回复。
保留旧协议解析分支，不能借此重写所有WS1/WS2/CP1报文。

## 目标和成品

| 用户目标 | entry | 最大帧 |
|---|---|---|
| Mode1默认/working/waiting/done | 0/1/2/3 | 8/12/12/12 |
| Mode2默认/working/waiting/done | 4/5/6/7 | 8/12/12/12 |
| Mode3默认/working/waiting/done | 8/9/10/11 | 8/12/12/12 |
| Mode4默认/working/waiting/done | 12/13/14/15 | 8/12/12/12 |
| 全局MULTI running/waiting/done | 16/17/18 | 12/12/12 |

协议mode=0..3，UI显示1..4。SINGLE灯效的ai_state=IDEState.getCode()，不是列表ordinal，
也不是OLED working/waiting/done的1/2/3。灯效ID0..16，OFF=0只能保存。
每帧160×80×2=25600有效字节+3072字节固定填充，slot=28672。
本轮主机填充提案为全00；CRC覆盖完整 padded stream，bytes=frames×28672。
CRC32采用固件0xEDB88320算法，初始流值0，与标准CRC32一致；host内按无符号u32处理。
不能把旧writeLargeData的“按slot起始但只写25600”当新事务布局。
Chunk length=1..48，offset从0严格连续；无逐包重传/续传/流水线协议。
每帧按100ms预览，与固件当前固定时长一致。

## 状态 owner

| 事实 | 唯一责任 |
|---|---|
| 当前键盘Mode/实际灯光与OLED presentation | 固件；Windows消费既有模式同步，不强制播放资源 |
| 本地选中格、草稿成品、进度、错误、保存索引 | Windows资源模型/库 |
| entry有效性/帧数/字节数/CRC、持久亮度/灯效 | 固件0x88/写ACK；主机只缓存最后确认事实 |
| 上传目标、内容hash、连接代次、transport、offset | Windows上传事务；确认后不可随UI修改 |
| 本地灯光效果动画 | Windows模拟器；不得标为设备事实 |
| CP1最新AI状态 | 原AiRuntimeDisplayService；上传期间不发送竞争命令，保留最新事实 |

草稿与设备基线分别存储，不能用一个status替代两者。

| 事件 | 本地状态/动作 | 设备事实 |
|---|---|---|
| 文件处理和持久保存成功 | 草稿，预览立即替换 | 不变 |
| 文件处理失败 | 保留原资源，弹具体错误 | 不变 |
| 发Begin前取消确认 | 草稿 | 不变 |
| Begin返回FAIL | 上次失败，保留成品、失效旧设备缓存并回读 | 单一FAIL无法区分前置拒绝与进入后失败，不断言旧资源保留或失效 |
| Begin ACK成功 | 上传中，冻结目标 | 旧用户资源已无效，WRITING |
| Chunk正常ACK | 更新已确认进度 | 尚未VALID |
| Commit ACK成功 | 已应用；可补充回读 | 固件确认持久VALID，不代表即时播放 |
| 上传断连/报错 | 上次失败，保留成品 | 未完成事务将INVALID；不能恢复旧资源声明 |
| Commit发出后ACK丢失 | 上次失败/结果未确认 | 可能VALID；下次同目标完整元数据核对 |
| 本地记录与新设备有效元数据不符 | 草稿、轻提示 | 不写设备 |
| 仅刷新失败 | 保留所有本地内容和历史确认 | 未知，不能断言空/不一致 |
| 清除本地且设备有效 | 无本地成品，设备已有占位 | 不发送0x8D |
| 清除本地且设备为空/无效 | 空态 | 不发送设备命令 |

本地“已应用”记录是历史事实，重启/换连接后须核对；未读到设备时不冒充当前设备已匹配。
若本地有草稿，刷新只更新独立设备基线，不以相同CRC擅自覆盖用户编辑意图。
BASIC+INTEGRITY需同一次连接/目标/加载generation；非有效记录integrity全零。
二次读取期间若设备状态变化则本次结果不合并，有限重读/显示未同步，避免拼接假一致。

## 事务与恢复

同一设备会话只允许一个主机显示配置事务。整个Begin..Commit持有逻辑lease；
不能只靠ReentrantLock逐包释放，因为await会释放锁，其他写入者仍可能插入。
lease在真正发送入口校验，覆盖UI保存、旧raw写、模式设置、CP1 runtime、状态轮询等路径。
上传期间仅该事务Chunk/Commit和0x00只读状态允许发送，0x88也暂停。
CP1事实仍更新，正常退出lease后发送最新快照，不重放全部历史，不推进错误的已发送标记。
不得扩大为修改CP1.5连接策略；断连取消、USB/BLE选择固定在本次transaction代次。
禁止一次上传中自动从BLE转USB，或等待重连后续传。

ACK超时是不确定结果，不能盲重发Chunk（重复offset会导致固件判INVALID）。
如Begin/Chunk超时且设备仍在线，主机进入恢复待定，停止其他写入；
不自动发送新Begin、STOP或0x8D，也不自动断开用户连接。界面明确本次未完成，
允许用户重新连接后重新同步再点上传。可先只读0x88探测是否仍拒绝；不无限重试。
Commit ACK丢失后若完整元数据等于冻结成品且VALID，可对账确认为已应用；不符保留草稿。
若Commit请求本身未到达，固件可能仍active并拒绝0x88；此时不能完成对账，进入恢复待定，
继续限制竞争写入，提示用户实际断开并重连后同步。仅释放本地lease不构成恢复。
连接重建使旧pending请求和回复失效；释放本地lease不等于固件仍在线事务已解除。
未收到BEGIN ACK时同样可能已使旧资源失效。即使收到FAIL，也无法知道是前置校验
拒绝，还是写入WRITING后发布/在线检查失败而转INVALID；主机不得保留旧有效缓存当现况。
重新读取BASIC+INTEGRITY后才更新设备事实，超时使用“设备保存结果未确认”，不做不可知断言。

同样的迟到ACK隔离覆盖0x89/0x8E，不仅OLED上传。协议ACK只有opcode/status，
无法用本地generation给线上ACK补出request-id；亮度和灯效保存甚至共用0x8E。
任一已发送CP2写请求超时后，将该设备会话写入状态标为结果未知，停止队列，
禁止同连接下一次preview/save/upload，直到用户重连建立新transport会话并丢弃旧接收缓冲。
回读可核对持久结果，但不能仅凭回读成功宣布旧ACK已排空并解除写隔离。
0x89超时则不显示设备已预览；0x8E超时不把后续项标成功。读请求超时也不得让迟到
status-only FAIL误完成下一个0x88；当前批次停止，同连接不重开可能混淆的读取批次。

0x8E任一成功会调用display_preview_stop，Windows同步结束设备预览状态及其关联模拟，
独立的本地草稿模拟可保留，但不再声称它代表设备preview；无需另发STOP。
保存FAIL保留原preview剩余期限，不重置10秒；未知ACK不推断是否已停预览。

本任务不添加用户取消上传按钮；正常UI离开/Mode切换在上传期间禁用。
进程异常退出不保证发送清理命令；下次启动将in-flight恢复为待对账失败草稿。

## 能力准入

仅有connected或一次0x88回复不足以证明固件包含本轮修复；不得使用资源写命令作能力探测。
优先复用现有固件身份机制绑定已核验CP2候选；若现有catalog不能唯一识别，内部JAR
交测以Owner明确确认已刷指定HEX作为设备写前置，单独记录，不偷偷创建量产兼容表。
unknown保持本地预览可用、禁用CP2设备写；不能误称为确定不支持。
正式配对交测仍要求有效Gate/候选/HEX哈希及实际安装确认。固件Owner UAT与Windows UAT分开。
