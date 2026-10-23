# WD-006 本地模型 Preview 使用说明

这是基于 WD-005 的本地语音适配体验包，版本号 1.0.6。语音方案来自已合入 main 的 ahakeyconfig-win-model-java（PR #172），未使用 eternal 语音代码。

安装包：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\WD006-LocalModel-20261023\installer-validated\AhaKeyStudio-1.0.6.exe
大小：288016896 字节
SHA256：d34607c4b3cee9650006dc55669f52db250346e0bd0f558f34d5db4df8b07a48
源码候选：24e1f9a899575421d0a2cde9078e90e057a2f3b1（win-zxy-harness）

包含 Java 17 运行环境、官方 Sherpa 1.13.3 Java/Windows 运行库、流式中英文 Paraformer int8 编码器/解码器/词表及既有 BLE 桥接程序。识别在本地进行，不需要另行下载模型。VAD与额外标点模型未启用。

操作与预期：
1. 先保存草稿、退出旧 AhaKeyStudio，再备份 C:\Users\20825\.ahakey；新旧版使用同一份用户配置。
2. 双击上述安装 EXE，按向导完成安装，然后启动 AhaKeyStudio。预期现有配置及 WD-005 的 OLED/灯光界面仍在。
3. 点击“启动语音输入”，在记事本中按住 F18 说一句中文，松开。预期松键后输入最终文字；再次录音应继续工作，不重复上一句。
4. 再试一句中英混合内容，以及一段较长文字输出后再次按键。预期无卡死、无重复输出；记录识别效果、等待时间与异常提示。
5. 停用本地语音后检查原有系统语音入口是否符合之前体验。本轮不要求升级固件或执行设备写入。

已完成：37项生命周期/失败/并发检查；两段官方WAV实际JNI识别及重复一致性；包内自带运行环境再次识别；安装器标准ICE校验通过，193项MSI载荷与已测app-image逐文件SHA一致。WD-005范围外87项生产文件未变。
未完成：真实安装升级、GUI、麦克风、F18键盘输出与硬件体验，需Owner反馈；上述机器结果不代表Owner UAT通过。

如果失败：停止本次测试，保留错误截图与日志；关闭新版本，恢复原WD-005包与备份的 .ahakey 配置。原归档位于 C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\changes\WD-005\builds\20261022T004444327311Z-731fe2\runtime-jar-classpath，未删除。

反馈请说明：能否安装启动；本地语音能否启用；首句/第二句是否输出；长句是否卡顿；WD-005界面是否正常。直接在当前聊天反馈即可，无需创建新对话。
