# AhaKey-X1 BLE 协议完整文档

> 来源：原厂工具 PyInstaller 反编译 + 抓包验证。2026-04-13 确认。

## 1. 架构概览

```
AhaKeyConfig (Swift) ──BLE──> AhaKey-X1 键盘
                                │
            Service 0x7340      │  Battery Service 0x180F
            ├─ 0x7341 DATA      │  └─ 0x2A19 Battery Level (read/notify)
            ├─ 0x7342 INFO      │
            ├─ 0x7343 COMMAND   │  Device Info Service 0x180A
            └─ 0x7344 NOTIFY    │  ├─ 0x2A24 Model Number
                                │  └─ 0x2A26 Firmware Revision
```

- 命令写入 → 0x7343 (COMMAND)
- 数据写入 → 0x7341 (DATA)，用于大数据传输（图片等）
- 响应回调 → 0x7344 (NOTIFY)，订阅后接收设备响应
- 0x7342 (INFO) → 返回 200 字节空数据，**不用**

## 2. 帧格式

```
[0xAA 0xBB] [Cmd:1] [Data:N] [0xCC 0xDD]
```

- 帧头: `AA BB`
- 帧尾: `CC DD`
- 最小帧长: 5 字节（空 data）
- Cmd 字段对应 DeviceCmd 枚举

## 3. 设备命令 (DeviceCmd)

| 命令 | 值 | 说明 |
|------|-----|------|
| CHANGE_NAME | 0x01 | 修改蓝牙设备名 |
| CHANGE_APPEARANCE | 0x02 | 修改 BLE Appearance |
| SAVE_CONFIG | 0x04 | 保存配置到 Flash |
| UPDATE_CUSTOM_KEY | 0x73 | 按键配置（快捷键/宏/描述） |
| PREPARE_WRITE | 0x80 | 大数据写入准备 |
| WRITE_RESULT | 0x81 | 写入结果 ACK |
| UPDATE_PIC | 0x82 | 更新动画参数 |
| READ_PIC_STATE | 0x83 | 读取动画状态 |
| **UPDATE_STATE** | **0x90** | **IDE 状态同步 → LED 变色** |

## 4. 设备状态查询

**发送**: `AA BB 00 CC DD`（写入 0x7343）

**响应**（0x7344 notify）: `AA BB 00 [7 bytes] CC DD`

第一字节 `00` 是命令回显，后续字段：

| 偏移 | 字段 | 说明 |
|------|------|------|
| 0 | BatteryLevel | 电量百分比 (0-100) |
| 1 | SignalStrength | 信号强度 |
| 2 | FwMain | 固件主版本 |
| 3 | FwSub | 固件子版本 |
| 4 | WorkMode | 工作模式 (0/1/2) |
| 5 | LightMode | 灯光模式 (0=关/1=常亮/2=呼吸) |
| 6 | SwitchState | 开关状态 (0=关/1=开) |
| 7 | Reserve | 保留 |

**抓包实例**: `AA BB 00 4A 32 01 00 00 00 00 00 CC DD`
→ 电量=74% 信号=50 固件=1.0 模式=0 灯=0 开关=0

## 5. 按键配置 (UPDATE_CUSTOM_KEY = 0x73)

### 帧格式

```
AA BB 73 [sub_type:1] [mode:1] [key_index:1] [data:N] CC DD
```

- `sub_type`: 0x73=快捷键, 0x74=宏, 0x75=描述
- `mode`: 0/1/2（3 种工作模式）
- `key_index`: 0=Key1, 1=Key2, 2=Key3, 3=Key4

### 5.1 快捷键 (sub_type = 0x73)

data = HID Usage ID 列表，修饰键在前，普通键在后。最多 98 字节。

```
AA BB 73 73 00 00 6D CC DD
          │  │  │  └─ F18 (0x6D)
          │  │  └──── Key1
          │  └─────── Mode 0
          └────────── SHORTCUT sub_type
```

组合键示例（Cmd+C）: `AA BB 73 73 00 00 E3 06 CC DD`（Left GUI + C）

### 5.2 宏 (sub_type = 0x74)

data = 动作对列表 `[action, param, action, param, ...]`，最多 98 字节。

| MacroAction | 值 | 说明 |
|-------------|-----|------|
| NO_OP | 0 | 空操作 |
| DOWN_KEY | 1 | 按下键（param = HID code） |
| UP_KEY | 2 | 释放键（param = HID code） |
| DELAY | 3 | 延迟（param = 延迟值，~3ms 单位） |
| UP_ALLKEY | 4 | 释放所有键 |

