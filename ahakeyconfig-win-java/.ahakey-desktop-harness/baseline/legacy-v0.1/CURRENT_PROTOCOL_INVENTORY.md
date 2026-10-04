# CURRENT_PROTOCOL_INVENTORY

## Framing

### AhaKey Application Frame

CURRENT_CODE_EVIDENCE:

- Header: `AA BB`
- Trailer: `CC DD`
- Format in Java builder: `[AA][BB][cmd][payload...][CC][DD]`
- Encode: `AhaKeyProtocol.buildFrame()`
- Validate: `AhaKeyProtocol.isValidFrame()`
- Status parse: `AhaKeyProtocol.parseDeviceStatus()`
- Response parse: `AhaKeyResponseParser.parseCommandResponse()`

### BLE-TCP Bridge Packet

CURRENT_CODE_EVIDENCE:

- Format: `[Type:1][Length:2 little endian][Data:N]`
- Java: `BleTcpPacket`
- Types:
  - `0x01 WRITE_DATA`
  - `0x02 WRITE_COMMAND`
  - `0x03 QUERY_BLE_STATUS`
  - `0x04 QUERY_DEVICE_INFO`
  - `0x81 BLE_NOTIFY`
  - `0x82 BLE_STATUS_RESP`
  - `0x83 DEVICE_INFO_RESP`

### USB HID Packet

CURRENT_CODE_EVIDENCE:

- Transport report size: 64 bytes.
- Command report:
  - byte 0: `0xA1`
  - byte 1: frame length
  - bytes 2..: AhaKey frame
- Data report:
  - byte 0: `0xA2`
  - byte 1: data length
  - bytes 2..: raw data chunk
- Java: `UsbHidTransport.sendCommand()`, `sendData()`。

## BLE Service / Characteristic

CURRENT_CODE_EVIDENCE:

- `ble_bridge.py` defines `CHAR_CMD_WRITE = "00007343-0000-1000-8000-00805f9b34fb"`。
- Java 当前不直接使用 GATT UUID，只连接 TCP bridge。

UNKNOWN:

- 当前发布使用的 `BLE_tcp_driver.exe` 内部 service UUID、notify characteristic、scan filter 未在本目录 Java 代码中完整出现。

## Response / ACK Rules

CURRENT_CODE_EVIDENCE:

- `AhaKeyResponseParser.parseCommandResponse(frame)`:
  - `cmd = frame[2]`
  - `status = frame[3]`
  - `payload = frame[4..len-2)`
- `BleManager.waitForResponse(expectedCmd)`:
  - timeout `15000 ms`
  - 仅接受当前 transport session token 的 response。
  - cmd 必须等于 expected。
  - status 必须为 0，否则抛错。
  - 对回读命令可要求 minimum payload bytes；收到空 ACK 会继续等完整回读数据。
- Error status text:
  - 1 参数或数据格式无效。
  - 2 地址/分区/范围无效。
  - 3 当前固件不支持此命令。
  - 4 此操作仅支持 USB。
  - 5 外部 Flash 未识别或尚未就绪。
  - 6 写入超出实际 Flash 容量。
  - 7 Flash 正忙。
  - 8 Flash 写入地址未按 4K 对齐。

## Command Inventory

