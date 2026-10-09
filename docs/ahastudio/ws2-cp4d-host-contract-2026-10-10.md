# WS2 CP4D 上位机协议契约摘录

来源：`AhakeyAI/AhaKey-X1-hardware-source` 的 `Fireware-harness` 提交 `d1b46a14a796790f2ffe0d228e6c5badcfc34d75`，以及其 `.ahakey-harness/workstreams/X1-INPUT-CONTROL/PRD.md`、`APP/sub_main/command_solve.c`。已接受测试构建为 `8167ba13049c781da2f975bc803eccfe0e6ea2aa`，HEX SHA256 `6F9759EB912EC067564C4E63558589AB9732126344D52C2D2A278383119516BE`。同一 catalog key 不保证同一构建；真机记录仍需提交号和 HEX 哈希。

帧头 `AA BB`、帧尾 `CC DD`。通用 ACK/错误帧为 `AA BB cmd status CC DD`；不能对含二进制载荷的命令简单扫描首个 `CC DD`。当前固件的 `0x00` 状态响应固定 13 字节；旧固件可有不同长度，须走旧版兼容解析。

| 命令 | 请求与成功响应 | 长度和处理约束 |
| --- | --- | --- |
| `0x00` | 查询 `AA BB 00 CC DD`；响应含电量、信号、主/次版本、模式、灯光、拨杆、亮度 | 当前 CP4D 总长 13；可作为旧设备回退事实，不含 catalog key |
| `0x9F` | 查询 `AA BB 9F CC DD`；成功 `AA BB 9F 00 <ASCII catalog key> CC DD` | ASCII 无 NUL 或长度字节；未知 key 只能安全探测，不因 key 相同就假定具体 HEX |
| `0x87` | 查询 `AA BB 87 mode key CC DD`；成功 `AA BB 87 00 mode key action_type action_len action desc_len desc CC DD` | 每次只读 1 个普通键，Power 不在范围；总长最多 64；`0x87 03` 表示过长，不截断或标成功；动作和描述可含帧尾字节 |
| `0x95` | 查询返回 `AA BB 95 00 lo hi CC DD`；设置返回通用 ACK | 仅 0/30/60/120 分钟；设置自持久化，不追加 `0x04` |
| `0x96` | 查询返回 `AA BB 96 00 state CC DD`；桌面 suppress 请求 `AA BB 96 03 CC DD` | 桌面只能写 suppress=3，不能写回 completed_mac=2；连接时不自动 suppress |
| `0x97` | 查询返回 `AA BB 97 00 sw_state 02 [bind_type action_len action]×2 CC DD`；设置返回通用 ACK | 根据两个 action_len 解帧；物理位置与绑定类型是不同事实；写后读回 |
| `0x92` | 设置当前模式后通用 ACK | 成功仍须用 `0x00` 读回目标模式；离线浏览不重放 |

当前共享解帧器先覆盖上述已知 CP4D 响应。未知命令不得猜测变长载荷边界；旧版命令保持原传输路径，待各命令格式和连接代次在 T02 中逐一接入。`0x98/0x99/0x9A` 所属 WS3 CP1 曾通过验收，但此分支当前固件头的 `project-state.yaml` 明确要求把 CP1 重新应用到 WS2 CP4D 基线，不能在此构建上开放 WS3 写入。
