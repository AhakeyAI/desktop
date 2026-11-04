# WD-007 R6 固件兼容、恢复与可见桥实现报告

DIB；effective Contract revision6 / build_round9。实现及离线检查完成，交主 DLA 实际审阅；不代表独立审阅、真机通过或正式发布。R5 顶层报告与历史副本字节一致后才替换当前报告；全部 R5 历史与 1.0.15 EXE 保留。submit 后本报告冻结，构建另写报告。

## 最终行为

统一当前连接能力：精确支持 HW1/HW2 1.0.1-r001 及既有 HW1 1.0.0-r001；有效完整 9F 通用 ACK 进入旧版普通配置兼容层，超时、坏包和未知完整身份不冒充旧版。业务入口消费当前代次能力；OTA 信任和随包 HEX 未扩展。旧版普通键/K1/灯光只发送明确编辑内容及设备 ACK，未读回的其他键不以占位值覆盖；无编辑不发送保存。旧版值明确是本地草稿，不假造读回确认。

正式固件恢复逐项核对19项 kind2 元数据，全部有效且无 WRITING 才解除隔离；EMPTY/INVALID 仅表示可继续普通操作，不声称旧上传成功。失败不再 finally 发布假连接，保留登记并允许重试。旧版仅用当前有效9F ACK和合法00状态恢复普通通信，保留 device-recovery.json 原记录及上次资源保存结果未知，禁用无证据扩展读回和原始资源写入。断开 UI 使用转换后代次；旧业务完成仍按原代次隔离。修正实际 BLE 模式读取仍使用旧桥命令的问题，统一走当前设备状态命令。

桥在同一个 ManagedBridge、BleCore 和 TCP owner 内增加 WinForms 控制窗口；列表显示名称与地址，连接/断开/刷新经 Java 协调器，窗口不直接写设备。X 隐藏、托盘可恢复，既有桥普通点击只唤起窗口，不枚举/重启连接。记住最近实际成功 BLE 名称和地址；启动候选与 USB 优先、手选、显式断开互斥，拔 USB 不后台切 BLE。选择携带窗口所见 connectionIntent/generation/target authority，验证与新意图获取原子化；迟到 A 或空会话选择不能抢占 B，迟到桥断开不能断开 USB。重显示不会重复启动 IPC server。

灯光草稿按目标隔离，切目标及同地址重连均清除旧的干净观察事实；用户明确编辑的草稿保留。亮度/模式保存必须有当前读回或明确编辑，不把默认值、A 的旧值或同地址旧代次值写到当前设备。

## 验证与真实边界

最终 Java compile-08 BUILD SUCCESS；新桥 bridge-build-02 PASS，桥 SHA256 6d0506fe4151a802597e0f34402dd7bedfaf4a8cb81263f44cf13aad23ea1569。真实编译 WinForms 隔离 smoke-03 验证创建/显示、两地址、关闭隐藏/重新唤起、选择意图和所属窗口退出；私有 IPC-02 29项通过，无真实蓝牙枚举或 GATT。

最新有效34类回归全部通过：完整 checks-02 为33通过、矩阵夹具 OLED padding 失败；只修正夹具的有效帧与填充范围后，matrix-03 exit0，3895条断言通过。不能称完整02轮首轮34/34。所有最终日志SHA已核对，命令/退出码/日志及源码身份见 MACHINE_EVIDENCE_R6_20261101.json。

六组合为 HW1/HW2/有效无完整身份旧版 × 内存USB/真实私有IPC模拟BLE：身份、状态、适用普通键/拨杆/睡眠/模式保存及读回；正式版实际 K1 分块/CRC/提交/读回、完整 OLED 单帧上传与读回；旧版仅明确编辑的普通键/K1/灯光 ACK，未编辑键不写、无编辑不保存；恢复失败/重试、保留未知旧资源记录、换目标与同名异地址、窗口唤起、USB优先、迟到选择/断开及灯光隔离。测试覆盖真实生产服务入口，但响应来自已核对候选协议的模拟端，不是物理设备测试。

原恢复/断开红测保留，green-probe-01 已验证新身份恢复及UI断开转绿；该旧fixture的睡眠通用ACK解析报错没有冒充通过，实际0x95响应由新矩阵验证。四份独立原始 probe 未改源重跑：LightingCrossTargetProbe、StaleSelectionProbe、LegacyRecoveryProbe、SameTargetLightingReconnectProbe 全部 exit0。独立早期 RED 报告不是最终独立审阅 PASS。

中间失败全部保留：依赖缺失红测启动失败、睡眠夹具非法值、拨杆夹具断言、恢复过早 isScanning=false、旧 BLE 模式命令、OLED夹具padding。既有测试中旧合同预期按有效R6要求更新为更严格的断开/持久化登记和当前身份门禁，不删除安全断言。报告生成默认GBK解码UTF-8失败、R5包路径误写为installer而非unsigned-installer均已纠正，只影响证据生成，不影响测试结果。

## 固件依据与尚未完成

HW1 candidate 09633824d5b19492e5256078187e89849e74e7ce，HEX E75BE8DEF007B7A24502E615C894D68CE454B0FD3A6139AEF45F7C697DEFC233；HW2 candidate fb59582bf1ca65afa9ba1a843452815530e79012，HEX E19F386D86282E489B595D6D5804F8F43C710429949A2F1C1B9CBCEFCBCF6A29。候选命令处理源码只读取证保存在实现证据目录。旧版依据历史 c1898c9^ 命令处理源码；Owner 实际旧设备 HEX 未证明，不能把旧版模拟扩大成所有历史固件全功能保证。

待主 DLA 累计实际差异审阅、fresh high-impact审阅、新 Preview token 和隔离 1.0.16 local-model 完整EXE/运行依赖检查。Git candidate、安装/升级、实际USB/BLE联调、窗口交互及 Owner UAT 未完成。未Git写、未安装、未写用户Hook/Cursor数据库、未操作真实设备/固件、未下载模型、未发布或改Harness规则。
