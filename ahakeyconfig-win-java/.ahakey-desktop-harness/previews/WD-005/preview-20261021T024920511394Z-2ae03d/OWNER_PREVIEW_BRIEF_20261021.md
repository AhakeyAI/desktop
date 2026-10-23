# 第九轮Owner Preview操作清单

本轮包静态核验通过，Owner已确认FFB920修复HEX。只代表可以执行以下预览，不是已通过。全局路由不变；正式fresh/candidate/UAT不在此自动通过。

## 先备份再启动

从托盘Exit退出所有旧AhaKey实例（会停止BLE桥接）。暂不启动BLE驱动，USB先拔掉，暂停不必要的AI运行。Hook默认8765、BLE TCP9000，不并行启动旧版抢占端口。若提示端口冲突，退出本次并检查旧实例，不安装Hook或盲改端口。

Owner在PowerShell逐行执行，勿替换成中文分号；DLA未执行以下命令：

```powershell
$backup = Join-Path $env:USERPROFILE ('ahakey-backup-WD005-R9-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (Test-Path -LiteralPath "$env:USERPROFILE\.ahakey") { Copy-Item -LiteralPath "$env:USERPROFILE\.ahakey" -Destination $backup -Recurse -ErrorAction Stop }
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$env:AHAKEY_STUDIO_SIMULATE_BLE = 'false'
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\previews\WD-005\preview-20261021T024920511394Z-2ae03d\runtime-jar-classpath'
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' '-Dsun.stdout.encoding=UTF-8' '-Dsun.stderr.encoding=UTF-8' '-cp' 'ahakey-studio-1.0.0.jar;lib/*' 'com.example.ahakey.Main'
```

新运行目录主JAR SHA256=97a5ae072c18a0ed229538fee7766426bd9f6c8ba807607aee10f141efa3052b，18依赖需同目录lib完整保留。包不含JRE、现场桥接和模型。启动会打开真实服务并使用用户数据，不是模拟沙箱。

## 操作与预期

1. 离线打开OLED/灯光：不再出现确认配对固件按钮；既有草稿资源/任务绑定保留；设备写入不可用并说明未连接，本地允许的导入预览仍可用。文字与中文日志可读。
2. 连接已确认固件的有线USB，不开BLE：读取中应显示读取原因，成功读到x1-c582-hw1-p1-1.0.0-r001后，相关设备操作自动开放；不需要人工HEX确认。若只显示基础V1.0.0或失败，不强行继续上传，发日志。
3. 核查灯光四分区：运行展示模式、亮度、单任务灯效、多任务任务槽。切SINGLE/MULTI，非当前模式操作实际禁用、原因可读；亮度不因模式单独误锁。任务槽本地说明不再与读取/未知原因冲突。
4. OLED默认屏幕先上传一张易辨认图片，只点一次并计时。预期明确成功且正确显示；如首次失败，先保留日志，不立即连点。成功后才测短GIF，检查名称/帧数/实际播放。上传/保存忙时冲突设备动作不可操作。
5. SINGLE：对工作中/已完成分别上传不同图片，触发一次明确Codex任务再结束；预期对应灯光和屏幕切换。等待中无法触发就记未执行，不算通过。空闲时记录是否再出现无来源闪灯。
6. MULTI：绑定两条可区分会话并设主槽，点应用后分别触发会话。预期对应槽灯变化、屏幕随主槽，未绑定槽不应自行亮；记录主槽结束与其他槽运行时的实际行为，RT-03仍待验证。
7. 灯光保存：先记原值，改亮度和一项SINGLE灯效，预览后分别保存并重新读取。预期只写目标配置，模式/其他项保留。测试会写设备持久配置；需要恢复时重新保存原值。
8. 无上传/保存活动时拔插USB：断连立即收回设备权限，重连须重新识别再开放；本地草稿/绑定不丢失。不故意在上传中断线，故障注入后续单独安排。
9. 回归查看设备版本、睡眠时间、按键/侧拨/Voice读回和Mode同步，避免无目的批量写入；异常明确记录。旧固件设备、长时睡眠、错误包及完整A01-A11未执行项不由本清单豁免。

## 停止与恢复

遇到超时、黑屏/重启、错槽、错误屏幕或按钮异常先停止新的写入，保存日志时间与截图；不要连点上传，不恢复出厂、不降级旧D7D105固件。先保留当前日志再安全退出，必要时在确认无活动写入后重新连接。
数据恢复：全部实例退出后，把当前.ahakey改名留存，再复制测试前备份为.ahakey。不覆盖现场BLE配置。PC数据恢复不回滚键盘Flash，资源/灯效需重新上传或保存原值。

反馈直接发原DLA对话：步骤号、USB/BLE、Mode、SINGLE/MULTI、预期/实际、发生时间及截图；日志为本运行目录logs/ahakey-studio.log。涉及会话/用户名可脱敏，但保留事件时间、状态和身份关联字段。DLA按Preview缺陷分类，不把局部成功登记完整UAT。

BLE先不做性能验收：现场EXE尚不能绑定新桥接源码，MTU/队列优化不能算已交付。需后续独立核对新桥接包再安排同图计时。当前固件仍是已接受CP2修复包，不包含后续CP2.5变更。
