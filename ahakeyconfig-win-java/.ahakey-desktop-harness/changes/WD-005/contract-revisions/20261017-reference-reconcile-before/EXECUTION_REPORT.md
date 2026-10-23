# WD-005 执行报告

日期：2026-10-16。Windows DIB；已批准 revision 1，J005/J006，high_impact。
这是实现与机器检查记录，不是 DLA 审阅、Owner Preview、正式交测或真机通过证明。

## 身份与授权

- HEAD/原起点仍为 `41c034171e60b2d4962b0adbe8f3cffbf80a0436`，无 Git 写入。代码指纹由正式 record-check/submit 绑定，不重写原 start。
- 沿用 REGISTRATION、change.json 和 20261015-wd005-owner-scope-approval.json。草案状态文字是历史快照，没有重写旧批准。
- Owner 初始禁止构建。DIB 后续明确询问“仅本地编译与离线测试，不打包、不连接或写入设备、不做 Git 写入”，Owner 回复“继续”；DIB 在执行前重述此窄授权。未扩大为正式应用启动或交测包授权。
- 历史 Harness 维护、WD-002/WD-004 记录、config_server.json、BLE 驱动包和 rollback backups 原样保留；未改 Harness 脚本/规则/seal、固件或 eternal。
- 最终 DIB preflight exit 0，只说明当前范围/阶段可工作，不代表业务验收。
- 固件沿用 REFERENCES 中 08dd24a6e8ce3526fef36661f5c97940add98a25 与指定 Gate/HEX；不声称设备已刷入或 Windows 已配对通过。

## 实际差异

| 文件（Java 路径均在 com/example/ahakey 下） | 本轮职责 |
|---|---|
| model/OledResourceState、DisplayConfigState、StudioState、LightEffectStyle | 19 目标、草稿与设备事实分离、失败/应用/未知状态；亮度和 4×9 灯效独立草稿；未知不转 OFF |
| service/OledResourceStore | .ahakey/oled-resources/v1 成品/索引原子提交，CRC/填充校验、重启恢复、清除墓碑/共享引用保护；无自动旧版本清理 |
| util/OLEDFrameEncoder | 黑底等比 160×80、RGB565BE 反解预览；GIF 偏移/disposal2/3；8/12 帧拒绝、2 MiB 与解码像素限额 |
| protocol/AhaKeyProtocol、AhaKeyResponseParser | 0x88/89/8A/8B/8C/8E、LE 元数据、长度/目标/ACK 校验，保留旧协议语义 |
| service/BleManager、UsbHidTransport | 二进制定长回复、整笔 lease、固定传输/连接代次、迟到 ACK 隔离；CP2 USB 写失败不盲重发 |
| service/OledUploadService | Begin/顺序 Chunk/Commit 逐 ACK；Commit 前持久化恢复阶段；本地异常先隔离，再释放 lease |
| service/DisplayConfigService | 单后台队列、按需读取/过期结果丢弃、草稿保护、旧路径幂等迁移、冻结目标上传、失败对账、亮度/灯效独立保存和部分成功 |
| service/FirmwareLightSimulator、AiRuntimeDisplayService | 同源 17 种八灯 50ms 模拟；事务期间仅保留最新 CP1 事实，不将跳过发送当成功 |
| app/StudioController | 选择/确认/清除/预览/保存接入；当前连接固件确认；断连/模式保护；全量保存入口过滤旧 0x84/85，未修改 DeviceSyncService |
| view/InspectorPane、CanvasController | 原热点与右侧布局、默认/SINGLE/MULTI、每格文件入口和统一上传、左侧成品/草稿 overlay；显式灯光预览/独立保存、亮度手输提交 |
| fxml/CanvasLayout.fxml、style.css、messages_zh/en.properties | OLED 160×80、八灯节点、局部样式/文案；无全局重构 |
| src/test/java/com/example/ahakey/displayconfig/ | 两个显式断言入口；真实编解码/上传/服务/FXML、内存 transport、临时目录，无新依赖 |

复用 JavaFX、Jackson、JDK ImageIO、原画布/Inspector、现有传输。OledModeDraft/StudioStore 保留旧字段作为迁移来源，未改文件。
没有 CP1.5、0x8D 清设备资源、硬件 GIF 预览、整图下载、颜色调节、安装包或 Release Batch。

## 实际检查

完整命令（本仓库执行，Maven 离线，无依赖下载）：

```powershell
$env:JAVA_HOME = 'D:\jdk-17.0.19.10-hotspot'
& 'C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd' -o -DskipTests test-compile
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' '-Djava.awt.headless=true' -cp 'target/test-classes;target/classes;target/lib/*' com.example.ahakey.displayconfig.DisplayConfigChecks
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' '-Dfile.encoding=UTF-8' -cp 'target/test-classes;target/classes;target/lib/*' com.example.ahakey.displayconfig.DisplayConfigFxChecks
git diff --check -- src/main src/test
python .agents/skills/ahakey-desktop-harness/scripts/desktop.py preflight --id WD-005 --role DIB
```

