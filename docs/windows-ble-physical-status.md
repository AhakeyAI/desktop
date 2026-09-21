# Windows BLE physical status investigation — 2026-09-19

Branch: `eternal-dev`. Scope: Windows Java client and C# BLE TCP bridge.
No firmware flashing, localization or voice-model changes.

## Confirmed root cause

`BLE_tcp_bridge/TcpServer.cs::OnBleNotify` recognized the **13-byte** legacy
`AA BB 00 <8 status bytes> CC DD` notification, updated `_deviceStatus`, logged
the correct fields, then **returned without broadcasting it**. This explains
why the bridge could show battery 98 / signal 50 / firmware 1.0 / mode 2 /
light 0 / switch 0 while Java never received the physical response.

Java expects that original notification in TCP `BLE_NOTIFY (0x81)`, not in
`BLE_STATUS_RESP (0x82)`. The latter contains connection metadata only.
The Java parser already accepts the legacy status; no firmware upgrade or
new status format is required for this path. A 14-byte extended status did
not match the bridge's exact-length filter and was already forwarded.

Fix: retain cache/log updates, remove the early return, and forward the
original notification unchanged using the existing `0x81` broadcast path.
Do not convert cached `0x83` or link-only `0x82` into fresh physical status.
Recovery, session invalidation, timing gates and approval semantics remain.

## End-to-end path

1. `BleManager.queryStatus()` (poll: 750 ms) or `queryStatusAndWait(timeout)`
   enters the shared fair transaction lock and `PhysicalStatusFreshness`.
2. `sendPhysicalStatusQuery()` builds `AA BB 00 CC DD` using
   `AhaKeyProtocol.queryDeviceStatus()`. BLE wraps it as
   **`02 05 00 AA BB 00 CC DD`** and writes/flushes TCP.
3. `TcpServer.ClientLoop` reads exactly a 3-byte header and its advertised
   body. `HandlePacket(WriteCommand)` writes the body to GATT **0x7343**
   through `BleCore.WriteDataToCharacterstuc` (20-byte chunks).
   Service is **0x7340**, data characteristic **0x7341**, notify **0x7344**.
4. Device response arrives at `BleCore.Characteristic_ValueChanged`, which
   copies the WinRT buffer and emits `ReceiveNotifyData`.
5. `TcpServer.OnBleNotify` caches recognized legacy status and now broadcasts
   its original bytes as `0x81`, including the AhaKey header/trailer.
6. `BleManager.startReader` reads the TCP header/body exactly;
   `handlePacketFromReceiver` captures `System.nanoTime()` before dispatch.
   `dispatchPacket(0x81)` calls `onBleNotify`, validates framing, then calls
   **`AhaKeyProtocol.parseDeviceStatus`** (not the generic ACK parser).
7. Java updates `DeviceStatus`, wall-clock `lastStatusUpdateTime` and the
   session-local status sequence. `recordPhysicalStatus` accepts freshness
   only for the active query/session, connected device, `WAITING` state and
   `receivedAtNanos > writeCompletedAtNanos`. It captures the approval switch
   snapshot and signals the waiting query. Receiving a frame alone is not
   equivalent to accepting approval freshness.
8. Without this notification, the wait becomes `TIMED_OUT_UNRESOLVED`;
   Java schedules single-flight recovery, invalidates receiver/session and
   rebuilds TCP after its bounded delay. `0x82` cannot resolve that wait.

## TCP types and framing

Both `Protocol.cs` and `BleTcpPacket.java` use
`[type:u8][payloadLength:u16 little-endian][payload:N]`. Length excludes the
3-byte TCP header. TCP read loops handle fragmented/coalesced socket reads.
TCP packet types and embedded firmware command IDs are separate namespaces:
outer `0x82` is link metadata, inner `0x82` is an image-update command.

