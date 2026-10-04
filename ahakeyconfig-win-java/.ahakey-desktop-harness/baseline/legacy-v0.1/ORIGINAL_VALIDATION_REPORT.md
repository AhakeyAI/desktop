# Validation Report — Desktop Harness v0.1-alpha1

- Baseline package: 8/8 markdown files present.
- Canonical protocol snapshot created from current Java code baseline; BLE GATT remains explicitly UNKNOWN.
- Flow reduced to one-time BASELINE_ADOPT + two long-lived phases CONTRACT / BUILD_VERIFY.
- DLA / DIB role separation encoded.
- UI Placement, Protocol Change, Cross-System Handoff policies encoded.
- Installer is Preserve-First and does not touch `src/main/java/**`.
- Python helper scripts syntax-checked before packaging.

Not yet validated on the user's actual Windows Java repository:
- Maven tests / JavaFX runtime screenshots;
- current CSS/typography visual baseline;
- BLE_tcp_driver.exe GATT behavior;
- real Firmware↔Desktop integration.
