# WD-011 ACR4 实现报告（revision 3 / build_round 3）

## 身份与范围
DIB 在 C:/Users/20825/.codex/worktrees/wd010-zxy-20261105/ahakeyconfig-win-java 基于已保存 1.0.22 HEAD 553af14068aaa982753aef05b77aea373c6cc983 实现；原始 start 不变。有效 CONTRACT.md + CONTRACT-ACR4.md，revision3 加入 DeviceSyncService 最后 ACK 依赖。Firmware candidate bb6a31ed5ed3f3811e3f9b32b3c93e1ce362f4a3 / HEX EAFFD569 配对。
本轮没有 Git 写、安装、kill、下载、真机写入、固件脚本或固件文件修改。主目录 dirty 不动。旧标准报告、submission、receipt、verification 原字节保存 evidence/implementation-acr4-r3/previous-implementation-records；此报告仅绑定新实现。

## 实际差异
- 新 LosslessResourceEncoder/Protocol/Service：独立 ACR4 原画质编码及状态机，RGB565/160x80/100ms 不变，RLE 仅严格较小时采用，否则 RAW；金样 SHA 与展开 CRC 匹配。严格长度/代次/token/sub/能力校验，STATUS 消歧，COMMIT 元数据核对，cancel-or-uncertain，90秒恢复/120秒清理边界。v3 生产编码/协议/服务源未改。
- OledUploadService/DisplayConfigService/StudioController：原画质默认 v4；只有明确 UNSUPPORTED 提示并再次确认兼容 CP2。取消/连接代次变化不写，未知/中途失败不降级。快速 v3 原入口保持；进度含确认字节及 RAW/RLE。
- OledResourceState/Store：旧资产保留，单独持久化上传协议/帧/展开字节/CRC 身份；重启元数据以该身份对照，旧记录兼容。
- CommandSessionArbiter/BleManager：整个上传会话排除普通设备命令（含00、Hook、模式、USB/TCP），先等旧在飞命令完整终结；普通超时/取消/可能写失败锁存 UNKNOWN 到新连接。80准备到整块81回复保持 raw 所有权；每次等待唤醒重新检查 owner/generation；同步消费保持事务锁，不让下一消费者清空/偷取 ACK；旧 async ACK 不满足新同opcode同步请求。上传不重放过时状态，K1 保持原有 latest runtime 释放语义。本地 bridge 查询不占设备帧会话。
- K1RouteProtocol 只增加 v4 分帧入口；仲裁 K1 BEGIN nonce 在12..15，其余请求5..8，完整真实 K1 保存+读回+嵌套描述保存已测。DeviceSyncService 改为逐命令等待 ACK，最后FAIL/中途FAIL/取消不会误报完成。

## 实际机器检查及限制
完整日志、退出码、输入和日志 SHA 见 evidence/implementation-acr4-r3/RESULTS.json；复跑命令见同目录 REPRODUCE.ps1。Java17 离线 javac 全生产编译通过，最后仲裁/K1修正重新编译通过。
通过：ACR4 5784断言，真实 BleManager 仲裁/普通保存/K1完整保存55，v3 Compact394866，v4真实Controller+FX13、v3真实FX19，K1分帧/Hook回归、恢复603/恢复竞争7、显示灯光真实FX36、语音AhaType真实业务链32。断言数包含逐字节/逐像素，不是同数量独立场景。真实截图保存 ui/。
独立预审发现 K1 BEGIN nonce 兼容缺陷；先保存真实红测 k1-begin-red.log，再修偏移，最终全链通过。初轮 K1 latest runtime 失败已修复；语音旧入口 ClassNotFound 是错误包名，正确 service.VoiceFinalChecks 已过32；这些初次失败原日志均保留。
以下旧测试真实退出1，不记PASS，亦不是基线失败：DisplayConfigChecks 的旧CP2-only mock不能回答新增默认v4 CAPS；Isolation/Race/Round5 仍断言上传结束重放 runtime，与新批准契约相反。它们终止后的分支未覆盖，不以该runner声称通过；新实际v4/v3/显式CP2 UI、仲裁、显示FX、K1测试分别覆盖本轮有效行为。原测试源码未修改或降低断言。
C04-basic-version-fallback-false 是前轮已经在1.0.21对照确认的 NOT_FIXED_BASELINE_DEBT，沿用原证据，未改无关catalog语义、未重复认定通过。

## 产物与交接
当前仅隔离classes可用于机器检查，尚无1.0.23安装包，不以旧1.0.22 EXE冒充本轮产物。没有真机USB/BLE、HID键盘、Key3/电源或Owner UAT结果。未宣称实际上传速度改善数值。
下一步 DLA actual diff + 独立 high-impact review，合法 Preview/build 路由后再制作1.0.23 Local Model EXE。原五项UI/日志/BLE外观修正仍延期。本轮DIB不自批审阅或UAT。
