WD-003 DLA reason for reference reconcile

WD-003 Owner Preview for token `preview-20261007T043528705385Z-bd644d` has been recorded as pass, but the result scope is `OWNER_PREVIEW_RESULT_ONLY_NOT_OWNER_UAT`.

During formal delivery preparation, `firmware-admit` and `record-check --check review --status pass` were both blocked by the Windows Harness reference guard:

`Pinned reference changed/missing: fw-cp4c-command-solve-c; DLA reconcile before using old approval`

Read-only verification found that several Firmware source-file references in `REFERENCES.json` now point at mutable files whose current working-tree bytes no longer match the previously approved hashes:

- `fw-cp4c-command-solve-c`: expected `d0e5f1ba61a63e69ffdf132c79eb288ab1b68681c7153108d0b91de65cb44cbb`, current file SHA256 `9DABDC1B446C7CFE1A02205240BC16D6F5C4787C1BC4C342A3C7D503B9C7C8AB`.
- `fw-cp4c-main-h`: expected `644918a0454d880db9099b895ca88b23b8c4f5ad380095647de78db45b844499`, current file SHA256 `13BB4F205320A43336F2714B6852A46C713A2E86B239BDE7D6CF4CC5926F3826`.
- `fw-cp4c-main-c`: expected `45ced5873fea2747b002cfccc7c532e3e6c456d77b7432092c6f1ebd7740947d`, current file SHA256 `D3C2E6A5BC9C7486739E8D6D1D0CD937B2C0F7ABD928D273501909D30861D66A`.

The CP4D formal gate receipt is stable evidence for this formal Firmware admission:

- Gate path: `.ahakey-harness/evidence/checkpoints/X1-INPUT-CONTROL/CP4D/20261007T131850/gate-receipt.json`
- Gate SHA256: `08A08C9031E0BDDCDA7787E89B48936CDE1508A5D64834DCAE58DE7BE8862312`
- Candidate commit: `8167ba13049c781da2f975bc803eccfe0e6ea2aa`
- HEX SHA256: `6F9759EB912EC067564C4E63558589AB9732126344D52C2D2A278383119516BE`

This reconcile replaces mutable Firmware source-file references that have drifted with stable CP4D formal gate and artifact evidence. It does not change Windows production code, Firmware source, protocol semantics, Git state, build outputs, Owner UAT status, release status, or true-device PASS status.
