# KeySilk Keypad Test Plan

This document verifies the KeySilk portable keypad SDK after it is integrated
into the AhaKey `vibebar` branch.

## 1. SDK Package Check

Run on Windows or macOS:

```powershell
cd C:\Users\20825\Desktop\codex\ahakey-desktop-vibebar\sdks\portable-keypad

node --check index.js
node --check companion-runtime.js
node --check core\device-model.js
node --check adapters\keysilk-v1\adapter.js
node --check adapters\keysilk-v1\config-codec.js

$env:npm_config_cache="C:\Users\20825\Desktop\codex\ahakey-desktop-vibebar\.npm-cache"
npm pack --dry-run
```

Expected:

```text
package: @ahakey/portable-keypad-sdk@0.1.0
total files: 17
```

Clean the temporary npm cache if needed:

```powershell
cd C:\Users\20825\Desktop\codex\ahakey-desktop-vibebar
Remove-Item .npm-cache -Recurse -Force
```

## 2. Plugin Build Check

The KeySilk plugin depends on the local AhaKey plugin SDK and portable keypad
SDK.

```bash
cd /path/to/ahakey-desktop-vibebar/sdks/typescript
npm install
npm run build:sdk

cd ../../plugins/keysilk-keypad
npm install
npm run build
```

Expected:

```text
plugins/keysilk-keypad/dist/main.js
```

## 3. AhaKey Plugin Host Load Check

This step needs macOS with Swift available, because the current plugin host is
implemented in `ahakeyconfig-mac`.

```bash
cd /path/to/ahakey-desktop-vibebar
export AHAKEY_PLUGINS_DIR="$PWD/plugins"
swift run --package-path ahakeyconfig-mac PluginShowcase
```

Expected in the Plugin Showcase window:

- `KeySilk Portable Keypad` appears under `Loaded Plugins`
- method list includes `keysilk/installCompanionProfile`
- activity log includes `keysilk-keypad plugin online`

## 4. Minimal Companion UI Test

The Plugin Showcase now has a smoke-test button for the KeySilk companion
runtime.

Steps:

1. Complete the plugin build check.
2. Start `PluginShowcase` with `AHAKEY_PLUGINS_DIR="$PWD/plugins"`.
3. Click `Reload Plugins`.
4. Click `Install KeySilk Baidu Hotkey`.
5. Press `Ctrl+Alt+Shift+B`.

Expected:

- the install button returns JSON containing an installed hotkey token
- pressing `Ctrl+Alt+Shift+B` opens `https://www.baidu.com/`

To clean up:

1. Click `Uninstall KeySilk Hotkeys`.
2. Press `Ctrl+Alt+Shift+B` again.

Expected:

- Baidu no longer opens through the KeySilk plugin hotkey registration

## Current Boundary

This test covers the software-side companion path:

```text
reserved hotkey -> AhaKey host -> keysilk/hotkeyTriggered -> SDK companion runtime -> host/openUrl
```

It does not yet test writing KeySilk config through AhaKey Desktop. That still
requires host HID APIs:

```text
host/hid/list
host/hid/readConfig
host/hid/writeConfig
```

