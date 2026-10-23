# 产品基线

状态：未批准。本文记录第一轮 DLA 从当前源码确认的产品事实与已继承承诺，不代表商品机已实测通过。

## 已继承产品定位

继承 `DECISIONS.md`：

- 平时在后台工作，主窗口主要用于配置和排障。
- 用户目标是快速完成设置、确认设备可用，然后回到原本工作。
- Java Preserve First；不以 Rust 或全量重写作为当前方向。
- 新增或改变可见入口，需要基于真实界面的局部预览和 Owner 批准。
- Windows 对 Firmware 工作区只读；协议正式定义与设备事实不能由 Windows 单方制造。

## 当前源码确认的产品形态

- 应用是 Windows JavaFX 桌面程序，主入口 `com.example.ahakey.App`，窗口名 `AhaKey Studio`。
- 主窗口是单工作台结构：顶部状态/操作栏、左侧键盘预览、右侧属性检查器、底部状态栏。
- 核心能力集中在：连接设备、编辑/保存键盘配置、AhaType/语音输入、Hook 联动、灯效/OLED/GIF、BLE driver 管理。
- 配置编辑以本地草稿为中心；保存时通过 USB 或 BLE bridge 写入设备。
- 当前工程包含打包脚本和 BLE driver 查找/复制逻辑，但不是旧调查描述的完整 release/update/firmware 维护工程。

## 当前不能承诺的内容

- 尚未有当前运行截图，不能确认真实视觉、文本溢出、布局拥挤或高 DPI 行为。
- 尚未绑定 Firmware path，不能确认固件真实支持表、协议正式语义、ACK 语义或 capability/version contract。
- 未有真机证据，不能确认 USB/BLE 连接、保存、OLED 写入、语音键路由、Hook 写灯在商品机上实际可用。
- 当前无测试目录；旧调查中“大量 JUnit 覆盖”不适用于本目录当前事实。
- 机器编译在临时 JDK 17 环境下通过；默认 Maven runtime 仍指向 Java 8，需要后续修正工具链配置。

## 明确不改

- 本轮不修改生产 Java/FXML/CSS/资源/构建/驱动代码。
- 不自动批准产品基线。
- 不把历史问题自动升级成本轮实现任务。
- 不创建 DIB 任务，不切换角色。