| Type | Direction | Payload / role | Physical freshness |
|---|---|---|---|
| `0x01 WRITE_DATA` | Java → bridge | Raw GATT 0x7341 data, bridge chunks at 200 bytes | No |
| `0x02 WRITE_COMMAND` | Java → bridge | Full AhaKey command frame to GATT 0x7343 | Starts query for inner `0x00` |
| `0x03 QUERY_BLE_STATUS` | Java → bridge | Empty, asks bridge about link | No |
| `0x04 QUERY_DEVICE_INFO` | Client → bridge | Empty, reads `_deviceStatus` cache; not Java physical polling | No |
| `0x81 BLE_NOTIFY` | Bridge → Java | Original GATT notification, including `AA BB … CC DD` | Only valid inner `0x00`, with timing/session checks |
| `0x82 BLE_STATUS_RESP` | Bridge → Java | `connected, nameLen, UTF-8 name, macLen, MAC, isTarget` | No; tracks link and invalidates old state on link transition |
| `0x83 DEVICE_INFO_RESP` | Bridge → client | 8 cached bytes below; no timestamp or request ID | No; Java currently accepts this metadata only on USB |

`BleStatusInfo` holds connected/name/MAC/target-characteristic readiness.
`DeviceStatusInfo` holds eight byte fields; `BuildDeviceInfoPacket` serializes
them in the same order as the legacy physical status payload:

| Physical frame offset | Cached payload offset | Meaning | Reported value |
|---|---|---|---|
| 3 | 0 | battery percentage | `62` = 98 |
| 4 | 1 | signal | `32` = 50 |
| 5 | 2 | firmware major | `01` |
| 6 | 3 | firmware minor | `00` |
| 7 | 4 | work mode | `02` |
| 8 | 5 | light mode | `00` |
| 9 | 6 | physical switch (`0` AUTO, `1` MANUAL; other values unknown) | `00` |
| 10 | 7 | bridge calls it reserve; Java calls it brightness | not supplied in log; fixture uses `00` |

Expected TCP example (last payload byte is an explicit fixture assumption):

```text
81 0D 00 AA BB 00 62 32 01 00 02 00 00 00 CC DD
```

Fields above are single bytes, so endian conversion is irrelevant except
for the TCP length. Java interprets signal as signed byte; 50 is identical
in either interpretation. That does not affect this failure. Extended
status adds readiness at physical offset 11 (14-byte total): bit 0 BLE
link, bit 1 HID input, bit 2 USB config. Legacy status has no readiness
flags; Java already permits a fresh legacy response when bridge link is up.
The bridge still caches only the exact legacy 13-byte format; extended
notifications are forwarded intact and do not refresh its legacy `0x83`
cache. Java BLE physical polling does not consume that cache.

## Other command responses, modes and firmware capabilities

Generic command replies use `AA BB <cmd> <result> <payload> CC DD`.
`AhaKeyResponseParser.CommandResponse` reads result at offset 3 and payload
from offset 4. **Physical `0x00` status has no result byte**: offset 3 is
battery. `onBleNotify` correctly parses physical status before generic ACKs.
Ordinary command responses wake `waitForResponse`, not physical freshness.

| Inner command | Purpose / expected response |
|---|---|
| `0x00` | Physical query; 13-byte legacy / 14-byte extended status above |
| `0x90` | AI/task state update; 6-byte ACK result is not the physical switch |
| `0x92` | Set work mode; generic result ACK; physical mode also comes from `0x00` |
| `0x9B` | Mode sync/query; result + mode/source/optional sequence. Updates work mode, never freshness |
| `0x98` | Task display query `AA BB 98 CC DD`; successful response `AA BB 98 00 <mode:0 or 1> CC DD`; setter adds mode to request |
| `0x99`, `0x9A` | Task slot update and heartbeat; generic ACK path |
| `0x9F` | Capability query `AA BB 9F CC DD`; result + protocol major/minor, firmware major/minor, hardware revision, 32-bit LE capability mask, optional firmware patch/model |

