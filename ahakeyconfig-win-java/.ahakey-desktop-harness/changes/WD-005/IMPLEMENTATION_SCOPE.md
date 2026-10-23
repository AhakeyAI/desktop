# 实现范围与实际代码依据

本页为拟授权路径，不是当前生产编辑许可。仅下列职责内最小修改；不整文件替换。
依赖扩大或新产品语义回CHANGE。新类名为建议，可在同职责下收敛；不同文件需先登记精确路径。

| 路径（相对仓库） | 观察到的现状与拟改 |
|---|---|
| src/main/java/com/example/ahakey/view/InspectorPane.java | :743亮度/九状态基本可复用；:1181旧OLED单Mode路径面板改资源分组、状态、确认/清除/进度；保留AI runtime区 |
| src/main/java/com/example/ahakey/view/CanvasController.java | :136热点复用；:180直接原图140×80预览替换为成品overlay；灯光改八灯同源模拟，不改按键热点 |
| src/main/resources/fxml/CanvasLayout.fxml | 仅OLED overlay、八灯绘制节点及必要约束；不改全局布局 |
| src/main/resources/style.css | 仅本面板资源格、预览、草稿标注、错误/禁用状态；遵循已有主题 |
| src/main/resources/messages_zh.properties | 已确认中文和本轮范围的状态/错误文案 |
| src/main/resources/messages_en.properties | 对应key的英文fallback；不改无关翻译 |
| src/main/java/com/example/ahakey/app/StudioController.java | :598/612/629旧0x91/0x85/0x84改CP2调用；:730/789文件导入/上传迁至服务；生命周期/Mode跟随/窗口清理关联 |
| src/main/java/com/example/ahakey/model/StudioState.java | :403旧OledModeDraft按Mode改十九目标引用；保留按键/语音/CP1字段，dirty与设备基线分开 |
| src/main/java/com/example/ahakey/model/OledModeDraft.java | 兼容旧数据读取，不用原源路径作为新库；可退为迁移DTO，不破坏旧json解析 |
| src/main/java/com/example/ahakey/model/LightEffectStyle.java | 复用0..16映射；未知ID不静默保存为OFF，局部unknown表示 |
| src/main/java/com/example/ahakey/model/OledResourceState.java（拟新增） | 十九目标、capacity、草稿/设备快照/结果、操作generation，模型中不做设备IO |
| src/main/java/com/example/ahakey/model/DisplayConfigState.java（拟新增） | 全局亮度和各Mode灯效草稿/回读基线/部分保存结果 |
| src/main/java/com/example/ahakey/util/OLEDFrameEncoder.java | :97黑底等比缩放/BE RGB565复用；:73静默截帧不能沿用；补GIF合成及成品预览一致性 |
| src/main/java/com/example/ahakey/util/StudioStore.java | :18现有~/.ahakey路径风格复用；旧字段幂等迁移、不得丢其他配置 |
| src/main/java/com/example/ahakey/service/OledResourceStore.java（拟新增） | 成品/索引原子提交、只清当前格、旧源路径迁移、IO失败显式上报；不删除用户源图 |
| src/main/java/com/example/ahakey/service/OledUploadService.java | 旧raw write+updatePicture/设备previewGif不能沿用；替换为CP2串行事务，身份/offset/ACK/CRC/恢复 |
| src/main/java/com/example/ahakey/service/DisplayConfigService.java（拟新增） | 按需读取、跨页面缓存/草稿合并、亮度与逐项灯效保存、设备预览状态 |
| src/main/java/com/example/ahakey/service/FirmwareLightSimulator.java（拟新增） | Java纯模拟时间/八灯颜色输出，对照只读固件psk_ws2812；不改固件、不发命令 |
| src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java | :57旧OLED常量保留兼容职责；新增CP2精确编解码/校验，不改0x87/0x90/0x95..0x99语义 |
| src/main/java/com/example/ahakey/protocol/AhaKeyResponseParser.java | typed0x88回复，ACK、未知状态/长度拒绝；不把status-only错误当完整成功 |
| src/main/java/com/example/ahakey/service/BleManager.java | :269命令锁、:810重连等待、:1043结束符重组需定向适配；lease、连接代次、replyselector匹配；保留原transport API |
| src/main/java/com/example/ahakey/service/UsbHidTransport.java | :208 extractFrame需CP2定长回复识别，保留64B报告；不改HID枚举/驱动/连接策略 |
| src/main/java/com/example/ahakey/service/AiRuntimeDisplayService.java | 只为CP2上传期间保留最新事实、发送准入及解除后重发最新快照；不改绑定/TTL/主槽位算法 |
| src/test/java/com/example/ahakey/displayconfig/（拟新增测试域） | 协议、转换、资源库、状态、事务、模拟器、UI测试替身；不得绕过正式入口自测一个未接线副本 |

实际仓库没有JUnit/TestFX测试基线。拟用上述测试目录中的无新增依赖Java断言入口，
显式失败退出并报告用例数；JavaFX控件与手动视觉验证分开，执行方式见ACCEPTANCE.md。
需要新增测试依赖/脚本时先追加CHANGE精确路径，不默认允许pom依赖扩张、网络下载或新构建系统。

## 实际观察边界

- UI依据为FXML/Java事件绑定和控件源码，本轮没有启动应用/拍真实窗口；不能声称已完成视觉验收。
- Inspector亮度和下拉编辑并未绑定connected禁用，预览/保存按钮才禁用；Canvas热点一直可点。
- IDEState显示顺序不等于协议代码顺序，必须用getCode()。
- StudioStore现有失败仅日志提示；新库不能继承静默丢草稿体验。
- 旧OledUploadService按总Flash减工厂预留后均分Mode的容量算法不适用于CP2固定19表。
- BLE通知与USB接收都扫描CC DD；0x88CRC字段需要同步修，不是只改固件发送端。
- sendCommand可能在等待响应时直接skip异步命令；上传后CP1最新状态不能被永久吞掉。

## 既有行为保护

保持0x00状态/Mode0x92、0x87按键、0x97侧拨、0x95睡眠、0x96语音、0x9F身份、
0x90/0x98/0x99 AI runtime原语义；只调整上传占用时发送准入。
保留Hook管理、语音路由、普通按键编辑、设备发现、USB/BLE连接生命周期。
不进入config_server.json、BLE驱动包、固件/eternal或Harness核心修复。
历史dirty原样保留，当前文档不替代后续baseline-start、Owner-bound隔离记录。

## 设计审阅与正式审阅

本任务为high_impact。独立设计检查仅核对本组文档的协议、状态责任、范围和Owner决策。
后续DIB提交后仍由原DLA读实际累计diff；正式验证另需绑定实际diff的fresh独立审阅。
不把本轮设计检查PASS用于免除未来实现审阅；不要求每次Preview迭代重走完整Grill。
