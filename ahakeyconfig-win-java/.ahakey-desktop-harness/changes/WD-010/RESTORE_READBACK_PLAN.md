# WD010 恢复读回与完成判定

状态：实现前源码映射，不是设备实测。恢复完成需匹配本任务的固件COMPLETE及Windows必需配置读回；恢复相关新状态由FactoryResetService持有，窗口只观察。

| 配置/事实 | 已有读取依据 | 完成约束 |
| --- | --- | --- |
| 任务恢复状态/次数 | 固件0x9E v1/0x30；新增FactoryResetProtocol | version/sub/nonce/attempt及目标代次全部匹配；历史COMPLETE不能无关联变成本轮成功 |
| 当前工作模式/设备状态 | BleManager.queryStatus、现有状态响应解析 | 新状态应对应恢复后的Mode1及可读状态，不能沿用恢复前缓存 |
| 四模式普通按键/宏/描述 | readOrdinaryKeyConfig，0x87 | 逐模式读取，Mode4空配置按协议合法解码；不得为填满UI写默认键值 |
| 四模式K1路由 | K1RouteService与0x9E路由读取 | 通过现有完整性/分片校验，不与恢复回复串扰；保留普通模式默认路由/Mode4空路由的真实读值 |
| 拨杆 | readSideSwitchConfig，0x97 | 读回两位置配置和当前物理位置，不以恢复前草稿覆盖 |
| 待机超时 | readSleepWaitTimeMinutes/querySleepWaitTime | 真实读取并更新UI；读取失败不得标同步完成 |
| 亮度及模式灯效 | displayRead(kind=0/1)，DisplayConfigService | 读取受影响模式/AI灯效项，不能仅刷新当前可见页就声称所有配置同步 |
| 图片/GIF选择 | readPictureState(mode) | 各模式可读选择重新加载，旧预览和自动运行显示写入作废 |
| 19条用户资源metadata | displayRead(kind=2/3) | 真实读取有效性、写入状态和完整性信息；保留电脑原图，不上传旧资源或宣称物理安全擦除 |
| 语音onboarding及固件内部保留/复位字段 | Firmware恢复协调器COMPLETE与其自身checked-write/readback实现 | 尚未在当前Windows找到全部独立读取口；不凭本地默认填为“已读回”。UI可读项必须真实刷新，不可读项明确依赖固件完成语义，后续若发现必须独立验证的UI字段则回DLA收敛，不擅自新增Firmware协议 |

## 生命周期

读取在工厂恢复专用权限内进行；普通配置写入、上传、预览和后台运行显示写入继续禁止。所有结果带目标、任务和连接代次，切换设备或更新任务后不能更新当前UI。必要字段有逐项完成结果；失败展示“设备已恢复，配置读取失败”，重新读取不能写恢复。

原子持久化记录在恢复命令发送前落盘，含关联依据/任务ID/attempt/提交阶段，不存自动重试帧。USB重连关联使用Owner已确认的人工入口作为兜底；明确不同设备不能使用。人工关联后仅查询，attempt不符继续未确认；手动恢复必须另行确认并重新读取attempt。

## 仍须实现方验证的工程事实

上述读取方法原本受普通维护门/显示能力准入控制。DIB需在本Contract允许文件内接通专用读取权限，并证明不会发生自行锁住读回、应用无法退出或解锁时重放旧写入。若恢复支持的实际固件不同时提供必要读口，报告真实限制并回DLA，不用mock成功掩盖。没有对应行为证据前不得勾选恢复完成验收。
