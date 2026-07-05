# Portable Keypad Integration

## Placement

The portable keypad work is split into two layers:

```text
sdks/portable-keypad/
plugins/keysilk-keypad/
```

`sdks/portable-keypad` contains the device SDK. It owns KeySilk / COIDEA config
parsing, config generation, host-action profiles, and embedded companion trigger
planning.

`plugins/keysilk-keypad` is the AhaKey plugin wrapper. It runs inside the
existing `plugin.json` + JSON-RPC plugin model and exposes KeySilk capabilities
to the AhaKey host.

## Why Not Put It In Existing Device Services

The Windows Java/Python and macOS device services target AhaKey's own device
protocol: modes, OLED frames, BLE/TCP bridge commands, and custom key commands.
KeySilk uses a different factory config format with raw `.bin` records and
host-action triggers.

Keeping KeySilk in a portable keypad SDK avoids mixing two unrelated device
protocols in the same service classes and lets future keypad adapters reuse the
same plugin surface.

## Current Plugin Surface

The `keysilk-keypad` plugin currently exposes:

```text
keysilk/listAdapters
keysilk/getLayout
keysilk/getBindings
keysilk/getCapabilities
keysilk/validateCompanionProfile
keysilk/getCompanionTriggers
keysilk/installCompanionProfile
keysilk/uninstallCompanionProfile
```

The companion profile installer registers the SDK hotkey trigger plan with the
host. When a hotkey fires, the host calls the plugin's `keysilk/hotkeyTriggered`
method, and the plugin dispatches the action through host methods.

## Host APIs Needed Next

To make companion actions run automatically when AhaKey Desktop starts, the host
should add permission-gated methods such as:

```text
host/hid/list
host/hid/readConfig
host/hid/writeConfig
```

The macOS plugin host now has the first five runtime methods:

```text
host/openUrl
host/openPath
host/pasteText
host/registerGlobalHotkey
host/unregisterGlobalHotkey
```

The remaining HID methods are still needed before the plugin can write KeySilk
configs directly through AhaKey Desktop.

The runtime dispatch path is:

```text
hotkey -> plugin -> SDK companion runtime -> host/openUrl or host/pasteText
```

The current smoke-test UI is in `PluginShowcase`: click
`Install KeySilk Baidu Hotkey` to register a sample `Ctrl+Alt+Shift+B` profile.
See `docs/keysilk-keypad-test-plan.md` for the full test flow.

For Bluetooth daily use, use the hotkey trigger pool. USB/2.4G can also support
raw host-action report prefixes once the host exposes HID/RawInput events.
