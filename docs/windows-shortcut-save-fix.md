# Windows shortcut editing and save regression — 2026-09-19

## Confirmed causes and changes

- `Form1_Load` explicitly set BLE window opacity to `0.8`; it now uses `1.0`.
- The shortcut editor removed the base key from its temporary `KeyConfig`, then
  called a `StudioState` setter that rejected modifier-only/empty values. The
  exception interrupted rebuilding; subsequent rebuilds restored the previous
  persisted key. Draft validation now accepts these intermediate values, including
  after reload. Final save still requires a complete shortcut for active custom
  actions. F18 remains reserved. Runtime normalization no longer silently replaces
  an incomplete draft with Win+H; it emits nothing.
- The list hid left modifiers whenever the matching right modifier was present.
  Both sides are now displayed independently. An explicit Clear button removes all
  keys. The translated hint explains the existing protocol constraint: modifiers
  plus one base key, with a new base key replacing the old one.
- Save synchronously selected a transport and probed the firmware contract on the
  JavaFX thread, before setting the busy indicator. These potentially blocking
  operations now run in the background save transaction, before any writes. Failed
  validation sends no commands and retains dirty state. ACK/readback checks and
  recovery safety remain unchanged.
- K1 desktop actions were unnecessarily gated by the device configuration contract
  even though the production write plan excludes K1. A desktop-only edit now saves
  locally, including while disconnected, and acknowledges success only after the
  store succeeds. Mixed K1/device edits still require device validation and ACKs.
- The top toolbar forced every group into one scrollable row. Primary actions now
  stay in the first row; secondary groups wrap. This is a limited toolbar change,
  not a redesign of the keyboard canvas or the central pane's existing scrolling.

Local saving does not add firmware capabilities. The previously observed legacy
firmware lacks the required `0x98`/`0x9F` payloads. Physical F18 routing and device
configuration retain their existing compatibility requirements; no firmware was
flashed or included in this build.

## Validation

- Combined checkout (Russian UI plus physical-status and WCHISP fixes): **314 Java
  tests, zero failures/errors/skips**, Maven package and release contents PASS.
- Added model regressions for delete H -> modifiers -> clear -> Shift/Ctrl -> D,
  draft reload, incomplete active/inactive actions, and mixed local/device dirtiness.
- Added runtime regression: incomplete/F18 custom shortcuts emit neither Win+H nor
  any other keys. Added background-preflight tests: no writes before successful
  validation, and no completion/commands when validation fails.
- Explicit JavaFX smoke test fires the actual Add/Delete/Clear controls, saves a
  local Ctrl+Shift+D while disconnected, checks the persisted draft and incomplete
  save feedback, and renders the toolbar at widths 1024 and 1280 with bounds checks.
  It uses a temporary user home and simulation; no device connection is opened.
  The installed app occupied Hook port 8765, so the smoke instance logged a bind
  failure before shutting down its services; editor/save checks still passed.
- MSBuild Release, BLE localization test and physical-status loopback test PASS.
- Portable EXE/ZIP and WiX setup built; the installed/running app was not replaced.
  End-to-end physical shortcut execution is not part of this software-only check.

## Reproduction commands (PowerShell, repository root)

```powershell
$env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot'
& 'C:\Tools\apache-maven-3.9.16\bin\mvn.cmd' -f ahakeyconfig-win-java/pom.xml package
& 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe' BLE_tcp_bridge/BLE_tcp_driver.csproj /restore /p:Configuration=Release /verbosity:minimal
& ./BLE_tcp_bridge/tests/Test-Localization.ps1
& ./BLE_tcp_bridge/tests/Test-PhysicalStatus.ps1
$env:AHAKEY_STUDIO_SIMULATE_BLE = '1'
& 'C:\Program Files\AhaKeyStudio\runtime\bin\java.exe' '-Dfile.encoding=UTF-8' -cp 'ahakeyconfig-win-java/target/test-classes;ahakeyconfig-win-java/target/classes;ahakeyconfig-win-java/target/lib/*' com.example.ahakey.view.ShortcutEditorUiSmoke ./ahakeyconfig-win-java/target/shortcut-preview
Remove-Item Env:AHAKEY_STUDIO_SIMULATE_BLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./ahakeyconfig-win-java/build-local-windows.ps1 -RuntimeImage 'C:\Program Files\AhaKeyStudio\runtime' -IconPath 'C:\Program Files\AhaKeyStudio\AhaKeyStudio.ico' -JdkHome 'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot' -WixBin 'D:\dev\ahakey\desktop\.toolchain\wix314' -OutputRoot 'D:\dev\ahakey\builds\shortcut-ui-fix'
```

The local package retains the existing version 1.5.3 and packaging limitations:
unsigned, without speech-model/native speech assets, firmware, or vendor flasher.
