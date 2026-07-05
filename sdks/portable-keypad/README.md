# Portable Keypad SDK

CommonJS SDK for configuring supported small keyboards. The current adapter
targets the KeySilk / COIDEA 3-key + 1-knob device.

## Supported Device

```text
Adapter: keysilk_v1
Brand: KeySilk / COIDEA
VID/PID: 4132:2107
Layout: keysilk_3key_1knob
Config HID interface: UsagePage=0xff00 Usage=0x0001
```

## Use From This Repository

```js
const sdk = require("./sdk");
```

Repository-level runnable examples live in:

```text
examples/
```

## Device Flow

```js
const sdk = require("./sdk");

const devices = sdk.listDevices();
const config = sdk.readDevice(devices[0]);

sdk.setActionBinding(config, {
  scope: "extended",
  action: "knob1.rotate_right",
  binding: "B",
});

sdk.writeDevice(config);
```

## Offline Flow

```js
const fs = require("fs");
const sdk = require("./sdk");

const raw = fs.readFileSync("config.bin");
const config = sdk.importConfig(raw, { adapter: "keysilk_v1" });

sdk.setActionBinding(config, {
  scope: "base",
  action: "key1.press",
  binding: "Alt",
});

fs.writeFileSync("out.bin", sdk.exportConfig(config));
```

## Apply A UI Model

```js
const model = {
  adapter: "keysilk_v1",
  layout: "keysilk_3key_1knob",
  base: {
    "key1.press": "Alt",
  },
  extended: {
    "knob1.rotate_right": "B",
  },
};

sdk.applyBindingModel(config, model);
```

## Host-Assisted Open URL

Open URL actions require a companion app on Windows. The keypad stores a
host-action trigger; the URL is stored by the integrating app or companion
profile.

```js
const fs = require("fs");
const sdk = require("./sdk");

const config = sdk.importConfig(fs.readFileSync("current.bin"));

sdk.setHostOpenUrlAction(config, {
  scope: "extended",
  action: "key1.press",
  url: "https://www.example.com/",
});

fs.writeFileSync("open_example.bin", sdk.exportConfig(config));
fs.writeFileSync(
  "open_example.profile.json",
  JSON.stringify(sdk.exportHostActionProfile(config), null, 2),
);
```

CLI equivalent:

```powershell
node tools\keysilk-cli.js set-url analysis\current_after_baidu_user.bin key1.press https://www.example.com/ analysis\open_example.bin analysis\open_example.profile.json
node tools\keysilk-cli.js write-noack analysis\open_example.bin
node tools\keysilk-cli.js url-companion-profile analysis\open_example.profile.json 300
```

## Bluetooth-Compatible Open URL

In Bluetooth mode the factory host-action trigger is not exposed through
Windows RawInput. Use the hotkey companion mode instead: the keypad emits a
reserved shortcut and the companion opens the URL/path.

```js
sdk.setHotkeyOpenUrlAction(config, {
  scope: "extended",
  action: "key1.press",
  url: "https://www.example.com/",
});
```

CLI equivalent:

```powershell
node tools\keysilk-cli.js set-hotkey-url analysis\current.bin key1.press https://www.example.com/ analysis\open_example_bt.bin analysis\open_example_bt.profile.json
node tools\keysilk-cli.js write-noack analysis\open_example_bt.bin
node tools\keysilk-cli.js hotkey-companion-profile analysis\open_example_bt.profile.json 300
```

## Companion Text Paste

Text paste uses the same Bluetooth-compatible hotkey path. The text is stored in
the companion profile and pasted at the current cursor.

```powershell
node tools\keysilk-cli.js set-hotkey-text analysis\current.bin key1.press "hello from KeySilk" analysis\hotkey_text.bin analysis\hotkey_text.profile.json
node tools\keysilk-cli.js write-noack analysis\hotkey_text.bin
node tools\keysilk-cli.js hotkey-companion-profile analysis\hotkey_text.profile.json 300
```

## Embedded Companion Runtime

If the SDK is embedded into a larger desktop app, the app does not need to ask
users to download or start a separate companion process. Start companion support
when the plugin/app loads:

