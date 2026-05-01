# BLE / Bridge / Hook Troubleshooting

这份文档用于排查 Windows 侧 BLE、TCP bridge、以及 Claude / Cursor hooks 相关的问题。

目标不是覆盖所有实现细节，而是给出一个稳定的排查顺序，帮助你先判断问题落在哪一层。

## 相关组件分别负责什么

- `platforms/windows/desktop-main/`
  - 用户侧主桌面程序
  - 通过 TCP 与本地 bridge 通信，再由 bridge 转发到 BLE 设备
- `platforms/windows/ble-bridge/`
  - BLE 与 TCP 之间的桥接程序
  - 负责把桌面程序或 hooks 发出的 TCP 命令转发给设备
- `platforms/windows/hook-installer/`
  - Claude / Cursor hooks 的安装、卸载和事件分发入口
  - 事件触发后会通过本地 TCP bridge 发送状态更新

## 预期连接链路

Windows 侧这条链路按顺序应该是：

1. bridge 进程先启动，并监听本地 TCP 端口
2. `desktop-main` 通过 TCP 连到 bridge
3. bridge 再通过 BLE 连到目标设备
4. hooks 触发时，通过 `hook-installer` 调用本地 TCP bridge
5. bridge 把状态更新转发给设备

如果其中任一层不通，后面的表现都会异常。

## 什么算“工作正常”

如果链路正常，通常应能看到这些结果：

- 桌面程序可以查询到设备状态和设备信息
- bridge 可以返回“已连接”状态，而不是空结果或超时
- hooks 触发后，bridge 能收到 TCP 包
- 目标设备能响应状态查询，而不是始终显示未连接

## 建议的排查顺序

### 1. 先确认 bridge 是否在运行

优先确认本地 bridge 进程本身是否可用。

当前仓库中，bridge 相关源码位于：

- `platforms/windows/ble-bridge/BLE_tcp_bridge_for_vibe_code/`

桌面程序和 hooks 都依赖它；如果它没启动，后面两个组件都会一起失败。

先看：

- bridge 是否已经启动
- 监听端口是否和客户端配置一致
- bridge 进程是否一启动就报错退出

### 2. 再确认桌面程序是否能连到 bridge

桌面程序的 TCP 通信逻辑在：

- `platforms/windows/desktop-main/vibe_code_config_tool/src/comm/tcp_client.py`
- `platforms/windows/desktop-main/vibe_code_config_tool/src/comm/device_service.py`

如果桌面程序无法查询设备状态，优先怀疑的是：

- bridge 没启动
- bridge 监听地址或端口不对
- 本地 TCP 连接失败

这一步先不要把问题归因到 BLE 设备本身。先证明桌面程序确实已经连到本地 bridge。

### 3. 如果 TCP 通了，再看 bridge 是否连到了目标设备

即使桌面程序已连到 bridge，也不代表 bridge 已连上目标 BLE 设备。

当前 hooks 侧的状态查询逻辑里，会读取 bridge 返回的：

- `connected`
- `name`
- `mac`
- `is_target`

如果这里返回的不是目标设备，或者 `connected` / `is_target` 为假，说明：

- bridge 在跑，但没有连到正确的 BLE 设备
- 或者 bridge 连接到了设备，但不是预期目标

这时重点看 BLE 配对、设备上电状态、以及 bridge 识别到的设备名称 / MAC 是否符合预期。

### 4. 再确认 hook 是否真的安装成功

Hook 入口脚本位于：

- `platforms/windows/hook-installer/vibe_code_hook/hook_install.py`

当前仓库能确认的行为是：

- Claude hooks 会写入 `~/.claude/settings.json`
- Cursor hooks 会写入 `~/.cursor/hooks.json`

如果你怀疑 hook 没生效，先确认：

- 是否真正执行过安装动作
- 对应配置文件里是否已经写入 hook 命令
- 当前触发的事件名是否在脚本支持范围内

如果 hook 根本没有被触发，那么 bridge 和 BLE 层再正常，也不会看到状态更新。

### 5. 检查 hook 的 bridge 配置

`hook-installer` 发送状态时，会读取本地配置文件里的 bridge 地址和端口。

当前代码可确认：

- 配置文件名为 `config_client.json`
- 默认会补出 `server_ip` 和 `server_port`
- 如果文件损坏，会按默认配置重建

因此可以重点检查：

- `config_client.json` 是否存在
- `server_ip` / `server_port` 是否指向正确的本地 bridge
- 配置文件是否被旧值覆盖，导致 hook 发到了错误地址

### 6. 用 fake bridge 先切掉真实 BLE 变量

如果你不确定问题在 hook、bridge，还是设备侧，可以先用：

- `platforms/windows/hook-installer/vibe_code_hook/fake_bridge.py`

这个脚本的作用不是替代真实设备，而是先模拟最小 bridge 行为，验证：

- hook 是否能发出 TCP 请求
- 本地状态查询链路是否打通
- bridge 地址 / 端口配置是否正确

如果 fake bridge 可以通，而真实 bridge 不通，问题更可能落在 BLE bridge 或设备连接层。

## 常见现象与对应方向

### 桌面程序一开始就查不到设备

先查：

- bridge 是否启动
- TCP 地址和端口是否一致
- bridge 是否已经监听成功

### hook 安装成功，但状态没有同步到设备

先查：

- hook 是否真的触发
- `config_client.json` 是否指向正确 bridge
- bridge 是否能返回目标设备状态

### bridge 在运行，但设备始终不是 target

先查：

- bridge 当前识别到的设备名称 / MAC
- 设备是否已经配对并处于可连接状态
- 是否连到了错误的 BLE 设备

### 想区分“hook 问题”还是“真实设备问题”

先用 `fake_bridge.py` 验证 hook 和本地 TCP 这一段。

如果 fake bridge 正常，而真实链路异常，就继续排 bridge / BLE / 设备层。

## 相关源码入口

- `platforms/windows/desktop-main/README.md`
- `platforms/windows/ble-bridge/README.md`
- `platforms/windows/hook-installer/README.md`
- `platforms/windows/hook-installer/vibe_code_hook/hook_install.py`
- `platforms/windows/hook-installer/vibe_code_hook/ble_command_send.py`
- `platforms/windows/hook-installer/vibe_code_hook/fake_bridge.py`
