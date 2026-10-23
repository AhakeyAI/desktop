# BRIDGE-01 退修检查证据

日期：2026-10-18。此文件记录本轮真实执行结果。所有构建均为离线构建；没有执行生成的 EXE。

## 环境与 Contracts 引用排查

- 操作系统 API：`Microsoft Windows NT 10.0.26100.0`
- PowerShell：`7.6.5`
- .NET SDK：`9.0.310`
- MSBuild：`C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe`，版本输出 `17.14.40+3e7442088`
- 项目仍为 `.NET Framework 4.7.2`。`Microsoft.Windows.SDK.Contracts` `10.0.26100.7705` 已还原在 NuGet 全局包缓存；`ref\netstandard2.0` 下存在 Windows SDK Contracts `.winmd` 与 `Windows.WinMD`。原经典项目调用未自动解析该已还原合同集，因此本轮使用桥接 `obj\BRIDGE-01_OfflineBuild.targets` 临时提供这些既有本地引用；不改 `.csproj`、包版本或目标框架。
- 曾尝试直接写桥接 `obj` 后遇到沙箱拒绝访问（MSB3021/MSB3191，退出码 1）；这属于输出路径权限问题，不是源码诊断。改为系统临时目录后成功。该失败不作为源码缺陷或成功构建证据。

## 离线编译

工作目录：`C:\Users\20825\Desktop\windows软件代码\desktop\BLE_tcp_bridge`

完整命令：

```powershell
$base=Join-Path $env:TEMP 'BRIDGE-01-OfflineCheck'
New-Item -ItemType Directory -Force -Path $base | Out-Null
'TEMP: '+$base
'OS: '+[System.Environment]::OSVersion.VersionString
'PS: '+$PSVersionTable.PSVersion.ToString()
'DOTNET: '+(dotnet --version)
& 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe' .\BLE_tcp_driver.csproj /t:Build /p:Configuration=Release /p:OutputPath="$base\bin\" /p:IntermediateOutputPath="$base\obj\" /p:BuildProjectReferences=false /p:CustomAfterMicrosoftCommonTargets='C:\Users\20825\Desktop\windows软件代码\desktop\BLE_tcp_bridge\obj\BRIDGE-01_OfflineBuild.targets' /p:GenerateResourceMSBuildArchitecture=CurrentArchitecture /v:minimal
```

退出码：`0`

实际输出：

```text
适用于 .NET Framework MSBuild 版本 17.14.40+3e7442088
  BLE_tcp_driver -> C:\Users\20825\AppData\Local\Temp\BRIDGE-01-OfflineCheck\bin\BLE_tcp_driver.exe
```

临时输出 EXE SHA-256：`02227AACF2A9530B40E9A9ABC08F5014655EDB550E51E7C21AB739720A135DE8`。该输出仅作编译证据，未启动。

## 受控离线时序测试

工作目录同上。

命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BRIDGE-01_OFFLINE_TIMING_TESTS.ps1
```

退出码：`0`

实际输出：

```text
PASS MTU 23/62/203/247/517; 20/59/200/201/401-byte fragment boundaries
PASS delayed old GATT cancellation, new-generation recovery, late completion isolation
PASS bounded queue rejects overflow and drains in FIFO order
PASS partial GATT failure stops remaining fragments without retry
PASS client departure cancels active wait and removes its queued writes
PASS stale notification/late-ACK identity rejected by generation and discovery round
PASS 9 production source guards
```

这些测试将生产纯逻辑 helper 源码提取后在内存编译，并检查 WinRT 回调接线的静态约束。测试覆盖受控假任务/队列和身份谓词，不是 BLE/WinRT 硬件回调模拟；“迟到 ACK”在此指迟到通知/响应身份隔离，不代表固件 ACK 已收到。

## 格式、差异与文件身份

- `git diff --check -- Form1.cs Program.cs TcpServer.cs`：退出码 `0`，无输出。
- 三文件差异相对共享父 Git 根的统计：`Form1.cs` 26 行变更；`Program.cs` 654 行变更；`TcpServer.cs` 407 行变更（合计 946 insertions / 141 deletions）。桥接目录不是单独 Git 根；共享父工作区有大量既存变化，本轮未对其执行 Git 写操作。
- 现场包和 `bin\Release` EXE：SHA-256 均为 `9B8F8C9D18AE7EE93B71ED7C867E1CE1E60040EBC6832498F5F2D00DCBD6106E`。
- `obj\Release` 和本轮临时构建 EXE：SHA-256 均为 `3FA372FDFE6789E8354FC013EE4063252D4EC88EC11B7883CF9EBBB7249C7A31` 与 `02227AACF2A9530B40E9A9ABC08F5014655EDB550E51E7C21AB739720A135DE8` 分别对应各自产物；现场包未被修改。
- `BLE_tcp_driver.csproj`：`5A463247A0DA8C70D0D67154059D55E4457B15AA0596CF0F4A03E60D9EDB110A`，与第一轮记录一致。
- 最终源码 SHA-256：`TcpServer.cs` `CD4978E768A8B3028F9CE1B93A3079F0BD574330444557CE0D4B67E4D4013745`；`Program.cs` `E235BDA01FA4C2C6AE35869D6D5FBB68C02923085146EEF0151B3BAEBA0D50D0`；`Form1.cs` `86A6FD0E6AA940209BDA074CCADD804E6B95840937E93CB273AB90A94C3F4DFC`。

## 明确未执行

未连接设备或 BLE；未停止进程；未启动临时/现场 EXE；未安装/替换现场驱动；未读取或写入 `config_server.json`；未运行 Windows Harness、Owner UAT、安装包构建或真实 TCP/BLE 压测；未做固件 ACK 伪造或重试；未提交、暂存或以其他方式写入 Git。上述未执行项是验证范围限制，不作为已经发生故障的判断。
