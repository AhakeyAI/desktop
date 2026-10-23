# BRIDGE-01 第一轮退修报告

日期：2026-10-18  
状态：退修项已实现并完成离线检查，返回 Windows DLA 复审；不是 DLA PASS、设备验证或 Owner UAT。

## 范围与保护

- 已先读取桥接实现边界 `BRIDGE-01_IMPLEMENTATION_BOUNDARY_20261018.md`、原始协作说明 BRIDGE-01 及 Windows DLA 第一轮结论 `BRIDGE_01_DLA_REVIEW_20261018.md`。
- 第一轮边界记录和 DLA 原审阅文件均保留，未修改。修改仅在桥接源 `TcpServer.cs`、`Program.cs`、`Form1.cs`，以及本次新增的离线测试和报告/证据文件。
- 未改 `.csproj`、目标框架、NuGet 依赖、TCP 消息格式、Windows Studio 或固件代码；未连接设备、启动桥接程序、停止进程、安装或写现场包/config_server；未进行 Git 写操作。
- 现场包 EXE `C:\Users\20825\Desktop\windows软件代码\desktop\BLE_tcp_driver_package\BLE_tcp_driver.exe` SHA-256 仍为 `9B8F8C9D18AE7EE93B71ED7C867E1CE1E60040EBC6832498F5F2D00DCBD6106E`，与桥接 `bin\Release` 产物相同。本轮只构建到系统临时目录，没有覆盖现场包。

## 退修项

- **B-F1**：`TcpServer.cs` 引入 `System.Threading`，使 `Interlocked` 使用有明确命名空间。
- **B-F2**：MTU 分片长度由实际协商 PDU 长度减 ATT 开销 3 字节计算，并取固件特征上限 200 字节的较小值；不可用或不大于 ATT 开销时保守回退 20 字节。增加 MTU/载荷边界测试。
- **B-F3**：连接代次和发现轮次作为原始身份一路附着在服务/特征发现及通知事件上。发现计数与完成状态归属独立轮次；Form1 在消费事件和执行不完整发现清理前再次原子核验身份。通知订阅闭包保留所属连接/发现身份，迟到通知不能作为新连接事务的响应。
- **受控发送队列**：保留有界 FIFO 和单写事务次序；连接代次变化或客户端离开时取消/移除尚未执行的请求。每片 GATT 写等待实际结果；失败或取消立即停止当前事务余片，不自动重传、不合成固件 ACK。仍使用 WriteWithResponse。
- **连接恢复**：旧 GATT 操作通过取消令牌关联到所属请求/代次；队列测试覆盖旧请求迟到完成不污染新代次的隔离行为。实际 WinRT 设备取消时延未作硬件验证，见未执行项。

## 实际差异摘要

- `TcpServer.cs`：修复命名空间；引入有界 FIFO 写队列、请求/代次隔离、取消与客户端离开处理；增加 TCP 收包、排队等待、GATT 分片和 TCP 回写阶段日志；不增加 TCP 结果消息。
- `Program.cs`：采用 MTU 与 200 字节特征上限的分片策略；为连接、发现轮次、通知和发现事件传递原始身份；处理迟到发现/通知及逐片 GATT 结果。
- `Form1.cs`：事件消费时校验事件自带的连接代次/发现轮次；清理未完成发现前进行身份原子核验。
- 项目文件 SHA-256 与第一轮边界记录相同：`5A463247A0DA8C70D0D67154059D55E4457B15AA0596CF0F4A03E60D9EDB110A`；未扩大到项目/依赖/目标框架范围。

## 源码身份

- `TcpServer.cs`: `CD4978E768A8B3028F9CE1B93A3079F0BD574330444557CE0D4B67E4D4013745`
- `Program.cs`: `E235BDA01FA4C2C6AE35869D6D5FBB68C02923085146EEF0151B3BAEBA0D50D0`
- `Form1.cs`: `86A6FD0E6AA940209BDA074CCADD804E6B95840937E93CB273AB90A94C3F4DFC`

完整构建/测试命令、环境、退出码和实际输出见 `BRIDGE-01_REPAIR_EVIDENCE_20261018.md`。

## 未执行项与 Windows 配合

- 未在真实 BLE 适配器/键盘上验证 WinRT GATT 操作取消、重连恢复、通知订阅退订和实际 MTU；离线测试不等同于设备时序验证。
- 未执行真实 TCP socket 多客户端压力/并发测试、吞吐基线/分段计时采集、现场应用启动、安装、EXE 替换、Windows Harness 准入或 Owner UAT。缺少这些测试不表示已发生故障。
- 本轮没有添加 TCP 传输失败回执。当前协议不能向调用方表达传输失败；若 Windows 侧要求即时传输结果，须由 Windows DLA 协调版本协商、结果字段及部分写入后结果未知语义，再另行授权。
- 请 Windows DLA 对本轮实际三文件差异和附带测试/构建证据作独立复审，并继续登记外部桥接快照归属。此报告不申请/宣称桥接准入、生产替换或 WD-005 整体通过。
