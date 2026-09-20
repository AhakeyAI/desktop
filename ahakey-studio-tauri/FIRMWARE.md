# Community firmware for AhaKey X1

## Identity and compatibility

- Hardware: **AhaKey X1, CH582M**. Do not flash a generic WCH development board,
  a different AhaKey model or an unidentified hardware revision.
- Firmware: **0.1.17**, unofficial, community, experimental.
- Companion client: AhaKey Studio **1.1.5**. The two version numbers are independent.
- Download: [fork Release](https://github.com/lgcyaxi/AhakeyAI/releases/tag/ahakey-studio-1.1.5).
- File: `AhaKey-X1-DualBLE-0.1.17.hex`.
- SHA-256: `771efe5a1d16bd8530c3cd0dd64931c400a757f6bc18ff1175418f9530dd67e8`.

The HEX contains application code, not chip configuration or DataFlash records.
The client neither downloads nor flashes it automatically. Building the Rust
client does not need any firmware source or binary.

## Changes and limits

USB and two BLE hosts may remain connected; physical input goes only to the
selected destination. In host-switch mode, attaching USB replaces the upper
lever's BLE destination; the lower BLE destination stays fixed. Removing USB
restores the upper BLE slot. Approval-lever mode remains optional.

Only an eligible selected, unpaired BLE slot is discoverable for new pairing.
Bonded peers have a separate reconnect path. USB attachment is not a command to
disconnect an existing BLE link. The client shows separate A/B status, labels
and recent faults. Client pairing resets require USB; a physical long press
resets the selected BLE slot, while selecting USB does not clear either bond.

Known-peer encryption-handshake timeouts enter bounded recovery; invalid
identity, key-size and explicit security failures remain blocked. Recovery is
not a guarantee that an OS will reconnect without user intervention.

On battery, about 60 seconds of suitable inactivity turns off the screen and
lights while BLE and input services continue. A key or lever wakes the display
without discarding the first input. USB power keeps presentation awake.
MCU deep sleep is disabled; battery current and total runtime are not measured.

The maintainer reports stable current dual-host use and satisfactory standby.
This is user-reported testing, not universal interoperability certification.
Image/card preview exists in the client, but uploading custom images or quota
cards to the device is not implemented in this release.

## Flashing and recovery

Experimental flashing can make input unavailable, invalidate pairing, or require
manual recovery. Keep another keyboard available and follow the vendor's
[official firmware instructions](https://github.com/AhakeyAI/firmware).
Use the exact X1 target and verified HEX, not a WCH demo image.

The tested update procedure preserves the existing chip configuration and
DataFlash: do not enable RST-as-reset, serial keyless download, or clear DataFlash
as part of this update. Do not improvise pin shorts or change protection bits.
Use the vendor's procedure to enter ISP, download, verify, and restart.

Keep the [official X1 v1.1.0 recovery Release](https://github.com/AhakeyAI/firmware/releases/tag/AhaKey-X1-v1.1.0)
available before flashing. Its `HID_Keyboard_582m_vibe_coding.hex` SHA-256 is
`09f4b60751c0bfcb374e5c62f6be5a2b4fa180f6d7dc623b8e8ca46d1d34205a`.
Rollback may require pairing again; it does not promise to restore every setting.

## Permission and attribution

Hardware and board implementation: [AhaKey](https://github.com/AhakeyAI).
[Written permission, 2026-09-13](https://github.com/AhakeyAI/desktop/issues/63#issuecomment-5653215712)
allows this project's modified compiled unofficial HEX in the maintainer's fork
Releases for personal, noncommercial research. It does **not** authorize publishing
controlled source, schematics, or modifications derived from controlled source.
Commercial use or disclosure outside that scope needs additional permission.
This notice does not relicense third-party components.

The Release includes `AhaKey-X1-0.1.17-NOTICES.txt` and
`AhaKey-X1-0.1.17-Apache-2.0.txt` with WCH, MultiButton and LwRB attribution.
Preserve these notices with the binary. This is not an official AhaKey firmware,
and no warranty of fitness or recoverability is provided.
