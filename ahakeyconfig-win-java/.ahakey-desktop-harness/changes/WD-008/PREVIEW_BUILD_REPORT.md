# WD-008 本地模型 1.0.17 Preview 构建报告

仅交付最终 R6 包；不是 WD007、Git candidate、正式发行或 Owner 真机验收。冻结的 IMPLEMENT 报告未改。

## 输入与构建
- preview token：preview-20261101T084504211860Z-fea4a2，DLA actual diff review PASS 后授权。
- 原始 snapshot 保留不动；target/WD008-Preview-Source-R6-1.0.17 从核对后的178输入文件重新复制，不携带任何 target 缓存。
- 输入来源165项 snapshot + 13项原 WD006 R13 installer 配方。实际输入逐字节 manifest：target/WD008-implementation/PREVIEW_FINAL_SOURCE_INPUTS_R6.json；构建后178文件全部复核未变。
- 为满足已有严格 SHA 校验，在派生源恢复原 WD006 R13 三项 CRLF 字节：ble-driver-fixes.patch、chiplist_CH57x_CH59x.wcfg、原内置 HEX。均确认仅换行差异；原工作源和原 snapshot 不变。参见 PREVIEW_BYTE_RESTORATION.json 与 PREVIEW_HEX_BYTE_RESTORATION.json；不修改期望 SHA 或跳过校验。
- 运行既有 package-local-model.ps1，AppVersion=1.0.17，ProductCode={FB93C778-6BB6-4615-AD95-C7834D4F3BB2}，SourceRoot=target/WD008-Preview-Source-R6-1.0.17，OutputRoot=target/WD008-Preview-R6-LocalModel-1.0.17。
- 实际工具：D:/jdk-17.0.19.10-hotspot；C:/Program Files/apache-maven-3.9.12/bin/mvn.cmd；C:/Program Files (x86)/WiX Toolset v3.14/bin。
- ModelRoot=target/wd006-dependencies/verified-models，NativeJar=target/wd006-dependencies/sherpa-onnx-native-lib-win-x64-v1.13.3.jar，MavenRepository=.m2repo，DtfRoot=target/wd006-dependencies/wix-dtf-5.0.2，BleDriver=target/wd006-preview-fix1-bridge-01/bin/BLE_tcp_driver.exe，BleDriverManifest=target/wd006-preview-fix1-bridge-01/BRIDGE_BUILD_MANIFEST.json，SherpaLicense=target/wd006-dependencies/Sherpa-ONNX-LICENSE.txt，InstallerType=exe。
- 最终完整脚本退出0，日志target/WD008-implementation/preview-package-r6.log与preview-package-r6-exit.txt。Maven离线 package→jlink→jpackage→MSI提取→发行签名→包内完整性与签名核验均实际执行。

## 最终身份与检查
- 可安装EXE：target/WD008-Preview-R6-LocalModel-1.0.17/installer/AhaKeyStudio-1.0.17.exe。
- EXE SHA256：42a15460426265439cfd69c11e1badf54606c5eb982a471760291a266803774c，296237624 bytes。
- 实际MSI版本1.0.17、local-model、x64；buildId=835bc98d958aaf2530e2d1b76e592cf00543ab306a1373c6891d934feb366075，MSI SHA256=edc0c010777a57cd3f57e5084e115eb008cdb17d3985cae00f65cf6c3f764c75。
- 完整 app-image 的314个文件在 PACKAGE_IDENTITY.json。固定公钥发行签名由包内Java和更新worker双重通过；不是Windows Authenticode签名。
- update-verification/result.json、actual-msi-structure.json通过；身份、安装路径/升级结构、WCH13文件、内置HEX与签名均实际检查。
- 模型3项和native JAR均严格原SHA验证，源模型配置保持false，交付JAR叠加true。
- 随包BLE二进制SHA256=1f4ed669834cb523a466b91e639623ae863e43380c4fdbb35102df723f7829d6，逐字节等于WD006 R13；没有恢复WD007桥。
- 用最终R6包内 runtime/bin/java.exe + 实际app JAR/lib（不使用实现classes替代产品）运行85项专项及8项补充，均退出0。测试类仅位于target/WD008-implementation/test-classes，未放进产品。日志packaged-r6-identity.log、packaged-r6-supplemental.log及各自exit文件。
- 测试仅内存USB/TCP与包内容；没有启动主程序/桥、安装、杀进程、设备读写或烧录。真实六组设备测试均待Owner。

## 失败尝试保留
第一阶段严格hash拒绝Git快照LF资源；R2/R3在沙箱中WiX ICE无法访问Windows Installer服务，未禁用ICE；通过自动审批后仅构建在沙箱外正常完成。
R4/R5最终内容检查拒绝错误换行的内置HEX，未交付；R5的源码已经正确，但Maven因恢复旧文件时间戳沿用早前target/classes缓存。R6从全新源只复制178已核对输入，根除缓存复用。最终源/classes/JAR内HEX均通过原SHA。
旧失败目录和日志保留，不能拿其中EXE测试。没有为通过构建更改校验规则、关闭防护、修改系统配置或安装产品。

## 交给DLA
完成preview-finish绑定后，仅向Owner提供上述R6 EXE。请按OWNER_PREVIEW_TEST.md和PREVIEW_FIRMWARE_MATRIX.json给出步骤；六组真机未执行，不称稳定性已通过。产品代码未提交Git，Preview仅绑定原HEAD、审阅增量与实际产物。
