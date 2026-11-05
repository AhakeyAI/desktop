# WD010 本地模型EXE交付准备

## 第3轮续接（2026-11-05）

Owner在额度恢复后明确继续。第2轮独立复核发现R2-FR-01：成功结果排入FX队列后服务端401使终态丢失；DLA已正式登记FAIL并request-fix进入第3轮。1.0.20构建成功但该包不得交付，所有构建/测试记录原样保留。第3轮新包采用1.0.21，使用重新冻结及审阅的快照。

第2轮成品运行时恢复准备61、协议状态603、生产UI21、runtime竞态7通过；SpeechLifecycleCheck在本地模型配置下触发其“默认非模型版关闭”前提断言而失败，不能记成该套件PASS。最终本地模型包应直接验证真实JNI和模型识别，不改变成品model.enabled迎合非模型版夹具。

续接后只读复核原v2正式receipt及两条已绑定HEX路径，三项仍不存在；Firmware正式配对/Owner真机验收缺口不变，不通过修改Windows记录补造。

## 第1轮审阅后的打包约束补充

第1轮正式审阅发现FR-01/02/03，已路由第2轮FIX。修复重新submit并实际审阅通过后才能生成Preview快照和构建；不得从第1轮失败包构建交付。

预期使用1.0.20，2026-11-05检查target无此版本目录。C盘约4.78GB剩余，上一版完整打包目录1.57GB、派生源码约51MB；构建开始前再次核对空间，保留所有旧包和证据，不能自动清理。需要时只为新构建进程使用D盘独立临时目录，不能改全局TEMP或移动旧产物。

最终包验证应使用包内runtime/java.exe、实际JAR和lib，开发target/test-classes仅提供fixture，不把开发target/classes混进classpath。包括本轮修复新增检查、云端/恢复/语音接缝、相关WD009回归及安装身份/签名封套验证。尽可能使用现有SpeechNativeCheck以包内模型/native对仓内现有公共样例target/wd006-dependencies/models/0.wav执行JNI/重复识别/释放；该检查不打开麦克风、不注入按键，不发送云端文字。核对该样例已有来源和哈希后使用，不新增下载。真实App.start可能启动hook/USB/桥接服务，不能仅因为测试类注释说无设备操作就不审查直接启动。

本轮完整EXE可以交付，但匹配Firmware v2正式证据及Owner硬件/账号/付款/安装反馈仍未取得，不把机器检查替代这些验收。

日期：2026-11-05；Owner明确自主推进并选择local-model。仅记录配方调查，不是构建收据。

## 可复用输入

scripts/package-local-model.ps1使用新隔离OutputRoot，拒绝覆盖既有目录；只执行Maven离线构建、jlink、jpackage及签名/包检查，不安装、不启动应用、不kill进程。参考上一版target/wd009-preview-build-04/COMMAND.json及run_package.ps1；不调用根build-exe.ps1的清理/镜像删除路径。模型encoder/decoder/tokens及Sherpa API/native、已验证BLE桥均存在，实算哈希记录DELIVERY_INPUT_DISCOVERY.json。无需下载替换模型。

## 路径与身份

待DIB submit及DLA实际审阅通过后，使用正式preview-open快照和新隔离派生输入构建完整本地模型EXE。暂定递增版本1.0.20，构建前核对未占用。新ProductCode，保持同一应用UpgradeCode和配置兼容；不覆盖1.0.19或其他阶段产物。需要的安装配方输入须核对Git基线与来源字节，不能混用旧pom/生产classes。

## 证据与声明

WD009已存在完整EXE Preview路径，不需要为拿到EXE伪造Release Batch CLOSED输入。当前任务先按Harness实现、实际审阅、独立高影响复核，再走适用Preview构建；成品为内部测试安装包，不能标正式发布或假造Owner安装/设备测试。
正式Release Batch要求已关闭的任务及Owner实际验收，本轮不绕过该条件。Owner请求完整EXE可由完整、可安装的Preview EXE交付，最终明确尚未覆盖的实测项目。机器验证使用最终包自己的runtime/JAR/lib和隔离user.home，验证新功能接缝、回归、包内容、模型/native/桥完整性和安装身份；不安装到Owner日用路径、不发送真实付款/恢复命令。

## 固件限制

FIRMWARE_DELIVERY_RECHECK.json记录：绑定Firmware根中v2正式receipt、其原HEX路径及旧closure所称同hash副本均不存在，Git所有已知refs没有该receipt历史。现有closure/UAT文本不能替代缺失文件，不能伪造正式v2准入；该限制须保留至实际配对交测，不得隐藏于最终交付报告。

## Git保存准备（实施仍在进行）

只读核对 origin/win-zxy-harness 仍为 46c5f3ffec7135470ee8cf12e76342eaab130e7d，当前工作HEAD为其祖先（落后153提交），不是两侧分叉。已在 C:/Users/20825/.codex/worktrees/wd010-zxy-20261105 建立本地 codex/wd010-zxy-delivery 隔离worktree，以该远端提交为基底。第一次checkout因历史深路径失败，Git自动回滚worktree；随后仅本次命令 -c core.longpaths=true 成功，未改系统Git配置。尚未复制、暂存、提交或上传WD010。候选将在冻结审阅后仅叠加批准增量和必要证据，远端目标仍仅win-zxy-harness。