| Cmd | Name | Request Payload | Response Payload | UI 使用 | Evidence |
|---|---|---|---|---|---|
| `0x00` | `CMD_QUERY_STATUS` | empty | status frame: battery, signal, firmware major/sub, workMode, lightMode, switchState, optional brightness, optional readiness flags | 连接/轮询/审批 freshness | CURRENT_CODE_EVIDENCE |
| `0x01` | `CMD_CHANGE_NAME` | name bytes max 21 | UNKNOWN | 未看到 UI 使用 | CURRENT_CODE_EVIDENCE for builder; UNKNOWN usage |
| `0x02` | `CMD_CHANGE_APPEARANCE` | UNKNOWN | UNKNOWN | 未看到 builder/UI 使用 | CURRENT_CODE_EVIDENCE constant only |
| `0x04` | `CMD_SAVE_CONFIG` | empty | command response status | 保存配置、OLED 上传、任务模式、待机设置后保存 | CURRENT_CODE_EVIDENCE |
| `0x73` | `CMD_UPDATE_CUSTOM_KEY` | subtype + mode + keyIndex + data | command response status | K2/K3/K4 mapping/macro/description | CURRENT_CODE_EVIDENCE |
| `0x80` | `CMD_PREPARE_WRITE` | `[0][lenLo][lenHi][addr0..addr3]` | command response status | OLED/GIF flash block write | CURRENT_CODE_EVIDENCE |
| `0x81` | `CMD_WRITE_RESULT` | none from Java; device emits after data | command response status | OLED/GIF data block completion | CURRENT_CODE_EVIDENCE |
| `0x82` | `CMD_UPDATE_PIC` | mode, startIndex LE, frameCount LE, delay LE | command response status | default OLED asset / static image / GIF index update | CURRENT_CODE_EVIDENCE |
| `0x83` | `CMD_READ_PIC_STATE` | mode | `PictureState`: mode,startIndex,picLength,frameInterval,allModeMaxPic | OLED state read/verify asset 0 | CURRENT_CODE_EVIDENCE |
| `0x84` | `CMD_SET_AI_LIGHT_CONFIG` | mode + effect codes | command response status | 保存/预览 AI light config | CURRENT_CODE_EVIDENCE |
| `0x85` | `CMD_SET_LIGHT_BRIGHTNESS` | brightness 1..100 | command response status | 亮度测试/保存 | CURRENT_CODE_EVIDENCE |
| `0x86` | `CMD_LEGACY_CONFLICT` | legacy conflict | UNKNOWN | 不再发送 | CURRENT_CODE_EVIDENCE deprecated comment |
| `0x90` | `CMD_UPDATE_STATE` | state byte | command response/status-ish; 6-byte `0x90` ignored by status parser | 拨杆/IDE state preview | CURRENT_CODE_EVIDENCE |
| `0x91` | `CMD_SET_LIGHT_EFFECT` | effect code | command response status | 灯效测试/预览 | CURRENT_CODE_EVIDENCE |
| `0x92` | `CMD_SET_WORK_MODE` | mode 0..3 | command response status | 模式切换 | CURRENT_CODE_EVIDENCE |
| `0x93` | `CMD_SET_AI_OLED_CONFIG` | mode,state,startIndex LE,frameCount LE,delay LE | command response status | AI OLED asset config | CURRENT_CODE_EVIDENCE |
| `0x94` | `CMD_READ_AI_OLED_CONFIG` | mode,state | `AiOledState`: mode,asset,startIndex,frameCount,frameInterval,totalFrameSlots | OLED verify/read asset >0 | CURRENT_CODE_EVIDENCE |
| `0x95` | `CMD_STANDBY_TIMEOUT` | query empty or set minutes LE | standby minutes LE | 待机设置 | CURRENT_CODE_EVIDENCE |
| `0x96` | `CMD_FACTORY_RESET` | `A5 5A` | command response status | 恢复出厂设置 | CURRENT_CODE_EVIDENCE |
| `0x97` | `CMD_VOICE_KEY_CONFIG` | shortCount + short HID codes + longCount + long HID codes | query response includes short/long codes + threshold LE | voice key config sync/read verify | CURRENT_CODE_EVIDENCE |
| `0x98` | `CMD_TASK_LIGHT_MODE` | query empty or mode 0/1 | payload[0] mode | 单/多任务显示模式 | CURRENT_CODE_EVIDENCE |
| `0x99` | `CMD_TASK_SLOT_UPDATE` | slot,profile,state,flags | command response status | Hook task slot state | CURRENT_CODE_EVIDENCE |
| `0x9A` | `CMD_TASK_HEARTBEAT` | `[0]` | command response status | Task heartbeat/reconcile | CURRENT_CODE_EVIDENCE |
| `0x9B` | `CMD_MODE_SYNC` | query empty | mode,source,optional sequence | 模式回读/设备事件 | CURRENT_CODE_EVIDENCE |
| `0x9C` | `CMD_GIF_LAYOUT` | query empty | profiles,assets,maxFrames,frameBytes,sectors,width,height,optional flash diagnostics/capacities | OLED upload plan validation | CURRENT_CODE_EVIDENCE |
| `0x9D` | `CMD_CONFIG_QUERY` | resource,index,offset | resource,index,totalLength,offset,chunkLength,data | post-flash/config verification | CURRENT_CODE_EVIDENCE |
| `0x9F` | `CMD_QUERY_CAPABILITIES` | empty | protocolMajor,protocolMinor,firmwareMajor,firmwareMinor,hardwareRevision,capabilityBits,optional firmwarePatch,deviceModel | contract gate, voice route gate, firmware verifier | CURRENT_CODE_EVIDENCE |

