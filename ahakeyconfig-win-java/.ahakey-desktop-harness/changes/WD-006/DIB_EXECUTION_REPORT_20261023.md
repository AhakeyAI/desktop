# WD-006 DIB 实现报告（2026-10-23）

实现角色 /root/voice_builder。当前 IMPLEMENT，未 submit，未自审、未写 Git、未启动应用/麦克风/Hook/键盘注入。DIB preflight 实际通过。来源限定 main@a2dae1a1772507b4d74201f045342599ebbf0603 的模型版语音方案与官方 Sherpa 1.13.3 API；没有读取或移入 eternal 代码。

## 实际实现

- 用流式 Paraformer 替换旧 SenseVoice 手工特征路径，仅适配本轮 encoder/decoder/tokens、官方 API；不迁移云/UI/VAD/标点。
- model.enabled=false 保持主线无模型可启动；隔离打包配置覆盖由父 DLA 负责。
- 保留 VoiceInputManager 公共生命周期与 F18 start/stop 接口，partial 是可替换假设不拼接，松键才 flush 最终文本并注入一次；第二次录音保留 UI 回调。
- 单 worker 独占 session/recognizer；松键关闭采集解除阻塞、补静音并 inputFinished/decode drain；关闭时抑制待交付结果，先释放 stream 后释放 recognizer。
- 缺/空模型在 JNI 前拒绝；初始化和录音的 LinkageError/异常可靠回传既有 error 状态，不伪装 ready。
- 模型 URI 正确解码；中文路径按内容 SHA256 缓存至 ASCII 临时目录，中文临时目录尝试 Windows short path，无法取得时明确报错。缓存更新不会复用同名旧模型。
- 本地 LibraryLoader 通过官方空 OnlineStream 的构造触发官方 once-only loader；javap 证实 1.13.3 此构造 ptr=0、不创建 native stream。避免原自解压/System.load 与官方自动加载重复。
- 增加纯离线 WAV probe：SpeechNativeCheck，完整 WAV 解码为 16k mono PCM；真实模型/官方 native JAR 到位后由父 DLA 执行。

## 实际机器检查

1. 全生产源码 javac（JDK 17.0.19）通过，三个新增测试类编译通过，调用记录 DIB_COMPILE_RESULT_20261023.json。编译成功没有输出，Tee-Object 未创建空日志；不可把空输出冒充运行测试。
2. SpeechLifecycleCheck 30 检查通过，DIB_LIFECYCLE_20261023_02.log：PCM端序、缺/空模型、中文路径/缓存更新、禁止重叠录音、松键flush一次、关闭取消/释放顺序、close导致read返回或抛异常、麦克风失败、JNI初始化失败、partial不注入、连续第二次回调、默认禁用不加载JNI。
3. 独立 JVM 不带 native resource JAR 实际运行 SpeechNativeFailureCheck，通过真实 UnsatisfiedLinkError 捕获与 loaded=false 检查，日志 DIB_NATIVE_MISSING_20261023_01.log。
4. 前两次编译因 Windows argfile 中文编码 / PowerShell 未引号参数失败，原始日志 _01/_02 保留；第三次通过，随后补stop竞态再做第四次最终编译。

完整逐文件和日志 SHA256 见 DIB_IMPLEMENTATION_CHECKS_20261023.json。编译目录 target/wd006-builder-check/classes、test-classes 为本轮隔离检查目录，未清理既有 target，也没有构建/交付 EXE。

复现命令（PowerShell）：
```powershell
javac '-J-Dfile.encoding=UTF-8' -encoding UTF-8 -cp 'target/lib/*;third-party/sherpa-onnx-java-api-1.13.3.jar' -d target/wd006-builder-check/classes '@target/wd006-builder-check/sources.txt'
java '-Dfile.encoding=UTF-8' -cp 'target/wd006-builder-check/classes;target/wd006-builder-check/test-classes;target/lib/*;third-party/sherpa-onnx-java-api-1.13.3.jar' com.example.ahakey.service.SpeechLifecycleCheck
java '-Dfile.encoding=UTF-8' -cp 'target/wd006-builder-check/classes;target/wd006-builder-check/test-classes;target/lib/*;third-party/sherpa-onnx-java-api-1.13.3.jar' com.example.ahakey.service.SpeechNativeFailureCheck
```

## 缺口 / 接力

父 DLA 尚需匹配模型/native资源真实WAV检查、WD-005非语音生产字节核对、打包脚本实现整合、正式record-check/submit、独立实际diff与fresh审阅、隔离EXE交付。当前机器检查不等于模型识别通过、Owner Preview或UAT通过。本报告仅记录本DIB范围；请在上述输入合并后另写最终EXECUTION_REPORT，不能把本报告冒充其他角色检查。
