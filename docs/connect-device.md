# Connect a Device

这份文档用于帮助新用户理解 AhaKey Desktop 当前的设备连接链路，并在连接失败时快速判断问题落在哪一层。

当前仓库中的 Windows 连接路径不是“应用直接连设备”，而是：

- `desktop-main` 通过 TCP 与本地 bridge 通信
- 本地 bridge 再通过 BLE 与目标设备通信

因此，设备连接问题通常需要按链路顺序排查，而不是只盯着 BLE 设备本身。

## 预期连接流程

推荐按下面的顺序理解当前连接链路：

1. 启动本地 BLE bridge
2. 启动桌面程序
3. 让桌面程序通过 TCP 连到 bridge
4. 让 bridge 与目标 BLE 设备建立连接
5. 在桌面程序中查询设备状态和设备信息
6. 在确认设备可见后，再继续做配置下发或动画上传

如果前面的步骤没有成功，后面的步骤通常都会一起失败。

## 相关组件分别负责什么

### `platforms/windows/desktop-main/`

这是用户侧主桌面程序。

当前仓库里能确认的是，它负责：

- 通过 TCP 与本地 bridge 通信
- 查询设备状态
- 查询设备信息
- 下发设备相关命令和数据

### `platforms/windows/ble-bridge/`

这是 BLE 与 TCP 之间的桥接层。

它的作用是：

- 接收桌面程序发出的 TCP 请求
- 再把这些请求转发给目标 BLE 设备

### `platforms/windows/hook-installer/`

这个模块不是桌面程序主连接链路本身，但它也依赖同一条本地 bridge。

如果 hooks 需要同步状态到设备，也会通过本地 TCP bridge 发送命令。

## 什么算“连接成功”

在当前仓库语义下，连接成功通常意味着：

- 桌面程序已经成功连到本地 bridge
- bridge 已经识别并连接到目标 BLE 设备
- 桌面程序可以查询到设备状态
- 桌面程序可以继续查询设备信息，而不是只停留在“桥接器在线”

换句话说，只能启动程序不算成功；bridge 在运行也不自动等于设备已连上。

## 建议的排查顺序

### 1. 先确认 bridge 是否在运行

当前桌面程序依赖本地 bridge。

如果 bridge 没启动，桌面程序的设备查询通常会直接失败。

先检查：

- bridge 是否已经启动
- bridge 是否持续运行，而不是启动后立刻退出
- 监听地址和端口是否与客户端配置一致

### 2. 再确认桌面程序是否连到了 bridge

当前仓库中的 TCP 通信逻辑位于：

- `platforms/windows/desktop-main/vibe_code_config_tool/src/comm/tcp_client.py`
- `platforms/windows/desktop-main/vibe_code_config_tool/src/comm/device_service.py`

如果桌面程序无法查询设备状态，优先怀疑：

- bridge 没启动
- bridge 地址 / 端口不对
- 本地 TCP 连接没有建立成功

这一步先不要直接归因到 BLE 设备。

### 3. 如果 TCP 通了，再判断 bridge 是否找到了目标设备

桌面程序连到 bridge，只说明本地 TCP 这一段是通的。

它不代表 bridge 已经连上正确的 BLE 设备。

当前代码链路里，bridge 会返回类似这些状态字段：

- `connected`
- `name`
- `mac`
- `is_target`

如果这些信息显示未连接，或者设备不是目标设备，问题通常还在 BLE / 设备识别层。

### 4. 用“能否查询设备信息”判断是否走通主链路

当前桌面程序的典型工作流中，连接 bridge 之后会继续查询设备信息。

所以可以用这个标准做判断：

- 如果只能启动程序，但查不到设备状态，通常还没连上 bridge
- 如果能查状态，但拿不到正确设备信息，通常问题还在 bridge 到设备这一段
- 如果状态和设备信息都能返回，基本说明主连接链路已经打通

### 5. 再继续做配置或上传动作

只有在前面的状态查询已经稳定之后，才建议继续：

- 编辑按键配置
- 下发到设备
- 上传动画或图片

否则很容易把“设备连接问题”误判成“配置上传失败”。

## 常见失败现象与检查点

### 桌面程序启动了，但设备页面一直没有状态

先看：

- bridge 是否在运行
- bridge 监听地址 / 端口是否正确
- 桌面程序是否真的连到了本地 TCP bridge

### 桌面程序能连本地服务，但设备不是目标设备

先看：

- bridge 当前识别到的设备名称
- bridge 返回的 MAC 信息
- 设备是否已经上电、配对并处于可连接状态

### 有时能连，有时不能连

优先从链路顺序排查，而不是同时怀疑所有模块：

1. bridge 是否稳定运行
2. 本地 TCP 是否稳定
3. BLE 设备是否稳定可见

### hook 能触发，但桌面程序侧还是查不到设备

这通常说明：

- hooks 那一侧可能能访问本地 bridge
- 但桌面程序主连接链路仍未稳定建立

不要把 hook 侧的现象直接当成桌面程序设备连接已经正常。

## 建议先看的相关文档

- `docs/installation.md`
- `docs/debug-ble-bridge-hook.md`
- `docs/architecture.md`
- `platforms/windows/README.md`
- `platforms/windows/desktop-main/README.md`
- `platforms/windows/ble-bridge/README.md`