## Subtypes for `0x73`

CURRENT_CODE_EVIDENCE:

- `0x73 SUB_SHORTCUT`: payload `[0x73][mode][keyIndex][hidCodes...]`
- `0x74 SUB_MACRO`: payload `[0x74][mode][keyIndex][macroData...]`
- `0x75 SUB_DESCRIPTION`: payload `[0x75][mode][keyIndex][ASCII <=20 bytes]`

## Device State / Status Payload

CURRENT_CODE_EVIDENCE:

`AhaKeyProtocol.parseDeviceStatus()` expects:

- `data[0..1] = AA BB`
- `data[2] = 0x00`
- payload base = 3:
  - `base+0`: battery
  - `base+1`: signal
  - `base+2`: firmwareMain
  - `base+3`: firmwareSub
  - `base+4`: workMode
  - `base+5`: lightMode
  - `base+6`: switchState
  - `base+7`: optional lightBrightness
  - `base+8`: optional readiness flags:
    - bit 0 BLE link
    - bit 1 HID input ready
    - bit 2 USB config ready

## Capability Bits

CURRENT_CODE_EVIDENCE:

- bit 0 `CAP_STANDBY_TIMEOUT_V2`
- bit 1 `CAP_FACTORY_RESET_V1`
- bit 2 `CAP_VOICE_KEY_DUAL_V1`
- bit 3 `CAP_STANDBY_NEVER_V1`
- bit 4 `CAP_TASK_LIGHT_MODE_V1`
- bit 5 `CAP_TASK_SLOTS_V1`
- bit 6 `CAP_GIF_LAYOUT_V1`
- bit 7 `CAP_MODE_SYNC_V1`
- bit 8 `CAP_DEVICE_MODEL_V1`
- bit 9 `CAP_CONNECTION_READY_V1`
- bit 10 `CAP_STABILIZED_CONTRACT_V1`
- required mask `0x7FF`

## Timeouts / Retry

CURRENT_CODE_EVIDENCE:

- General command response timeout: `15000 ms`。
- Status poll wait timeout: `750 ms`。
- Transport recovery backoff: `2000 ms`。
- OLED block attempts: `3`。
- OLED chunk size: `4096`。
- OLED transfer batch: `1024` bytes, delay `12 ms`。
- USB HID reader join timeout: `2000 ms`。
- Manual approval dialog timeout: `15 s`。

## Deprecated / Not Currently Sent

CURRENT_CODE_EVIDENCE:

- `0x86 CMD_LEGACY_CONFLICT`: comment says it was reused by different firmware branches for GIF suite and standby timeout; protocol v2 keeps the value but no longer sends it. Standby uses `0x95`。
- `0x02 CMD_CHANGE_APPEARANCE`: constant exists, no builder/UI path found.
- `0x01 CMD_CHANGE_NAME`: builder exists, no UI path found.

## UI Uses But Protocol Definition Is Weak

- `CMD_UPDATE_STATE 0x90`: used both for switch state and IDE/task-ish state preview. Parser explicitly ignores 6-byte `0x90` frames to avoid overwriting switch state. This is current-code evidence of semantic overlap.
- `CMD_WRITE_RESULT 0x81`: Java waits for it after raw data writes, but request shape is device-originated/implicit, not a Java command builder.
- BLE service/characteristic beyond `CHAR_CMD_WRITE` is UNKNOWN in current Java repo.

## Protocol Fixtures

CURRENT_CODE_EVIDENCE:

- `src/test/resources/protocol-fixtures/ahakey-protocol-3.2.json` contains golden:
  - `0x9F` request `AA BB 9F CC DD`
  - `0x9F` response with protocol `3.2`, firmware `1.4.7`, capability `0x7FF`, device model `1`
  - `0x9D` valid/invalid responses including trailer-like data chunk.
