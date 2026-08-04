# AhaKey Studio - Rust 重写版本

Tauri 2 + Svelte 桌面应用,键盘/鼠标/灯条/OLED 配置工具。

## 在 VS Code 运行

### 方式 1:用 Tauri CLI 一键启动(推荐)

```powershell
# 1. 首次需要装 tauri-cli
cargo install tauri-cli --version "^2.0"

# 2. 启动(自动 build Rust + 启动 Vite + 弹窗)
cd D:\idea-yins\desktop\ahakeyconfig-win-rust\src-tauri
cargo tauri dev
```

### 方式 2:分开启动 UI + Rust(热重载更稳)

**终端 1(UI/Vite,带 HMR):**
```powershell
cd D:\idea-yins\desktop\ahakeyconfig-win-rust\ui
npm install
npm run dev
```

**终端 2(Rust 后端):**
```powershell
cd D:\idea-yins\desktop\ahakeyconfig-win-rust\src-tauri
cargo run
```

### 方式 3:VS Code 内置 Run

- 按 `Ctrl + Shift + B` → 选 "Cargo Build (debug)"(已配好,看 .vscode/tasks.json)
- 或终端直接 cargo run

## 编译产物位置

| 类型 | 路径 |
|------|------|
| Debug | `E:\RustData\cargo-target\debug\ahakey-studio.exe` |
| Release | `E:\RustData\cargo-target\release\ahakey-studio.exe` |

> 已配置 `.cargo/config.toml` 的 `target-dir`,所有编译产物在 E 盘,不污染 D/C 盘。

## 项目结构

```
ahakeyconfig-win-rust/
├── ui/                   Svelte 前端
│   ├── src/components/   TopBar / CanvasPane / InspectorPane / Modal / Toast / StatusBar
│   ├── src/App.svelte    根组件
│   └── src/main.ts       入口
├── src-tauri/            Rust 后端
│   ├── src/              命令 / 状态 / 设备 / Hook / 协议
│   ├── src/commands.rs   30 个 Tauri commands
│   └── tauri.conf.json   Tauri 配置
├── .cargo/config.toml    target-dir 指向 E 盘
└── scripts/              构建脚本
```

## 工具链

- Rust 1.88.0-x86_64-pc-windows-gnu(已装在 `E:\RustData\.rustup\`)
- Node.js 18+(npm)
- Tauri 2.x + Tauri CLI 2.x

## 常用命令

```powershell
# 开发
cargo tauri dev

# 构建 release
cd src-tauri; cargo build --release

# 清理(E 盘 debug 产物很大,经常 clean)
cargo clean

# 检查代码
cd ui; npm run check
```