`TaskActivityService.heartbeatAndReconcile` waits for connected device state,
then separately queries `0x98` and reports a task-display sync error if that
fails. `queryDeviceCapabilities()` separately waits for `0x9F`;
`requireStabilizedDeviceContract()` applies the firmware capability contract.
Neither reply is required by `sendPhysicalStatusQuery()` or
`PhysicalStatusFreshness`, and neither advances physical status freshness.
An unsupported generic command may return result 3 or never respond. Actual
support of `0x98`/`0x9F` on this particular firmware cannot be established
from the two version bytes in the supplied log; no firmware 1.0 source or
captured command replies were supplied. Unsupported optional commands may
cause separate feature failures, but are not needed to explain this bug.

## USB comparison

USB writes the same inner `AA BB 00 CC DD` command via HID.
`UsbHidTransport` extracts AhaKey frames from split/padded/multiple HID reports,
captures arrival time before extraction/dispatch, then `acceptUsbFrame`
feeds the same `onBleNotify` handler using logical type `BLE_NOTIFY`.
Both paths use the same parser, switch-state update, sequence and freshness
coordinator. USB has no C# status filter or TCP envelope. USB readiness uses
the USB config flag when available; BLE uses bridge connected plus BLE
readiness when available. USB deliberately retains the last BLE battery
percentage instead of treating charging voltage as state of charge.

## Diagnostics and regression checks

Java DEBUG logs now include full reassembled packet hex, type, length,
payload, transport, arrival time, session and receiver; parsed physical
fields, status wall-clock/sequence update; successful query write boundary;
freshness acceptance/rejection. Timeout/interruption and recovery scheduling
log the reason and coordinator state. Existing `logback.xml` already enables
DEBUG for the application. USB logs show a logical dispatch envelope, not
the original padded HID report.

Bridge logs include received TCP packet/payload hex and forwarded notify
payload. Existing legacy physical-field diagnostics remain.

`BLE_tcp_bridge/tests/Test-PhysicalStatus.ps1` compiles the **production**
`TcpServer.cs` and `Protocol.cs` with only Bluetooth hardware types/IO replaced
by test doubles. It uses a real loopback socket on an ephemeral port, checks
a fragmented query reaches the command characteristic, exact legacy `0x81`
output, preserved cached `0x83`, extended notifications and command replies.
Before the fix this test timed out waiting for the legacy notification;
after the fix all checks pass. No real device is accessed.

Java regression tests cover the reported firmware 1.0 fields over two
separate physical queries (AUTO then MANUAL), no recovery, sequence updates,
and rejection of ACK/malformed frames. Existing tests cover `0x82`/`0x83`
not satisfying freshness, extended frames, pre-write arrivals, late replies,
session isolation and actual lost-response recovery.

## Build and validation

Run from the repository root in PowerShell (paths reflect this machine):

```powershell
$env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot'
& 'C:\Tools\apache-maven-3.9.16\bin\mvn.cmd' -f .\ahakeyconfig-win-java\pom.xml -U package
# Focused packaging run after the full-suite result below:
& 'C:\Tools\apache-maven-3.9.16\bin\mvn.cmd' -f .\ahakeyconfig-win-java\pom.xml `
    '-Dtest=BleManager*Test,PhysicalStatusFreshnessTest,TaskActivityServiceTest,AhaKeyProtocolTest,UsbHidTransport*Test' package
.\BLE_tcp_bridge\tests\Test-PhysicalStatus.ps1
& 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe' `
    .\BLE_tcp_bridge\BLE_tcp_driver.csproj /restore /t:Rebuild `
    /p:Configuration=Release /p:Platform=AnyCPU `
    /p:OutputPath=bin\Release-physical-status\ /nologo /verbosity:minimal
