# D02-A WS3呈现协议层

固件accepted source70ca334；最新Harness归档076382b确认CP2接受。来源APP/services/display_presentation.c/h、APP/sub_main/command_solve.c及ARCHITECTURE的CP1协议表，当前生产文件无变更。

- 帧为AA BB + command/payload + CC DD。0x98只能set模式0/1；没有query或持久化。切换模式清理对应旧运行态；重复相同模式不是清空操作。
- 0x90 state0–8为旧SINGLE；0x99是version1完整四槽快照，每槽valid/state/foreground共3字节，含opcode长度14、完整帧18。只允许4槽，不发送旧per-slot形式。valid=1时state为running1/waiting2/done3、foreground为0/1；valid=0忽略其余两字节。编码空槽统一清零；多个foreground合法，不在客户端擅自拒绝或重新排序。
- 0x9A无payload，只表示链路兼容ACK，不查询模式、不刷新task寿命、不代表OLED呈现。0x90/0x99在错误模式也可返回OK。因此解析结果仅received或rejected，不提供applied/confirmed/live等成功语义。
- 精确6字节ACK需匹配命令、帧头帧尾；非法命令参数不得借ACK变成功。全部状态和协议模型是纯值，无文件/蓝牙/Runtime副作用。
- 本批不修改FirmwareCapabilityProfile或ConfigurationCommandPolicy，不给已知catalog自动开放WS3呈现写。旧0x90行为不变，0x98/99/9A不接入生产队列。不能将同catalog或CP2只读事实误作CP1显示能力证明。

验收：模式/旧SINGLE/heartbeat精确编码；完整四槽黄金帧；空槽/多foreground；非法版本/flag/state/长度/旧per-slot拒绝；空槽无效字节忽略并规范编码；精确ACK及错误模式ACK只接收语义；既有配置写门控保持。D02-B/C仍需任务来源、映射、前台/TTL、代次/串行发送/显式选择、断连/Quiet/Sleep边界及真实显示验收。协议代码通过不表示D02全功能已开发或真机通过。

验证结果：新增7项协议测试通过，全277项Swift测试通过；未发送真实蓝牙命令、未更换本机已验证候选。
