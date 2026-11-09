# WD-011 revision2：原画质 ACR4 无损上传及统一命令会话

本修订与原CONTRACT.md共同构成有效范围；原画质协议、配对固件、仲裁和交付版本如有冲突，以本修订为准。原Contract字节与其历史批准保留，不追溯改写1.0.22。

## 授权、基线与责任

Owner指派见evidence/20261108-acr4-owner-authorization.md。在既有1.0.22 candidate553af140上增量实施，不改变原start与历史批准。最新固件candidate bb6a31ed5ed3f3811e3f9b32b3c93e1ce362f4a3，HW1配对HEX EAFFD569237E295B7EDB0CBAE5AACFDED34ADCB47994BA4E5674603A526FC1C4，来源artifacts/hw1/lossless-upload/EAFFD569；formal7/7及独立review通过，实机未替Owner声明通过。Firmware/eternal只读，使用交付包或candidate原文，不用foreign dirty。

Journey J005/J006/J010/J011/J019；protocol_change + architecture_change；high_impact独立审阅。Windows负责编码、请求排队、会话隔离、本地草稿与UI，固件负责处理/持久化。快速v3 Owner已反馈OK，具体未测分支仍保留待测。

## 用户行为

保留“原画质上传”“快速上传”及既有导入/预览/上传确认。旧原画质资产无需重导入：从每帧CP2前25600字节取160x80 RGB565大端像素，保留全部帧、顺序和原100ms节奏，不重新合成GIF、缩放或量化。原画质上传优先ACR4无损传输，RLE严格更小才用RLE，否则RAW。两者均原画质，不增加让用户猜编码的入口。

明确不支持v4时说明并提供用户主动确认的旧CP2兼容上传；取消不写。CAPS超时、身份/格式异常、连接变化或已经开始的新协议失败不得自动降级或重发BEGIN。重用冻结目标和资源确认；兼容确认时核对同一连接/资源，旧提示过期不写。快速仍走原v3路径与16色预览。

显示确认后的编码字节进度、耗时和实际编码方式，压缩比例不代表实测速度。成功必须COMMIT+METADATA核对；失败保留本地原资源，明确未完成或结果未知。无已批准新取消入口时不新增取消按钮，但服务异常必须走cancel-or-uncertain清理；窗口关闭不伪称设备已取消。

## 编码与协议

以REFERENCES.json绑定的ACR4协议为准，9E version4独立于version1/2/3。v4 CHUNK成功body5，总18字节；v3 body9不变。请求、回复显式长度及version/sub/token/transport/generation精确校验，失败ACK也严查长度和归属。完整CAPS签名/flags/尺寸/预算/块长/帧数均符合才准入；每代次重新协商，不凭相同版本字符串认定支持。

RAW/RLE对象16字节头，每帧100ms:u16+像素编码；RLE literal/repeat按像素成对且不越帧，最大307240并受槽位8/12帧限制。对象CRC与展开CRC独立，展开为原像素+AT03描述符+FF填充。原资产bytes/crc保持，另保存实际已上传的协议/展开身份，保证上传后与重连metadata一致；不能拿旧CP2尾部CRC误报匹配/不匹配。旧记录向后兼容，保存原子化。

USB40/BLE128为最大数据量，按协商取上限。独立v4状态机：超时停止新数据，以同token/version查询STATUS；PROCESSING有界等待，RECEIVING=end只计一次，=start才允许有界原块重发，其他offset/INACTIVE显式失败。BEGIN不确定只查询、不自动BEGIN；COMMIT不确定用METADATA严格核对VALID/entry/帧/展开字节/CRC。CANCEL不确定锁存隔离，断连换代不续传、不关联别的设备。遵循全部状态码、预算与时限，不沿用v3的50000预算到v4。

## 命令会话与异常恢复

统一仲裁全部实际设备命令入口，覆盖USB/TCP、状态poller/hook/模式查询、配置读写、AI状态、K1/Restore及旧CP2。会话获得前阻止新普通命令，并等待已发普通请求的完整回复/明确终结，不能只保护一次WriteFile。普通请求超时/取消后若结果或固件槽位未确认，应阻止新上传至新连接，不直接释放锁假设设备空闲。

上传会话期间仅本会话上传/CAPS/STATUS/CANCEL/METADATA等帧可到设备；00查询也让路。本地BLE桥查询与硬件HID键盘报告保持可用。不排队重放已经过时的模式/配置写入。所有终止路径释放本地owner或明确锁存uncertain；不能无限等待/死锁/偷写。保持固件维护、FactoryReset、K1与设备身份边界；旧固件原画质路径也采用修正后的命令隔离。

## 验收

- Codec：与固件交付金样/期望CRC一致；RGB字节序、RAW/RLE、不可压缩回退、8/12帧、边界/超限/非法数据拒绝；像素与旧资产逐帧相同。
- Protocol：v1/v2/v3/v4独立分帧、最大USB/BLE、二进制帧尾字节、错version/token/sub/generation、畸形长度/能力/错误ACK拒绝。
- Session：重放已证00插队故障应不再出现；覆盖全部普通写入口、上传前在途查询、普通超时/迟到回复、busy/断连/换代、无过时命令重放，HID保持。
- Upload：ACK丢失/STATUS=start/end/PROCESSING/异常offset、BEGIN/COMMIT/CANCEL不确定、CRC/storage异常、重连metadata、无v4显式兼容确认、未知无降级、失败无假成功。
- Regression：快速v3金样/流程、旧资源/CP2、显示和灯光、K1/FactoryReset/维护、语音/AhaType/账号及BLE桥身份；DLA实际累计diff和独立high-impact审阅。
- Package：1.0.23 Local Model隔离构建，使用既有本地模型，不下载/安装/kill；核验真实EXE、包内JAR/runtime/models/桥/配置身份。提供本版本匹配诊断启动器收集联调日志。
- Owner：配对新HEX后USB/BLE原画质静态/8帧/12帧、不可压缩素材、快速回归、键盘输入/Key3/电源、异常恢复/版本读取/重连资源一致，记录真实耗时。

## 交付与边界

此次Owner已明确要求EXE，延续Local Model，无需重复询问形态。目标1.0.23内部Preview；绑定实际候选/产物/固件与报告，未实测不写PASS。Git提交/上传如无本轮明确授权不自动执行，可使用Harness Preview身份交测；旧Git候选和产物不覆盖。

语音工具栏、跨屏、画布、BLE外观筛选和全局日志改造继续延期。临时诊断启动器属于本轮联调材料，不修改全局日志方案。不改Firmware/eternal、不刷机、不上传素材到真机、不安装EXE、不发布、不操作main-anpx。
