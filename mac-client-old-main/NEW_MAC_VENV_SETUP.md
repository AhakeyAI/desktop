# 新电脑 `.venv` 与构建环境说明

更新时间：2026-04-11

本文档专门回答一个问题：

```text
把项目拿到一台新的 Mac 上后，`.venv` 要不要重新做？
```

短答案：

- 要。
- 更准确地说：**不要把旧电脑的 `.venv` 直接当成新电脑的正式环境使用。**
- 推荐做法是：把源码拷到新电脑后，**让 `build_macos.sh` 自动创建或重建 `.venv`**。

如果后续只想快速知道怎么做，直接看本文档第 4 节。

## 1. 结论先说

新电脑上建议这样处理：

- 复制源码仓库
- **不要依赖旧电脑拷过去的 `.venv`**
- 在新电脑上运行 `./build_macos.sh`
- 脚本会自动：
  - 选择可用 Python
  - 创建或复用根目录 `.venv`
  - 安装主程序依赖
  - 安装 `capswriter` 的 macOS 依赖

也就是说：

- 新电脑**需要有自己的 `.venv`**
- 但你**不需要手动先建好**
- 只要环境满足要求，`build_macos.sh` 会自己处理

## 2. 为什么不要直接搬旧电脑的 `.venv`

`.venv` 不是一个“跨机器通用的独立黑盒”，它和当前机器环境强相关。

主要原因有 5 个：

### 2.1 Python 解释器路径会变化

虚拟环境内部会记住创建它时使用的 Python 路径。

旧电脑和新电脑上，下面这些很可能不同：

- Python 安装路径
- Homebrew 路径
- 系统架构
- base interpreter 版本

所以把旧 `.venv` 原样拷过去，最常见的问题是：

- 能激活但实际不可用
- `pip` 和 `python` 指向不一致
- 某些依赖能 import，某些不能

### 2.2 本机架构和编译产物可能不同

这个项目里不是只有纯 Python 包，还包含：

- `PySide6`
- `numpy`
- `sounddevice` 相关依赖
- `PyObjC` 相关依赖

这些依赖可能包含：

- 平台相关二进制
- 架构相关 wheel

如果旧电脑和新电脑的架构、系统版本、解释器来源不同，直接搬 `.venv` 很容易留下隐患。

### 2.3 发布机要追求可重复

正式发布机最怕的是：

- “看起来能跑”
- 但不是稳定、可重复的状态

相比“省一次依赖安装时间”，更重要的是：

- 新电脑能稳定复现打包结果
- 后续 AI / 同事重新执行时结果一致

### 2.4 当前脚本本来就已经支持自动处理 `.venv`

`build_macos.sh` 里已经实现了：

- 自动选择支持的 Python
- 如果没有 `.venv` 就创建
- 如果 `.venv` 的 Python 版本不合要求，就重建

相关位置：

- [build_macos.sh](<repo-root>/build_macos.sh)
  - `ensure_venv()`
  - `Creating virtual environment with: ...`
  - `Recreating virtual environment with: ...`

所以最稳的方式不是手工迁移 `.venv`，而是让脚本按当前机器重新做。

### 2.5 正式签名/公证和 `.venv` 不是一回事

需要特别分清楚两类东西：

1. **应该重新在新电脑准备的**
   - `.venv`
   - Python 依赖
   - 本机构建缓存

2. **应该从旧电脑迁移过来的**
   - `Developer ID Application` 证书和私钥（`.p12`）
   - `notarytool` 的 keychain profile（或者在新机重新 store-credentials）

也就是说：

- 证书要迁
- 公证凭据要迁或重建
- `.venv` 不建议迁

## 3. 当前 `build_macos.sh` 已经会自动做什么

当前脚本已经内置以下逻辑：

### 3.1 自动选择 Python

脚本会按这个优先级找：

- `python3.13`
- `python3.12`
- `python3.11`
- `python3.10`
- `python3`

只接受：

- `3.10`
- `3.11`
- `3.12`
- `3.13`

不接受：

- `3.14`

### 3.2 自动创建 `.venv`

如果根目录下没有 `.venv`，脚本会自动创建。

### 3.3 自动重建不合规 `.venv`

