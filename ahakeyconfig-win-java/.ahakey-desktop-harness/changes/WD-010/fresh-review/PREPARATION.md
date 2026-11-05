# WD-010 独立高影响审阅准备

日期：2026-11-05（Asia/Shanghai）。状态：PREPARATION_ONLY；没有审阅 PASS/FAIL，不是正式 REVIEW.json、candidate 或测试准入。

## 身份、授权与观察位置

- 独立审阅聊天：01a1a970-ac70-77a3-bfc4-3e4ebe225604；不同于原 DLA（01a1a594-ba84-7a33-bd03-48125a887c69）及 DIB（01a1a968-73d2-7cc3-84e1-0487f363f991）。
- 按原 DLA 本轮指派，仅作只读准备；允许新增本文件。授权来源：evidence/20261105-wd010-autonomous-exe-owner.md。Owner 已选择带本地模型 EXE，无需再次询问。
- 本轮观察 STATE revision=267，WD-010 为 IMPLEMENT / IMPLEMENT，next_actor=DIB；尚无 IMPLEMENTATION_RECEIPT.json。未生成 review-pack，未冻结或审阅仍在修改的生产代码。
- 只读观察 HEAD=70ccc3361ecd90e6c67828bac581a6975ebdccb2，branch=codex/win-zxy-work；这不是本轮审阅候选身份。正式阶段须重新核对冻结输入。
- CONTRACT 与 IMPLEMENTATION_SCOPE 文首仍有草案/待批准文字；change.json 和独立 Owner 批准记录明确已批准。8 个 approval assets 的实际 SHA256 全部匹配批准绑定。保留原字节，不修改文首或重批。

## 已读依据与历史材料层级

已读取根 AGENTS、Lead/Harness Skill、RULES、OPERATING_MODE、GUARDED_DELIVERY、DISTRIBUTION_DELIVERY、STATE/local、OWNER_COMMUNICATION；WD-010 的 CONTRACT、IMPLEMENTATION_SCOPE、RESTORE_IDENTITY_REVIEW、RESTORE_READBACK_PLAN、REFERENCES、HISTORICAL_REFERENCES、INVESTIGATION、恢复 UI 场景、云端决定材料及交付准备；WD-009 Contract 及其修订。

历史清单的 11 份快照 SHA256 全部核对相符。对 f6c7a5c8 的配置、账号/支付、窗口、AhaType 和语音接缝作定向阅读/定位；这是准备性定位，未宣称完成所有历史源码逐行审阅。正式阶段按实际 diff 回查相关完整方法和调用方。

历史客户端仅证明历史接口/行为存在，不证明后端当前可用，也不授予旧错误行为继续存在的资格。已看到旧配置默认额度为 0、明文 remembered_password 字段、支付金额宽松回退和支付后刷新结果处理，正式审阅要按现 Contract 的未知值、受保护存储和真实反馈语义核对，不能机械移植。

## 正式审阅检查重点

