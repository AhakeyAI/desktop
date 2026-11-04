# R2：Kimi BLE 审批状态入口

真实消费者与旧桥证据见 KIMI_BLE_SCOPE_FINDING.json。旧桥 9000 直接返回物理位置，而 Kimi 将有效非零位置强制 manual_lock；只修 Java 无法满足保存动作决定审批、其他状态回平台默认的已批准需求。

Owner 于 2026-11-02 明确批准最小范围扩展。采用内部原始桥端口与既有 Kimi 兼容端口隔离的必要改动；原桥通过现有 scripts/ble-driver-fixes.patch 构建隔离派生产物，不编辑父仓桥脏文件。Java 对 USB/BLE 使用同一已确认保存事实。属于 scope_expansion + protocol_change（仅本机 TCP 端点归属），high_impact，必须实际差异与独立审阅。

原合同五组要求及 WD008 兼容性不变，旧历史与失败证据保留。新增补丁及对应桥离线测试允许路径；不改任何 GATT、分片、串行、通知、窗口、连接选择和上传行为。实际消费者和端口占用/覆盖/生命周期必须离线验证，不能冒充真机通过。
