# WD-006 Fresh 独立审阅（2026-10-23）

审阅对话：`/root/voice_fresh_review`，独立于实现 `/root/voice_builder` 与原 DLA `/root`。本记录只审阅和记录证据，不修改生产代码，不代填正式 REVIEW.json。

结论：发现的 1 项实现阻断已修复；复查后的生产代码和打包配方未发现剩余静态阻断。允许原 DLA 继续实际 JNI/WAV 验证及绑定 Preview 构建。本结论不是安装、GUI、麦克风、设备或 Owner UAT PASS。正式 review-pack 尚待父 DLA 生成，随后以追加记录绑定；当前实际文件身份见末尾。

## 审阅依据与实际范围

已读本地 lead/harness SKILL、RULES、OPERATING_MODE、GUARDED_DELIVERY、DISTRIBUTION_DELIVERY、OWNER_COMMUNICATION、STATE/local 与 WD-006 CONTRACT。对 `recovery/current-at-guard-start` 原字节进行比较，只有 pom、App、ModelConfig、SpeechService、VoiceInputManager、LibraryLoader、model_config 七个原有文件变化；其余恢复副本所覆盖的 WD-005 生产文件均字节相同。新增测试、API JAR 和打包脚本在批准路径内。

逐项核验 SOURCE_MANIFEST 的 9 个 main-model-source 文件：SHA256 与 snapshot 相符，Git 对象与 `main@a2dae1a1772507b4d74201f045342599ebbf0603:ahakeyconfig-win-model-java/...` 相符。审阅未读取或采用 eternal。实际 Paraformer encoder/decoder/tokens、OnlineModelConfig/OnlineRecognizer 与 main 固定来源一致；以单 worker、独立 stream、按键松开 flush 适配当前按住录音/最终注入流程，未迁入模型版 UI、云服务或固件。

## 发现与处理

F1（原阻断，已修复）：初稿 `VoiceInputManager.onFinal` 全方法 synchronized，持有 manager monitor 调用慢速 KeyboardInjector.injectText（300ms + 每字20ms）。App 的 F18 Hook 同步进入 startRecording，长输出中再次按 F18 会等待 monitor，影响 Hook 和停用/关闭。DIB 修复为锁内一次性 claim generation、检查取消与取得 injector；外部 status/partial/result 回调和慢输出均在锁外。输出提交前取消先取得锁则抑制输出，已提交输出允许完成；不修改旧 KeyboardInjector。独立重新执行修复后 SpeechLifecycleCheck，37 项 PASS，含慢输出期间 F18/停用/shutdown 500ms 内返回、阻塞结果回调时取消后零输出、同 generation final 仅一次。

P1（配方风险，已修复）：初稿新固定 upgrade UUID 和 per-user 安装与旧脚本默认 machine 范围不同，可能造成并存。父 DLA 移除了新增 UUID/per-user 参数，保留既有 AhaKeyStudio 名称、AhaKey vendor 与默认安装范围。实际已安装旧包身份/升级保留配置仍需 Owner 验证，未声明无缝升级通过。

## 逐项语义核对

- SpeechService：同一识别器只有单 worker 或加锁离线 recognize 使用；worker 保持 busy 到最终回调结束，连续按键不叠加 stream。stop 关闭 capture 解除 read 阻塞；正常松键追加尾静音、inputFinished 后最后 decode，final 只发一次。release 先标 closed、停录音，worker 释放 stream 后才释放 recognizer；closed 阻止最终输出。麦克风失败释放 stream 并走错误通知。
- VoiceInputManager：partial 是替换假设，只用于 UI，不再累积/注入重复文字。final 保留原最终文本注入时机，重复 generation 不重复输出；停用/关闭先失效 generation；多次录音保留 UI callbacks。初始化 Exception/LinkageError（含 UnsatisfiedLinkError）使 enabled=false，现有 TopBar 显示不可用。
- JNI：官方 API 1.13.3 的 OnlineStream 字节码已用本机 javap 核对：空构造调用官方 once-only loader，ptr=0；release/close 对 ptr=0 不执行 native delete。包装器因此不重复 System.load；matching native resource JAR 由打包提供。缺 DLL 不是成功初始化。
- 路径：模型相对 JAR 位置解析经 URI 解码；中文路径模型按内容 SHA 缓存到 ASCII 临时路径，非空检查与缓存失效测试覆盖。中文用户名且短路径不可用时明确报错，不伪称加载成功；当前机器中文项目路径的真实 JNI/WAV 测试由父 DLA 执行。
- 默认/回归：源 model.enabled=false，App 保留原条件初始化和 F18 回调，App 本轮仅两条日志变化。WindowsVoiceRelayService、Hook、协议、OLED/灯光/会话生产字节未改。旧系统路由保持原代码，未在此审阅启动 Hook。
- 打包：输入模型/API/native 固定 SHA 验证，主源 false，仅 staged JAR 覆盖 true；不 clean/kill/install/启动应用。使用新 OutputRoot、离线 Maven、JDK17 jlink、Main 入口、app-image 后制 EXE。核对本机 JDK17 LauncherData/CfgFile 字节码确认 input 目录 JAR 被纳入 launcher classpath，脚本还核验 API/native 的 cfg 条目。旧 Microsoft ONNX runtime 不入 staging，官方 native resource JAR 保持完整。实际调用必须使用 preview-open 返回的隔离 snapshot（脚本 SourceRoot 是参数，不能单靠脚本证明调用者选择正确）。

