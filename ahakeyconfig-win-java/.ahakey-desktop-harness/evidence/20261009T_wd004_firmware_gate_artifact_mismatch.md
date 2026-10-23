# WD-004 Firmware Gate Artifact Mismatch

Date: 2026-10-09
Role: DLA
Mode: DELIVERY_PREP

Windows WD-004 has a reviewed Git candidate and a runnable JAR/classpath build receipt.

During formal delivery preparation, DLA discovered the matching Firmware formal gate:

- Gate: `.ahakey-harness/evidence/checkpoints/X1-AI-WORKFLOW-PRESENTATION/CP1/20261006T143035/gate-receipt.json`
- Gate SHA256: `491fec8b21cfab0bb4d0568efac9444cbd77f23f6f0d01048ff30583d13efa2f`
- Gate result: `PASS`
- Firmware candidate commit: `3d3e6e677068c305cfb022a4c12f213cf1a1da1d`
- Gate artifact path: `.ahakey-harness/evidence/builds/ws3-cp1-ai-presentation/HID_Keyboard_582m_vibe_coding.hex`
- Gate artifact SHA256 recorded in gate: `0a6886220f97b3eff4d74ffa1b1fcaa34e5e56a9d0da69d5feeda3a5a7f1f5a0`

Read-only byte inspection of the current HEX at the same path returned:

- Current HEX SHA256: `0b606bc4eecfe3621eaddafb301a38b06db070750359bfbfa8cd2c0819e011b9`

Harness `firmware-admit --id WD-004 --role DLA --gate .ahakey-harness\evidence\checkpoints\X1-AI-WORKFLOW-PRESENTATION\CP1\20261006T143035\gate-receipt.json` stopped with:

`HARNESS STOP: Formal gate artifact is not the exact Firmware paired with this task`

Meaning:

- This is not a Windows build failure.
- This is not an Owner UAT result.
- WD-004 Owner test packet must not be published until Firmware provides/restores an exact formal gate and artifact pairing accepted by `firmware-admit`.

No build, app launch, Hook install/update, device write, Git write, or firmware write was executed by DLA in this turn.
