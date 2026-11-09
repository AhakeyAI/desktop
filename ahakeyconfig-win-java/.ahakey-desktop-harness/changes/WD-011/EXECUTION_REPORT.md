# WD-011 BLE 状态恢复实现报告（revision 4 / build_round 4）

## 身份与授权
DIB 在权威 worktree C:/Users/20825/.codex/worktrees/wd010-zxy-20261105/ahakeyconfig-win-java 按 CONTRACT-BLE-RECOVERY.md 及 DLA 请求归属裁定实现；preflight PASS。Git 基础仍为 553af14068aaa982753aef05b77aea373c6cc983，前轮 ACR4 已批准工作保留。本轮无 Git 写、安装、kill、下载、真实设备读写、Firmware 修改或脚本执行。上一轮标准报告/回执/submission/verification 原字节已保存 contract-revisions/before-ble-recovery-20261109。本报告只冻结本轮实现，不冒充新安装包或 Owner UAT。

## 实际修复
- C# 补丁继续更新完整 00 状态缓存，同时将真实原始 13 字节响应经既有 generation/discovery/socket 锁校验转发给 Java；缓存查询功能保留。去掉 ready 后桥自主 00 查询和 LastClaudeState 重放/无消费者赋值，使产品设备命令统一由现有单个 BleManager 发出；连接发现、订阅、重连和端口路径保留。
- CommandSessionArbiter 增加物理请求 ticket；BleManager 的短 00 业务等待只在同 generation/ticket/opcode 仍有效时提前返回，不释放在飞请求，不重置原 15 秒运输期限。收到合法原始帧才能终结；缓存、错帧、旧代次不能放行。中断尚未发送的等待者不会污染别人的在飞请求；已发送请求的中断/写失败仍保守隔离。
- 后台状态轮询在已有 pending/其他 owner 时不追加设备查询；明确 UNKNOWN 后同代次仅提示一次并停发，重连换代恢复。TCP 接收不中断，迟到回复不能清除 UNKNOWN。原 Controller 心跳 >15 秒无状态可主动断开，未改该分支，仅源码核对，不宣称新增实测。

## 实际验证
完整输入 SHA、原始日志、退出码见 evidence/implementation-ble-r4/RESULTS.json；命令见 REPRODUCE.ps1。Java17 全生产源离线编译通过。
- 红测：实际 1.0.23 JAR 失败于“短业务等待后 pending 仍 known”；旧 C# 真实 OnBleNotify 更新缓存但原始 socket 读取超时。两份失败日志保留，未写成 PASS。
- 新 C# 真实抽取生产通知/发送路径，经隔离 TCP socket 输出 16 字节包；Java 使用该确切包进入真实 TCP 包处理。147 行为检查、14 端口案例及原离线桥检查通过；新桥离线构建 build-02 全部 exit0。没有启动桥 App 或 BLE 硬件，跨语言是有字节身份的分层对照。
- Java BLE 状态 38 断言通过：500ms 后700ms回复、pending 阻止上传、15秒 UNKNOWN、晚到不解锁、重连恢复、错帧/缓存/旧代次、等待他人请求时中断、已发送中断/写失败，以及连续同 opcode 00 的旧回复不能完成第二请求。
- 当前生产类实际回归：CommandSession55（含完整 K1 保存/读回、80/DATA/81与普通最后ACK），ACR4 5784，ACR3 394866，FactoryReset603及竞争7，K1协议/Hook检查，全部 exit0。断言数含逐字节/像素，不等于独立场景数。
- Java/测试脚本 diff whitespace 检查通过；统一补丁文件有一个必需的单空格空上下文行被 git diff --check 标为 trailing whitespace。严格补丁应用及构建已通过，保留格式而不破坏补丁。

## 边界与交接
新桥 target/wd011-bridge-recovery-r4-build-02/bin/BLE_tcp_driver.exe，SHA256 79d64eff5dc5594c391bceffa51b3d367c916a2378af774818c5dcf332a89bee；manifest/patch/test 输入完整绑定。该桥尚未构成 1.0.24 安装包，禁止用旧桥或旧 EXE 冒充。
产品内唯一设备 writer 已由独立预审核查；任意第三方并发 TCP writer 不在本轮支持承诺中。短500ms是已发送后的业务等待，进入前仍须等待已有请求终结。无真机 USB/BLE、键盘输入、Owner UAT结果。r3旧 fixture 与新契约冲突、C04基线债务仍保留旧报告，不作为本轮 PASS，也未扩范围修复。前五项 UI/日志/BLE 外观调整继续延期。
下一步 DLA actual review 与独立审阅；得到新 Preview token 后按批准隔离配方打包 1.0.24 Local Model，并以包内 JAR/runtime、新桥以及真实安装器身份检查再交 Owner。
