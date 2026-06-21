# 打包指南

## 环境准备

```bash
# 安装 PyInstaller
pip install pyinstaller

# 确保所有依赖已安装
pip install -r requirements.txt
```

## 打包方法

### 方法 1：使用 spec 文件（推荐）

```bash
pyinstaller KeyboardConfig.spec
```

### 方法 2：直接命令行打包

```bash
# 单文件模式（exe 更大，启动稍慢，但便于分发）
pyinstaller --name="KeyboardConfig" --onefile --windowed main.py

# 文件夹模式（启动快，体积小，但需要分发整个文件夹）
pyinstaller --name="KeyboardConfig" --onedir --windowed main.py
```

## 参数说明

- `--onefile`: 单个 exe 文件（推荐用于分发）
- `--onedir`: 生成文件夹（包含 exe + 依赖库）
- `--windowed`: 不显示控制台窗口（GUI 必须）
- `--icon=app.ico`: 设置应用图标
- `--name`: 最终 exe 的名称

## 输出位置

- `dist/KeyboardConfig.exe` — 单文件模式
- `dist/KeyboardConfig/` — 文件夹模式

## 优化选项

### 1. 减小体积

在 spec 文件中排除不需要的库：

```python
excludes=[
    'matplotlib',
    'numpy',
    'pandas',
    'cv2',
    'tkinter',  # 如果不需要 Tkinter
]
```

### 2. 使用 UPX 压缩

下载 UPX：https://github.com/upx/upx/releases

解压后将 `upx.exe` 放到系统 PATH 或 PyInstaller 目录。

在 spec 文件中设置 `upx=True`（已默认开启）。

### 3. 清理缓存重新打包

```bash
# 删除旧的构建文件
rmdir /s /q build dist
del KeyboardConfig.spec

# 重新打包
pyinstaller --name="KeyboardConfig" --onefile --windowed main.py
```

## 常见问题

### Q: exe 运行时报错找不到模块？
A: 在 spec 文件的 `hiddenimports` 中添加缺失的模块。

### Q: exe 体积太大（100MB+）？
A:
- 使用 `--onedir` 模式
- 在 spec 文件中排除不需要的库
- 使用 UPX 压缩

### Q: 打包后无法连接设备？
A: 确保防火墙允许该程序访问网络。

### Q: 需要添加配置文件或图片资源？
A: 在 spec 文件的 `datas` 列表中添加：

```python
datas=[
    ('configs/*.json', 'configs'),
    ('images/*.png', 'images'),
],
```

## 分发

将 `dist/KeyboardConfig.exe` 直接发给用户，无需安装 Python 环境即可运行。