最终 compile-06 exit 0：65 个生产源文件、2 个测试源文件编译。
offline-05 exit 0：175 项显式断言；fx-02 exit 0：36 项。合计 211 项，不是 Maven 零用例成功，也不是 211 项完整产品验收。
diff --check 和最终 preflight 均 exit 0。日志全名及哈希见 IMPLEMENTATION_CHECKS.json。
Maven 仍有 6 条 JavaFX 依赖模型警告，FX classpath 启动有 unnamed-module 警告，没有隐藏。

保留历史：compile-01 因 Maven 旧 JDK 失败，compile-02..06 临时 JAVA_HOME 后成功，无系统配置修改。
offline-01 日志末尾显示 101 项通过，恢复时进程 ID 已失效，不补造其退出码。
offline-02/03 的 GIF 断言失败来自测试夹具默认调色板，解码为深蓝。修正夹具显式调色板后，红/绿/蓝预期不变，offline-04/05 通过，没有放宽生产代码或断言。
fx-01 为 32 项；fx-02 增加手输亮度、空值和边界 4 项。
曾尝试 build-open，因 review pending 被拒绝，没有构建 token；后续仅为已授权机器编译，未伪造正式构建。

## 分层覆盖

本表“已执行”只是对应检查的范围，不将整条 A01-A11 标 PASS。未执行项目仍保留在验收中。

| 项目 | 已执行 | 仍待验证 |
|---|---|---|
| A01 | 19 容量、唯一映射、模式/分组/冻结选择 | 完整 Inspector 和跨 Mode 操作 |
| A02 | 独立 RGB565、静态/透明/黑边、GIF 偏移/disposal2/3、8/9/12/13 边界、损坏/超大小拒绝、FXML 成品像素 | 更多真实样本、选择文件/弹窗体验 |
| A03 | 无源文件成品重启、清除墓碑、崩溃阶段恢复、损坏索引保护、草稿标记 | 真实只读/写满/进程中断、旧路径迁移全流程、共享引用清理专项 |
| A04 | 真实服务首连接零全量读、OLED 14 条/灯光 10 条、保护草稿、设备已有、错误目标 | 快切页面/真实读取时延 |
| A05 | 1/8/12 帧实际上传链，逐包 offset/内容/CRC/填充、BLE 17 处分片/粘包、CRC 内头尾字节、USB 提取 | 物理 USB/BLE 吞吐、确认弹窗 |
| A06 | 真正 15 秒超时、迟到 ACK、连接代次、Begin FAIL、本地异常先隔离、Commit 未知模型对账 | 各阶段实机断连、Flash/丢 ACK、原生 reader 阻塞生命周期 |
| A07 | 真实服务第 5 项失败停止；前 4 项清 dirty、后 5 项留草稿；亮度独立；OFF/未知 | 实机保存和九状态触发 |
| A08 | 17 个初始 tick/100 亮度常量金样、移动边界/反弹/35 亮度、300 tick 范围；ACK 预览、保存 FAIL 保留仅余 2 秒期限、成功结束、离开零 STOP | 更多相位、实体颜色/光度、真实 10 秒和最新 presentation 恢复 |
| A09 | 隔离 Canvas FXML 成品/草稿/占位/八灯/锁定；断连可本地编辑、不写；真实亮度 Spinner 手输/空值/范围 | 完整最小窗口、100/150/200% DPI、全 Inspector/长错误文本 |
| A10 | 旧协议字节/ACK、其他草稿 JSON 不变、12 类竞争入口和 raw data 阻止、最新 runtime 只补一次 | 真实按键/侧拨/语音/Hook/模式/连接切换/CP1 |
| A11 | 原 HEAD/批准保留、日志/截图哈希、无设备访问 | actual/fresh review、Preview、Git candidate、包/固件身份、真机/UAT |

灯效常量从固定固件整数方程独立整理，不由生产 Java 函数生成；初始相位通过不代表全部相位/实体光度通过。
FX 测试没有创建 App/StudioController，没有启动 Hook/语音/桥接、Socket/HID 枚举或设备连接。临时库、隔离 Scene 800×600 截图已查看，但不是完整应用/高 DPI 验收。

## 产物与 DLA 接续

仅机器编译 classes/test-classes 和组件截图；没有本轮 JAR/EXE/安装包、正式构建回执、Preview 或候选提交。不得拿旧 target 包验收本轮。
重点交 DLA 检查累计实际 diff：共享传输互斥/断连、CP1 补发、本地索引事务、旧全量保存过滤和可见状态。
原 DLA actual review 通过后按正式流程准备 Owner Preview；正式配对仍需高影响 fresh review、Git candidate、实际包与固件身份。构建另获授权，DIB 不自批审阅/UAT。
下一次交接必须在聊天正文完整展示中文 Prompt。
