# V10：Consumer与逐模式Voice混用静态核验

依据：本机已刷候选对应接受源70ca334f65d73b6a2f20a0598e55c6da59f26526；先前核验的Fireware-harness最新头076382b仅新增Harness归档，没有生产源/HEX变化。本轮未刷写、未修改固件或键盘绑定。

## 结论

当前接受固件不能仅靠现有普通键配置，实现某些模式用Consumer系统听写、其他模式用App转写或第三方快捷键的完整混用。此结论来自分发代码，不再只是根据全局标志推测。需要固件增量合同与可验收构建；普通键按模式映射和App端路由可以继续独立开发。

## 源码依据

1. [`main.c:381`](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/70ca334f65d73b6a2f20a0598e55c6da59f26526/APP/sub_main/main.c#L381)：`voice_onboarding_mac_consumer_voice_active`仅检查全局平台状态和引导是否可见，不根据当前模式选择。
2. [`psk_multi_button.c:368`](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/70ca334f65d73b6a2f20a0598e55c6da59f26526/APP/hardware/psk_multi_button.c#L368)：Key1且上述全局条件为真时，按下/松开发0x00CF，随后直接return，所有模式的普通绑定都被绕过。
3. [`psk_multi_button.c:236`](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/70ca334f65d73b6a2f20a0598e55c6da59f26526/APP/hardware/psk_multi_button.c#L236)：普通短/长动作当前都来自`user_key_bind[mode][key]`同一位置，不构成独立长按配置接口。
4. [`psk_multi_button.c:300`](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/70ca334f65d73b6a2f20a0598e55c6da59f26526/APP/hardware/psk_multi_button.c#L300)：普通动作解析仅处理0x73键盘快捷键和0x74键盘宏，不能将Consumer usage当普通键盘HID码写入替代。
5. [`command_solve.c:471`](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/70ca334f65d73b6a2f20a0598e55c6da59f26526/APP/sub_main/command_solve.c#L471)：0x96写接口仅接受全局SUPPRESSED_BY_DESKTOP，不提供逐模式Consumer选择或恢复。

因此：保持Mac预设时所有模式Key1优先Consumer；写全局suppress后所有模式改走普通绑定，现有接口没有逐模式保留Consumer的中间状态。不能通过移除客户端Voice保护、写四个F18或重放现有0x96解决完整需求。

## 所需最小固件协作范围（待对接，不自行分配opcode）

- 每模式可持久化的Voice输出选择：Consumer或普通绑定；App原生/AhaType等具体策略由主机按模式处理，不要求固件了解第三方App。
- 查询/设置/确认的实际协议合同、能力身份及迁移默认值；旧存储升级保持现有用户行为，不默认覆盖四模式键位。
- 普通绑定模式下Key1只发实际配置，Consumer模式下仅发Consumer，不双触发。
- 按下时固定输出路线；按住期间切模式/断连/休眠必须释放原路线，不能用新模式路线吞掉旧释放。
- 写入失败、重启保持、可逆切回Consumer的语义和证据；不得仅ACK成功。
- 不冲突WS4/5保留命令范围，不在当前草案未接受时擅分配新命令。

## 客户端与验收

保留当前已验证的Voice配置，继续I01/I02a；I02b可做逐模式草稿、直发与监听隔离、原生/AhaType路由和按次录音策略。I02c等待新合同/构建，不能隐藏不支持入口后宣称完成。

最终至少验收四模式Consumer/自定义组合键/App原生/AhaType混用、模式切换及重启保持、App关闭时Consumer和普通快捷键可用、按住切模式的释放配对、没有Siri/重复转写/修饰键卡住。第三方快捷键和Fn/Globe需按实际输出能力分别验证，不能将Fn/Globe当作普通键盘Command组合键能力承诺。

这是新增产品需求的静态可行性记录，不是已完成固件修改，也不把历史Command滞留现象归因于此代码分支。本轮未另发外部消息或新issue。


2026-10-22复核：通过GitHub API确认Fireware-harness头仍为076382b2214289ac7bc1735d669d7de78730c4da。与70ca334f比较仅一个Harness证据/状态归档提交，没有生产代码变化；上述全局Consumer分发与0x96限制仍适用。Key1逐模式App方案已在PR155完成本机保存与语音正常路径验收，不能据此宣称Consumer混用已被固件支持。
