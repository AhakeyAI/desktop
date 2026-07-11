# Repo Layout

## 顶层原则

- 顶层 `docs/` 只放仓库级共享文档。
- 代码按平台 / 组件拆分独立目录,不按工具混放。
- 安装包不进仓库,发布走 GitHub Releases;构建产物(`.app` / `.dmg` / `.exe` / `.class` / `.o`，以及 `*/target/` 等构建目录)不应入库。

## 顶层目录

- `ahakeyconfig-mac/` — macOS 客户端(Swift · SwiftUI),由根 `Package.swift` 构建
- `ahakeyconfig-win-java/` — Windows 客户端(Java · JavaFX · Maven)
- `ahakeyconfig-win-python/` — Windows 客户端(Python · PyInstaller,Capswriter 基线)
- `ahakeyconfig-ubuntu-java/` — Linux 客户端(Java · JavaFX · Maven)
- `CH582m_vibe_coding_BLE_keyboard-master/` — 键盘固件(C,CH582M)
- `BLE_tcp_bridge/` — BLE ↔ TCP 桥接(C#)
- `Package.swift` — macOS targets 的根 SwiftPM 清单
- `docs/` — 仓库级文档(架构、BLE 协议、安装、发布)
- `docs/versioning.md` — 界面开发版本管理（小白版：看哪个分支、怎么打版本）
- `assets/` — 共享品牌 / 构建资源

## macOS 子目录(`ahakeyconfig-mac/`)

- `Package.swift` — 平台工程清单(也被根清单引用)
- `Sources/` — Swift 源码(客户端 + `Agent/` 后台守护进程)
- `Resources/` — 运行所需资源
- `scripts/` — 构建 / 签名 / DMG 打包脚本

## Java 客户端子目录(`ahakeyconfig-win-java/`、`ahakeyconfig-ubuntu-java/`)

- `pom.xml` — Maven 工程
- `src/main/java/com/example/ahakey/` — Java 源码(入口 `Main` / `App`)
- `src/main/resources/` — JavaFX 资源(`.fxml` 等)

## Python 客户端(`ahakeyconfig-win-python/`)

- `main.py` — 入口
- `requirements.txt` — 依赖
- `*.spec` — PyInstaller 打包配置
- `hook/` — IDE hook 安装相关
