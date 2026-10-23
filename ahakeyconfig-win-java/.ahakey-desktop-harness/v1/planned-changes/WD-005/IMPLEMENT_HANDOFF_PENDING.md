# DIB IMPLEMENT交接预备稿

状态：NOT_DISPATCHED。Owner已批准产品范围，但正式CHANGE/路由尚未就绪。
本文件不是当前开工授权。DLA完成正式登记、起点与批准路由后，核对引用并在聊天正文交付。

```text
$ahakey-desktop-builder
$ahakey-desktop-harness
角色：Windows DIB；目标窗口：独立DIB对话
工作目录：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java
任务：WD-005 / WS3 CP2 OLED与灯光配置
模式：IMPLEMENT，仅正式STATE、change、approval及preflight均允许时开工。

先读取适用AGENTS、Builder/Harness Skills、正式规则和当前STATE/local；
核对changes/WD-005的正式CONTRACT、REFERENCES、allowed_paths、Journey、
classification、approval、dispatch、immutable start及隔离记录。
不得从本预备稿自行new/approve/activate，不得重启WD002或重写旧批准和起点。
Owner批准依据：.ahakey-desktop-harness/evidence/20261015-wd005-owner-scope-approval.json
设计来源：.ahakey-desktop-harness/v1/planned-changes/WD-005/
读取CONTRACT、DECISIONS、IMPLEMENTATION_SCOPE、PROTOCOL_AND_STATE、
ACCEPTANCE、DESIGN_REVIEW、REFERENCES和FIRMWARE_EVIDENCE_REVISION_02。
若formal引用与Owner批准设计有实质差异，先交DLA，不自行补义。

实现OLED：复用左侧OLED入口和右侧Inspector；当前Mode默认/SINGLE，
全局MULTI共19目标；左侧160×80 RGB565成品overlay，完整等比黑边。
静态1帧，默认8/状态12帧；GIF完整合成、固定10fps，不静默截帧。
每格选/换文件，统一上传并应用，确认弹窗只能确认冻结目标。
成品/草稿保存至~/.ahakey/oled-resources/v1，重启恢复，不按设备分库；
仅显式清除本地，不发0x8D；不删源图，不覆盖其他配置及已有新库。
按合同实现设备已有/草稿/已应用/失败/未知对账与不一致降级。

实现灯光：保留现有布局；全局亮度与当前Mode九个SINGLE AI灯效分开保存。
显式0x89临时预览，不拖动发命令；左侧八灯同源模拟，离开不发STOP。
0x8E成功同步结束设备preview；逐项保存如实报告部分成功。
按需读取、不覆盖草稿；编辑中断连可本地编辑，禁止设备写。

协议以只读固件C:\Users\20825\Desktop\vibe-code正式源码为准；
当前设计绑定CP2 20261015T185611 PASS、candidate08dd24a6及记录的HEX哈希。
0x88配置/元数据；0x8A Begin、0x8B Chunk、0x8C Commit；
slot28672、有效像素25600、固定填充3072、Chunk最多48、CRC覆盖成品流。
同步修复USB/BLE二进制回复边界；整笔上传lease及连接代次隔离。
Begin FAIL不保证旧资源有效；Commit未知需对账；全部CP2写ACK超时隔离；
旧ACK未排空不得继续可混淆写入，不自动跨重连续传，不自动断连恢复。
固件决定实际presentation，上传成功不承诺立即播放。
具体字节、偏移、状态责任以已批准协议映射为准，不发明错误状态码。

只修改正式allowed_paths内已批准职责，保护历史dirty、按键/侧拨/语音/CP1。
不改Firmware/eternal、Harness核心/规则/seal；不Git写入、杀进程、下载模型、
设备写入、烧录、安装或Release Batch。构建/测试执行权限以正式dispatch为准；
不把产品范围批准解释为当前已有构建授权。
离线及协议模拟验证须覆盖ACCEPTANCE A01-A11适用部分，不用零测试PASS充数；
真实设备项保持未执行。没有现成JUnit/TestFX，不自行扩大依赖或改pom。
实现完成记录真实EXECUTION_REPORT及测试证据，经submit回DLA实际diff审阅；
高影响fresh review仍需独立进行，本轮设计复审不能代替。
全程中文；遇真实范围/协议冲突回DLA，不重新Grill既定UI。
下一次交接在聊天正文完整展示提示词。
```
