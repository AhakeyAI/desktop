# WD-003 Owner confirmation: config_server.json is foreign local BLE configuration

At 2026-10-08T08:23:36+08:00, Owner resumed DLA with task
`WD-003 candidate-plan 被 config_server.json 外部输入挡住后的保留记录与重试`.

Owner-facing discussion before this record identified `config_server.json` as the
external `BLE_tcp_driver.exe` local runtime configuration file, not WD-003
production Java implementation or firmware source. The current change is local
BLE device binding:

- `BleName`: `AhaKey AD1E` -> `AhaKey 645E`
- `BleMac`: `D0:F8:AD:1E:7B:5F` -> `DC:7F:64:5E:CB:4C`

Current SHA256:
`14C1886BB4192876644A73B260A4AF0338C64EA023B63BC37EE7A768D9622F62`

Scope decision:

- Preserve `config_server.json` as a foreign/local runtime input.
- Do not include `config_server.json` in the WD-003 Git candidate.
- Do not revert, stash, stage, commit, or push it.
- This record does not modify production Java, firmware, protocol semantics, or
  Harness rules.
- This record is not formal Owner UAT, true-device formal PASS, Git candidate,
  formal build, release, or publication.
