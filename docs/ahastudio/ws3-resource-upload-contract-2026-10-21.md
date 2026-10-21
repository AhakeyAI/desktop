# D04 CP2 显示素材上传

基线connect&talk/d39c3ea（PR146），新分支codex/connect-talk-ws3-resource-upload。固件最新Fireware-harness再次核验为076382b，已接受CP2生产源70ca334、已刷HEX ffb9208f不变。本批不刷固件。

## 已核对的生产合同

- 19项资源，0–15为四工作模式×默认/进行中/等待/完成，16–18为多任务进行中/等待/完成。默认项0/4/8/12最多8帧，其余最多12帧。RGB565大端160×80图像25600字节，必须补3072个FF形成28672字节帧槽；CRC覆盖包括padding的完整字节流。资源位置由固件映射，不复用旧slot10/80/150/220物理写地址。
- 全帧AA BB…CC DD。Begin为`8A entry bytes:u32 frames:u16 crc32:u32`，完整16B。Chunk为`8B entry offset:u32 length:u8 payload`，完整11+length B，payload1–48B。Commit为`8C entry`。整数LE；三种ACK恰好6B，status0仅表示接收。
- 本合同Chunk数据内联CMD 7343，**不走旧DATA写入**。按CoreBluetooth实际写类型的maximumWriteValueLength减11计算分块；BEGIN至少16B。串行逐块ACK、绝对相对资源偏移，不静默截断、不盲重试。0x04/0x8E不参与上传持久化。
- 固件固定100ms/帧，当前不能设置新资源FPS；客户端明确10帧/秒，不修改旧客户端FPS偏好。源文件≤2MB，超8/12帧拒绝，不静默降帧或丢弃不可解码帧。
- **0x8D是清空资源，不是abort**，本批不开放清空/恢复。上传active时仅同owner的8B/8C和状态查询可用；错误chunk/commit或真正链路loss由固件标INVALID。客户端取消/超时停止后续数据并撤回配置通道，不发送8D、不伪造错误包当abort。Mac系统HID可能保留物理BLE连接，因此取消配置连接不等于固件已观察到loss；需真机核对，必要时提示正常重启键盘，不能声称立即清除固件transaction。

## 客户端授权和交互

先在当前配置连接读取完整19项快照，严格known WS2+当前generation验证；目录键本身不能授权资源写入。仅ws3Resource明确事务开放合法8A/8B/8C；新固件旧80/DATA路径仍禁用，legacy原上传保留。

显示与灯光页独立19项选择，图片/GIF选择与首帧预览在后台准备。选择不会写入；确认具体目标/文件后上传。先重读目标basic/integrity与界面baseline比对，冲突不Begin。上传期间锁其他配置、阻止旧状态raw写抢占通道，逐ACK更新进度，Commit后读回valid/frames/bytes/CRC完全相同才标元数据确认成功；这不是读回Flash原图或实际OLED视觉证据。失败/取消/断连撤快照并断开，保留本地源文件和草稿，不声称回滚。

旧画布LCD提供新素材设置入口，旧版设备的原上传与全量保存路径保持。显示清空、完整恢复和CP3扩展归D05，不能把8D接成取消或自动清掉用户素材。

## 验证边界

自动测试先覆盖CRC/帧padding、19项容量、线格式/窄授权、48B及MTU20分块、连续offset、拒绝/取消/断连停发、基线冲突、Commit后CRC不符、精确分片ACK等。候选安装后须先只读识别/选择素材预览，再在明确目标上真机写入、核对显示、断电保持与取消恢复。上传会改变不可通过协议原字节备份的资源；不得将合成测试通过当真机已完成。
