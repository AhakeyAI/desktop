# WD-006 执行报告

## 身份与范围

DIB `/root/voice_builder`，2026-10-23，Contract revision 1 / Journey J007，IMPLEMENT 实现完毕待 DLA VERIFY。当前接收仓 HEAD `8c654c99a582d897d50698148e6c83cbe51c5d59`，WD-006 生产变化仍在工作区，未创建本任务 Git candidate、未提交或推送 Git。原始起点指纹 `98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9` 保持不变；本轮完成指纹 `e9928c761f70109b3e31235104ec78de826e24f520b87a77170b05356475969a`，以随后 helper submission/receipt 的核对为准。

固定来源为同仓 main@a2dae1a1772507b4d74201f045342599ebbf0603 的 ahakeyconfig-win-model-java；仅适配官方 Sherpa 1.13.3 流式 Paraformer。配套模型来自固定上游 revision 8e40c43232a1c5c66c82111efc5820d3accca11b，官方API/native和模型SHA见MODEL_INPUTS_20261023.json。没有读取或移入 eternal 语音、UI、云或其他代码，没有改固件仓。

## 实际差异

- pom：用固定本地 Sherpa API 1.13.3 替代旧 Microsoft ONNX Java依赖。官方native资源JAR由打包脚本显式放入lib，主程序不重复跨加载器System.load。
- ModelConfig / model_config.properties：本轮流式Paraformer路径参数；主线model.enabled=false保持；只有隔离staging JAR覆写true。
- SpeechService：替换旧SenseVoice手工特征提取；单worker与每段独立stream，松键补尾静音/inputFinished/decode后最终输出；录音关闭解除read阻塞，关闭先stream后recognizer，关闭不交付迟到结果。缺/空模型在JNI前拒绝；URI解码与内容SHA缓存支持当前中文安装/项目路径。
- VoiceInputManager：保持激活/F18 start-stop接口和最终文本注入时机；partial作为假设替换不拼接；连续录音保留UI回调。错误进入现有error提示；generation取消、最终结果只认领一次。fresh审阅发现的慢注入持锁阻断已修复：外部回调和慢输出均离锁；停用先于输出提交时零输出，已提交输出允许结束，不改旧KeyboardInjector。
- LibraryLoader：通过官方API空OnlineStream触发官方once-only loader；API字节码已核对ptr=0、无native对象。
- App：仅两条语音日志更新，F18路由、现有初始化条件不变。
- 三个speech测试类：生命周期/失败/并发，真实WAV JNI探针，缺native失败探针。
- scripts/package-local-model.ps1：父DLA编写隔离打包配方；模型/API/native固定SHA、离线Maven、新输出目录、staged启用模型、官方native资源JAR、jlink、app-image/EXE、launcher classpath检查。执行时必须使用preview-open隔离snapshot；本轮尚未运行此脚本。

WD-005 OLED/灯光/协议/Hook/会话等范围外87项字节与任务start一致。父DLA提供WD005_PRESERVATION_20261023.json，本DIB提交前独立重新逐项hash核对；同时复核7项API/native/模型/WAV文件大小与SHA，结果及本轮全部允许路径最终SHA见IMPLEMENT_INPUTS_FINAL_20261023.json。

## 已执行机器检查

### 本DIB实际执行

JDK17.0.19，全生产源码及3个新测试类编译退出0；最终编译和生命周期执行为工具输出chunk `1fa5fa`。编译无输出，因此没有假造空日志；初轮DIB_COMPILE_RESULT_20261023.json和修复后DIB_CONCURRENCY_FIX_20261023.json记录实际exit0。早期两次编译调用的argfile中文编码/PowerShell引号错误日志保留，之后已修正并成功。

实际生产编译命令：
```powershell
javac '-J-Dfile.encoding=UTF-8' -encoding UTF-8 -cp 'target/lib/*;third-party/sherpa-onnx-java-api-1.13.3.jar' -d target/wd006-builder-check/classes '@target/wd006-builder-check/sources.txt'
```

实际测试命令：
```powershell
java '-Dfile.encoding=UTF-8' -cp 'target/wd006-builder-check/classes;target/wd006-builder-check/test-classes;target/lib/*;third-party/sherpa-onnx-java-api-1.13.3.jar' com.example.ahakey.service.SpeechLifecycleCheck
java '-Dfile.encoding=UTF-8' -cp 'target/wd006-builder-check/classes;target/wd006-builder-check/test-classes;target/lib/*;third-party/sherpa-onnx-java-api-1.13.3.jar' com.example.ahakey.service.SpeechNativeFailureCheck
```

SpeechLifecycleCheck最终37检查PASS，日志DIB_LIFECYCLE_20261023_03.log。覆盖缺/空模型、PCM、中文路径/缓存失效、stop flush、read关闭异常、释放顺序、失败反馈、禁用默认、partial不注入、多次录音、取消迟到结果、并发慢输出期间F18/停用/shutdown在500ms上限内返回、取消先赢零注入、重复final只1次。所有音频/输出测试使用可控替身，没有用户麦克风或真实键盘注入。独立fresh审阅者也实际复跑37检查通过，其事实见FRESH_REVIEW_20261023.md，DIB不代替其审阅结论。

SpeechNativeFailureCheck在不带native JAR的独立JVM实际捕获UnsatisfiedLinkError并确认loaded=false、进程继续，退出0，日志DIB_NATIVE_MISSING_20261023_01.log。错误堆栈是预期测试事实。

### 父DLA实际执行、本DIB读取并绑定的证据

父DLA使用官方配套native JAR和固定模型，调用SpeechNativeCheck对上游0.wav/1.wav进行真实离线JNI识别，每个进程重复识别并release两次，实际java退出码均0。日志NATIVE_WAV_0_20261023.log、NATIVE_WAV_1_20261023.log均包含RECOGNIZED文本与PASS real Sherpa JNI/WAV repeat and release。本DIB没有声称亲自执行这些WAV命令；本DIB读取日志并复核输入SHA。

可观察输出分别为“昨天是 monday today day is 礼拜二 the day after tomorrow 是星期三”和“这是第一种第二种种叫嗯与 always o s 什么意思啊”。该检查证实真实模型可以加载和输出、重复和释放工作，不证明识别准确率，也不替代实际麦克风/F18/输入焦点体验。

## 实际可运行产物

当前只有隔离检查classes/test-classes、固定资源与模型，以及静态打包配方；未实际构建本任务app-image/EXE，没有安装包SHA、没有安装/启动或Owner测试。父DLA下一阶段必须review-pack绑定实际diff，完成正式审阅记录后preview-open，使用其隔离snapshot执行配方；不得把旧WD-005产物当本任务模型版。

## 交给DLA

本轮没有改Harness规则/批准/起点，未自审review，未代填Owner真机/UAT。四项machine/core_regression/special_regression/mock仅按上述实际证据登记；本任务real_device=false应由DLA记NA，owner_uat保留pending（DIB helper禁止写这两项，即使NA/pending）。Git candidate尚无、正式review-pack尚需绑定、实际EXE构建/内容核验/安装与Owner体验尚待。

限制：中文用户名且系统禁用短文件名、无法得到ASCII临时目录时明确失败并提示java.io.tmpdir；当前中文工程路径有真实WAV覆盖。已提交到KeyboardInjector的输出不强制中断；尚未提交的generation取消可靠。旧安装身份/升级保留配置未实际验证。没有Hook、设备写入、BLE启动、杀进程、安装、烧录或真实录音行为。后续构建证据必须另写phase-scoped记录，不能追加修改冻结后的本报告。
