# WD-003 Reconcile Reason - CP4D 0x87 Firmware Reference Changed

Date: 2026-10-07

Reason:

- DIB preflight stopped because the pinned firmware reference `fw-cp4c-command-solve-c` changed.
- Firmware now contains CP4D `0x87` ordinary-key readback implementation and related constants:
  - Request: `AA BB 87 mode key_index CC DD`
  - Success: `AA BB 87 00 mode key_index action_type action_len action_payload desc_len desc_payload CC DD`
  - Errors: `01` invalid payload, `02` out of range or unsupported stored action, `03` too large for one 64-byte response
- Firmware commit observed: `8167ba13049c781da2f975bc803eccfe0e6ea2aa`.
- Current observed source hashes:
  - `APP/sub_main/command_solve.c`: `d0e5f1ba61a63e69ffdf132c79eb288ab1b68681c7153108d0b91de65cb44cbb`
  - `APP/sub_main/command_solve.h`: `2bab97bf5238df74b12874ea8f254ff4948551d90e78ad427541a73f7ec255c3`
  - `APP/sub_main/main.h`: `644918a0454d880db9099b895ca88b23b8c4f5ad380095647de78db45b844499`
  - `APP/sub_main/main.c`: `45ced5873fea2747b002cfccc7c532e3e6c456d77b7432092c6f1ebd7740947d`
- Existing CP4C `0x97` host-test anchors were re-hashed under the same firmware commit and still protect the accepted side-switch behavior:
  - `tests/host/input_control/test_side_switch_customization.c`: `72ab6f38ea329c66a4d0098257c138675f0dcc44739c382cedc3f461b8670f37`
  - `tests/host/input_control/run-side-switch-customization-tests.ps1`: `a58d124350ec09dd5c0cd85f0a1c2db7d885443e41fdd41d35a20413b7facd02`

Windows reconcile action:

- Update WD-003 protocol contract and firmware references to the CP4D single-packet `0x87` readback contract.
- Route implementation back to DIB so Windows can parse empty/shortcut/macro readbacks, handle `0x87 03` fail-closed, and preserve the already-tested `0x97` side-switch behavior.

Non-goals:

- No firmware edit.
- No Harness script bypass.
- No formal review pass, true-device pass, Owner UAT, release, installer build, or Git write.