| 边界 | 必须追踪的真实链路与反例 |
| --- | --- |
| 输入身份与范围 | 接收原 DLA 固定 review_pack.json/实际 pack、完整 diff、code fingerprint 和 submit receipt；核对包 hash、原始起点、全部新增/修改/删除文件、范围内行为及 preserved foreign；逐文件读真实调用方，不能仅读新服务或测试。并发改动使指纹变化时保留观察，不沿用结论。 |
| 账号生命周期 | TopBar → Controller/单实例窗口 → CloudAccountManager/AhaType → HTTP → 状态/FX回调/持久化。登录、注册、刷新、整理、兑换、建单、轮询均绑定账号及会话代次；控制退出/换账号/关闭重开与请求完成的先后，检查旧成功、旧401、失败及排队 UI 回调均不能污染新会话。注册无token、重复提交、超时结果未知、服务到期与会话失效分别处理。 |
| DPAPI与配置 | Windows用户级保护、明文迁移先保护并原子保存再删除、保护/解密/写入/删除失败可见且不降级明文；取消记住密码立即删除而不清有效会话，退出清会话但保留已选回填，重启不自动密码登录。检查临时文件、备份和日志不得泄露秘密。仅使用合成值/隔离目录，禁止读取真实账号文件。 |
| 兑换与充值 | 独立窗口及重开操作归属、防重复、无自动重发/建单；未知结果不等于失败或成功。验证严格订单号/链接/金额/状态解析，缺金额的套餐报价来源明确，未知状态不判成功；支付/兑换成功与权益刷新失败分开。轮询约2秒/3分钟及HTTP超时、关闭窗口/退出后的线程与迟到响应隔离。 |
| AhaType输出 | 当前 VoiceInputManager 的 final → 异步整理 → 最终交付/KeyboardInjector，partial零请求零注入；成功或回退恰好一次。验证取消、停用、下一次录音、退出、重复final、账号变更、线程中断无效及FX排队后的最后一刻检查。回调与注入之间的竞态也需核对；保留F18/Win+H、语言/简繁和WD009生命周期。刷新菜单真实刷新状态，不发消费额度的测试请求。 |
| 恢复命令与分帧 | TopBar/FactoryResetDialog → FactoryResetService → 事务/维护门 → BleManager/UsbHidTransport → FactoryResetProtocol；只读v1/0x30查询与v2/0x31写入、17字节回复、version/sub/nonce/attempt/connection generation全关联。可靠durable attempt+1与u32边界，不接受旧6字节ACK、错误版本、迟到K1回复。USB/BLE拆包/合包/连续帧/噪声/并发K1均走真实生产解析器，不只测编码器。 |
| 确认与持久化 | 默认取消、未确认零恢复写入；确认期间目标/连接变化作废。提交前原子持久化失败保留草稿且零发送；提交后落盘失败维持内存只读、结果未知且不重发。记录损坏、阶段不一致、完成后清理失败、崩溃窗口及应用重启只查询，不持久化自动重放写帧。 |
| 目标关联 | USB无序列号，container/port/名称不能证明跨重启唯一身份；BLE地址需来源/长度/生命周期证据，不混作跨通道统一身份。人工确认只在无可靠自动依据且无明确冲突时允许，只查询且仍匹配attempt，不标硬件身份PASS；明确另一设备不能继承任务或被旧回调更新。 |
| 状态、读回与目标只读 | result=0不等于COMPLETE；COMPLETE也不等于完整同步。分别核对进行中、未知、INCOMPLETE、存储不可用、不支持、配置读取失败及重试动作。读回逐项覆盖四模式普通键/宏/描述/K1、拨杆/实际位置、模式/语音状态、待机、亮度/模式灯效、图片选择/19条metadata；使用设备实际结果，不拿缓存或默认值充数。全部必要项成功才能解锁，不可独立读项说明固件语义依据。 |
| 后台写入与退出 | UI、服务、传输三层同目标门禁；普通配置、资源上传/预览、AiRuntimeDisplay、MULTI、定时器、排队执行器及旧回调在解锁后不得补发旧写入。专用查询/读回不被自己锁死，不调用刷机后备份回写服务；明确其他设备和账号仍可用，退出可释放资源。 |
| WD009及已有行为 | 保存事实与草稿分离、当前目标拨杆动作/审批、Hook平台隔离和保留第三方配置、Cursor并发/过期等待、F18与宏模拟取消释放、版本和菜单、K1完整性/分片、显示隔离、维护互斥/退出。审查实际既有检查及新组合时序，不以compile或模拟服务PASS代替真实调用链。 |

## 证据标准与保留缺口

- 正式记录应逐文件给出目的、已读 hunks、调用链、反例、发现及处置；机器测试只是证据之一。正式审阅结论仅适用于被冻结的代码身份。
- 测试须确认使用生产类、实际入口和可控制时序；测试替身不能把需要验证的锁、代次、分帧、读回替换成永远成功的实现。需要补证据时先记录具体缺口，不修改生产代码或降低验收。
- RESTORE_IDENTITY_REVIEW 明确 USB 无序列号；这是设计约束，不把人工确认等同硬件身份证明。
- REFERENCES / DELIVERY_PREPARATION 记载恢复v2正式receipt和确切HEX绑定仍有缺口；本轮未重新查找Firmware全库，不将旧closure、源码或其他固件PASS替代正式准入。正式阶段重新核对相关证据的新状态。
- WD009 1.0.19 Owner Preview PASS 不等于WD009 CLOSED；JAR、离线fixture、EXE包内容、实际安装/设备/账号/付款验收各自分开。独立代码审阅也不能补造这些结果。

## 本轮执行及下一步

本轮仅本地只读材料/快照哈希检查和新增本准备记录；未构建、运行产品或测试、请求线上服务/设备/付款、执行Firmware脚本、访问真实账号秘密、修改Git、生产代码或Harness状态。未创建正式REVIEW.json，未登记PASS，也未向其他聊天发送消息。

等待原DLA在本聊天提供固定审阅包及代码指纹后再开始正式独立审阅；不轮询，不要求Owner转发或再次批准，不主动创建新身份。后续仍须独立查看实际调用链、状态与测试，不能仅凭DIB报告或测试PASS给结论。
