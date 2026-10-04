# WD-002 Preview Fix Review - UI bounce log root cause

Status: PASS

## Review focus

This review is limited to the Preview Fix fast lane for the Owner-reported Windows-initiated mode switch UI bounce.

## Findings

No blocking issues found.

## Reasoning

The implementation still requires the firmware/device `0x92` acknowledgement before considering the mode switch accepted. It then verifies the target mode using refreshed status evidence that includes BLE bridge `DEVICE_INFO_RESP`, which is the status path shown in the logs to carry the new work mode before the old implementation timed out.

The change does not alter keyboard-initiated mode switching behavior, polling cadence, firmware protocol, product contract, installer packaging, or release flow.

## Residual risk

This still needs Owner real-device preview because the failure is timing-sensitive and depends on BLE bridge response ordering.
