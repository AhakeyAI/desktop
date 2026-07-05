# KeySilk Portable Keypad Plugin

This plugin is the AhaKey host-facing wrapper for the portable keypad SDK.

The SDK package in `sdks/portable-keypad` owns KeySilk config parsing,
configuration generation, host-action profiles, and companion trigger planning.
This plugin owns the JSON-RPC surface exposed to AhaKey Desktop.

Current status:

- exposes SDK capabilities for the KeySilk / COIDEA 3-key + 1-knob adapter
- validates host-action profiles
- returns embedded companion trigger plans
- installs companion profiles by registering the reserved hotkey pool with the
  AhaKey host
- dispatches hotkey companion actions through `host/openUrl`, `host/openPath`,
  and `host/pasteText`
- leaves USB/2.4G raw report listening and HID config writes to future host
  APIs

Plugin methods:

```text
keysilk/listAdapters
keysilk/getLayout
keysilk/getBindings
keysilk/getCapabilities
keysilk/validateCompanionProfile
keysilk/getCompanionTriggers
keysilk/installCompanionProfile
keysilk/uninstallCompanionProfile
keysilk/hotkeyTriggered
```

Build:

```bash
npm install
npm run build
```
