# R5 最小界面能力修订 — 2026-10-24

依据 Owner 连续交付授权（20261023-continuous-ble-update-delivery-owner-authorization.md），将 R6 独立审阅发现 R6-F1 的必要界面修正纳入精确文件范围。此次不要求新的产品选择：按钮只应在实际支持对应操作时可用。

R6-F1：可信非 r001 固件的 lights 能力只允许读取/保存灯光；共用 writeReady 错误开启 0x89 预览和多任务模式。底层拒绝正确，不能扩大协议授权来修复界面。

新增精确路径：
- src/main/java/com/example/ahakey/view/InspectorPane.java：仅分开灯光保存/读取与预览、运行模式的可用条件和必要原因提示。
- src/main/java/com/example/ahakey/model/DisplayConfigState.java：仅加入上述动作可用状态，供实际服务和界面绑定。

已有 DisplayConfigService、Controller、资源文案及已批准测试文件只作本缺陷必要配套；不增加协议命令、不扩大非 r001 的 OLED/运行态权限、不改维护锁或底层能力语义。DIB 可选择最小实现，不要求两个新增路径都必须改。

回归须实例化实际 InspectorPane/DisplayConfigService，可信非 r001 精确 catalog、内存传输；灯光保存/读取可用，预览和多任务禁用并有可理解原因，不发送被禁用动作帧；r001 原功能保持；覆盖 lights 子集与未知 catalog。

R4 原件已封存 contract-revisions/20261024-r4-before-ui-capability-fix/ARCHIVE.json。保留原 start/guard-origin、所有历史批准和失败。当前 R6 不记 PASS；本次由正式 contract-reconcile 生成 R5/build_round 7 后 DIB preflight 实现，提交新 pack 再双重审阅。真实安装/设备/烧录仍 Owner 后置。
