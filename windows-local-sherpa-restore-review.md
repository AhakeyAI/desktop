# Windows local Sherpa voice restoration review

DATE=2026-09-16
BRANCH=voice-k1-local-input-restore
BASELINE=0aefda71c3fc0bbc956846879be5de7955090782

## Scope

This change restores the verified historical local Sherpa-ONNX Paraformer backend
to the current desktop application.  K1/F18 routing, the 350 ms state machine,
Shortcut Editor, firmware, BLE/GATT, Approval, Hook, WCHISP, OLED/GIF and lighting
contracts were not redesigned or changed.

## Historical versus current chain

The historical `release-private/AhaKeyStudio-voice-baseline.zip` contains
`sherpa-onnx-java-api-1.13.3.jar`, `encoder.int8.onnx`, `decoder.int8.onnx`,
`tokens.txt`, `silero_vad.onnx`, and the x64 native DLLs.  Its production chain is
`VoiceInputManager -> SpeechService -> LibraryLoader -> OnlineRecognizer /
OnlineStream -> text -> KeyboardInjector`.

The old current branch instead referenced the unavailable `model_q8.onnx` through
Microsoft ONNX Runtime.  The restored implementation uses the historical streaming
Paraformer model and keeps the public manager lifecycle (`initialize`,
`startRecording`, `stopRecording`, `shutdown`) unchanged.  VAD remains opt-in and is
off by default, so the first release is explicit press-to-record/release-to-stop.

## Changed files

- `ahakeyconfig-win-java/pom.xml`: pins the historical Sherpa API vendor JAR,
  copies it to `target/lib`, and puts it on the executable JAR class path.
- `ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/SpeechService.java`:
  replaces the unavailable SenseVoice/model_q8 implementation with Sherpa online
  Paraformer, microphone PCM16 streaming, endpoint handling, and bounded release.
- `ahakeyconfig-win-java/src/main/java/com/example/ahakey/sherpa/LibraryLoader.java`:
  loads x64 sidecar/native resources from an explicit property, environment, installed
  app layout, or classpath extraction, with complete failure causes.
- `ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/VoiceInputManager.java`:
  invokes the no-argument Sherpa initialization and propagates initialization failure
  instead of claiming a usable service.
- `ahakeyconfig-win-java/src/main/java/com/example/ahakey/config/ModelConfig.java` and
  `src/main/resources/model_config.properties`: declare the Sherpa model tree,
  sample rate, thread count and opt-in VAD.
- `ahakeyconfig-win-java/src/main/java/com/example/ahakey/App.java`: labels the
  initialization path as Sherpa and retains the complete exception cause in logs.
- `ahakeyconfig-win-java/third-party/sherpa-onnx-java-api-1.13.3.jar`: version-pinned
  API artifact used by Maven and the packaged application.
- `build-release-installer.ps1`: stages the four model files and extracts the three
  historical native DLLs from the authorized baseline JAR into
  `app/lib/sherpa-onnx/native/win-x64`.
- `preview-part3-release-overlay.ps1`: compiles and allowlists the current
  `LibraryLoader` alongside `SpeechService`.
- `Test-ReleaseArtifactContents.ps1` and its Java test: require the Sherpa classes,
  model configuration, and (when a release input is supplied) all model/API/native
  sidecars.
- `src/test/java/com/example/ahakey/service/SpeechServiceTest.java`: covers config,
  complete model directory admission, legacy single-file rejection, and empty-file
  rejection.
- `AGENTS.md` and `docs/windows-stabilization-plan.md`: record the deployed resource
  layout, historical restore, test evidence, and validation limits.

## Verification evidence

HISTORICAL_SHERPA_SPIKE=PASS (JDK17 x64; native load, Paraformer recognizer creation,
and WAV decode against the archived model assets)
MAVEN_CLEAN_TEST=290 tests, 0 failures, 0 errors, 0 skipped
MAVEN_CLEAN_PACKAGE=BUILD SUCCESS
JAR_CONTENTS=RELEASE_ARTIFACT_CONTENTS=OK
SHERPA_RELEASE_INPUT_STAGING=OK (temporary baseline staging test)
POWERSHELL_SYNTAX=OK (11 project scripts)
GIT_DIFF_CHECK=PASS

## Frozen and outstanding checks

FIRMWARE_CHANGED=NO
F18_CHANGED=NO
BLE_CHANGED=NO
GATT_CHANGED=NO
APPROVAL_CHANGED=NO
HOOK_CHANGED=NO
WCHISP_CHANGED=NO

The current source JAR intentionally does not embed the hundreds of megabytes of
model binaries or native DLLs.  A formal installer still needs the authorized
baseline assets, jpackage/WiX, and a signed release environment.  Real microphone
capture, F18 HID delivery, Windows hook behavior, text injection, and end-to-end
old/new firmware hardware checks remain pending; automated tests and the historical
Sherpa spike do not constitute hardware validation.
