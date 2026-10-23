# WD-003 Owner Scope Approval - UsbHidTransport preview defect repair

Date: 2026-10-06
Change: WD-003
Role: DLA
Mode: DEFECT_TRIAGE / SCOPE_RECONCILE

## Owner Authorization

Owner authorized proceeding with the DLA-proposed repair direction:

```text
可以按照你的来搞吧
```

This approval is interpreted narrowly as permission to repair the WD-003 Owner Preview FAIL caused by Windows selecting the wrong USB HID interface for configuration traffic.

## Effective Scope Addition

Add this production source file to WD-003 `allowed_paths`:

```text
src/main/java/com/example/ahakey/service/UsbHidTransport.java
```

## Boundaries

The repair is limited to selecting the correct AhaKey USB vendor/config interface for existing configuration commands.

Allowed:

- Fix USB HID device-path selection so configuration commands use the vendor/config interface, expected as `mi_01`.
- Remove or avoid the current behavior where `mi_00&col02` can be selected as a configuration channel.
- Optionally add a narrow non-destructive capability/probe check if needed to skip wrong HID collections.

Not allowed:

- No change to approved `0x87`, `0x97`, `0x9F`, or `0x95` protocol semantics.
- No firmware changes.
- No installer build, installation, device write, or flashing.
- No Git add, commit, push, reset, clean, or stash.
- No unrelated BLE/USB rewrite or UI/product scope expansion.

