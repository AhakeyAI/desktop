# WD-006 — main 模型版最小本地语音适配

Owner 已批准已合入 main 的模型版方案，范围依据 evidence/20261023-wd006-main-model-owner-approval.md。Journey J007；architecture_change + scope_expansion，high_impact 独立审阅。

仅借鉴 main@a2dae1a 的 ahakeyconfig-win-model-java 语音配置、Sherpa 1.13.3、流式 Paraformer 初始化与识别，来源清单 SOURCE_MANIFEST.json。允许为当前服务接口、正确释放/失败传播、中文安装路径、JNI独立依赖和打包适配做必要修正。不得整包复制，不用 eternal 代码，不纳入模型版 UI、云服务、宏编辑、固件。

allowed_paths 以 change.json 精确列表为准。保留原 App/VoiceInputManager 生命周期接口、现有语音启动入口、F18系统路由、键盘注入时机；不改变 WD-005 OLED/灯光/协议/Hook/会话。现有语音入口与通知反馈沿用，失败要记录原因并显示未启用，JNI UnsatisfiedLinkError 必须捕获。

主线默认配置继续可不带模型运行；model-bundled 隔离包明确开启。模型、API/JNI允许从正式上游取得固定版本并记录SHA，不从eternal取文件。VAD保持关闭，标点非必需，流式中英文Paraformer；未取得真实匹配模型不得伪装成功。

机器检查：JDK17编译；加载缺失/空模型和JNI错误的反馈；生命周期停止/关闭；固定上游WAV真实离线识别及可观察输出；WD-005生产文件字节未变。允许离线合成音频/上游测试WAV，不自动开启用户麦克风或键盘注入。主程序启动若会启动Hook/BLE须先隔离，未经确认不启动旧运行实例。

交付：原WD-005归档不重开。本任务实现后先DLA实际diff及fresh独立审阅；新候选身份另存。EXE打包使用批次隔离输入输出，配置覆盖只在staging发生，禁止clean既有target、kill进程、自动安装/烧录/设备写入。WB-001是原WD-005批次草案，语音新代码不能冒充旧候选，后续新批次/Preview记录必须绑定新代码。

Owner UAT：安装/启动、启用本地语音、F18录音输出和WD-005界面实际体验尚待Owner；离线WAV检查不代替麦克风/硬件测试。恢复方式使用原WD-005归档包与原配置；不删除用户配置。
