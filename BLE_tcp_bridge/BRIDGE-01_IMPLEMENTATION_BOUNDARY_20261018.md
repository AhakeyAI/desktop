# BRIDGE-01 Implementation Boundary

Date: 2026-10-18
Status: Owner-authorized source repair; bridge-local registration, not a Windows Harness admission or PASS.

## Source and runtime identity

- Shared Git root: `C:/Users/20825/Desktop/windows软件代码/desktop`
- Observed HEAD: `41c034171e60b2d4962b0adbe8f3cffbf80a0436` (`WD-004 AI runtime presentation candidate`).
- Bridge source files are tracked and clean at inspection time. The shared Git root has extensive unrelated pre-existing changes; no Git writes are authorized.
- Source hashes at intake:
  - `TcpServer.cs`: `C311670D0F172D9CB8CF9DB0AE4EAA55541689CB7CDDE84C7A447E3535104353`
  - `Program.cs`: `6C93E77D3939FBB96CD9659329850E841412C1C37CBF5C6C71B79D94AD26D25C`
  - `Form1.cs`: `5448D02312D6B6A32D4C6B1FE56A63083964316CE99ED07E55F566A31CAD8E07`
  - `BLE_tcp_driver.csproj`: `5A463247A0DA8C70D0D67154059D55E4457B15AA0596CF0F4A03E60D9EDB110A`
- The running process (PID 48192 at inspection) uses `C:/Users/20825/Desktop/windows软件代码/desktop/BLE_tcp_driver_package/BLE_tcp_driver.exe`.
- Runtime package EXE, bridge `bin/Release` EXE and `obj/Release` EXE are byte-identical: 52,736 bytes, version `1.0.0.0`, SHA-256 `9B8F8C9D18AE7EE93B71ED7C867E1CE1E60040EBC6832498F5F2D00DCBD6106E`, timestamp 2026-09-30 11:43:20. This verifies package/output identity only; build provenance against current source remains unproven.
- `BLE_tcp_driver.csproj` targets .NET Framework 4.7.2 and already references Windows SDK Contracts 10.0.26100.7705.

## Allowed scope

- Primary implementation files: `TcpServer.cs`, `Program.cs`.
- `Form1.cs` is used only to reject stale characteristic-discovery callbacks by connection generation and route startup control writes through the shared ordered queue.
- No target-framework or package changes. Any required dependency change or TCP protocol extension pauses for Windows DLA coordination.
- Offline diagnostics may be added only if needed and must be listed before implementation.

## Required behavior and exclusions

- Preserve existing TCP packet types and command payload semantics.
- Bound and serialize GATT write transactions across all TCP clients; keep fragments of each frame contiguous and preserve FIFO order.
- Fragment using verified negotiated MTU minus ATT overhead, capped to the characteristic value limit; conservatively use 20 bytes when the negotiated value is unavailable or too small.
- Distinguish WinRT `AsyncStatus` from `GattCommunicationStatus`; failed/canceled writes must not raise success callbacks or create synthetic firmware ACKs.
- Isolate queued and in-flight writes by connection generation; cancel stale queued work after disconnect/reconnect.
- Serialize concurrent TCP writes per client so notification/status frames cannot interleave.
- Add stage timing for TCP frame receipt, queue wait, each GATT fragment, total transaction, and TCP return writes, with relevant status/error and MTU/generation context.
- Keep `WriteWithResponse`; do not add WriteWithoutResponse or automatic retransmission.
- Existing TCP protocol has no write-result message. Do not invent one; document the smallest versioned extension needed for Windows DLA review if callers must receive transport failures.
- Do not connect to a device, stop processes, install, overwrite the runtime package or any `config_server.json`, or perform Git writes.

## Offline verification plan

- Review the final diff and confirm only the listed bridge source files plus this registration file changed.
- Run available source/build checks without launching the executable or touching runtime configuration.
- Report missing build tools or environment limits instead of changing project dependencies/framework.

## Implementation and check result

- Changed `TcpServer.cs`, `Program.cs`, `Form1.cs`, and this boundary record only; no TCP packet type, dependency, or target-framework change.
- Final source SHA-256:
  - `TcpServer.cs`: `0698DC8E8C4ED05F193F03EA75923285ADFFFE2477FF5C368DA8CA5D6AD3CFE9`
  - `Program.cs`: `B648C8B77E30276D9DEE36FCC133754A0EE041A96968913834E905F5E6CFA9D7`
  - `Form1.cs`: `0DEAA2A28E7EBCEAB7388974C2E64B5910D2572693C3657DF9DA8A54B7393930`
- `git diff --check` passed for the bridge scope.
- Offline build was attempted into `bin/OfflineCheck`, without launching the app. The first attempt could not start the x86 .NET task host. The current-architecture retry reached C# compilation but the classic project invocation did not resolve the already-restored `Microsoft.Windows.SDK.Contracts` references (`Windows.*` unresolved); no source compile result can therefore be claimed. No dependency or project-file workaround was made.
- Runtime package EXE fingerprint remained `9B8F8C9D18AE7EE93B71ED7C867E1CE1E60040EBC6832498F5F2D00DCBD6106E`; it was not overwritten. This remains a different artifact from the edited source and does not establish source provenance.
- No device connection, process termination, package/config write, or Git write was performed.

