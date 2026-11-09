# WD-011 revision4：BLE真实状态回复与查询恢复

本文件追加到有效Contract；与前三轮“桥EXE完全复用”及短等待超时立即全局UNKNOWN要求冲突的范围，以本修订为准。Owner授权evidence/20261109-ble-fix-owner-authorization.md。新交付目标1.0.24 Local Model Owner Preview。已有ACR4/ACR3、固件EAFFD569、原资产/上传事务和全部延期范围保持。

## 修复范围

- 现有C# BLE桥对完整0x00通知继续更新缓存，同时按实际连接generation/discovery归属把真实原始帧转发给主程序。仍支持既有QUERY_DEVICE_INFO缓存读取；不伪造ACK，不用缓存值或无关联的TCP状态推断真实设备回复。
- 主程序区分有限业务等待（例如autoApproval500ms）与运输层完整请求生命周期。业务等待到期可返回未取得新事实，但已经发出的请求仍阻止后续普通写/上传，直到正确原始回复或运输层终结；不能释放后把迟到回复归给新请求。真正超时、写失败、断连、协议错误与未确认资源写入仍保守隔离。保留完整ACK的opcode/shape/selector/token及generation判断。
- 对同一代次的明确不可恢复UNKNOWN，后台不重复发送无效设备查询/反复onError；首次提示明确重连，重连换代后可正常再查询。已在飞但尚未到运输时限的读取不被当成永久故障；不能通过隐去错误假装连接健康。沿用现有状态反馈和重连入口，不新增无关UI布局。
- BLE桥目标选择、重连、订阅、端口、socket/generation写锁、收发失败保护保持；核查桥主动初次状态请求和通知顺序，不将旧连接通知/旧缓存认作当前请求。USB真实ACK逻辑不因桥兼容退化。
- 主Java最小修改限现有allowed_paths；桥修改提交在scripts/ble-driver-fixes.patch，不修改eternal/reference源。scripts/test-ble-driver.ps1新增真实抽取生产OnBleNotify/发送路径的验证；build-ble-driver.ps1沿原离线配方、manifest门重新构建唯一新桥，不复用旧EXE。

## 验证

先保留已有实机日志和两次Java TCP红测，再新增真实C#桥OnBleNotify→实际隔离TCP socket→主Java解析测试或有明确字节身份的分层对照。覆盖状态缓存同时原帧转发、500ms之后而运输时限以内回复、新请求不能超车、旧代次/错帧/缓存不释放pending、运输超时仍隔离、后续轮询不反复提示、重连清理、上传owner拒绝普通00。

实际回归ACR4/ACR3上传、K1完整保存/读回、FactoryReset及普通保存最后ACK，检查短等待和接收队列/锁顺序；旧测试不能靠放宽断言冒称PASS。代码实际审阅及独立高影响审阅，修复可测后隔离打包1.0.24 LocalModel。

打包输入主JAR、新桥binary+manifest+patch必须一致；核验真实EXE版本/runtime/模型/native/318类文件身份，包内专项执行。诊断启动器绑定新JAR hash，记录上传和状态恢复事实。仅本轮必要诊断，不扩展全局日志改造。

Owner验收：退出旧主程序和旧桥后安装/启动新版本，确认新桥生效；BLE连接静置超过原故障周期，无重复提示，完整版本可读；原画质/快速上传并读回；短时延迟/断连后明确状态，重连恢复；USB回归及键盘正常输入。Agent不代安装、kill、访问真实设备或刷机。新包测试PASS仍须Owner反馈，不把机器checks当实机。
