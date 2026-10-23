# WD-005 正式交付证据复用及差额核对

日期：2026-10-22，DLA，仅新增交付记录。有效合同 revision5 / round9，不改原批准或测试结果。

## 真实输入

- Git candidate e08524cc07077a06d34b79130ddea074355ea2fb；代码指纹 98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9。
- 已测 Preview：preview-20261021T024920511394Z-2ae03d；主 JAR SHA256 97a5ae072c18a0ed229538fee7766426bd9f6c8ba807607aee10f141efa3052b。
- 本日重新核对 Preview 回执的全部 19 个运行文件与 9 个日志/记录 SHA，全部一致；第九轮检查表 evidence_hashes 的 19 项全部一致，八进程断言记录合计 656。此次是读取/哈希核验，未重跑测试。
- Owner 已确认 FFB920 修复 HEX 并对该 Preview 清单整体反馈通过。只复用该清单范围，不能把「全部通过」扩成未安排的故障注入、BLE 或高 DPI。
- 正式候选包由 DIB 在此次独立 build-only 授权下构建。旧 Preview 回执不改名、不覆盖；新旧包内容等价须实际比对后再记录。

## 原验收 A01-A11

以下是精确覆盖审计，不是全条 PASS。日志路径统一在 evidence/20261021-wd005-r9，Owner证据在上述 Preview 目录。

| 合同 | 可复用证据与范围 | 仍需补充或明确处理 |
| --- | --- | --- |
| A01 | DisplayConfigChecks 的19容量、19唯一选择、全局名称；Preview步骤1/3/4/6覆盖普通资源/模式及槽位体验 | 未单列全四Mode与全部19目标的人工巡检，不用算法断言冒称每格实测 |
| A02 | Checks 的静态图、透明黑底、RGB565独立像素、GIF偏移/disposal2/3、8/9/12/13帧限制；FxChecks最终像素；Preview图片及短GIF成功 | 完整错误弹窗实景和所有边界人工交互未单列；纯编码算法无需重复真机验证 |
| A03 | Checks 的 restart-no-source、清除墓碑、损坏索引保护；FxChecks草稿标识；Preview原草稿/资源/绑定保留 | 实际重启并移除源图、本地只读/写满/迁移全部异常缺适用证据；临时库恢复断言不等于实际用户库验收 |
| A04 | FxChecks按需14/10次读取、Checks草稿保护/未知/不一致降级，RaceChecks旧读取取消/新意图隔离 | Preview刷新/重连普通路径可用；设备已有无本地成品及完整元数据不匹配实景未逐项反馈 |
| A05 | Checks真实内存上传链、完整8/12帧offset/payload/CRC、二进制分片/粘包、互斥各命令；Preview静态图/短GIF普通上传 | 真实8/12帧、USB/BLE跨传输及并发输入表现未覆盖；不能用内存BLE代替无线 |
| A06 | Checks及Revision3Checks覆盖Begin FAIL、Chunk/Commit未知、迟到ACK、代次、无自动重试；RaceChecks目标/草稿隔离 | Preview明确排除上传中故障注入；真实上传中断连、重连对账/人工重试仍待，正常空闲拔插不能替代 |
| A07 | FxChecks第五项失败/部分dirty、Checks OFF/未知ID/亮度职责；Preview亮度与一项SINGLE灯效分别保存回读 | 真机OFF保存、未知值和批量部分失败未逐项反馈；故障分支优先沿用模拟，物理持久化见A11 |
| A08 | Checks17灯效独立金样及边界、FxChecks临时预览/保存撤销/离开不STOP；Preview普通预览保存 | 真机10秒到期与真实AI状态竞争未单列；算法金样不证明真实灯珠及全部时序 |
| A09 | Revision3UiChecks局部布局、CapabilityChecks原因/禁用、FxChecks离线编辑；Preview完整应用普通交互已接受 | 实际最小窗口及100/150/200% DPI和长文案巡检未执行，局部FX不能替代 |
| A10 | Checks旧命令/草稿/上传锁、RaceChecks代次/最新补发、R3/R5运行态归属及TTL；Preview版本/按键/侧拨/Voice读回/Mode普通回归 | BLE实链路、系统/本地语音实际输入及更完整重连组合未覆盖；原任务历史证据只在身份适用时引用 |
| A11 | 候选/审阅/旧Preview身份，Owner已确认固定HEX；本日重核文件哈希 | 本轮正式BUILD_RECEIPT/交测包待生成；断电重启后的资源与灯效持久化、正式结果绑定待补。EXE不在范围 |

## 增量 C01-C07 与修复问题

C01-C04/C07已由R9能力/隔离断言及原回归覆盖的具体分支可复用；C05/C06组件与Owner正常UI可复用，但高DPI、旧固件实机、USB/BLE实切等未执行内容保留。R9共656是断言数，不是656个完整应用场景。

UI-01/UI-02/UI-03/LOG-01收到适用Preview整体通过反馈，已有隔离UI和编码证据；FB-01、RT-01/02及R4/R5修复有受控内存分支证据。未知来源事件不可从“未再看到”推断所有来源问题彻底解决。

UP-01/02历史根因仍未确认；当前正常上传通过与失败隔离断言可以分别记录，不抹掉首次失败历史。
RT-03外部固件主槽回退与BLE-PERF-01三端优化未凭Windows PASS闭环。

## 外部配对

正式CP2 Gate20261018T175441 schema6/PASS，candidate70ca334f65d73b6a2f20a0598e55c6da59f26526。
Gate SHA bf6efc5ac8380b6420c4ded17492b4bc798cad46072699c38ede41945fb5dbaa；HEX SHA ffb9208f79084aa24a832ad2562a14dbbea5df4d114a135cb5b2eb98d4e05539；本日重新核对一致。

本日初次新建身份记录时 Gate SHA 多录一个 b，随后独立逐项哈希比对发现。修正前身份及绑定保留在 delivery-history/20261022-dla-identity-transcription-before-correction，修正后重新执行正式 firmware-admit；此处不改固件、原批准或旧Preview证据。
固定协议沿用当前批准的 pinned REFERENCES，不接纳固件工作区后续CP2.5改动。
现场桥接 EXE SHA 9b8f8c9d18ae7ee93b71ed7c867e1ce1e60040ebc6832498f5f2d00dcbd6106e，仍是原包，不证明来自BRIDGE-01修复源码。不能宣称BLE优化已交付。

## 最短接续

1. DIB正式build-only，产出回执并比较新旧ZIP条目及依赖；DLA核对后再创建正式delivery草稿。
2. 原Owner正常路径不无理由整套重测。新旧内容若相同，作为复用论据；若有实际class/resource变化，解释差异并限定补测范围。
3. 补测/证据差额归并：本地恢复及目标/错误边界；上传中断线恢复；断电持久化及预览时序；高DPI/长文案；BLE与外部依赖。尚未取得Owner后置决定，全部保留pending，不静默豁免。
4. 正式配对、逐条结果及覆盖有效后，再archive-plan；额外Git归档需精确清单授权。本轮不操作设备、不启动应用、不执行Git写入。
