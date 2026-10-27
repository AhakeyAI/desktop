# Restore repeat v2 — independent review

Frozen base `ae1c430`, head `617729efa189a2ccb8125e299cd09a4a99968c0d`.

Spec: `docs/ahastudio/firmware-repeat-restore-v2-sync-2026-10-27.md`, accepted firmware amendment and exact ed426c9 dispatcher/store/coordinator. Standards: CONTRIBUTING, applicable Mac architecture/BLE guidance and existing conventions. Reviewers read frozen code independently, did not edit/run hardware or use credentials.

## Standards

No actionable documented violations or substantive judgement smells across all19 files. Protocol/transaction/model/view boundaries remain intact; both generated localization catalogs and their source generator are updated; validation and untested boundaries are explicit.

## Spec

No substantive missing/wrong behavior or scope creep. v1 first/incomplete retries preserve compatibility; explicit COMPLETE repeat uses v2 with fresh attempt+1. Overflow/changed status stops before submission. Actual BLE exchange, both production write-policy checks,17-byte framing and exact version/nonce matching were traced; transport capacity and same-generation Restore proof are enforced.

One mutation is issued; unknown/lost reply stays unconfirmed without fallback or blind retry. Fresh terminal read resolves ambiguity but clears consent and emits no successful write outcome. Known refusal needs unchanged state/attempt; advanced failed attempt remains unfinished. Verified success still requires full defaults readback bracketed by unchanged status. COMPLETE UI warns older firmware may refuse.

Final full Swift result:941 passed. Neither axis establishes formal firmware REGATE, new HEX or hardware UAT readiness.

Findings: Standards0; Spec0.
