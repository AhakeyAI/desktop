# WD-002 Owner 真机测试交接
配套填写OWNER_TEST.json，所有步骤指向同一候选。
## Windows候选：Git、实际构建/入口、完整路径、runtime依赖、SHA
## 固件/硬件：实际可测试候选、HEX、来源、SHA；已安装版本需Owner确认
## 前置：USB/BLE、配置备份、哪些操作写设备、有何风险
## Test Now：每步操作、预期、失败时回传
## 相关旧行为回归（不要求全软件重测）
## Deliberately Unchanged：本轮不变/不测内容
## 停止与恢复、收集反馈
内部联调不等于发布；缺候选准入时不烧录、不猜HEX。

## v1.0 必须直接呈现给Owner
本轮功能/交付形式/发行配置；Windows主产物+依赖+Java完整路径；Firmware生产方+原完整路径+候选+SHA；前置；编号动作/预期；停止恢复；反馈。正文从OWNER_BRIEF_INPUT生成，使用handoff-publish/owner-brief，不能只给链接。合同要求逐条映射，JAR不代表双安装版。
