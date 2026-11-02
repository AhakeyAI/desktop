# 新固件K1离线USB轮询修复核对 — 2026-11-02

远端固定为 `efecc471376f99ce6753e257933bfba287937bb4`，相对此前 `ed426c97d4aad9a20c1585d6b15125252b6caa49` 共8个提交。只在独立临时bare仓库取源码，没有修改用户固件工作区、客户端代码或设备固件。

## 实际行为改动

候选 `fe2278616f69087b7f9097ae4777f7231ff39a30` 相对其已接受源码基线 `9892d2833df292099f71bf4615ed0b11bd971937`，生产行为修复集中在 `APP/sub_main/command_solve.c::command_link_lost()`：在IRQ保护范围记录live→lost是否真实发生，恢复IRQ后仅当转换发生才清除共享K1 capture。重复的USB-already-offline轮询不再无条件清除BLE K1按下记录；真实USB/BLE失连仍清理。

此前每秒无USB供电检查会调用USB link-lost，可能在BLE K1按下与松开之间清掉capture而不发松开报告。新改动与此前Voice漏松开/卡住风险相关，但没有将Consumer改成固定短脉冲，不能据此认定所有Siri触发已解决。相对ed426c9的其他生产变化主要为既有K1诊断日志；源文件范围为psk_multi_button.c、keyboard.c、command_solve.c。

## 证据与产物

- 正式回执 `CP2.6_K1_CAPTURE_RELEASE_FOLLOWUP/20261030T210024/gate-receipt.json`：PASS，17项machine checks，contract/path错误为空；本轮读取并核对记录，未冒称独立重跑17项。
- HEX记录SHA256：`297B7390362A38B04A509EBC26E8BDB7EF6EC48065E6AA66E6086129213E672A`。
- 仓库Owner UAT记录为旧硬件整体使用反馈PASS；没有逐次30/30、BLE送达抓包或所有逐项回归结果。新硬件ID01仍未验证，不扩展成完整产品发布验收。
- 原候选HEX本体未随固件分支入库，文档中的路径不是已验证可下载地址。最初检查本机固件工作区、Downloads及此前用户提供附件的2026-10/11目录共42个HEX，无SHA匹配。随后使用固定fe22786源码、既有CH583 SDK和官方MounRiverGCC8.2工具链独立重建77个C源，产物完整SHA256与正式门禁297B记录完全一致，已恢复该精确产物；没有要求Owner重新寻找旧07A8文件，没有拿旧产物冒充新候选。客户端生产FirmwareImageValidator已独立通过IntelHEX格式、校验和、EOF和地址范围检查。
- 本轮键盘只做正常重启后的显示清理，没有刷写。协议元数据不等于精确HEX字节证明，不能把当前键盘上的结果计作297B候选验收。

## 客户端与WBS影响

没有新增命令／字段／路由编码，不需要因这次capture修复改客户端协议。长宏完整动作＋描述读回、任意键独立短长按、可信发布目录／恢复镜像输入仍未在此次固件delta补齐；Kimi接口属于独立上游依赖，本次未作新版调查。

显示上传事务／flash writer／取消处理没有此次行为修复；2026-10-30对07A8取消后配置拒绝的失败记录保留，2026-11-02只通过正常重启后的恢复和单位置清理。17项Gate和第三方整体Owner反馈均不能关闭本机完整Voice或素材故障矩阵。

精确HEX现已在客户端仓库[归档](../validation/connect-talk-hil-2026-10-22/firmware/k1-offline-poll-fe22786-297b7390.hex)，并保存[重建回执](../validation/connect-talk-hil-2026-10-22/firmware-k1-artifact-recovery-2026-11-02.json)。不替换客户端内置镜像，不标为稳定／recovery-safe版本；没有重跑原17项门禁或新增发布批准。后续验证须按需要备份配置、取得当次刷写授权后集中做真实K1按下/松开、切模式及重连观察；本文件不构成刷写授权，不把尚未测的结果标完成。

依据均为固定分支的源代码和仓库证据：[生产修复](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/fe2278616f69087b7f9097ae4777f7231ff39a30/APP/sub_main/command_solve.c)、[正式回执](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/efecc471376f99ce6753e257933bfba287937bb4/.ahakey-harness/evidence/checkpoints/X1-INPUT-CONTROL/CP2.6_K1_CAPTURE_RELEASE_FOLLOWUP/20261030T210024/gate-receipt.json)、[Owner反馈](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/efecc471376f99ce6753e257933bfba287937bb4/.ahakey-harness/evidence/owner-uat/X1-INPUT-CONTROL/CP2.6_K1_CAPTURE_RELEASE_FOLLOWUP/OWNER-UAT-PASS-20261030.md)。
