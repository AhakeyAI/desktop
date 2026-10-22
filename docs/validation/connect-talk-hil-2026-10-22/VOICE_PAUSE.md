# VOICE-PAUSE-01：连续长按停顿后前句丢失

状态：已定位、候选修复及487项自动测试通过，真实修复回填待复验。优先于继续其他WBS。

## 已确认事实

用户首次反馈短/长按回填正常、主动重复词保留、Dock正常。但日志显示当时长按分为几次独立录音，不把它当作连续停顿验证。补测要求全程按住，说测试前句，停顿约2秒，再说后句，最后才松手；用户明确反馈缺前半句。

同一录音内13条实际识别快照显示：前句由1/2/4/5/6字逐步识别到完整6字，再相同6字；停顿后识别结果重新从后句的1/2/3/4/5/7字增长，最终结果仅后句7字。只有一次录音开始，实体down在13:21:05Z、up在13:21:15Z；中间没有松手，最终bypassAhaType=true，提交原文和输出都只有后句且只粘贴一次。第二次连续测试再次出现相同覆盖形态。不是两次粘贴，也不是云端裁剪或BLE触发漏键。原始语音/快照仅本机private保存。

以实际采集的13条文本快照输入当前生产SpeechTranscriptSnapshot.applying，稳定输出firstPhrasePreserved=false、secondPhrasePreserved=true、characters=7、退出1。该命令无需录音或用户交互。

## 与先前重复字修复的关系

先前为避免把同一句反复改判的结果误拼接，改为最新非空文本替换旧假设；短句修订/最终变短的回归通过。但当前本机recognizer停顿后会返回不含前句的新片段，单纯替换使已识别前句丢失。不能回退到按中文字数或文字重叠猜测拼接，否则会重新引入原来的局部重复。

## 需区分的假设及探针

1. 新音频片段：若是，SFTranscriptionSegment的音频时间向后推进，可据真实片段边界保留前句。
2. 同一句修订：若是，音频范围继续重叠，应替换该句而不是追加。
3. 录音意外重开：应出现新start/generation；当前真实trace未发现，仍记录generation以校验。

Apple文档：[segment timestamp](https://developer.apple.com/documentation/speech/sftranscriptionsegment/timestamp)、[recognition metadata](https://developer.apple.com/documentation/speech/sfspeechrecognitionmetadata)。诊断包仅增加DEBUG-voice-pause-20261022标签的segment timestamp/duration/字数及metadata时序，不额外输出语音文本，不改算法、键位、Voice策略或输入设备。最终修复提交前须移除临时探针，并同时回归“短句改判不重复、真实重复词保留、最终假设变短、长停顿保留前文、每次只粘贴一次”。

## 旁路观察

首轮首次短按录音启动约3秒后用户停止，得到No speech detected；随后短按和长按均可工作。偶发启动延迟VOICE-LAT-01仍开放，不将后续成功当作已解决。成功短按保留主动重复，提交与最终识别一致，云端处理前后文本发生变化；这与此前ClosedEndpoint不同，但尚不据此声称四模式云端完整验收通过。

## 时序诊断与候选修复

诊断候选ec6e584已签名安装，用户连续长按再次复现缺前句。实际13条时序表明，第一句完成时isFinal=false，但speechRecognitionMetadata已经存在：start2.640、duration2.250；前后单词跨度一致。第二句的临时结果重新从1字开始（时间为0、metadata=nil），最终isFinal=true、start7.680、duration2.100。整个过程中generation相同，只有一次录音。已明确这是同一recognitionTask内的两个完成句子，而非同一句反复改判。

新增SpeechTranscriptAccumulator，以完成音频区间保留句子；同一区间的修订替换相应句子，累积结果覆盖其涵盖区间，不按字数或字符串重叠猜测拼接。无时间的partial只更新当前句；完成时优先使用有效单词时间的包围区间（包含静默间隔），不把发声时长相加误当整个音频跨度，metadata作为回退。每次录音重新初始化状态；保留原generation/处理策略锁定和一次回填门控。不同音频中相同的词仍保留，用空格分隔不同句子，不改写识别出的词和标点。

先将新接口等价接入旧替换逻辑，9项聚焦测试出现3项失败；真实13条时序/文本生产回放也稳定firstPhrasePreserved=false、secondPhrasePreserved=true、characters=7。修复后同一回放为true/true/14，13项新回归及既有6项快照回归通过，完整487项测试通过。回归覆盖真实停顿序列、重叠音频改判/变短、跨句真实重复、全量累计结果、未给出后句时间即停止、重复final、空结果、新录音隔离、零起点/相邻区间和无效时间。

临时DEBUG探针已从生产源码移除，无额外语音文本或临时时序记录；不改变麦克风、权限、HID/Consumer或键盘配置。最终签名修复包及原路径真机复验待继续，不以回放或487项自动测试宣称本问题已真机解决。
