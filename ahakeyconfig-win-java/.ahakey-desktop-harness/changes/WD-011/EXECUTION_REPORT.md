# WD-011 DIB 实现报告（round 1）

## 身份与范围
工作目录：C:/Users/20825/.codex/worktrees/wd010-zxy-20261105/ahakeyconfig-win-java。
已保存基线 HEAD 98a58926b787f7bbe18794ea04c6355361289454；Contract revision 1，批准“采用双选项，快速上传先预览”。开始代码指纹 d7b7fccda079eb0994892199ed6edf41760d0202ef71bd4a5d4e6cf9ec63a58b 保持不变；当前每个 allowed input 的 SHA256 见 evidence/implementation-r1/RESULTS.json，完整提交指纹由本轮 submit 回执绑定。
DIB 开始及提交前 preflight 均 PASS。主目录历史 dirty、Firmware 和 eternal 均未写；未 Git add/commit/push。DLA 同步的治理记录不归 DIB 生产改动。

## 实际差异
- CompactUploadProtocol：严格 ACR3 帧长、nonce/token/sub/status、完整 CAPS 校验；K1RouteProtocol 只增加 v3 帧界定入口，v1/v2 原路径保持。
- BleManager：DisplayLease 内增加单在途 ACR3 交换，USB/BLE 原通路与维护权限保持；迟到异 token/sub 回复忽略，断连后旧 finally 不清除新代次请求；超时隔离由事务层在 lease 关闭前设置。
- CompactUploadService：每次上传协商，BEGIN 携 header 后从 offset16 上传，USB40/BLE128；迟到同 token CHUNK ACK 经 STATUS 消歧；仅 offset 未前进可有界重发，BEGIN/COMMIT 不盲重发，提交以匹配 VALID/帧数/展开长度/CRC 的元数据确认。失败保留草稿并隔离后续写，不跨连接续传；总600秒、恢复90秒、块最多5次。
- CompactResourceEncoder/OLEDFrameEncoder：复用 GIF 合成，保留合法时长；固定16色共享palette、80x40，确定性加权median-cut，最近邻展开、AT03及FF尾；不自动删帧/降尺度。
- OledResourceState/OledResourceStore：旧零尾资源仍可读取，新增编码对象 sidecar 与展开字节严格对应校验；index 原子替换，旧草稿在写失败前不覆盖；清除本地记录同时清除关联 compact sidecar。
- DisplayConfigService/StudioController/CompactUploadPreviewDialog/InspectorPane：原入口双模式，本地转换后显示实际像素/时长/字节，确认预览保存草稿，再单独确认上传；确认中设备代次改变则停止。取消预览不改变旧草稿，不发设备命令。
- CanvasController：仅 OLED 预览按资源真实帧时长播放；未改画布布局或跨屏策略。上传进度保留原百分比前缀，增加已确认字节数。
- 新增 wd011 离线测试及交付包复制金样，来源 SHA 见 src/test/resources/wd011/SOURCE.json；未执行任何固件脚本。

## 已执行机器检查
JDK17、离线 Maven test-compile PASS，最终日志 compile-05.log。完整命令、耗时、退出码、源输入哈希、日志哈希见 evidence/implementation-r1/RESULTS.json。
通过：CompactChecks 394868断言（主要为逐像素/填充金样，不代表同数量独立场景）；CompactUiChecks19条真实JavaFX/服务断言、3张截图；DisplayConfigChecks/Isolation/Race/Round5；Revision3 72条；DisplayConfigFx 36条；K1RouteProtocolChecks；RestoreChecks/RuntimeRestoreRaceChecks；VoiceFinalChecks32条。
失败历史保留：进度前缀导致Revision3失败已修生产文本并复跑原测试通过；VoiceFinal首次入口package错误，改正确运行命令后通过，无测试门修改。
**NOT_FIXED_BASELINE_DEBT**：DisplayConfigCapabilityChecks 在 C04-basic-version-fallback-false 失败。相同测试在实际1.0.21包内JAR仍同点失败：旧断言要求 V1.2，原产品返回 V1.2（完整标识未读到）。DeviceStatus本轮未改；按DLA指示保留当前/基线对照，不算PASS，不修改旧测试或catalog语义。受影响用例后续分支未声称覆盖。
本轮无设备/麦克风/键盘注入/固件写入，USB/TCP均内存fixture。独立UI启动不执行App.start、不连接硬件；本地转换/预览/保存草稿证实零设备写。

## 实际可运行产物
当前只有 target/classes 和 target/test-classes 离线检查输出；尚无本轮JAR/EXE交测产物。1.0.22 Local Model 打包等待DLA实际审阅、候选与BUILD_ONLY路由；不把compile或旧1.0.21包当新包。

## 交给 DLA
需实际累计diff审阅、独立high-impact审阅、Git候选、合法隔离打包及产物身份；不自批review/UAT。
配对固件为6CB9958A047E57885F272FD0715C1DC4AD9D1AD4A8E4880E71243A74DDFF0624（HW1，709c546a）。真实USB/BLE耗时、设备像素/时长、断连/重连元数据和断电表现待Owner联调，不声称30–60秒或实际加速倍数。
不提供上传中取消按钮；失败写隔离需重连，状态查询不解除隔离。1.0.22向前兼容旧资源，若已保存新的compact资源后降回1.0.21，旧零尾校验器不能读取这些新资产；旧版降级不在本轮验收承诺，需保留用户资源库备份。
前五项语音工具栏/日志目录/跨屏尺寸/键盘布局/BLE外观筛选全部延期，桥EXE未改；打包patch换行问题由DLA正式配方记录处理，DIB不改manifest或冻结snapshot。