### 5.3 描述 (sub_type = 0x75)

data = ASCII 字符串，最多 20 字节。显示在 OLED 屏幕上。

```
AA BB 73 75 00 00 45 63 68 6F 57 72 69 74 65 CC DD
                      "EchoWrite" (ASCII)
```

### 5.4 写入后必须 SAVE_CONFIG

写入键位后发 `AA BB 04 CC DD` 保存到 Flash，否则断电丢失。

## 6. 设备名称修改

```
AA BB 01 [UTF-8 name bytes] CC DD
```

- 最长 21 字节 UTF-8
- BLE 广播名只显示前 15 字节，超出会乱码
- 修改后需 SAVE_CONFIG

## 7. BLE Appearance 修改

```
AA BB 02 [appearance:1] CC DD
```

常用值: 0=未知, 961=HID 键盘, 962=HID 鼠标

## 8. OLED 图片/动画协议

### 显示参数

- 分辨率: 160x80 像素
- 编码: RGB565 大端
- 每帧 slot: 28672 字节
- 最大总帧数: 74

### 大数据写入流程

1. **PREPARE_WRITE**: `AA BB 80 [flag:1] [chunk_len:2 LE] [address:4 LE] CC DD`
   - 地址必须 4K 对齐
   - 等待 ACK（响应首字节 = 0 表示成功）
2. **写入数据块**: 通过 0x7341 (DATA) 写入，最大 4096 字节/块
3. **WRITE_RESULT** ACK: 设备通过 0x7344 返回确认
4. 重复直到所有数据写完

### 更新动画参数

```
AA BB 82 [mode:1] [start_index:2 LE] [frame_count:2 LE] [time_delay:2 LE] CC DD
```

time_delay = 1000 / fps（毫秒）

### 读取动画状态

**发送**: `AA BB 83 [mode:1] CC DD`

**响应**: `AA BB 83 00 [mode:1] [start_index:2 LE] [pic_length:2 LE] [frame_interval:2 LE] [all_mode_max_pic:2 LE] CC DD`

## 9. 响应格式

所有命令响应通过 0x7344 notify 返回，格式：

```
AA BB [cmd_echo:1] [status:1] [data:N] CC DD
```

- `cmd_echo` = 发送的命令值
- `status` = 0 表示成功，非 0 表示错误
- 设备状态查询例外：`status` 位置开始就是数据字段

## 10. 数据模型

```
KeyboardConfig
├─ name: String
└─ modes[3]: ModeConfig
   ├─ mode_id: 0/1/2
   ├─ keys[4]: KeyBinding
   │  ├─ key_type: SHORTCUT(0) / MACRO(1)
   │  ├─ keycodes: [UInt8]     (快捷键 HID 码列表)
   │  ├─ macro_data: [UInt8]   (宏动作对列表)
   │  └─ description: String   (OLED 显示，最多 20 字节)
   └─ display: DisplayMode
      ├─ fps: Int (默认 10)
      └─ frame_paths: [String]
```

## 11. HID 键码表

### 修饰键 (0xE0-0xE7)
| 名称 | HID | 名称 | HID |
|------|-----|------|-----|
| Left Ctrl | 0xE0 | Right Ctrl | 0xE4 |
| Left Shift | 0xE1 | Right Shift | 0xE5 |
| Left Alt | 0xE2 | Right Alt | 0xE6 |
| Left Cmd | 0xE3 | Right Cmd | 0xE7 |

### 功能键
| 名称 | HID | 名称 | HID |
|------|-----|------|-----|
| F1 | 0x3A | F13 | 0x68 |
| F2 | 0x3B | F14 | 0x69 |
| ... | ... | F15 | 0x6A |
| F11 | 0x44 | F16 | 0x6B |
| F12 | 0x45 | F17 | 0x6C |
| | | **F18** | **0x6D** |
| | | F19 | 0x6E |

### 字母键 (0x04-0x1D)
A=0x04, B=0x05, ... Z=0x1D

### 数字键 (0x1E-0x27)
1=0x1E, 2=0x1F, ... 0=0x27

