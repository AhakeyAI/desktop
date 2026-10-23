# WD-005 第三轮 Owner Preview 简报

## 当前结论

2026-10-17，原DLA核验完成。可按以下前置由Owner进行离线UI和有线USB Preview，不是正式配对/UAT通过。本轮Agent没有启动应用、安装Hook、连接/写设备、烧录、Git写入或重新构建。
全局仍VERIFY/DLA_REVIEW，未手改路由。正式fresh/candidate/交测包和完整A01-A11仍独立待完成。

## 版本身份

- Preview token：preview-20261017T104547091113Z-0e6fcf；revision=2，build_round=3。
- 主JAR：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261017T104547091113Z-0e6fcf\runtime-jar-classpath\ahakey-studio-1.0.0.jar
- JAR SHA256：e8bbe9ee0dc3da54733d057c4bc2ab6ee8d12fa9bdc333290b4947f055e752e5。
- PREVIEW_RECEIPT SHA256：a60899a40bf0d341f4bd8fcb793a18fca350e683d8ad86f6fe73066d7da0d18c。
- 19个运行文件与两份绑定日志全部hash匹配；包资源与快照一致。构建退出0，-DskipTests跳过测试，283项只是第二轮复用。
- 固件HEX：C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\builds\ws3-cp2-resource-display-config\HID_Keyboard_582m_vibe_coding.hex
- HEX SHA256：D7D10510482228B74A2978BD8272F6A4E32668CF6B4F31F491A8503B0DC11E2E。
- 来源：WS3 CP2正式Gate C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\checkpoints\X1-AI-WORKFLOW-PRESENTATION\CP2\20261015T185611\gate-receipt.json，schema6 PASS，candidate 08dd24a6e8ce3526fef36661f5c97940add98a25。Gate SHA256 f9d0849a8a54b58dee20c2e11376c0dea2735434632958770a66152454b742c5，18项机器记录均pass；不是物理设备测试。
- Owner已明确确认本次键盘刷入这一份，原话见同目录OWNER_INSTALLED_FIRMWARE_CONFIRMATION.md；没有读Flash验证，不适用于换一块键盘。

## P1 启动前与运行方式

1. 保存IDE正在进行的工作，暂停自动AI工作流。通过托盘Exit正常退出旧AhaKey实例；关主窗口可能只是最小化，不能据此认为已退出。单实例锁只是辅助，不通过删锁/杀Java来强行启动。
2. **退出旧实例前先确认没有其他工作在使用BLE_tcp_driver.exe。** 旧/新应用的正常退出路径都可能按进程名结束所有同名桥接，不区分本窗口。本轮不点击BLE驱动按钮，也不安装/更新Hook。
3. 在应用退出后，把整个 C:\Users\20825\.ahakey 复制到一个新的带日期备份目录（例如桌面AhaKey-backup-20261017-首次预览）；确认能看到studio-draft.json、ai-runtime.json、preferences.properties等原有文件；已有oled-resources必须整目录备份，原本没有则记录不存在。不要只备份JAR。保留原始图片/GIF和设备当前各项设置截图。
4. 隔离仅针对源码和产物，**不是用户数据沙箱**。启动会读取现有草稿，可能迁移旧OLED草稿至.ahakey/oled-resources/v1并保存索引。随后编辑/关闭窗口也可能保存本地偏好。本轮没有替Owner做备份。
5. 包含JavaFX/JNA等依赖，不含JRE、BLE桥接及其配置、本地语音模型。使用本机已存在的JDK17；原model.enabled默认false未更改。系统语音与本地语音分开，不能宣称本地模型可用，也不是Lite/EXE安装包。
6. 启动真实系统语音键监听和127.0.0.1:8765起的Hook服务（占用时尝试至8774）；USB连接后Kimi桥接使用9000，BLE连接也依赖9000桥接。端口冲突应记录，不自行结束未知服务或安装Hook改端口。现有AI Hook可能触发请求/弹窗，离线体验时暂停这些工作流。
7. 先拔掉本次键盘USB，不点连接。不将模拟模式设为true；下列环境变量只设当前PowerShell进程，避免历史模拟开关导致假连接：

