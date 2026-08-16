# AhaKey-X1 通信协议（Protocol v2）

> 本文是 AhaKey-X1 固件、Windows Java 客户端和 Python 基线客户端的命令字唯一登记表。
> Protocol v2 从 2026-07-24 起生效，解决历史固件分支对 `0x84`～`0x86` 的重复分配问题。

## 1. 传输通道

同一设备帧可以经 BLE 桥或 USB HID 传输，命令含义与响应格式保持一致。

### BLE

- Service：`0x7340`
- DATA `0x7341`：图片等大数据
- INFO `0x7342`：旧接口，不使用
- COMMAND `0x7343`：命令帧
- NOTIFY `0x7344`：设备响应

### USB HID

- Windows 客户端通过 `UsbHidTransport` 发送同一套设备帧。
- 固件通过 USB HID EP2 返回响应。
- USB HID 可用性与 WHICP/烧录能力属于后续 OTA 阶段，不计入本版能力位。

## 2. 设备帧

```text
[AA BB] [Command:1] [Payload:N] [CC DD]
```

- 所有多字节整数使用小端序。
- 最短命令帧为 5 字节。
- 普通响应格式：

```text
[AA BB] [Command:1] [Status:1] [Payload:N] [CC DD]
```

状态码：

| 值 | 名称 | 含义 |
|---:|---|---|
| `0` | OK | 成功 |
| `1` | INVALID_PAYLOAD | 长度或参数格式错误 |
| `2` | OUT_OF_RANGE | 参数超出允许范围 |
| `3` | UNSUPPORTED | 当前协议/固件不支持 |
| `4` | USB_REQUIRED | 该危险操作只能通过 USB 执行 |

`0x00` 状态查询是历史例外：响应在命令字后直接返回状态字段，没有 `Status` 字节。

## 3. 命令字登记表

| 命令 | 值 | Protocol v2 含义 |
|---|---:|---|
| QUERY_STATUS | `0x00` | 查询设备状态 |
| CHANGE_NAME | `0x01` | 修改 BLE 名称 |
| CHANGE_APPEARANCE | `0x02` | 修改 BLE Appearance |
| SAVE_CONFIG | `0x04` | 将待保存配置写入 Flash |
| UPDATE_CUSTOM_KEY | `0x73` | 更新快捷键、宏或描述 |
| PREPARE_WRITE | `0x80` | 大数据写入准备 |
| WRITE_RESULT | `0x81` | 大数据块写入结果 |
| UPDATE_PIC | `0x82` | 更新普通 OLED 动画参数 |
| READ_PIC_STATE | `0x83` | 查询普通 OLED 动画参数 |
| SET_AI_LIGHT_CONFIG | `0x84` | 配置各 AI 状态对应的灯效 |
| SET_LIGHT_BRIGHTNESS | `0x85` | 设置灯光亮度 |
| LEGACY_CONFLICT | `0x86` | **保留；v2 固件返回 UNSUPPORTED** |
| UPDATE_STATE | `0x90` | 同步 AI/IDE 状态 |
| SET_LIGHT_EFFECT | `0x91` | 立即切换灯效 |
| SET_WORK_MODE | `0x92` | 切换键盘工作模式 |
| SET_AI_OLED_CONFIG | `0x93` | 配置 AI 状态 OLED 动画 |
| READ_AI_OLED_CONFIG | `0x94` | 查询 AI 状态 OLED 动画 |
| STANDBY_TIMEOUT | `0x95` | 查询或设置待机时间 |
| FACTORY_RESET | `0x96` | USB-only 恢复初始化（确认载荷 `A5 5A`） |
| VOICE_KEY_CONFIG | `0x97` | 查询或设置全局语音键短按/长按快捷键 |
| QUERY_CAPABILITIES | `0x9F` | 查询协议、版本和能力位 |

命令范围：

- `0x00`～`0x9F`：AhaKey 官方命令
- `0xA0`～`0xEF`：SDK 用户扩展命令
- `0xF0`～`0xFF`：系统、调试和工厂保留

### 0x86 兼容性规则

历史分支曾将 `0x86` 分别定义为“GIF 套图切换”和“待机时间”，两种载荷可能被错误解释。Protocol v2 的规则是：

1. 新客户端不发送 `0x86`。
2. 新固件收到 `0x86` 返回状态码 `3`。
3. 客户端能力查询失败时，把设备视为旧固件并隐藏 v2 配置，不能尝试 `0x86` 回退。

## 4. 能力协商（0x9F）

请求：

```text
AA BB 9F CC DD
```

响应：

```text
AA BB 9F 00
  protocol_major:1
  protocol_minor:1
  firmware_major:1
  firmware_minor:1
  hardware_revision:1
  capability_bits:4 LE
  firmware_patch:1
CC DD
```

当前版本值：

- Protocol：`2.2`
- Firmware：`1.1.0`
- Hardware revision：`1`

能力位：

| Bit | 常量 | 含义 |
|---:|---|---|
| 0 | `CAP_STANDBY_TIMEOUT_V2` | 支持 `0x95` 查询/设置待机时间 |
| 1 | `CAP_FACTORY_RESET_V1` | 支持 USB-only `0x96` 安全恢复初始化 |
| 2 | `CAP_VOICE_KEY_DUAL_V1` | 支持 `0x97` 全局语音键短按/长按配置 |
| 3～31 | Reserved | 必须忽略未知位 |

