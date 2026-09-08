# CH582 真实烧录测试清单

本清单用于 `windows-flash-rewrite` 的一次真实闭环验证。代码和自动测试通过后才执行；本清单本身不会运行 WCHISP，也不会自动触发烧录。

## 测试前检查

1. 确认分支和 JAR：

   ```powershell
   git branch --show-current
   git rev-parse HEAD
   Test-Path .\target\ahakey-studio-1.5.3.jar
   ```

2. 确认显式 WCHISP runtime 目录包含 `WCHISPTool_CH57x-59x.exe`、`CH343PT.DLL`、`WCH55xISPDLL.dll` 和 `CONFIG_CH57X59X.WCH`。正式 packaged runtime 仍必须满足 metadata/release contract。

3. 当前 Windows PnP 探测只能确认 `VID_4348&PID_55E0`，不能从现有接口证明 CH582 型号。因此开发期真实测试必须显式加入：

   ```text
   -Dahakey.dev.allow-isp-flash-with-unknown-chip=true
   ```

   该开关只在非-jpackage 开发运行中生效；正式安装包即使设置也 fail closed。诊断日志必须记录 `CHIP_MATCH_STATUS=UNKNOWN` 和 `CHIP_GATE_ALLOWED=YES`。

4. 选择真实、已审计的 CH582 Intel HEX；确认目标版本、当前版本/降级确认和 provenance 校验条件满足。

5. operation 日志位置：

   ```text
   %USERPROFILE%\.ahakey\logs\firmware-update\
   ```

   每次 operation 还会创建独立临时 workspace 和诊断目录；保留 `operation.json`、`command.txt`、`uid-*`、`flash-*`、`result.json`、`timing.json`、`runtime.json`、`chip-match.txt` 和 `uid-warning.txt`（如有）。

6. 回滚方式：在没有未保存工作区改动的前提下切回本次变更前的 commit/分支；不要使用 `reset --hard` 覆盖用户改动。固件回滚必须使用已经验证过的真实 HEX，并另行确认设备版本和数据保留策略。

## 测试启动

开发 JAR 可用等价命令启动（路径按本机调整）：

```powershell
& "$env:JAVA_HOME\bin\java.exe" `
  "-Dahakey.wchisp.path=C:\app\WCHISPTool\WCHISPTool_CH57x-59x" `
  "-Dahakey.dev.allow-isp-flash-with-unknown-chip=true" `
  -jar ".\target\ahakey-studio-1.5.3.jar"
```

不要启动旧安装版 Studio；确认窗口来自当前 JAR。保留本次测试拥有的 Studio 进程 PID，不使用全局 `taskkill`。

## 测试步骤

1. 启动 Studio，进入“固件管理（CH582）”。
2. 选择已确认的 bundled/latest/local HEX。
3. 点击“检测烧录环境和 ISP”，确认报告至少包含：
   - `RUNTIME_READY=YES`
   - `ISP_PRESENT=YES`
   - `CHIP_MATCH_STATUS=UNKNOWN`
   - `CHIP_GATE_ALLOWED=YES`（仅开发开关开启时）
   - `UID_CONFIRMED=YES/NO` 均可；UID 为可选诊断信息。
4. 关闭键盘；按住最左侧语音键并插入 USB，等待 UI 进入 `WAITING_ISP` 后检测到 `VID_4348&PID_55E0`。
5. 点击“开始烧录”。本轮只允许 Studio 正式生产路径执行 flash；不要手工运行 WCHISP，不要点击独立下载/校验按钮。
6. 记录以下证据：
   - operation id 和完整诊断目录；
   - `flash-command.txt`（确认仍为 `-c <config> -o download -f <hex>`）；
   - WCHISP PID、owned process IDs、elevation/termination reason；
   - flash exit code 和 `Finished/Code 0/Message Succeed` 证据；
   - `WAITING_RECONNECT` 到正常设备连接的时间；
   - `VERIFYING` 中读取的 Firmware version、Protocol 3.2、model 1、capabilities `0x000007FF`；
   - 最终 `SUCCESS` 或明确失败状态。

## 安全停止条件

发现 runtime、config、HEX、PID 归属或命令参数异常时立即取消 operation，保留诊断，不尝试修改代码或重复烧录。任何没有 `Finished/Code 0/Message Succeed` 和 post-verify 的结果都不能记录为成功。

## 当前验证边界

自动测试验证 UID 空/失败不再阻止 flash、runtime 失败阻止、chip mismatch 阻止以及 flash 命令未改变；真实 USB ISP、WCHISP、重连和 post verify 仍需人工硬件执行。
