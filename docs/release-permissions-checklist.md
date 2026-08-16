# 1.2.0 发布权限清单

本地代码、安装包、固件和 CI 私有输入已经准备完成。正式发布只需要配置以下权限并完成真机验收。

## 本地已生成

| 文件 | SHA-256 |
| --- | --- |
| `AhaKeyStudio-1.2.0-windows-x64.exe` | `9056b946cb8197687f248f64ded819decd011300775ce630128c50de7028bf80` |
| `AhaKey-X1-firmware-1.1.1-ch582.hex` | `10ff6af2e7b6915751794ca45d8dc8d8873a1c350d9c551436e6098876ff9a50` |
| `AhaKeyStudio-voice-baseline.zip` | `3202419edf0b137b73e39d5a97465385708e3100e6e49134c9809827783105df` |
| `WCHISPTool-CH57x-59x.zip` | `e3949c1ee4c8c434ae2374c3d3b0ecf06a58ad2fd7eade20a83d2bec422eff36` |

私有 ZIP 位于 `ahakeyconfig-win-java/release-private/`，已被 `.gitignore` 排除。

## 现有 CloudBase 对象存储

不创建新的 COS 存储桶。发布流程直接复用 `ahakey-web` 所在 CloudBase
环境的现有对象存储，并使用以下目录：

- `release-inputs/*`：构建依赖，仅发布账号可读写。
- `releases/v版本号/*`：安装包、固件及校验文件。
- `releases/stable.json`：客户端和网站共同读取的稳定版清单。

`releases/*` 需要一个不会过期的 HTTPS 公网访问基址。现有 CloudBase
存储域名、访问权限和自定义域名均在线上配置时单独确认。

发布子账号只授予当前 CloudBase 环境中上述目录所需的读取和上传权限，
不授予删除环境或删除整个存储空间的权限。

第一次配置凭据后，在本机设置下列环境变量：

- `TENCENTCLOUD_SECRET_ID`
- `TENCENTCLOUD_SECRET_KEY`
- `WECHAT_CLOUD_ENV_ID`

然后运行：

```powershell
cd ahakeyconfig-win-java
.\upload-release-dependencies.ps1 `
  -FirmwareHex "C:\path\to\AhaKey-X1-firmware-1.1.1-ch582.hex"
```

## desktop 仓库 GitHub Secrets

- `TENCENTCLOUD_SECRET_ID`
- `TENCENTCLOUD_SECRET_KEY`
- `WECHAT_CLOUD_ENV_ID`
- `CLOUDBASE_STORAGE_PUBLIC_BASE_URL`
- `WINDOWS_SIGNING_PFX_BASE64`（代码签名 PFX 的 Base64 内容）
- `WINDOWS_SIGNING_PFX_PASSWORD`
- `WINDOWS_SIGNING_TIMESTAMP_URL`（可选，默认使用 DigiCert 时间戳服务）
- `WINDOWS_RELEASE_BASELINE_SHA256` =
  `3202419edf0b137b73e39d5a97465385708e3100e6e49134c9809827783105df`
- `WCHISP_BUNDLE_SHA256` =
  `e3949c1ee4c8c434ae2374c3d3b0ecf06a58ad2fd7eade20a83d2bec422eff36`
- `FIRMWARE_1_1_1_SHA256` =
  `10ff6af2e7b6915751794ca45d8dc8d8873a1c350d9c551436e6098876ff9a50`

建议把这些 Secret 放在受保护的 GitHub `production` Environment 中。

## ahakey-web 仓库 GitHub Secrets

- `TENCENTCLOUD_SECRET_ID`
- `TENCENTCLOUD_SECRET_KEY`
- `WECHAT_CLOUD_ENV_ID`
- `WECHAT_CLOUD_SERVICE_NAME`（当前应为 `ahakey-web`）

微信云托管生产环境另外设置：

- `STABLE_MANIFEST_URL=https://你的下载域名/releases/stable.json`
- `STABLE_MANIFEST_CACHE_SECONDS=60`

## 仍需人工确认

1. 沁恒 WCHISP 命令行组件的商业安装包再分发许可。
2. Windows 安装包代码签名证书；当前本地安装包未签名，只适合内部验收。正式
   Release 工作流已包含签名和签名校验步骤。
3. CH582 真机烧录、USB/BLE、语音识别和恢复初始化验收。
4. 合并两个本地分支后创建并推送 `v1.2.0` 标签。
