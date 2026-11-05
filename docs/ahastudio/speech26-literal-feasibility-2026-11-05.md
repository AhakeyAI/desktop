# 关闭整理后保留口述原词：新版Apple转写接口可行性

结论：本机两组合成音频验证了 `SpeechTranscriber` 可保留“换行”原词、主动重复词及停顿前后内容，并与现有文字拼接器配合。**尚未接入正式客户端，不能标记为语音问题已修复。** 当前安装仍是build559，未切换识别引擎或更改用户配置。

## 原因与候选范围

旧链路读取 `SFSpeechRecognizer.bestTranscription.formattedString`。现场关闭云端整理时，回调已包含换行符，客户端原样粘贴，没有把“换行”替换为命令。关闭自动标点不等于禁用这类口令。

Apple提供另一套[SpeechTranscriber模型](https://developer.apple.com/documentation/speech/speechtranscriber)，与系统听写模型有别；接口要求macOS26及受支持设备，必须动态核对硬件、语言和资产，不能仅按版本号启用。现有最低系统要求不能因此直接提高。Owner已确认：优先优化兼容设备；旧系统保留原链路及其口令限制，不提高最低系统版本，不新增第三方模型。

## 已执行实验

本机macOS26.3.1、arm64，SDK26.4。仅使用本机Tingting生成的测试音频，没有打开麦克风，没有请求安装模型，没有写键盘、剪贴板或账号。

- 普通文件转写保留两处“换行”，没有生成换行符。
- 实时节奏回放并使用生产 `SpeechTranscriptAccumulator`：普通配置虽收到21个volatile更新，但均集中在输入结束后，不能计为实时性通过。
- 增加官方 `fastResults` 后，“确认确认＋2秒停顿＋后半句”得到21个volatile更新，其中18个结果在输入结束前到达；首个结果距首份音频约1.12秒，两次“确认”及前后句均保留，无需人工核对的拼接冲突。
- 同一低延迟配置对“换行”样本得到25个volatile更新，其中22个结果在输入结束前到达；两处“换行”仍为文字，换行符数量0。

初版流探针误用AVAudioFile默认Float32，触发Speech框架SIGTRAP；查询兼容格式并使用16000Hz单声道Int16后重跑通过。该失败不能归咎为新版接口本身不可用；生产接入必须显式转换、校验输入格式。

官方明确提示[`fastResults`以准确度换取响应速度](https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption)。以上只有两组可控合成样本，不代表真实麦克风、口音、长句或所有语言验收通过。准备模型约1.3–1.8秒也不等于实际按键启动延迟，需单独处理准备与首次反馈。

## 接入所需工作

1. 保留现有 `NativeSpeechCapturing` 边界，增加新版实现和动态能力选择；未安装资产时不静默下载、不宣称支持逐字转写。
2. 将真实麦克风格式转换为模型要求的PCM，处理取消、队列积压、转换失败与模型结束，避免静默丢音或重复录音。
3. 按[Apple的结果时序](https://developer.apple.com/videos/play/wwdc2025/277/)处理volatile与已定稿片段。片段的`isFinal`不等于整次录音结束，只有结束录音后才能触发单次粘贴。
4. 延续胶囊实时文字、录音策略锁定、晚到结果隔离和原文回退；关闭AhaType时不调用云端整理。
5. 在明确兼容策略后完成接线，再集中验收真实短按/长按、主动重复词、长停顿、“换行”、首次启动、取消及故障场景。

这一路线依赖系统Speech框架，不依赖AhaKey Runtime。但旧系统逐字能力与真实语音质量尚未闭合，不能用本机合成样本替代全平台交付。

## 可重放探针

研究脚本为 `ahakeyconfig-mac/scripts/fixtures/speech26-stream-probe.swift`，不加入产品编译目标。需要macOS26、Xcode26+和本机可用的中文模型。不要把私人录音放入公开CI日志。

```sh
swiftc -parse-as-library ahakeyconfig-mac/Sources/Utilities/SpeechTranscriptSnapshot.swift ahakeyconfig-mac/scripts/fixtures/speech26-stream-probe.swift -o /tmp/speech26-probe
say -v Tingting -r 160 -o /tmp/speech26-input.aiff '确认确认，今天测试语音输入。[[slnc 2000]]前后内容都保留。'
afconvert -f WAVE -d LEI16@16000 /tmp/speech26-input.aiff /tmp/speech26-input.wav
/tmp/speech26-probe /tmp/speech26-input.wav --fast
```

[实验回执](../validation/connect-talk-hil-2026-10-22/speech26-literal-feasibility-2026-11-05.json)保留计时和验收边界，不包含用户录音或个人信息。

## 后续生产接入（2026-11-05）

已实现 `AdaptiveNativeSpeechCaptureSession`：macOS26且SpeechTranscriber可用、目标语言模型已安装时采用新版，否则保留SFSpeechRecognizer。不会主动下载模型或更改键盘路由；Consumer系统听写不受此替换影响。新版使用volatile＋fastResults，将句子定稿写入现有带时间轴的拼接器，整次录音结束前不粘贴。末尾显式排空重采样器；原生48kHz Float32→16kHz Int16及排空帧数测试通过。

模型结束等待最多5秒；处理出错、音频队列溢出或结束未确认时，保留已有文字供核对，不把半段结果自动回填。启动取消不允许之后重新打开麦克风。11项初轮专项及后续1040项全量测试通过；真实麦克风、快捷键、口令原词与首次启动仍须Owner集中验收。实验回执中的“尚未接入”保留为实验当时状态，不作为当前开发进度。
