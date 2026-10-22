# Integrated firmware update contract

The UI validates the approved 1.4.8 / protocol 3.2 CH582 package before offering
an update. Same-version reinstall is under Advanced and requires confirmation.
Custom HEX selection validates the file but does not authorize flashing it.
Unknown hardware, missing USB identity, mismatched package or unavailable
components block programming. BLE is never a firmware transport.

The owner package SHA-256 is
`2A09C21EEBE764390DD2CBC55C5BF7411C2A641DB6F120125D21B66D9C93DD0C`.
Provenance references firmware source commit
`f1903791f2119d02f71eb92afe9efbb360edb06a`.
Firmware assets are excluded from Git and are not authorized for public release.

## Dependencies and operation

Studio is self-contained .NET x64. Firmware programming additionally uses the
official WCHISPTool components and CH375_A64 driver. The MSI detects the driver;
Studio verifies the pinned vendor binary hashes and offers explicit component
setup. Missing components do not prevent ordinary BLE use. Vendor executables
and driver packages are not redistributed. Driver installation may require UAC.

The user-confirmed entry procedure is: switch the device off and disconnect
power; hold Record; connect USB while holding Record; release after a few
seconds. The app waits for a unique WCH ISP device. This procedure does not
authorize starting it automatically.

The update owns the operation gate, suspends reconnect/integrations, saves the
target and package hashes, disconnects the normal session, and stages a verified
image. A hidden worker owns a cross-process file lock during the vendor operation.
No automatic retry, forced termination, or cancellation during programming is
offered. A durable journal records transitions and exposes recovery after an
interruption. A failure is not relabeled successful simply because the process
exited. Success requires the vendor terminal success record and expected exit
code, then reappearance of the same application identity and matching 00/9F
firmware, model, protocol and capability fields.

The vendor backend is prepared in software but awaits the explicitly approved
physical same-version reinstall. Its actual completion/exit behavior and
physical recovery are not yet certified. A long-running vendor worker is allowed
to finish rather than being killed at a timeout.

## Data and recovery limits

Code flash is replaced. DataFlash clearing is disabled in the prepared vendor
configuration, but preservation of device settings/assets is not a promise:
there is no full physical configuration or pixel backup. External flash capacity
alone never proves firmware mapping/migration compatibility. Recovery uses the
same validated package and saved target; it never switches to arbitrary firmware.
Studio reports recovery-required state rather than claiming rollback.
