# vibe_code_config_tool

## 模块简介

`vibe_code_config_tool` 是用户侧主桌面程序，负责连接键盘设备、编辑按键和动画配置、查看设备信息、处理用户账号与订阅操作，并可一键启动本地语音服务 `Capswriter`。

它同时连接三类对象：

- 云端服务 `wxcloudrun-flask`
- 本地 BLE-TCP 桥接器
- 本地语音服务 `Capswriter`

## 功能概览

- 键盘配置文件新建、打开、保存
- 设备连接与状态查询
- 自定义按键映射下发
- 动画帧上传与模式配置
- 用户登录 / 注册
- 配额查询
- 兑换码兑换
- 微信支付充值
- 启动 / 停止本地语音服务
- Typeless 开关与本地订阅状态同步

## 目录结构说明

```text
vibe_code_config_tool/
├─ main.py
├─ requirements.txt
├─ BUILD.md
├─ KeyboardConfig.spec
├─ src/
│  ├─ app.py
│  ├─ comm/
│  │  ├─ protocol.py
│  │  ├─ tcp_client.py
│  │  └─ device_service.py
│  ├─ core/
│  │  ├─ device_state.py
│  │  ├─ config_manager.py
│  │  ├─ keymap.py
│  │  ├─ cloud_api.py
│  │  ├─ cloud_settings.py
│  │  ├─ typeless_store.py
│  │  └─ ...
│  └─ ui/
│     ├─ main_window.py
│     ├─ pages/
│     └─ widgets/
├─ hook/
├─ ico/
└─ asr/
```

说明：

- `src/` 是主要源码目录
- `hook/` 是 Claude / Cursor hook 与 BLE 状态桥接辅助脚本
- `asr/` 目录结构上与 `Capswriter` 非常接近，当前更像打包副本或嵌入运行目录，需结合实际发布方式判断是否仍在使用

## 技术栈

- Python 3
- PySide6
- requests
- socket
- 自定义 TCP/BLE 协议
- Pillow / numpy
- qrcode

## 运行方式

```powershell
cd vibe_code_config_tool
pip install -r requirements.txt
python main.py
```

## 依赖安装方式

```powershell
pip install -r requirements.txt
```

主要依赖：

- `PySide6`
- `Pillow`
- `numpy`
- `requests`
- `pyqtdarktheme`
- `qrcode`

## 配置项说明

### 本地用户配置

通过 `QSettings` 保存，代码位于：

- `src/core/cloud_settings.py`

主要保存：

- 云端 API 地址
- access token
- 记住密码状态
- 保存的手机号与密码

### 键盘配置文件

通过 JSON 保存，代码位于：

- `src/core/config_manager.py`

数据模型定义位于：

- `src/core/keymap.py`

主要结构：

- 键盘名称
- 3 个模式
- 每个模式 4 个按键
- 每个模式的动画帧列表与 FPS

### Typeless 配置

本模块会通过 `typeless_store` 维护本地 Typeless 配置，并与用户页中的订阅状态联动。

## 核心文件说明

### `main.py`

程序入口，调用 `src.app.run()`。

### `src/app.py`

初始化 Qt 应用、主题和 Typeless 配置文件。

### `src/ui/main_window.py`

主窗口，负责：

- 菜单栏
- 模式页、设备页、用户页
- 启动 / 停止 `Capswriter`
- 配置文件新建、打开、保存
- 一键保存到设备

这是当前最核心、也最重的 UI 文件。

### `src/core/device_state.py`

整个 UI 与通信层之间的状态中枢，统一管理：

- TCP 客户端
- DeviceService
- 当前配置
- 当前模式
- 连接状态

### `src/comm/tcp_client.py`

负责通过 TCP 与 `BLE_tcp_bridge_for_vibe_code` 通信。

### `src/comm/device_service.py`

负责具体设备命令协议，包括：

- 发送普通命令
- 查询状态
- 查询信息
- 写入大块数据
- 更新按键
- 读取图片状态
- 更新动画参数

### `src/comm/protocol.py`

定义 TCP 包协议和设备帧协议，是配置工具和桥接器之间的协议基准。

### `src/ui/pages/mode_page.py`

模式配置页，负责：

- 编辑按键
- 管理动画帧
- 上传动画到设备

### `src/ui/pages/device_page.py`

设备信息页，负责：

- 展示 BLE 状态
- 展示设备信息
- 修改设备名
- 修改 BLE Appearance
- 查看通信日志

### `src/ui/pages/user_page.py`

用户信息页，负责：

- 登录 / 注册
- 显示配额
- 兑换码兑换
- 微信支付充值
- Typeless 本地状态同步

### `src/core/cloud_api.py`

封装云端接口调用：

- 登录 / 注册
- 用户信息
- 兑换码兑换
- 微信支付下单
- 订单状态轮询

## 与其他模块的关系

### 与 `wxcloudrun-flask`

通过 HTTP 交互，完成：

- 登录
- 查询用户信息
- 兑换码兑换
- 微信支付

### 与 `BLE_tcp_bridge_for_vibe_code`

通过 TCP 交互，发送设备命令和动画数据，再由桥接器转发到 BLE 键盘。

### 与 `Capswriter`

通过拉起 `start_server` / `start_client` 进程启动本地语音服务。

## 典型工作流

1. 启动配置工具
2. 连接 BLE-TCP 桥接器
3. 查询设备信息
4. 编辑按键和动画配置
5. 保存为本地 JSON 或下发到设备
6. 登录云端账号
7. 查看配额或使用兑换码 / 支付
8. 启动本地语音服务

## 当前架构特点

### 三端协同

该模块是全工程里最复杂的用户入口，需要同时协调：

- 设备控制
- 云端账号与订阅
- 本地语音服务

### 状态中心明确，但页面职责仍偏重

`device_state.py` 作为状态中枢是一个优点，但 `main_window.py`、`user_page.py`、`mode_page.py` 都已经开始承担较多业务逻辑。

## 开发建议

- 保持 `device_state -> UI` 的单向状态驱动思路
- 将云端接口封装进一步抽成共享模块，减少和 `vibe_admin` 的重复
- 把语音服务管理从主窗口中拆为独立 service
- 为设备上传流程增加更明确的任务状态管理

## 已知工程问题

### 1. 主窗口职责过重

`src/ui/main_window.py` 同时管理菜单、设备连接、页面切换、语音进程控制、配置保存和整机上传。

### 2. 云端 API 封装重复

`src/core/cloud_api.py` 与 `vibe_admin` 的同类文件重复度高。

### 3. 配置模型版本不一致

`ConfigManager.SCHEMA_VERSION = 1`，但 `KeyboardConfig.to_dict()` 写出的是 `version = 2`。  
这会导致版本判断语义不清晰，后续扩展时容易出问题。

### 4. 动画临时文件管理不完整

`mode_page.py` 中导入 GIF 后会写入临时目录，但当前没有统一清理机制。

### 5. 语音目录搜索逻辑分散在 UI 层

`Capswriter` 的查找、启动、停止逻辑直接写在主窗口里，后续维护成本较高。

## 后续安全分析建议关注点

- 本地保存 token 与密码的方式
- 微信支付订单轮询与本地状态同步
- 设备写入协议的输入校验
- 启动外部进程时的路径与参数控制
