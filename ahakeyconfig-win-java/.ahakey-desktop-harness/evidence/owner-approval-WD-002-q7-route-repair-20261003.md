# WD-002 Owner Approval - Narrow Q7 Route Repair

Status: OWNER_APPROVED_NARROW_HARNESS_ROUTE_REPAIR
Role: DLA
Harness: AhaKey Windows Harness v1.0.1
Date: 2026-10-03

## Context

WD-002 DIB preflight is blocked after the Owner-corrected Q7 semantics patch.

Current Q7 product meaning:

- Offline state is browse-only for keyboard configuration.
- Edit Configuration first tries to connect the keyboard.
- If the keyboard remains disconnected, Windows must not enter keyboard configuration edit state.
- Device-write actions remain disabled while disconnected.

## Owner Approval

Owner response in chat:

`我批准`

## Authorized Scope

Approved only:

- DLA may attempt a narrow Harness route-repair/recovery pass for WD-002.
- The repair target is limited to resolving the protected `start-fingerprint.json` / Q7 approval reconcile blocker.
- DLA may record evidence and Harness feedback for the recovery attempt.

Not approved by this record:

- Java implementation changes.
- Firmware or eternal workspace changes.
- Build, installer, flashing, Release Batch, or device write.
- Git add, commit, push, reset, clean, stash, or checkout.
- Declaring WD-002 DIB preflight restored unless it actually passes.
- Declaring builder submission, DLA review, machine checks, Git candidate, Owner test packet, or Owner UAT PASS.

## Result So Far

After approval, DLA retried the supported route helper and confirmed it still stops on protected origin mismatch. DLA did not bypass the guard and did not claim restoration.
