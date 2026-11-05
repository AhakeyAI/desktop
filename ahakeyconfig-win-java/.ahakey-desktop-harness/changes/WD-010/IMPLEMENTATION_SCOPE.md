# WD010 实现文件边界

状态：待批准Contract的范围清单，不是DIB开工授权。允许路径与change.json一致；无需改动的文件不必为凑清单而修改。新增文件按职责拆分，改名或范围外依赖须先由DLA调整草案/正式revision。

工作目录：C:/Users/20825/Desktop/windows软件代码/desktop/ahakeyconfig-win-java。所有下列路径相对该根。

## 入口、窗口与状态（仅本任务接线、只读控制和状态显示）

- src/main/java/com/example/ahakey/App.java
- src/main/java/com/example/ahakey/app/StudioController.java
- src/main/java/com/example/ahakey/model/StudioState.java
- src/main/java/com/example/ahakey/model/DeviceStatus.java
- src/main/java/com/example/ahakey/model/DisplayConfigState.java
- src/main/java/com/example/ahakey/model/FactoryResetState.java
- src/main/java/com/example/ahakey/view/TopBar.java
- src/main/java/com/example/ahakey/view/InspectorPane.java
- src/main/java/com/example/ahakey/view/CanvasController.java
- src/main/java/com/example/ahakey/view/CanvasPane.java
- src/main/java/com/example/ahakey/view/StatusBar.java
- src/main/java/com/example/ahakey/view/FloatingVoiceNotification.java
- src/main/java/com/example/ahakey/view/CloudAccountDialog.java
- src/main/java/com/example/ahakey/view/FactoryResetDialog.java

## 云端及语音接缝（保留当前识别引擎和录音代次）

- src/main/java/com/example/ahakey/service/AhaTypeService.java
- src/main/java/com/example/ahakey/service/AhaTypeConfig.java
- src/main/java/com/example/ahakey/service/CloudAccountManager.java
- src/main/java/com/example/ahakey/service/VoiceInputManager.java
- src/main/java/com/example/ahakey/platform/windows/WindowsCredentialStore.java

## 工厂恢复、传输与目标写入约束（不修改固件协议定义或刷机算法）

- src/main/java/com/example/ahakey/protocol/FactoryResetProtocol.java
- src/main/java/com/example/ahakey/protocol/K1RouteProtocol.java
- src/main/java/com/example/ahakey/service/FactoryResetService.java
- src/main/java/com/example/ahakey/service/FactoryResetStore.java
- src/main/java/com/example/ahakey/service/BleManager.java
- src/main/java/com/example/ahakey/service/UsbHidTransport.java
- src/main/java/com/example/ahakey/service/K1RouteService.java
- src/main/java/com/example/ahakey/service/DisplayConfigService.java
- src/main/java/com/example/ahakey/service/AiRuntimeDisplayService.java
- src/main/java/com/example/ahakey/firmware/DeviceMaintenanceCoordinator.java
- src/main/java/com/example/ahakey/util/StudioStore.java

## 文案、二维码依赖与定向检查

- src/main/resources/messages_zh.properties
- src/main/resources/messages_en.properties
- pom.xml
- src/test/java/com/example/ahakey/wd010

## 责任与限制

- App仅负责新服务生命周期/退出资源；不得修改安装、更新或Hook策略。
- StudioState/StudioStore仅负责新状态、目标草稿隔离和恢复读回，不重写全局持久化格式或删除无关配置。
- 视图沿现有JavaFX风格；恢复菜单替换旧功能，不全局改版。
- BleManager/UsbHidTransport/K1RouteProtocol必须保持既有共享0x9E帧边界、连接generation和事务隔离；新恢复解析不得接受旧ACK。
- DeviceMaintenanceCoordinator仅增加与工厂恢复配合的权限及生命周期；现有刷机备份恢复Service不在修改范围，不调用它回写旧配置。
- pom.xml仅添加经核对的二维码必要依赖，不更换Java/JavaFX/JNA/Sherpa版本，不下载模型。
- wd010测试目录用于本任务真实接缝、故障注入及组合回归；既有检查照常执行，不降低既有验收断言。
- Firmware、eternal、BLE_tcp_bridge及Harness核心不在范围。若需要改后端、协议定义或扩展生产文件，先回DLA。

## 交接前置

完整Contract批准、可恢复Git起点及Harness正式IMPLEMENT路由。DIB收到草案/复制提示词不等于已授权开工。交测仍须实际审阅、独立高影响审阅及适用Preview流程、候选/产物/固件绑定。
