# WD-005 第七轮 Preview：当前只开放离线 UI

本包完成身份核验，但设备配对仍写着旧固件，暂不执行设备上传/应用/确认。具体身份见同目录 DLA_HANDOFF_VERIFICATION_20261020.md；不要求回刷旧固件。

## 开始前

1. 从托盘正常退出旧 AhaKey Studio。新包并非独立用户环境，仍读写用户 `.ahakey`，不要同时开两个版本，不手删锁文件。
2. 断开目标键盘 USB 和 BLE，正常退出桥接。`SIMULATE_BLE=false` 不等于硬件隔离，启动会建立真实服务。
3. 退出后备份 `%USERPROFILE%\.ahakey` 整个目录；至少涵盖 studio-draft.json、ai-runtime.json、oled-resources/v1。可由 Owner 手动执行下面的复制命令；DLA没有替你执行。

```powershell
Copy-Item -LiteralPath "$env:USERPROFILE\.ahakey" -Destination (Join-Path $env:USERPROFILE ("ahakey-backup-wd005-r7-" + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))) -Recurse -ErrorAction Stop
```

运行仍使用单实例文件锁 `.ahakey/.ahakey-studio.lock`，Hook 服务8765、桥接相关9000端口。若已有服务占用，保留错误与进程信息反馈，不自动杀无关进程。退出应用存在停止所有同名 BLE_tcp_driver.exe 的既有行为，会影响其他使用该桥接的实例。

包不含 JRE、BLE_tcp_driver.exe/配置、本地语音模型。不是 EXE 安装包或全功能自包含应用。默认 model.enabled=false 未改变。

## 启动

以下逐行执行；不要把换行替换为中文分号，不使用 java -jar：

```powershell
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$env:AHAKEY_STUDIO_SIMULATE_BLE = 'false'
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261020T065100738948Z-669e97\runtime-jar-classpath'
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' '-Dsun.stdout.encoding=UTF-8' '-Dsun.stderr.encoding=UTF-8' '-cp' 'ahakey-studio-1.0.0.jar;lib/*' 'com.example.ahakey.Main'
```

主 JAR SHA256：c0b3f122fc2f69021514e5ed910265ef1b3c205f722da14f105dfc87b00022b1。
配方已静态核对，DLA未执行启动。

## 本轮可做的离线步骤

1. 打开 OLED 页面，查看卡片标题、资源名、帧数、禁用状态文字。预期不再白底白字，中文日志可读；未连接和固件未确认提示属于预期。
2. 查看默认屏幕/SINGLE/MULTI分类和灯光页面。预期 OLED 多任务入口附近提示开关位置；灯光区按模式选择、亮度、单任务、多任务排列，非当前模式部分浅色且不可编辑。离线不能据此要求切换模式的设备 ACK 成功。
3. 在允许本地操作的资源项选择图片/GIF，检查本地名称、帧数和预览；取消选择应不误报上传成功。选择文件只改本地草稿，不等于已上传。若离线按钮锁定，记录截图，不绕过锁定。
4. 正常退出、重新启动后核对本地草稿保留情况。不得点击确认配对固件、上传并应用、设备保存、BLE驱动或 Hook 安装。

失败时保存截图、操作时间、控制台原文和运行目录下 `logs/ahakey-studio.log`，在原 DLA 对话反馈；日志可以作为附件，不必粘贴整段到正文。区分“显示难读”“本地草稿问题”“启动异常”和设备问题，未测项明确写未测。

恢复：先正常退出所有 AhaKey，保留失败现场 `.ahakey` 副本，再从开始前备份恢复用户数据；不能运行中覆盖。启动旧包不代表自动回退用户数据，更不自动恢复设备配置。需要恢复时交回 DLA 指导，不自动删除目录。

## 设备测试计划，当前未开放

先修正 Windows 配对身份并生成新包，再核对设备实际刷入的是已接受 HEX；不把上次确认旧 HEX 当作新固件证明：
`C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\builds\ws3-cp2-memory-safety-20261018\HID_Keyboard_582m_vibe_coding.hex`
SHA256：FFB9208F79084AA24A832AD2562A14DBBEA5DF4D114A135CB5B2EB98D4E05539。
这里只给仓库身份，不授权自动烧录或声称已刷入。

届时依次执行：

1. USB版本/能力/Mode/睡眠读取，保留WS001-004回归；预期真实设备一致，不因CP2修改丢失旧功能。
2. 默认屏幕单张首传、重传及短GIF，记录开始/结束/错误/耗时；上传时相关控件和其他写入正确互斥，失败不假成功。未经单独安排不主动制造高风险断电。
3. SINGLE工作/完成及可触发的等待状态；MULTI绑定真实会话、主槽位、终态、超时和重连；预期不由其他会话抢占、不恢复过期事实。RT-03和来源缺失事件单独记录。
4. 灯光亮度和模式对应编辑、保存/取消、全量保存旧命令过滤。不能仅凭界面提示证明设备持久保存成功。
5. BLE必须先完成桥接实际复审、构建身份及受控替换，再用同一资源对比上传耗时、ACK和日志；不使用旧现场 EXE 的结果宣称新桥接优化通过。

以上是后续计划，不是已执行。formal fresh、candidate、真实配对和 Owner UAT 继续独立收口。
