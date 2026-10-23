# WD-003 Owner Preview feedback - wired pass, BLE blocked

Source: Owner chat feedback on 2026-10-06.

Preview token: `preview-20261006T075111394494Z-abd1b1`

Owner reported:

- The listed wired tests all passed.
- In wireless/BLE testing, clicking the BLE driver button had no response, so Bluetooth testing could not be performed.

Interpretation for Harness routing:

- Record this Owner Preview as pass for the requested WD-003 wired CP4C preview coverage: `0x9F`, `0x95`, `0x97`, `0x87`, side-switch save/readback, combination shortcut, and short macro.
- Do not treat this as formal Owner UAT, true-device release PASS, Git candidate approval, or release.
- Do not claim wireless/BLE coverage passed. BLE driver button no-response is a separate blocker for wireless coverage and should be triaged separately from the WD-003 wired CP4C preview pass unless Owner explicitly folds wireless driver behavior into this change.
