# D02-B1 真实会话任务观测与只读概览

基线connect&talk/6094d89（PR143全CI通过后合入）。D02-A已有严格wire codec；本批补任务事实生产接线，不把一个全局LED状态冒充四个任务。

## 事实与数据边界

- Claude/Codex/Kimi只接真实session_id；Cursor优先conversation_id，也接受明确session_id。元数据解析仅限64KiB输入，超限保留原链路。非字符串/空白/控制字符/超256字节拒绝，不用cwd、命令、短诊断ID或IDE名称造身份。按客户端+完整会话做SHA256，内存与概览只用完整hash；原标识仅随当次本机socket请求，不落新文件。源事件、cmd/value/reset等保持原语义，不附带tool/command/cwd内容。
- 通用Hook分发和四类专用permission路径都附可选metadata，无标识仍走原有链路，不影响批准。Claude SubagentStop不作为父会话完成；当前按会话汇总，不声称单独追踪每个子代理。SessionStart/idle不制造运行任务；SINGLE值0/1对应waiting，2/3/7对应running，5/6将已存在任务置done，8移除；PreCompact为running。未知/无身份事件不进入新事实模型。
- Agent仅在持有BLE锁且命令通道、真实状态就绪时接纳事实；离线不排队或重放。单连接内4个稳定槽，同会话更新原槽，空槽优先，否则可替换最旧done，绝不挤走活跃槽。满容量时计未纳入的事件数，不伪装成唯一任务数。保留警示直到该连接事实清空。
- 300秒没有新Hook事实时过期，状态轮询/只读概览/LED延迟归位不能续命或把工具完成当会话完成。单调时间注入；断连、停止进程/所有权交接清空。前台事实尚无可靠来源，所有foreground为false，不以最近一条Hook猜前台。

## 真实接线与界面

既有state/state_with_reset/permission请求附task后，Agent观察再执行原有LED与审批分发。新增presentation_tasks socket命令只返回connected、4槽内client/hash/state和未纳入事件数，不发GATT、不写配置、不改审批。不包含任何键位或语音数据。

显示与灯光页新增只读任务概览，用户点击读取；清晰标为读取时快照，不宣称MULTI已开启或实时刷新。只能在后台日常连接读取；归属、连接或运行状态改变清除旧界面。异步结果校验所有权/发布代次，停止后旧结果不能恢复。旧Agent不认识命令时提示未获得信息，不伪装成0任务成功。

GUI socket读共用有界newline消息读取，支持分片和大于原256字节的概览，8192上限/2秒socket超时、过长路径拒绝、SO_NOSIGPIPE；不在主线程阻塞。既有连接心跳仍单worker/去重，read-only任务概览不引入新的周期轮询。

## 本批完成标准与未做

测试真实metadata/隔离Codex handler接线、四槽生命周期/容量/TTL/清空、隐私与报告格式，以及临时Unix socket的分片/大消息/未结束/超限输入；全测试及签名构建后做真实安装UI和已安装Hook→Agent概览验证。使用合成会话标识时必须标注，不能当所有真实CLI版本已验收。

不更改0x98/99生产写门控，不选择SINGLE/MULTI模式、不写Voice/按键、不上传素材或刷固件。D02仍缺显式模式设置、当前连接能力证据、串行发送与代次处理、任务来源/前台适配和实际OLED/灯效验收；Quiet/Sleep与App直连任务路径也仍需接线。协议/任务观测通过不等于多任务显示已完成。

验证：新增7项任务事实、2项真实临时socket、1项实际Codex handler隔离接线回归通过；全287项Swift测试通过。任务概览真机/已安装Hook接线将在候选构建后单独记录。