```js
const sdk = require("@ahakey/portable-keypad-sdk");

const profile = sdk.exportHostActionProfile(config);
const validation = sdk.validateCompanionProfile(profile);
if (!validation.ok) throw new Error(validation.errors.join("; "));

const triggers = sdk.getCompanionTriggers(profile);

// Register these with the host app's native global-hotkey layer.
for (const trigger of triggers.hotkeys) {
  registerGlobalHotkey(trigger.hotkey, () => {
    sdk.handleCompanionHotkey(profile, trigger.hotkey, {
      openUrl: (url) => shell.openExternal(url),
      openPath: (path) => shell.openPath(path),
      pasteText: (text) => pasteTextAtCursor(text),
    });
  });
}

// Register these with the host app's RawInput/HID listener for USB/2.4G.
for (const trigger of triggers.rawReports) {
  registerRawReportPrefix(trigger.reportPrefixHex, (reportHex) => {
    sdk.handleCompanionRawReport(profile, reportHex, {
      openUrl: (url) => shell.openExternal(url),
      openPath: (path) => shell.openPath(path),
    });
  });
}
```

The current CLI companion is only a prototype runner for repository testing. A
shipping product should embed this runtime contract and keep the native event
listeners inside the main app or plugin host.

## Public API

```text
listAdapters()
listDevices()
readDevice(device)
writeDevice(config)
importConfig(raw, options)
exportConfig(config)
getLayout(deviceOrConfig)
getBindings(deviceOrConfig)
getCapabilities(deviceOrConfig)
getActionBinding(config, actionId, options)
setActionBinding(config, request)
applyBindingModel(config, model)
setHostOpenUrlAction(config, request)
setHostOpenPathAction(config, request)
setHotkeyOpenUrlAction(config, request)
setHotkeyOpenPathAction(config, request)
setHotkeyTextAction(config, request)
setSimpleMacroTapsAction(config, request)
exportHostActionProfile(config)
normalizeCompanionProfile(profile)
validateCompanionProfile(profile)
getCompanionTriggers(profile)
dispatchCompanionAction(action, host)
handleCompanionHotkey(profile, bindingOrHotkey, host)
handleCompanionRawReport(profile, reportHex, host)
```

## Supported Actions

```text
key1.press
key2.press
key3.press
knob1.rotate_left
knob1.press
knob1.rotate_right
knob1.press_rotate_left
knob1.press_rotate_right
```

## Supported Bindings

```text
Hardware verified:
  Ctrl Alt A B Esc Enter Space
  Mute VolumeDown VolumeUp PlayPause
  NextLayer PreviousLayer
  HostOpenUrl HostOpenPath
  MouseLeftClick MouseRightClick MouseMiddleClick
  MouseWheelUp MouseWheelDown
  CtrlMouseWheelUp CtrlMouseWheelDown
  simple macro taps via setSimpleMacroTapsAction()

Observed in captured configs:
  Digit2 Digit3 Digit4 Digit5 Digit6 Digit7 Digit8
  TextObserved
  OpenCalculatorObserved

Inferred, pending batch hardware verification:
  C-Z
  Digit0 Digit1 Digit9
  Shift Win
  CtrlA CtrlC CtrlV CtrlX CtrlZ CtrlY CtrlS CtrlP CtrlF
```

`getBindings()` returns `verification` metadata for each binding:

```js
const bindings = sdk.getBindings(config);
console.log(bindings.CtrlC.verification); // inferred
```

## Notes

- `writeDevice()` defaults to the no-ACK write path because it has been more
  reliable with the current sample device.
- Extended record creation has been hardware-verified for all 8 actions on the
  current KeySilk sample.
- Host-assisted open URL is supported through `HostOpenUrl` plus a companion
  listener. It is not a standalone device-side URL launcher.
- Host-assisted open file/program path is supported through `HostOpenPath` plus
  a companion listener. The path is stored in the companion profile, not in the
  keypad config.
- Bluetooth-compatible open URL/path is supported through a reserved hotkey pool
  (`CtrlAltShiftB` through `CtrlAltShiftI`) plus the embedded companion runtime.
- Host-side text paste is supported through the same reserved hotkey pool plus
  the embedded companion runtime.
- Config writes are supported through USB or the factory-supported wireless
  configuration path. Bluetooth config writes are not supported by this adapter.
- Mouse button, wheel, and simple macro tap writes are hardware verified for
  captured variants. Text-slot records are parsed from captured configs, but
  SDK writes remain disabled until the encodings are hardware verified.
- Built-in host open actions can be parsed. Standalone device-side open-program
  path storage is not implemented yet.