git diff --check
```

The original `bin/Release/BLE_tcp_driver.exe` is held by a running process;
the fixed bridge is therefore built in `bin/Release-physical-status/`.
Initial Maven test dependency resolution had a transient Maven Central TLS
failure. `clean package` then hit a locked `target/lib/slf4j-api-2.0.9.jar`
from the running application; `package` is used to rebuild without stopping
it. Full suite: **302 tests, 1 failure, 0 errors, 0 skipped**. The sole failure
is unchanged `InspectorPaneVoiceActionChoicesTest` line 46: a source-text
assertion searches for `createShortcutEditor(\n            shortcutModel`,
but this Windows checkout uses CRLF. Read-only verification found the CRLF
pattern and the LF pattern after in-memory newline normalization; neither
the source nor the unrelated test was modified.

Focused packaging run: **47 tests, 0 failures, 0 errors, 0 skipped**,
`BUILD SUCCESS`, `RELEASE_ARTIFACT_CONTENTS=OK`. Bridge regression:
`BLE_PHYSICAL_STATUS_TESTS=PASS`; Release rebuild to the separate output
directory succeeded. `git diff --check` passed.

Artifacts:

* `ahakeyconfig-win-java/target/ahakey-studio-1.5.3.jar`
* `BLE_tcp_bridge/bin/Release-physical-status/BLE_tcp_driver.exe`

The running client/bridge have not been replaced or restarted, and hardware
regression is still pending. No claim of live device validation is made.

## Live follow-up after user closed applications (2026-09-19)

This section supersedes the hardware-pending statement above for the
physical-status forwarding/recovery regression only.

Rebuilt the bridge successfully into the normal `bin/Release/` directory
using the same MSBuild command without the `OutputPath` override. Bridge
regression passed again. Java packaging recompiled the application and
passed the same 47 focused tests plus `RELEASE_ARTIFACT_CONTENTS=OK`.
`clean` still could not remove the target directory itself; ordinary
`package` succeeded. No unrelated source/test was changed.

Started the rebuilt bridge using its saved AhaKey AE1E configuration.
A read-only socket probe made 20 status queries over one TCP connection:
**20/20** returned `0x81`, **17–131 ms** response time. Actual payload:
`AA BB 00 64 32 01 00 02 00 00 23 CC DD` (battery 100, signal 50,
firmware 1.0, mode 2, light 0, switch 0, brightness 35).

The first normal Java launch selected USB HID, so it was stopped; the user
unplugged USB and the visible Java client was restarted and connected to BLE.
The observation window was **11:11:42–11:15:32 Asia/Shanghai**:

* **1** BLE TCP connection, same live client socket at the end.
* **5** physical freshness acceptances in session 3.
* **0** physical response timeouts, recovery schedules or transport rebuilds.
* Parsed physical status remained connected with firmware 1.0 and switch 0;
  light changed from 0 to 1 during normal application activity.

This confirms the original reconnect loop is fixed on the actual device.
It does not establish a steady two-second polling cadence: a separate
legacy command/readback incompatibility was observed in the normal app:

```text
0x98 request: AA BB 98 CC DD
actual reply: AA BB 98 00 CC DD       (empty success ACK)
expected:     AA BB 98 00 <mode> CC DD

0x9F request: AA BB 9F CC DD
actual reply: AA BB 9F 00 CC DD       (empty success ACK)
expected:     AA BB 9F 00 <capability payload, >=9 bytes> CC DD
```

The bridge forwards both replies intact. Sixteen empty `0x98` ACKs and
one empty `0x9F` ACK were captured in the observation window.
`TaskActivityService` repeats the task-display query after its 15-second
response wait fails; the shared transaction lock delays status polling and
can make approval refresh fail closed while that command is pending.
`0x9F` reports `capability response unavailable`. This is direct evidence
that this device does not supply the readback contracts expected by the
current client, not proof that every firmware labelled 1.0 lacks them.
The separate task-display retry/capability behavior has not been changed
in this physical-forwarding fix, and no firmware was flashed.

Local evidence (ignored build output):
`BLE_tcp_bridge/bin/tests/live-ble-physical-status.json`,
`live-java-ble-status.log`, and `live-java-ble-summary.json`.
The last two contain only selected protocol diagnostics and a summary,
not unrelated Hook request content. The rebuilt GUI client and bridge
were left running for the user.
