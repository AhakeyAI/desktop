# WD-001 Owner feedback - consolidated wired pass and BLE block

Timestamp: 2026-09-30
Role recording: DLA

Earlier Owner statement:

> 我用有线模式测试完全可以的，不过这个BLE驱动，我点软件里面的BLE 驱动也没有反应。感觉是不是这个 BLE 驱动后台没有起来，所以我在无线模式情况下是没有办法测的，但是有线模式我测是通过了的

Clarification context:

DLA explained that the selected steps `T02-T06`, `T08-T09`, and `T11` correspond to firmware/device identity confirmation, current value readback, setting 30 and immediate readback, persistence after real reboot, legal-value matrix, real Sleep/Wake observation, power lifecycle regression, and final result/restoration recording.

Owner confirmation:

> 都测试通过了

DLA interpretation:

- Owner confirms the selected wired/device steps `T02`, `T03`, `T04`, `T05`, `T06`, `T08`, `T09`, and `T11` passed over wired mode.
- App launch is considered no longer blocking because Owner reached and completed wired device testing.
- BLE/wireless remains blocked by the BLE driver/backend issue and is not recorded as PASS.
- `T07` illegal-value negative testing was not included in the selected clarification and remains not executed unless Owner separately confirms it or applicable independent evidence is accepted.
