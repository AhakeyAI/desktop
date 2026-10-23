# WD-002 deferred follow-up - keyboard-initiated mode latency

Date: 2026-10-04
Change: WD-002
Decision owner: Owner

Owner decision:

- Do not change this part in the current batch.
- Reason: although keyboard-initiated mode sync is slow, it is usable enough for now.
- Owner wants WD-002 records collected and the current node closed so the next feature can start.

Observed behavior:

- When the keyboard itself switches mode, the Windows UI follows slowly, roughly 4-5 seconds in observed use.
- Prior Windows logs showed that after a status packet reaches Java, Java applies it essentially immediately.
- Current Windows status polling period is 5 seconds, so the delay matches waiting for the next status poll.

Firmware and bridge diagnosis:

- Firmware status readback exists through the existing 0x00 state path. The returned state includes running_data.mode_data.
- Firmware local keyboard mode changes call set_mode(...) but do not currently emit an active status notification for the desktop.
- BLE bridge code can recognize the firmware status notification frame and update its internal status cache.
- Current BLE bridge behavior consumes device-status notifications and does not immediately broadcast a DeviceInfoResp 0x83 packet to Java clients.

Recommended future implementation, if Owner later schedules it:

- Firmware: after local keyboard mode changes, actively emit the existing status frame over BLE notify, without introducing a new opcode unless the firmware contract changes.
- BLE bridge: when receiving a device-status notification, update cache and immediately broadcast DeviceInfoResp 0x83 to connected TCP clients.
- Java: keep the existing 0x83 status update path and retain low-frequency polling as fallback.

Current status:

- Deferred by Owner.
- Not included in the current WD-002 Preview Fix acceptance.
- Requires a future Owner-approved change if it becomes important.
