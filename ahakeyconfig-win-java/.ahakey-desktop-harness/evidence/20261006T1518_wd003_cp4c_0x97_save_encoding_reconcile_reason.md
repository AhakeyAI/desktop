# WD-003 Reconcile Reason - CP4C 0x97 save encoding and firmware reference drift

Reason for reconcile:

- DIB preflight stopped with:
  `HARNESS STOP: Pinned reference changed/missing: fw-cp4c-command-solve-c; DLA reconcile before using old approval`
- Firmware source `APP/sub_main/command_solve.c` changed after the WD-003 approval reference snapshot.
- Latest Owner Preview confirmed `mi_01` selection and readback stability:
  - `0x9F` firmware catalog key read succeeded.
  - `0x95` sleep wait time read succeeded.
  - `0x97` side-switch config read succeeded.
  - `0x87` ordinary-key readback succeeded.
- The remaining Preview failure is a side-switch save encoding mismatch:
  - Windows sent `AABB970103012A030128CCDD`.
  - Firmware returned `AA BB 97 02 CC DD`.
  - The sent frame encoded Backspace and Enter as bare HID keycodes `2A` and `28`.
  - Current firmware expects Custom actions to be wrapped as `0x73/0x74 + len + payload`.

Observed current firmware facts:

- Firmware root: `C:\Users\20825\Desktop\vibe-code`
- Firmware HEAD observed read-only: `9e27b57cf53eeb236d289a81cb62d3140729cdba`
- `APP/sub_main/command_solve.c` SHA256: `e160e6c1b7649cb550541083256619a248bc5b87bd2a9f33870aa1180f977b78`
- `APP/sub_main/main.c` SHA256: `ac1ae5fe877b2d755c58cc0e2392cb5889f84eff3026cf2e2fbd1e1f684735cc`
- `APP/sub_main/main.h` SHA256: `fac9df73156785ae731ccb2329bdd18a33e37358743b8cdecc76673b0339b258`
- `APP/sub_main/command_solve.h` SHA256 remains `622e1f9a445b2b25d144b98b14b697cde7c2a1fa5c5e4eaf095e99ee12239ea4`
- `tests/host/input_control/test_side_switch_customization.c` SHA256: `b529698df514cdd97f0cbea443797bd970812ccbcfe13f5bdf6e5c5bd09da5cc`
- `tests/host/input_control/run-side-switch-customization-tests.ps1` SHA256: `3c68a553401b42b1f47306164708c073f53134c4a56444a9ab243daa3a0dd3a4`
- Preview-linked firmware HEX exists at `.ahakey-harness/evidence/builds/ws2-cp4c-usb-97-readback-oversize-fix/HID_Keyboard_582m_vibe_coding.hex`, SHA256 `a324143be8d23cd3cf9c549afdb61d360d23da7a9d28288069c78433229a2101`.

Governance meaning:

- This reconcile does not claim formal Firmware gate PASS for the current CP4C preview firmware.
- This reconcile does not claim Windows DLA review pass, Owner UAT, true-device PASS, formal candidate, release, or installer validation.
- This reconcile only refreshes WD-003's effective implementation reference and product/protocol boundaries so DIB can legally continue the in-contract Preview Fix.
