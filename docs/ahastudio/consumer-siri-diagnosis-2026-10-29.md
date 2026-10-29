# Consumer Voice误触发Siri：本轮真机失败

## 当前结论

build521配07A8DF32工程固件，Owner正常重启后屏幕正常，实际听写能输入；再次短按停止时以及稍慢按键时多次出现Siri，需反复关闭才能继续。Consumer功能验收为FAIL，先前的路由字节读写通过仍有效，不能等同听写稳定通过。没有修改输入方式、系统Siri设置、固件或客户端配置。

Apple官方说明麦克风键短按松开启动听写、按住唤起Siri：[macOS听写说明](https://support.apple.com/en-gb/guide/mac-help/mh40584/26/mac/26)。这不是任意Consumer usage的跨版本保证；本机macOS26.3.1/0x0C:0x00CF实测与时长有关。

## 反馈回路与实物证据

只匹配AhaKey505C的非独占IOHID监视器，过滤Consumer CF和左右Command，无文字/音频采集。180秒窗口记录17组完整按下/松开：105.038～4492.850ms，其中4组超过1秒；Owner同时反馈必须很快轻点，稍慢多次触发Siri。没有逐次Siri UI时间标记，不能强行把每次Siri归属某个pulse。

HITL回路把Owner的Siri实际观察与原始时序分开记录：`hitl-consumer-siri.sh`输入yes，退出1：`FAIL: unexpected Siri during dictation test`。它依赖人的UI观察，不能用原始HID自动证明Siri界面。

没有Command元素事件。窗口最后有一组down未在监控截止前配对；后续独立IOHID读取Consumer仍为1、左右Command均0。Owner随后明确全部松开，立即独立读回Consumer=0、左右Command=0；第二段120秒窗口10组轻点（113.306～192.506ms）均配对且结束无按住。因此**本轮未证明持续漏释放**，不能把第一段监控截止时的开放按键当作已证实卡键。较长持续时间也不能直接等同BLE丢包。

原始事件与可复跑监视器只存本机`local-builds/consumer-siri-20261029`私有目录，仓库仅保留去标识统计回执。

## 新旧差异与源码定位

刷写前完整备份中voice onboarding=3（退出Consumer），四个K1普通动作均为0x73/e6右Alt；当前四模式K1路由已读为Consumer CF。两轮链路不同，无法仅凭本轮Siri判作固件版本回归。2026-10-13旧Consumer隔离测试也抓过3.360623秒按住并唤起Siri，App退出时存在；旧历史不替代新固件本轮隔离。

ed426c9的`APP/hardware/psk_multi_button.c:271`中`input_control_k1_route_event`在PRESS_DOWN发Consumer down，PRESS_UP调用finish发up，无固定脉冲定时器，物理按住持续时间被透传。旧fallback路径455行也按事件down/up透传。`keyboard.c:378`经Report5发送，`psk_hid.c:432`封装不返回HidDev_Report结果，release可靠性仍需定位，不以静态风险代替现场根因。

客户端`VoiceRelayService.action(for:)`对systemDictation返回nil，当前Consumer方案不注册App语音路由；event tap只处理普通keyDown/up。此为静态排除重复转发的依据；若完整短脉冲仍误触发，须继续App退出对照与系统映射调查，不能只改UI文案算修复。

## 排查顺序与修复诉求

1. 固件透传按住时长导致系统长按：源码与本轮长pulse支持。若固定短脉冲后Siri消失，可进一步确认。
2. release失败/延迟放大短按：现有void发送路径及末端CF=1需要补实物全部松开后的证据/发送返回码；不可直接定性。
3. 正常短脉冲下系统判定或第二输入链路：需App退出对照/系统事件相关性，当前没有确证。

推荐固件为Mac的K1 Consumer CF语音用途提供“仅听写”单次短脉冲：按下只触发一次，独立有界定时释放；保持按住不重触发，实体松手不额外切换。脉冲时长须用目标Mac测定，不声称Apple公开某个安全阈值。禁止阻塞主循环等待；down/up发送结果可见、release优先且有界重试，断连/休眠/切模式/路由改变收尾，避免旧timer释放新动作。

范围仅Mac Consumer CF语音；普通组合键/宏、App按住录音、Windows链路及其他Consumer用途保持各自语义，不能全局截断所有长按。该产品规则会取消该Voice路径的长按Siri，需固件方按Owner目标在现有Harness完成合同/实现与复验，不在Mac偷偷转发另一组快捷键补丁。

重验：快按、正常按、1/3/5秒按住及停止听写均只切换一次，无Siri；重复20组、掉包/重连/休眠/模式切换后无卡住；App退出也通过。普通键/App语音长按和其他模式分别回归。当前未生成/烧录任何修复HEX。


## 重启保持读回补证

Owner已明确正常重启后，build521再从Agent交接读取完整四路由：24个分片、四个102字节记录及CRC全部有效，与重启前最终记录逐字节相同，无路由写入、无超时。随后交还Agent并关闭详细日志。关闭“本轮路由断电保持未验证”子项；Consumer实际听写误触发Siri仍为FAIL，不因保持通过而关闭。固件反馈已补[Issue #7 FW-13](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7#issuecomment-6492446474)。


## 旧版对照与频次修正

Owner要求降级后，ffb9208f已刷入Verify OK，旧版Mac预设2/Codex模式、Studio完全退出时也复现Siri。Owner明确旧版频次/概率更低，**不能用旧版也发生来否定新版本可能放大的回归**。无逐次Siri计数/时间，且App状态和按住时长未严格匹配，不计算概率。新增路由不可用时漏release的离线探针已红，但未证明现场进入该前置状态，不定为本轮根因。详见[新旧对照](consumer-siri-old-new-comparison-2026-10-29.md)。当前保留旧固件、Studio退出，未刷回新包。