如果已有 `.venv`，但里面的 Python 版本不在允许范围内，脚本会删掉并重建。

### 3.4 自动安装依赖

脚本会安装：

- `vibe_code_config_tool-master/requirements.txt`
- `vibe_code_config_tool-master/capswriter/requirements-mac.txt`

所以新电脑第一次跑构建时，时间会比老电脑长，这属于正常现象。

## 4. 新电脑最推荐的处理方式

下面这套是当前最稳的流程。

### 第 1 步：复制项目源码

把整个项目目录复制到新电脑，例如：

```text
<repo-root>
```

### 第 2 步：不要优先依赖旧 `.venv`

推荐做法：

- 如果项目里已经带着 `.venv` 复制过去了，也不要信任它是可发布状态
- 最稳方式是直接删掉新电脑里的旧 `.venv`

例如：

```bash
cd <repo-root>
rm -rf .venv
```

这一步不是绝对必须，但对于“正式发布机首次接手”我推荐这么做。

### 第 3 步：确认 Python 可用

先检查：

```bash
python3 --version
```

如果不是 `3.10` 到 `3.13`，建议安装一个支持版本。

### 第 4 步：直接运行打包脚本

```bash
cd <repo-root>
chmod +x build_macos.sh
./build_macos.sh
```

脚本会自动创建新 `.venv`，并安装依赖。

### 第 5 步：正式发布时再带签名参数

等确认新电脑本地打包链没问题后，再用正式命令：

```bash
cd <repo-root>

CODESIGN_IDENTITY="Developer ID Application: <Your Name> (<TEAM_ID>)" \
NOTARY_PROFILE="<notary-profile-name>" \
NOTARIZE_TARGET="dmg" \
./build_macos.sh
```

## 5. 哪些东西可以从旧电脑带过去

### 5.1 应该带过去的

- 项目源码
- `Developer ID Application` 证书和私钥（`.p12`）
- `notarytool` 凭据，或在新机重新配置
- 如果桥接器现成产物稳定，也可以保留：
  - `mac_bridge/dist/BLETcpBridge.app`

### 5.2 不建议直接照搬的

- `.venv`
- `vibe_code_config_tool-master/build`
- `vibe_code_config_tool-master/dist`
- `mac_bridge/build`
- `mac_bridge/bin`
- `mac_bridge/obj`
- `dist-macos`

这些目录要么是本机依赖环境，要么是构建缓存，要么是旧产物。

## 6. 如果新电脑第一次打包失败，先检查什么

优先检查下面几项：

### 6.1 Python 版本

确认 `python3 --version` 在允许范围内。

### 6.2 `.venv` 是否是新建的

如果你怀疑环境是从旧电脑拷来的，先删掉重来：

```bash
rm -rf .venv
./build_macos.sh
```

### 6.3 证书是否已导入

```bash
security find-identity -v -p codesigning
```

必须能看到：

```text
Developer ID Application: <Your Name> (<TEAM_ID>)
```

### 6.4 notarization profile 是否可用

```bash
xcrun notarytool history --keychain-profile <notary-profile-name>
```

### 6.5 蓝牙桥接器依赖是否齐全

如果要重建 bridge：

- `dotnet`
- `swiftc`

如果没有，但 `mac_bridge/dist/BLETcpBridge.app` 已存在，通常可以先复用。

## 7. 对后续 AI / 同事的明确规则

如果后续有新的 AI 或同事接手，请默认遵守这条规则：

```text
新电脑不要直接复用旧电脑的 .venv，优先让 build_macos.sh 在当前机器重建。
```

这条规则比“能不能勉强跑起来”更重要，因为它关系到：

- 打包结果是否可重复
- 构建依赖是否匹配当前机器
- 签名/公证前的环境是否稳定

## 8. 最短执行版本

如果你只想记最短步骤，就记下面这段：

```bash
cd <repo-root>
rm -rf .venv
./build_macos.sh
```

正式发布再用：

```bash
cd <repo-root>

CODESIGN_IDENTITY="Developer ID Application: <Your Name> (<TEAM_ID>)" \
NOTARY_PROFILE="<notary-profile-name>" \
NOTARIZE_TARGET="dmg" \
./build_macos.sh
```

这就是当前新电脑接手时最稳的做法。