## 独立执行与未执行

2026-10-23 独立命令：`D:/jdk-17.0.19.10-hotspot/bin/java.exe -Dfile.encoding=UTF-8 -cp target/wd006-builder-check/classes;target/wd006-builder-check/test-classes;target/lib/*;third-party/sherpa-onnx-java-api-1.13.3.jar com.example.ahakey.service.SpeechLifecycleCheck`。

实际退出 0，输出 `PASS SpeechLifecycleCheck: 37 checks; no devices or keyboard injection`。预期的 fake unavailable / fake missing DLL / disabled-model 错误由测试主动触发，不是运行失败。该独立调用未把资源目录加入 classpath，因此其中 disabled-model 检查验证缺配置时默认 false；源码 properties 的显式 false 另行实际读取确认。

未运行实际 App、Hook、麦克风、键盘注入、设备、安装或旧进程清理。真实模型 WAV 输出、隔离 EXE 字节内容/运行时验证、安装/GUI/F18 真实使用和 WD-005 Owner 回归分别等待相应证据。不得将本报告等同产品全功能通过。

## 本次复查文件 SHA256

- `pom.xml`: `b6fa46812aa860758e2e54db7d44ccd224f1b3a8f16ea08ab5ccca73e9055b0b`
- `src/main/java/com/example/ahakey/App.java`: `a23aa9be360dbfbebecffdf02e0df7f7de5e45f6d4e856c1308e6b0cbe2f37a8`
- `src/main/java/com/example/ahakey/config/ModelConfig.java`: `d201444fc438db279fa88721239ab84e46390853791b7f358dd3cc7f52ba85d1`
- `src/main/java/com/example/ahakey/service/SpeechService.java`: `4f2551fcc3c519d30b3cfe84daf398bebc05078c77bec48facd17d2fcbd02b34`
- `src/main/java/com/example/ahakey/service/VoiceInputManager.java`: `f0e1c5438e0f7247334b0c362722b445ee9b375883ab2ab00cc61a2b662b1bfe`
- `src/main/java/com/example/ahakey/sherpa/LibraryLoader.java`: `122336c83ed023b70452f25d137f323c3c1debaef1c1e31f8ca50f137fd60f79`
- `src/main/resources/model_config.properties`: `bffbce2f84b05bc2cc328ada986bcf8d643e2b140b81642f35efdaef1155f91b`
- `src/test/java/com/example/ahakey/speech/SpeechLifecycleCheck.java`: `3bd2ac4cef71b377d3e6561cfe0e36a38bc8537278d6bf3cad280ea4f6a4373b`
- `src/test/java/com/example/ahakey/speech/SpeechNativeCheck.java`: `109ebcc661f673fba38dfe3d18eab8779da443c352052d3ebe62302a654b8ae4`
- `src/test/java/com/example/ahakey/speech/SpeechNativeFailureCheck.java`: `d6dfb2c07b1b0529a2dd1861dd2d0d7695edc6a2f01826792ebcd6499d0b6508`
- `scripts/package-local-model.ps1`: `d8ff6a56cb4c7f57b03acfe10686fa75b7da81d1083614bce689036e2774bccc`
- `third-party/sherpa-onnx-java-api-1.13.3.jar`: `4a1fabf547d5e3bb5c9b0ddfc767142692cabe658da84f16adfafd519149b082`
