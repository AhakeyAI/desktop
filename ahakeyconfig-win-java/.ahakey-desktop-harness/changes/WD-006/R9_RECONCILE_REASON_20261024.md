# R9 完整实施修订原因

Owner 最新完整授权见 `.ahakey-desktop-harness/evidence/20261024-complete-update-cp26-owner-authorization.md`。恢复此前暂停的更新中心，并纳入 CP2.5/CP2.6。原 Contract revision6/build8 和批准已备份于 `contract-revisions/20261024-r6-before-complete-delivery/`，不重置任务起点、旧报告或实际失败。

DLA 已检查实际 UpdateCenterDialog、StudioController、DeviceSyncService、StudioState：原固件页仍要求外部工具、备份、恢复；全配置保存会给每个模式的 K1 下发旧键绑定，且现有 dirtyParts/dirtyModes 不能识别具体模式的 K1 编辑。新范围必须修改真实入口和状态归属，不仅添加未接线的服务。用户已充分确认简单烧录、未知 HEX、Consumer 只读、明确 K1 保存、单版本/双地址和升级测试包；不再重复这些问题。

独立设计审阅为 `r9-review-20261024/R9_DESIGN_REVIEW.md/json`。其中 B1 是真实外部缺口：CP2.6 candidate 2f7c54a927410c59479307c1ebc2b0d20f236d97 在无有效 route store 时，0x9E read 返回通用失败，单模式 commit 先 load 全部记录而失败。不能区分缺失、损坏和 restore pending；启动投影不创建记录。Windows 不得伪造空普通键、退回旧 K1 写入或悄悄使用 selector=0xFF。先落实有效记录的单模式编辑与缺记录安全禁写；完整首次配置要求保持未完成，等待 Firmware 正式协议/实现/交测证据闭合。已向 Owner 询问是否交固件负责对话处理；答复前不向其派工或修改 Firmware。此项不阻止独立的 OTA、烧录与版本只读成功判定。

采纳独立审阅约束：ordinary route data 包含动作 envelope，原始动作最大98字节；每模式 K1 编辑及 revision 快照；精确 capability/分片/CRC/连接代次；commit 不确定先回读。发行签名采用固定 RSA3072 公钥，明确单一字节封装，Java/.NET 互验，签名覆盖完整原始 EXE prefix 与实际 MSI 身份；worker 独立校验并持锁。仅精确已确认云主机及受限 HTTPS 重定向。官网只返回三字段来源的 schema3，不带私密环境。WCH 随包13文件、固定驱动准备及 owned Job 有界清理，真实 driver/干净系统/烧录结果不得由静态检查代替。

官网独立任务已完成 `/stable.json` 最小实现及六组离线测试，尚未部署。环境变量是 WINDOWS_LATEST_VERSION、WINDOWS_DOWNLOAD_LITE_URL、WINDOWS_DOWNLOAD_STT_URL；Owner 不维护额外 JSON/hash/signature 字段。DLA 已只读检查 handler 与 server.js 两处接线，既有下载重定向保留。

新交付使用1.0.11起点→1.0.12目标，取代 intake 旧示例“升级到1.0.11”，不改旧调查原件。仍提供两种形态逻辑覆盖，但本轮实际两个 EXE 均本地模型版。CP2.6 单独机器 gate 不当作合并 HEX UAT；正式配对继续等待 Firmware 允许交测的 CP2.6+WS4 Restore 候选。

本修订只收敛已有 Owner 授权和经验证的工程边界，不表示实现、Git candidate、EXE 或 UAT 通过。DLA 独立实际累计 diff 和 fresh 实现审阅、精确候选、隔离 build-open/finish、完整 payload 身份以及 Owner 实测均继续执行。
