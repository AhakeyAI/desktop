# macOS Client

本目录存放 AhaKey 官方 desktop baseline 的 macOS 客户端源码。

本次迁移来源于更新后的独立 macOS 客户端源码目录 `ahakeyconfig-mac-master`，迁入目标固定为 `platforms/macos/client/`。本轮只做结构迁移、必要忽略和文档整理，不改业务逻辑，不重构代码，也不调整现有 bundle id。

## 当前导入内容

- `Sources/`
  - Swift / SwiftUI 客户端主源码
  - 包含 BLE、界面、模型、工具类和 Agent 源码
- `Resources/DefaultOLED/`
  - 客户端依赖的默认 GIF 资源
- `Package.swift`
  - Swift Package 工程入口
- `Makefile`
  - 简单构建命令入口
- `scripts/`
  - 已导入的脚本：
    - `ahakey-state.sh`
    - `build-debug.sh`
    - `build.sh`
    - `ensure-dev-signing.sh`
    - `fix-debug-permissions.sh`
    - `generate_dmg_background.swift`
    - `generate_icons.swift`
    - `package_dmg.sh`
    - `release_dmg.sh`

## 本轮未导入内容

- `scripts/copy-to-new-location.sh`
  - 含本机硬编码路径，不适合作为官方 baseline 内容
- `scripts/package-test-dmg.sh`
  - 依赖未导入的本地迁移脚本，本轮不纳入
- `.git/`、`.idea/`、构建产物目录、缓存目录、安装包、证书和其他敏感文件

## 目录结构

```text
platforms/macos/client/
├── Package.swift
├── Makefile
├── README.md
├── Resources/
│   └── DefaultOLED/
├── scripts/
└── Sources/
```

## 构建入口

当前可判断的环境要求：

- macOS 15.0+
- Xcode 15+ 或等效 Swift toolchain
- Swift 5.9+
- Apple Silicon（arm64）

当前可判断的构建入口：

```bash
swift build -c release --arch arm64 --product AhaKeyConfig
bash scripts/build.sh
make build
```

当前可判断的打包入口：

```bash
bash scripts/package_dmg.sh
bash scripts/release_dmg.sh
```

`.dmg` 等安装包不进入仓库，只通过 GitHub Releases 分发。

## 当前状态

- macOS 客户端源码已进入 `platforms/macos/client/`
- 当前仍处于迁移后的早期整理阶段
- `lab.jawa.ahakeyconfig` 相关内容本轮保持现状，作为后续清理项处理

## 迁移备注

- 当前迁移输入中未包含独立的 `docs/ble-protocol.md`
- 当前迁移输入中未发现 `VibeCodeKeyboard.ico`
- 部分构建 / 打包脚本已按原样保留，后续再统一整理 macOS 发布流程
