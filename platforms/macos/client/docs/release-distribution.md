# AhaKey Studio Release Distribution

更新时间：2026-04-16

## 1. 目标

本文件定义 `AhaKey Studio` 的正式对外分发流程，目标产物为：

- 已签名的 `AhaKey Studio.app`
- 已签名、已 notarize、已 staple 的 `AhaKey-Studio-macOS-prod-YYYYMMDDHHmmss.dmg`（默认带时间戳；可用 `DMG_BASENAME` 覆盖）

适用场景：

- 官网下载
- 包装盒二维码下载
- 发给购买硬件的终端用户

## 2. 当前仓库已支持的脚本

- 构建 `.app`：[scripts/build.sh](../scripts/build.sh)
- **构建可分发 `.dmg`（含公证）**：[scripts/release_dmg.sh](../scripts/release_dmg.sh) — 对内测试与对外发版可用同一套产物；内部调用 [scripts/package_dmg.sh](../scripts/package_dmg.sh)

## 3. 你需要先准备的东西

正式分发前，必须先在当前 Mac 上准备：

1. `Developer ID Application` 证书
2. Apple Developer Program 团队权限
3. `notarytool` 的 keychain profile

### 3.1 Developer ID 证书

Apple 官方要求：

- 代码、应用、磁盘镜像这类产物要用 `Developer ID Application` 证书签名
- `pkg` 才使用 `Developer ID Installer`

参考：

- https://developer.apple.com/documentation/security/resolving-common-notarization-issues
- https://developer.apple.com/developer-id/

### 3.2 Notary 凭据

建议先在本机存一个 `notarytool` profile，例如：

```bash
xcrun notarytool store-credentials "AhaKeyNotary" \
  --apple-id "<你的 Apple ID>" \
  --team-id "<你的 Team ID>" \
  --password "<app-specific-password>"
```

也可以用 App Store Connect API key 方案，但对当前首发准备来说，上面这条更直观。

参考：

- https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## 4. 正式出包命令

当证书和 `notarytool` profile 都准备好后，执行：

```bash
cd /path/to/ahakeyconfig
zsh scripts/release_dmg.sh
```

默认使用：

- `NOTARY_PROFILE=AhaKeyNotary`
- 自动寻找本机第一个 `Developer ID Application` 证书

如果你要手动指定：

```bash
SIGNING_IDENTITY="Developer ID Application: <Your Name> (<TEAMID>)" \
NOTARY_PROFILE="AhaKeyNotary" \
zsh scripts/release_dmg.sh
```

## 5. 脚本会做什么

正式脚本会顺序完成：

1. 用 release 配置构建 `AhaKeyConfig` 与 `ahakeyconfig-agent`
2. 组装 `AhaKey Studio.app`
3. 使用 `Developer ID Application` 签名 app 内主程序、helper、bundle
4. 创建 `AhaKey-Studio-macOS-prod-YYYYMMDDHHmmss.dmg`
5. 对 `dmg` 再做 Developer ID 签名
6. 用 `notarytool` 提交 `dmg`
7. 对 `dmg` 执行 `stapler staple`
8. 对最终产物做 `hdiutil verify`

## 6. 本地验收

正式出包完成后，至少检查：

```bash
codesign --verify --deep --strict --verbose=2 "dist/AhaKey Studio.app"
spctl --assess -vv "dist/AhaKey Studio.app"
# 将路径换成 dist/ 里本次生成的 .dmg（例如 AhaKey-Studio-macOS-prod-20260427143000.dmg）
spctl --assess -vv "dist/<本次的>.dmg"
hdiutil verify "dist/<本次的>.dmg"
```

再做一轮人工体验：

1. 双击挂载 `dmg`
2. 拖拽到 `Applications`
3. 启动 App
4. 连接键盘
5. 做一次真实同步测试

## 7. 当前状态说明

若本机已具备 `Developer ID Application` 与 `notarytool` profile，执行 `release_dmg.sh` 即可得到与终端用户一致的安装包；**测试场景也推荐直接安装该 DMG**，以便验证 Gatekeeper、公证与真实分发路径。

若仅有开发证书、不想走公证，可只做应用调试：

```bash
zsh scripts/build.sh
```

这样会得到 `dist/AhaKey Studio.app`（无 DMG、无公证，不适合外发）。