Windows 客户端连接设备后应先查询 `0x9F`。只有 Bit 0 为 1 时才显示或启用待机时间设置。

## 5. 待机时间（0x95）

单位为分钟，`uint16 LE`：

- 固件和桌面端只接受：`5 / 10 / 15 / 30` 分钟
- 恢复初始化后的默认值：`30` 分钟

查询：

```text
请求：AA BB 95 CC DD
响应：AA BB 95 00 [minutes:2 LE] CC DD
```

设置 30 分钟：

```text
请求：AA BB 95 1E 00 CC DD
响应：AA BB 95 00 CC DD
```

设置成功只修改运行时配置并标记为待保存；客户端随后必须发送：

```text
AA BB 04 CC DD
```

## 6. 恢复初始化（0x96）

请求仅允许经 USB HID 发送：

```text
AA BB 96 A5 5A CC DD
```

固件先返回成功，再写入掉电可恢复的清除标记并重启。启动阶段清除当前设备的 GIF、用户配置、按键配置、待机配置、其他用户数据和蓝牙配对，恢复内置默认 GIF 与 30 分钟待机值；固件版本、设备标识和 MAC 不变。清除全部完成后才移除标记，因此中途掉电会在下次启动继续。

只有 `SAVE_CONFIG` 成功后，断电重启仍会保留新值。

## 7. 状态查询（0x00）

请求：

```text
AA BB 00 CC DD
```

响应：

```text
AA BB 00
  battery:1
  signal:1
  firmware_major:1
  firmware_minor:1
  work_mode:1
  light_mode:1
  switch_state:1
  light_brightness:1
CC DD
```

版本字段必须与 `0x9F` 返回的固件版本一致。

## 8. 按键配置（0x73）

```text
AA BB 73 [sub_type:1] [mode:1] [key_index:1] [data:N] CC DD
```

| sub_type | 含义 | data |
|---:|---|---|
| `0x73` | 快捷键 | HID Usage ID 列表 |
| `0x74` | 宏 | `[action, parameter]` 对 |
| `0x75` | 描述 | 最多 20 字节 ASCII |

按键配置完成后必须发送 `SAVE_CONFIG`。

### 全局语音键短按/长按（0x97）

该配置独立于四个工作模式，物理左一键在所有模式下共用：

- 短按不足 350ms：发送一次完整的快捷键点击。
- 按住达到 350ms：按下长按快捷键，物理键松开时释放。
- 任一动作的按键数量为 0 时，该动作禁用。
- 每个动作允许 0～8 个左右可区分的修饰键，以及最多 1 个普通 HID Usage ID。

设置请求：

```text
AA BB 97
  short_count:1 short_codes:N
  long_count:1  long_codes:M
CC DD
```

查询请求为 `AA BB 97 CC DD`。查询响应：

```text
AA BB 97 00
  short_count:1 short_codes:N
  long_count:1  long_codes:M
  long_press_ms:2 LE
CC DD
```

默认短按为 Right Alt（`E6`），默认长按为 Left Ctrl + Left Win（`E0 E3`），阈值固定为 350ms。设置后客户端必须发送 `0x04 SAVE_CONFIG`，再查询 `0x97` 回读校验。

## 9. OLED 大数据

参数：

- 分辨率：`160 × 80`
- 编码：RGB565 大端
- 每帧数据：25,600 字节
- 每帧 Flash slot：28,672 字节（7 个 4 KiB sector）
- 写入块：最多 4,096 字节，地址必须 4 KiB 对齐

写入流程：

1. `0x80 PREPARE_WRITE`
2. 通过 DATA 通道发送数据块
3. 等待 `0x81 WRITE_RESULT`
4. 重复至完成
5. 使用 `0x82` 或 `0x93` 更新动画元数据
6. 发送 `0x04 SAVE_CONFIG`

普通动画：

```text
0x82 payload = mode:1 + start:2 LE + count:2 LE + interval_ms:2 LE
0x83 request = mode:1
0x83 response payload = mode:1 + start:2 + count:2 + interval_ms:2 + max_frames:2
```

AI 状态动画：

```text
0x93 payload = mode:1 + ai_state:1 + start:2 LE + count:2 LE + interval_ms:2 LE
0x94 request = mode:1 + ai_state:1
```

## 10. 客户端兼容流程

```text
连接设备
  -> 发送 0x9F
     -> 成功且协议主版本为 2：按 capability_bits 启用功能
     -> 超时 / UNSUPPORTED：标记为旧固件，仅保留已验证的旧功能
     -> 协议主版本高于客户端：保留基础功能，并提示升级桌面软件
```

客户端不得仅凭固件版本猜测命令支持情况；功能开关以 `capability_bits` 为准。

## 11. 变更规则

新增或修改命令时，必须在同一个变更中同步：

1. 本文命令登记表
2. 固件源码副本
3. 固件实际构建工程副本
4. Java 客户端协议与测试
5. Python 基线协议与测试

严禁复用已经登记或被标记为历史冲突的命令字。
