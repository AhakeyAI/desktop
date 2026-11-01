# WD-008：WD-006 正式固件身份兼容修复

Owner 2026-11-01 已明确批准最小修复及 EXE，授权记录 ../../evidence/20261101-wd008-owner-authorization.md。无需重新 Grill 已定产品方向。

## 基线与隔离
当前 Git 42696a6bdf0ed72df8d0a416c22e8e3d82e3fb96，产品为 WD006 R13（对照9365911b）。WD007 Owner全部拒绝，保持PAUSED，历史脏文档保留，不恢复其实现。旧EXE 1.0.12是可恢复Preview，不宣称全产品已验收。失败复现 target/wd006-ble-diagnosis-20261101。

## Classification / Journey / UI
bug_fix，high_impact（设备能力准入风险需独立审阅）。主旅程J016：WD006连接→读取当前身份→按已证实能力读配置→用户显式保存→ACK/读回确认；回归J002/J005/J006/J010。ui_mode existing，沿用StudioController.handleFirmwareCatalogKey、InspectorPane、BLE驱动窗口。不改菜单/连接动线。固件实际配置为真相，Windows草稿独立；未知、断连和失败不伪造能力或成功。

## 实现范围
统一离线支持 x1-c582-hw1-p1-1.0.1-r001、x1-c582-hw2-p1-1.0.1-r001，保留 x1-c582-hw1-p1-1.0.0-r001。完整受证实集合匹配，不用startsWith放开陌生固件。
核对普通键/侧拨自动读回和保存、OLED/灯光/显示、runtime display、维护恢复的身份能力判断；修正只认旧字符串的遗漏。K1继续原0x9E能力/route语义，不能以版本代替真实握手。
无完整标识的旧固件保持WD006已有行为和能力层级，不新增未经证实能力。查询超时仍为通信失败，不归类旧协议；旧ACK保留已有回退。
不删除恢复记录或伪造对账成功。保持实际回读要求；独立故障交DLA分类，不借机改传输。
运行连接能力与可烧录目标分开：不改变内置HEX、烧录硬件约束或自动恢复策略，不能新增HW2连接能力后允许误刷HW1内置HEX。
allowed_paths见change.json，仅作必要身份表/接线及回归。不整文件覆盖；桥/分片/超时/通知/USB/BLE传输、语音/onboarding、Hook、OTA与安装路径保持WD006。

## 固件与协议
FIRMWARE_FACTS.json绑定两正式gate、HEX、immutable候选。
HW1 candidate 09633824d5b19492e5256078187e89849e74e7ce，HEX E75BE8DEF007B7A24502E615C894D68CE454B0FD3A6139AEF45F7C697DEFC233。
HW2 candidate fb59582bf1ca65afa9ba1a843452815530e79012，HEX E19F386D86282E489B595D6D5804F8F43C710429949A2F1C1B9CBCEFCBCF6A29。
0x9F/87/97/9E/88/89/8E及8A/8B/8C保持既有协议，不新增固件命令。Firmware只读，不运行其脚本，不烧录。

## 验证及交付
离线验证实际身份帧→能力→相关入口：两个正式版本通过、旧支持版本通过、陌生/畸形/profile错误拒绝、timeout不升级能力、重连不沿用旧身份。无ID旧分支有回归。核对两版正式候选协议；隔离user.home，无真实HID/TCP写入。
DIB实现→DLA actual diff→独立审阅。既有相关测试和新增覆盖本bug的测试；编译/模拟不代表真机。
Owner授权本地模型完整EXE，独立target输出与旧包并存。使用既有模型/runtime，不下载、不安装、不kill、不发布。允许经Harness Preview snapshot交付，记录基础Git、增量hash与包身份，未提交不得称已提交candidate。新包版本避免与原包混淆，保留安装/签名规则。
Owner矩阵三种固件×USB/BLE：连接、信息/适用配置读回、用户显式保存/重连、断连和换设备身份。未执行记not_executed；完整步骤与HEX身份在交付正文。失败保留日志草稿与恢复记录。

## 排除与批准
无关蓝牙动线、Hook、语音/UI重做不纳入。Owner已批准上述目标，无新增产品歧义；真实发现范围扩大时再回CHANGE。内部Preview不是UAT或官网发布；不自动Git写。保留所有旧任务记录。
