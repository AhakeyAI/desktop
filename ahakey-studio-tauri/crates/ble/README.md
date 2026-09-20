# Native BLE transport

`ahakey-ble` uses btleplug's native WinRT, CoreBluetooth and BlueZ implementations.
It requires no separate bridge, TCP listener or driver application. The Windows
crate has been compiled and unit-tested; macOS/Linux and physical-device acceptance
must be tested separately. macOS applications require a Bluetooth usage description
and permission; Linux requires a running BlueZ service and D-Bus access.

Create one `BleClient::new().await` handle per application, subscribe to its
broadcast events, then expose explicit scan, connect, disconnect and configuration
actions in the UI. `scan(Duration)` only discovers advertisements. Save the chosen
`DeviceInfo.id` in the application's local settings and use `reconnect(id)` on the
next launch; IDs are OS-local and cannot be transferred between platforms. If no
adapter is available, show the initialization error and offer retry.

`Ready` requires all three firmware characteristics (7341 data, 7343 commands,
7344 notifications), a successful subscription and a valid 13-byte status response.
The service checks connectivity every three seconds and requests fresh status about
every fifteen seconds; no valid response for 45 seconds clears stale telemetry and
reports an error. A dropped link never becomes a fake zero-percent battery.
Reconnect is bounded to three attempts. No adapter reset, pairing removal or
unbounded background reconnection is performed.

All writes use acknowledged GATT requests. Config batches and periodic status
queries share a write gate. `save_profiles` validates all four profiles before
writing the 39-frame batch; each has four raw-HID key mappings and nine AI-state
light effects, indexed by firmware state 0..8. Typical voice usages are F17=0x6C
and F18=0x6D, Enter=0x28, Escape=0x29 and Backspace=0x2A. Modifier usages E0..E7
precede the base key usage. Descriptions are printable ASCII, capped at 20 bytes.
Save completion proves acknowledged writes, not persistence after power cycling.
Brightness, mode, light-effect and IDE-state methods are nonpersistent until a
save command is included in a profile batch.

Await `disconnect()` during application shutdown. It cancels pending connection
and write operations, joins the notification worker, unsubscribes and detaches with
timeouts. A monotonic generation blocks notifications and retries from obsolete
sessions. Dropping the handle cancels its worker as a fallback, but does not replace
the explicit asynchronous shutdown path.

Run `cargo test` and `cargo clippy --all-targets -- -D warnings` from this crate.
Tests exercise byte-for-byte protocol vectors, strict status parsing, generation
isolation and cancellation without scanning or writing a real device.
