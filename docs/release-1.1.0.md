# AhaKeyStudio 1.1.0 发布说明

> 历史候选方案，仅用于追溯。当前正式流程请使用
> `release-1.2.0.md`、`releases.md` 和 `release-permissions-checklist.md`。

## 发布资产命名

同一个稳定版 GitHub Release（标签 `v1.1.0`）上传：

- `AhaKeyStudio-1.1.0-windows-x64.exe`
- `AhaKey-X1-firmware-1.1.0-ch582.hex`

可选上传对应 `.sha256` 文件。没有 SHA-256 时客户端仅提示警告，不阻止安装或烧录。

## 客服配置

在仓库创建 `release-config` 分支，在分支根目录放置：

```json
{
  "supportUrl": "https://替换为最终客服链接"
}
```

该地址必须是绝对 HTTPS URL。客户端每天最多刷新一次并保留最后一份有效缓存；未配置时显示“客服入口配置中”。二维码由客户端本地生成。

## WCHISP 再分发

在获得沁恒明确的再分发许可前，不把 WCHISP 二进制提交到仓库或安装包。客户端依次查找：

1. JVM 参数 `-Dahakey.wchisp.path=...`
2. 安装目录 `tools/wchisp/WCHISPTool_CH57x-59x.exe`
3. `C:\app\WCHISPTool\WCHISPTool_CH57x-59x\WCHISPTool_CH57x-59x.exe`

缺失时会提示用户安装官方 WCHISPStudio。获得许可后，只需把命令行组件随安装包放到第 2 个路径。

## 安全构建原则

发布包必须以已安装的 1.0.0 发布 JAR 为基线，仅覆盖本次变更类。构建脚本会逐项校验：

- `VoiceInputManager`、`SpeechService`、`ModelConfig` 字节完全不变；
- `model_config.properties` 不变；
- 保留 `encoder.int8.onnx`、`decoder.int8.onnx`、`silero_vad.onnx` 和 `tokens.txt`；
- 不允许引入 `models/model_q8.onnx`；
- 所有实际变化必须命中覆盖白名单。

先执行：

```powershell
cd ahakeyconfig-win-java
.\preview-part3-release-overlay.ps1
```

看到 `OVERLAY_VALIDATION=OK` 后才可继续打包。

## 固件编译

固件工程位于迁移资料的：

`EVT\EXAM\BLE\HID_Keyboard_AhaKey`

使用 xPack RISC-V Embedded GCC 8.2.0 和仓库根目录的脚本执行 clean build。脚本会在隔离的构建目录中修正旧工程 makefile 内的原开发机绝对路径，并生成 HEX 和 SHA-256：

```powershell
.\build-firmware-1.1.0.ps1 `
  -ToolchainBin "C:\path\to\riscv-none-embed\bin"
```

输出文件：

`AhaKey-X1-firmware-1.1.0-ch582.hex`

普通固件更新配置必须保持 `IsClearDataFlash=0`，并在下载后执行 WCHISP `verify`。

## Windows 安装包

确认固件构建完成后，在 `ahakeyconfig-win-java` 中运行：

```powershell
.\build-release-installer.ps1 `
  -FirmwareHex "C:\path\to\AhaKey-X1-firmware-1.1.0-ch582.hex" `
  -WixBin "C:\path\to\WiX-3.x"
```

脚本会重新执行语音基线保护校验，并生成：

- `installer\AhaKeyStudio-1.1.0-windows-x64.exe`
- `installer\AhaKeyStudio-1.1.0-windows-x64.exe.sha256`

正式对外发布前，需要使用公司的 Windows 代码签名证书签署 EXE；未签名安装包仅用于内部测试。

## 发布前设备验收

连接 CH582 实机后完成以下测试，再发布稳定版 Release：

1. USB 和 BLE 分别读取、保存 5/10/15/30 分钟待机时间，并断电重连复核。
2. 恢复出厂设置，确认默认 GIF、用户/按键/待机配置及 BLE 绑定已清除，设备标识、MAC 和固件版本保留。
3. 使用内置稳定版、Release 最新版和本地 HEX 各执行一次下载及校验；同时覆盖重试、未知版本、降级保护路径。
4. 验证语音输入按钮可用并完成一次真实录音识别。
