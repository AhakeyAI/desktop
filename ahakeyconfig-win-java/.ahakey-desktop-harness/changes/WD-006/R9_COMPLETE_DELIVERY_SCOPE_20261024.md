# 本轮完整交付范围：CP2.5/2.6、软件OTA、HEX烧录

本文件是 Owner 已讨论确认产品语义的实施范围。取代r6仅F18文案的暂停边界；历史不删除。Journey J002/J005/J007及既有更新维护旅程；scope_expansion + protocol_change + architecture_change，high_impact独立审阅。DLA按正式contract-reconcile后唯一DIB preflight实施，未派工前不得生产编辑。

## A. Windows K1 路由与 CP2.5

正式输入为 CP25_CP26_WINDOWS_INTAKE_20261024.json 所绑定Firmware协议/源码/gate。旧协议commands表是调查快照，采用reviewed_allocations 0x9E v1与当前候选实现：102字节单route、408字节四route，frame<=62，读片<=42、写片<=47。capability严格校验nonce/version/subcommand/flags/modeCount，不能按仍相同r001 catalog推断或接受generic ACK。ordinary动作有明确kind；Consumer只读显示，Windows没有Consumer设置入口。

实际编辑入口/模式切换读取选中模式的设备权威K1route；普通快捷键/宏的明确编辑保存才写ordinary+动作，保存后回读确认。全配置保存不能把未修改的K1或其他模式Consumer覆盖为旧草稿。缺route可明确配置，读取失败不可伪装空普通键。K2-K4/侧拨/既有0x96语义不变。旧固件保留旧路径，未知能力不猜；维护锁/read/write权限与真实入口配套。命令错ACK/CRC/断连/commit不确定通过回读解决，不盲重放；原始数据/metadata如目标mode需在异步切换时固定，不写错模式。CP2.5做现有传输/资源上传/断连恢复/实际readiness回归，避免不必要BLE重写。

## B. 软件 OTA

固定 HTTPS https://ahakey.com/stable.json，网站从三个环境变量动态生成schema3：schema=3/channel=stable/version=WINDOWS_LATEST_VERSION/windows.lite.url=WINDOWS_DOWNLOAD_LITE_URL/windows.local-model.url=WINDOWS_DOWNLOAD_STT_URL。一个共享version，缺形态不串包，无效/404/网络异常不冒称最新。不让Owner维护JSON文件、hash、size、签名字段或证书。网站单独项目实现并提供部署说明，不自动部署。当前客户端schema2可按实际兼容需要保留读取但不能绕过新信任门。

采用已独立研究的应用固定公钥发行签名包（r8-design-review-20261024方案A），标准RSA3072/SHA256withRSA，对原EXE prefix摘要/长度和版本、形态、架构、产品、UpgradeCode及实际ProductCode签名。严格EOF封装/长度上限/唯一格式，公钥固定在应用及worker中；下载后和安装前worker独立复验，远程JSON/请求不可替换公钥。私钥只在本机非仓库输出的专用受限签名目录创建/保留，不打印、不上传、不入Git，报告可恢复保管位置而非内容；打包脚本自动签最终EXE，Owner只上传该EXE。签后不可再改包。保留MSI实际身份验证、文件锁、ready/exit-permit/父PID+启动时间退出确认、UAC/退出码/receipt/安装后真实身份核对。未经验证原app不退出，下载可取消，缓存不能当信任。云存储HTTPS下载允许实际tcb.qcloud.la来源与精确跳转策略，禁止HTTP/凭据URL/不受限重定向；日志去query，响应大小与安装包本地上限约束、流式读写。

工程计划1.0.11升级起点和1.0.12目标，均完整本地模型版。每个包真实app-release/MSI/签名身份一致。用户已有1.0.10空信任配置不声称可直接OTA；手装1.0.11后OTA至1.0.12。两版仍统一发行号，基础API和匹配测试覆盖lite/local-model，但本轮产物不额外构建Lite。

## C. HEX烧录

用户已选定简单流程：选HEX→关机按住语音键插USB→检测boot→点击烧录→按提示退出boot正常USB重连并读取版本→成功。无需正常USB先备份，不强制读当前版本/检查降级，不加入恢复配置/onboarding分支。双区清除告知一次，写入前固定HEX字节/hash并校验Intel HEX；本地未知HEX明确显示未知目标版本，成功只显示实际读到版本。已知HEX可核对目标身份，不把任意文件名当版本。

WCH工具随包，包括原厂固定EXE/DLL/芯片表/净化配置、缺失的x86 CH375DLL与匹配驱动文件；依据r8工程STATIC_INPUTS，不扫描用户C:/WCH作为发行依赖。应用内准备驱动允许用户UAC而不另找工具；固定系统工具/验证随包hash，不能从任意外部路径自动执行；本机实施阶段不实际安装驱动。合法许可未知如实记录，不凭未知虚构禁止/允许。

boot探测独立于BLE/普通HID/旧缓存身份，支持已确认硬件ID集合；单台UI无需复杂多目标选择，如意外多台只简短要求保留一台而不任意写第一台。检测/准备不自动启动下载，只有点击启动一次。校验真实WCH明确终态和进程已结束，保留当前verify机制或经审阅等效校验，不能exit0冒充成功。超时/失败统一“本次链路失败，点击退出重新链路”；退出清理仅本次可核对进程树，等待有上限、无无限wait，旧进程未确认退出不能开始第二次写入。保存诊断，不自动重刷。正常重连不等onboarding完成；一旦实际读到版本则按成功条件结束，UI无过多结果分支。

## D. 产物与验收

先DLA实际增量/累计diff与独立高影响审阅，缺口修复，再精确Git候选/产物身份绑定和隔离build-open/build-finish。既有R7与F18增量证据保存，不覆盖冻结报告/安装包。不得clean现有target、kill用户运行app、自动安装/刷机、修改Firmware/eternal、公开发布。复用已有模型/运行时，不重复下载模型。

交付两个完整可安装EXE：1.0.11起点、1.0.12目标。需真实包内模型/JNI/BLE/WCH/driver/签名/版本/MSI提取核对；离线GUI用隔离方式，不触发真实设备操作。证明追加签名不改变MSI payload。测试覆盖route协议/真实UI入口与不改Consumer、旧固件降级、OTA错版本/形态/签名/截断/取消/worker锁/安装回执，以及烧录prepare/detect/write/verify/reconnect/超时/清理假进程路径。无需以成百重复静态断言代替行为检查。

最终提供从上传目标包、部署官网接口、修改环境变量、手装起点、检查下载、退出安装、重启确认和再次检查最新的逐步方案，含原配置保持和失败预期；明确本机已测与Owner待测。用户不搬运仓内固件信息。CP2.6独立gate机器PASS不代替合并HEX UAT；现有已准入CP2.5可作默认候选需重新固件准入，CP2.6最终实机配对必须等Firmware正式允许交测的合并HEX，不能擅自放宽其要求。