### 基础键
| 名称 | HID | 名称 | HID |
|------|-----|------|-----|
| Enter | 0x28 | Caps Lock | 0x39 |
| Escape | 0x29 | Print Screen | 0x46 |
| Backspace | 0x2A | Scroll Lock | 0x47 |
| Tab | 0x2B | Pause | 0x48 |
| Space | 0x2C | Insert | 0x49 |
| Minus | 0x2D | Home | 0x4A |
| Equal | 0x2E | Page Up | 0x4B |
| Left Bracket | 0x2F | Delete | 0x4C |
| Right Bracket | 0x30 | End | 0x4D |
| Backslash | 0x31 | Page Down | 0x4E |

### 方向键
Right=0x4F, Left=0x50, Down=0x51, Up=0x52

### 小键盘
Num Lock=0x53, KP /=0x54, KP *=0x55, KP -=0x56, KP +=0x57,
KP Enter=0x58, KP 1-9=0x59-0x61, KP 0=0x62, KP .=0x63

## 12. IDE 状态同步 (UPDATE_STATE = 0x90)

原厂通过 Claude/Cursor hooks 把 IDE 运行状态实时推送到键盘，驱动 LED 变色和 OLED 显示。

### 命令格式

```
AA BB 90 [state:1] CC DD
```

### ClaudeState 枚举

| 状态 | 值 | 含义 | LED 行为（推测） |
|------|-----|------|----------------|
| CL_Notification | 0 | 通知 | 闪烁 |
| CL_PermissionRequest | 1 | 等待授权 | 黄色常亮 |
| CL_PostToolUse | 2 | 工具执行完毕 | 绿色闪一下 |
| CL_PreToolUse | 3 | 工具执行中 | 蓝色呼吸 |
| CL_SessionStart | 4 | 会话开始 | 绿色常亮 |
| CL_Stop | 5 | 已停止 | 熄灭 |
| CL_TaskCompleted | 6 | 任务完成 | 绿色闪烁 |
| CL_UserPromptSubmit | 7 | 用户提交 | 白色闪一下 |
| CL_SessionEnd | 8 | 会话结束 | 熄灭 |

注：LED 具体颜色/模式由固件决定，以上为推测。

### 拨杆 + PermissionRequest 联动

原厂 hooks 中 PermissionRequest 事件处理：
- 查询键盘 `SwitchState`
- `SwitchState == 0`（静止）→ 输出 `{"decision": {"behavior": "allow"}}`（自动批准）
- `SwitchState != 0`（拨动过）→ 输出 `{"decision": {"behavior": "ask"}}`（人工确认）

### 与现有 hooks 的兼容方案

原厂做法是用自己的二进制接管所有 9 个 hook 事件。我们的做法是**追加**而不是替换：

Claude Code 的 hooks 支持数组——同一个事件可以有多个 hook 并行执行。方案：

1. **现有 hooks 完全不动**（notify-macos.sh、protect-sensitive.sh 等）
2. **追加一个轻量脚本** `~/.claude/hooks/ahakey-state.sh`
3. 脚本通过 Unix domain socket 通知 AhaKeyConfig 进程
4. AhaKeyConfig 发送 `AA BB 90 [state] CC DD` 到键盘

```json
// settings.json hooks 示例（追加，不替换）
"Notification": [{
  "matcher": "",
  "hooks": [
    {"type": "command", "command": "~/.claude/hooks/notify-macos.sh"},
    {"type": "command", "command": "~/.claude/hooks/ahakey-state.sh Notification"}
  ]
}]
```

需要 AhaKeyConfig 常驻后台（menu bar 模式）来维持 BLE 连接。

## 13. 原厂工具架构参考

```
Vibecoding Keyboard.app
├─ KeyboardConfig (PyInstaller, PySide6 GUI)
│  ├─ src/comm/protocol.py    — 帧编解码、命令常量
│  ├─ src/comm/tcp_client.py  — TCP 桥接客户端
│  ├─ src/comm/device_service.py — 高级设备命令
│  ├─ src/core/keymap.py      — 数据模型
│  ├─ src/core/keycodes.py    — HID 键码表
│  └─ src/core/image_processor.py — RGB565 编码
├─ BLETcpBridge.app
│  ├─ BleTcpBridge (.NET 8.0, TCP<->stdin/stdout)
│  └─ ble_helper.swift (CoreBluetooth, JSON protocol)
└─ CapsWriter (SenseVoice-Small ASR)
```

原厂通过 TCP 桥接（Python <-> .NET <-> Swift BLE helper）间接通信。
我们直接用 CoreBluetooth，省掉整个桥接层。

反编译源码保存在 `.build/factory-extracted/`。
