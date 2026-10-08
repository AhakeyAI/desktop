# Owner record - input configuration domain CHANGE

Date: 2026-10-05 17:57:47 +08:00

Owner decisions in current DLA conversation:

- Confirmed a new Windows CHANGE for the input configuration domain.
- Scope: four ordinary keys plus side switch.
- Excluded from this CHANGE: light, OLED/GIF, voice, mode, power.
- Protocol facts:
  - 0x97 remains side-switch configuration only.
  - 0x98 is already occupied by `AHAKEY_CMD_TASK_LIGHT_MODE` and must not be used for ordinary key readback.
  - 0x87 is the ordinary key configuration readback-only narrow command candidate.
  - 0x87 request: `AA BB 87 mode key_index CC DD`.
  - 0x87 response: `AA BB 87 status mode key_index action_type action_len action_payload desc_len desc_payload CC DD`.
  - 0x87 status: 0 OK, 1 invalid payload, 2 mode/key_index out of range.
  - 0x87 boundary: read-only, one mode plus key_index per read, no full Host Protocol.
- Owner agreed to register Journey `J003`: CP4C input configuration domain integration.
- Owner agreed to change meta: `classification=protocol_change`, `review_policy=high_impact`.
- Owner authorized DLA to write Windows Harness governance records only:
  - `journey-register`
  - `new`
  - `change-meta`

Boundaries:

- No production code changes.
- No build.
- No app/device launch.
- No Git write operation.
- No DIB implementation authorization yet.
