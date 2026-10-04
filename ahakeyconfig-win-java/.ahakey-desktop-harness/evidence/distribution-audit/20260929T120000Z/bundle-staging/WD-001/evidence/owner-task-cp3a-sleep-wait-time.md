# Owner Task — CP3A Sleep Wait Time Windows Contract

Date: 2026-09-28
Role: DLA
Mode: CONTRACT

Owner requested a minimal Windows Contract for CP3A firmware integration of the
"睡眠等待时间" feature, without editing production code first.

Confirmed boundaries from the conversation:

- UI name: 睡眠等待时间
- Description: 键盘无按键操作，且未收到上位机灯效、显示或配置指令达到设定时间后，将进入睡眠。
- Entry: More / "Hawk 安装分发工具" dialog / first "设备信息" card; do not add a new card.
- Options: 永不, 30 分钟, 60 分钟, 120 分钟.
- Firmware CP3A: command 0x95 is self-persisting set/query.
- Windows must not send 0x04 save_config for this setting.
- Windows flow: 0x95 set -> wait 0x95 OK -> 0x95 query -> readback match.
- Firmware CP3A HEX: C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\builds\ws1-cp3a-host-configurable-quiet-sleep-timeout\HID_Keyboard_582m_vibe_coding.hex
- Firmware CP3A HEX SHA256: 9AABCE5F015FD44D980FF6818D825B6BAB34F6E4B4F7AC277E942272D700444C

Owner instruction: do not modify production code yet; first write the minimal
Contract and Owner confirmation points.