```powershell
$env:AHAKEY_STUDIO_SIMULATE_BLE = 'false'
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261017T104547091113Z-0e6fcf\runtime-jar-classpath'
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' '-cp' 'ahakey-studio-1.0.0.jar;lib/*' 'com.example.ahakey.Main'
```

不要用java -jar。配方是静态核对后给Owner执行，尚无运行成功证据。预期出现主窗口且未连接；无窗口/第二实例提示/JavaFX或端口错误先停止并回报，不绕过检查。启动日志在 C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261017T104547091113Z-0e6fcf\runtime-jar-classpath\logs\ahakey-studio.log。

## P2 离线UI和图片处理

点击键盘上的OLED热点。四个Mode分别看默认屏幕、SINGLE三态；MULTI三态应始终是同一份全局资源，共19个目标，不是28份。左侧为唯一成品预览，首次默认屏幕；MULTI旁应说明用于主槽位AI会话状态。

用测试副本导入静态PNG/JPG、透明图和合法GIF。预期160×80、完整等比/黑边、透明黑底、静图1帧、GIF按10fps成品播放；默认最大8帧、SINGLE/MULTI状态最大12帧。导入超过2MiB、不支持/损坏文件，或9帧默认/13帧状态时应有具体错误且不丢原草稿、不静默截帧。没有相应素材的分项记录未执行。

导入期间观察“处理中”、完成后草稿/帧数和左侧预览；不应假显示设备已应用。小窗口和长名字不能遮挡操作；100/150/200% DPI按实际测过的值分别记录。设备预览/上传/保存按钮离线禁用，本地资源导入可用。切灯光，拖亮度/改灯效仅改变本地模拟/草稿，不宣称实体键盘接受。

## P3 本地恢复与清除

用非重要测试图副本完成一次导入，正常退出应用后把该测试源文件改名（不要删除个人原图），重开同一命令：成品仍应恢复。更换失败不应丢旧成品。清除某个测试格只影响该格本地成品/索引；若有已应用基线，应先提示不会删除键盘上的资源。其他格、按键、任务槽和源文件不应被删除。

不要用真实.ahakey做写满磁盘/坏索引/权限破坏；这类故障注入留给隔离测试环境，不豁免A03。

## P4 有线身份与读取

已确认本次测试键盘固件身份后，再插USB并点连接；预期明确是USB HID路径，失败自动尝试BLE不能算有线通过。出现BLE桥接错误先回报，不点击BLE驱动按钮补救。

连接本身会走真实身份、按键/侧拨读回和原CP1模式偏好同步，不是纯只读会话。为避免实时AI事件干扰先暂停自动任务。查看“更多”中的设备信息入口，确认版本标识/睡眠配置能读取；0x9F版本或catalog只是能力线索，不能替代精确HEX确认。

进入OLED/灯光，点击“确认配对固件”，核对弹窗SHA与上文一致再确认。该按钮是对已刷入事实的声明，不会刷机。每次断连重连后重新确认，换设备重新核实；不要盲点。点击刷新设备配置，预期按当前集合读取且不覆盖已有草稿；没有本地成品但设备有效显示“设备已有”，读失败是未知/同步失败，不应当作空资源。

## P5 OLED上传

选择一个允许被替换的测试格，先保留该格原成品或接受无法恢复原自定义图的风险。应用不能下载设备原图，.ahakey备份也不等于设备Flash备份。

导入1帧小图，点击“上传并应用”，确认弹窗中的Mode和目标完全正确才继续。观察进度、目标/文件/Mode及其他竞争写按钮锁定，窗口可响应；只有完整提交ACK后才可报已应用。不是上传成功就保证立即播放，须由真实固件默认/AI状态触发；Quiet/Sleep有更高显示优先级。

依次在需要覆盖的Mode默认、SINGLE测试格及全局MULTI格验证目标，未测目标明确未执行。上传成功后刷新，确认设备元数据与本机对应。若原文件没有本地备份，不承诺可恢复旧自定义资源。首轮不要在上传中故意拔线；故障路径见P8。

