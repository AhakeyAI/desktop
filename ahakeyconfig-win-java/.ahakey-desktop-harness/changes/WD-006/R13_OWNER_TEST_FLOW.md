# R13 1.0.12 本地模型测试包

两项修正：正确解析WCH实际结果；失败工具结束后，关闭入口先结束本次链路，避免主窗口X和托盘Exit被静默拦住。

安装包：C:/Users/20825/Desktop/windows软件代码/desktop/ahakeyconfig-win-java/target/WD006-R13-LocalModel-1.0.12/installer/AhaKeyStudio-1.0.12.exe
SHA256：21de9ab7c4e5c5b915cbd92c7f0f3d62b003ef90f9df20ceb962b46ae0b36af7
大小：296237624 字节。
版本1.0.12 / local-model / x64；buildId：96d9a365a0296b9dcf5e4e5f9782f13cd6cd706ab4ff4884a21c37c5a664a988。
来源：已审阅Preview快照 preview-20261026T105435810998Z-dfc116，另加13个原字节不变的已审安装配方输入；不是新正式Git候选，详细绑定见DLA_ARTIFACT_REVIEW.json。

1. 旧软件若无法关闭：更新中心→键盘固件→退出本次链路，然后从右下角托盘图标菜单选择Exit。当前两份现场回执已确认工具结束。不要反复烧录来解除界面。
2. 不先卸载，双击本文件，按提示安装；预期继承原D:/ahakey位置。仍显示1.0.12属于正常，本次同版本修订需手动安装。
3. 先测退出：主窗口X应收起到托盘；重新打开后，托盘Exit应真正退出。重新启动软件继续烧录测试。
4. 选择下方同一X1/CH582M/hw1配对HEX，确认清空CodeFlash与DataFlash。关闭其他WCH工具避免占用。
5. 拔USB并关机，在关机状态按住最左语音键，保持按住插入同一USB接口；检测设备后点开始烧录。写入/校验期间保持连接及按住，等待明确提示完成。
6. 提示写入与校验已完成后，再拔USB、松开语音键、正常连接开机，点击检查正常重连；预期烧录成功，当前版本XXX。未知HEX只显示实际读到版本，不宣称已核对目标版本。
7. 若显示失败，点退出本次链路；也可关闭窗口，工具已结束时应完成收口。如果仍提示工具未结束，保留提示和日志，不反复重刷。我直接查看本机日志。

配对HEX：C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\builds\ws45-cp2_6-restore-combined-regate-20261025\HID_Keyboard_582m_vibe_coding.hex
HEX SHA256：6ec0413cfc983788cdc99f628f0f8e2a64c6af147d2a5e1727a03f036bf1123c
来源Firmware候选292a49f32939e2b778b15eceb194746133d3b2c7的CP2.6+WS45正式REGATE。沿用R12已审配对，不涉及Restore或其他硬件。r001字符串不证明具体候选。

截图设置并非逐项相同：清空DataFlash和CodeFlash均开启；串口免按键下载关闭；下载后自动运行关闭，保留先独立校验、再人工正常重连。DataFlash偏移未显式配置，不声称核实默认值为0。这一轮没有改INI。

已验证：206项源码针对性检查；最终EXE的313项实际载荷/发行签名，最终包内两份现场日志回放、79项解析检查、23项隔离窗口检查。实际新包安装及硬件完整链路仍待你测试，不能记为UAT通过。软件OTA和此前审批提醒不在本次变更中。

日志：C:/Users/20825/.ahakey/updates/firmware 和 D:/ahakey/logs/ahakey-studio.log。
反馈：原路径安装是否成功、X能否收起、托盘Exit能否退出，以及烧录/校验/正常重连显示的结果；异常发截图，我直接读取日志。
