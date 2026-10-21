# D04/D05 多帧与恢复保护补充

基线connect&talk/5d45b4d，代码2b23c2d。349项Swift测试、Standards与Spec独立复核通过；0.2.3 arm64 Developer ID候选已安装，deep/strict签名校验通过。已接受CP2固件未变，无刷写。

## 自动回归

新增5项：完整快照任意位置WRITING禁新上传（含不同目标）、目标fresh WRITING不得BEGIN与重新取得EMPTY后的显式重试、三帧跨padding连续偏移及Commit后元数据、第一帧后取消不得继续/Commit/clear、真实ImageIO不同颜色GIF帧解码顺序。取消为可控transport异常，不冒充真机中断验收。

## 真机进展

- 原生设置完整19项读回35%/有效1项；Codex位置8仍自定义1帧，位置18为原EMPTY默认。
- 用本机生成的160×80红/绿/蓝三帧GIF临时上传18，1792个分块全部确认；Commit后3帧、86016字节与CRC元数据一致，界面报告成功，有效2/19。
- 交还同源Agent后临时隔离官方Socket，只注入一项合成Cursor任务running→done。requestedMode=1、唯一task state3，供实际OLED播放观察；不修改真实任务记录或向他人发消息。测试结束应清除合成任务、恢复SINGLE及官方Socket，再恢复18默认。
- 用户确认OLED红→绿→蓝持续循环，无花屏/卡住/重连。125次后台读取保持唯一done任务，随后清除合成任务、恢复SINGLE与官方Socket，脚本failure=null。原生设置重读后显式恢复18，ACK+后读EMPTY确认、有效回到1/19、35%不变；重新选择原Codex JPEG只读查询，元数据一致、未写入。已关闭设置交还同源日常Agent。截图/原始RPC只保存在本机私有证据目录。

## 未覆盖

三帧素材的断电保持、完整19位置、8/12帧上限的真机写入、真实传输中断/断连/拒绝矩阵及CP3整库恢复仍待。活跃上传期间10秒CPU累计约4.03秒，属于上传负载样本，不用于宣称低CPU或长期性能通过；关闭设置、后台播放三帧测试期间另取10秒样本：GUI累计+0.01秒、Agent+0.04秒；仅说明该短窗口，无长时性能结论。用户原Codex图片、键位、Voice和亮度未写。