## P6 灯光预览与保存

先截图记录当前亮度、当前Mode九项SINGLE灯效。改变亮度/下拉但不点按钮：只应改变草稿/左侧八灯模拟，不自动改实体灯光。

点击“预览”，成功ACK后才显示设备预览提示，临时约10秒，结束回固件真实状态而不是保证全灭；离开面板不立即发STOP。OFF可保存但其设备预览按钮应禁用。左侧模拟不是设备确认。

分别验证：只点“保存亮度”，不应顺带保存九项灯效；只点当前Mode灯效保存，不应保存未保存的新亮度。刷新并记录确认值；有草稿时回读不覆盖，不能把屏幕草稿误认为已读回值。九项保存逐条执行，不具有原子性；失败应指明进度/失败项并保留未完成草稿，不能宣称全部成功。任一成功保存应撤销临时预览；失败不重启10秒计时。

## P7 正常恢复、设备持久化和旧功能

只在上传/保存结束且无未知ACK时，断开并重连；本地成品/未保存草稿保留，重新确认配对固件、刷新。完成保存后给键盘真正断电（有电池时只拔USB不等于断电），重启回读已保存配置，触发实际状态观察。断电步骤不覆盖上传中断电故障。

回查普通按键/侧拨已有配置读回、设备信息、Windows切Mode稳定后不弹回、键盘切Mode界面跟随。用无敏感内容的测试文本框检查普通键/侧拨快捷键及已有系统语音路径；不在终端触发宏。仅在已有最新版Hook时测CP1 SINGLE/MULTI任务状态、主槽位与上传后最新状态补发；需要安装/更新Hook则记录受阻并回报，本轮不授权自动安装。物理实际任务状态才是结果，不凭发送日志当灯光通过。

BLE、本地语音模型、完整全量保存过滤旧0x84/85的协议轨迹仍需后续专门验证；不能仅看界面存在宣称WS001-004全回归通过。

## P8 失败与未完成验收

任何错误先停止进一步设备写，不连续重试，不自动清设备、恢复出厂、刷机或删除草稿。保存控制台、UI截图、时间、Mode/目标、连接方式和日志。

上传Begin成功后原资源可能已失效；即使Begin回FAIL也不能保证原资源仍在。Commit ACK未知时不要断言一定失败/成功。手动断开重连、重新确认固件并刷新元数据对账；只有状态已核清后再决定是否人工重传。未知期间不盲发同opcode请求，固件可能使用fallback。本地有效成品保留，用其人工重传才能恢复自定义资源。

本地数据需恢复时：退出所有AhaKey，保留本次.ahakey为另一份故障副本，再把启动前完整备份恢复到 C:\Users\20825\.ahakey；不在应用运行时合并覆盖，不把锁文件残留当作恢复成功。此操作只恢复电脑数据，不能撤销键盘Flash写入。键盘亮度/灯效按记录重新保存，OLED须有原成品重传；未知原图不保证恢复。

首轮未安排：上传中故意断连/掉电、丢失/迟到ACK、非法selector、磁盘故障等风险注入；A01-A11完整映射见PREVIEW_ACCEPTANCE_COVERAGE.json，所有未反馈项not_executed，不是Owner同意豁免。正式high-impact fresh、candidate、完整配对及真实验收继续独立完成。

## 反馈与下一步

直接在原DLA对话返回：P编号；通过/失败/未测；USB或BLE；Mode/资源格或灯效项；操作和现象；时间；截图；对应日志。无需搬运仓库已有HEX或commit；可以先报第一个阻塞，不必一次完成全部。

失败先分类：合同内实现Bug -> PREVIEW_FIX交DIB，实际差异轻审后重新打包；产品语义变化 -> contract-reconcile；协议/架构/范围变化 -> CHANGE。不得修改冻结包自修。收到实际反馈前不登记Preview PASS，更不填formal owner_uat PASS。
