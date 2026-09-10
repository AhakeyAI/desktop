# Native speech for AhaKey

`ahakey-speech` supplies microphone capture, a SenseVoice recognizer, local
provisional subtitles, and explicit model download/import. It runs in the
application process through CPAL and the **official** `sherpa-onnx` 1.13.7 Rust
wrapper/C API. No Java, C# driver, Python service, or ASR subprocess is used.
The library never starts capture or downloads weights on application startup.

## Application integration

Add `ahakey-speech = { path = "../crates/speech" }` to the Tauri Rust manifest.
All methods returning `Result` use `anyhow::Error`.

```rust,no_run
use ahakey_speech::{SessionConfig, SpeechEvent, SpeechSession};
use std::path::PathBuf;

let config = SessionConfig::new(PathBuf::from("app-data/models/sensevoice-int8-2024-07-17"));
let session = SpeechSession::start(config, |event| {
    // Enqueue only. The app associates this callback with its session generation.
    match event {
        SpeechEvent::Partial(text) => { /* update non-activating subtitle window */ }
        SpeechEvent::Final(text) => { /* gate by active generation/target before insertion */ }
        _ => {}
    }
})?;
// On key release, retain the handle until Final/Error/Cancelled:
session.finish();
# Ok::<(), anyhow::Error>(())
```

- `SessionConfig::new(model_dir)` defaults to the default microphone, four CPU
  threads, 800 ms preview spacing, and a 120 second recording cap. Set
  `device_name` to one of `input_devices()` or `None` for the OS default.
- Events are `Loading`, `Recording`, `Partial(String)`, `Recognizing`,
  `Final(String)`, `Error(String)`, and `Cancelled`. The callback runs on a worker
  and must enqueue quickly. It must not directly change UI widgets.
- `finish()` closes the microphone and requests finalization; `cancel()` or
  dropping an active handle closes capture and discards pending decode output.
  `is_finished()` indicates worker completion. Native inference in progress is
  allowed to finish; cancellation never inserts its result.
- The UI **must** associate callbacks with a monotonically increasing session
  generation, ignore all events from superseded sessions, and recheck that
  generation and the intended target before inserting final text. This closes
  cancellation races between worker callbacks and queued UI events. Partial
  text must never be injected. This library itself never injects text.
- Capture starts before a cold model load so the first words are retained. One
  verified model is retained for subsequent sessions, avoiding per-press reloads.
- `MicrophoneCapture::start(device_name, on_audio, on_error)` supplies 16 kHz mono
  `Vec<f32>` chunks for other backends (including cloud); `.stop(&mut self)` joins
  its owner thread. Callbacks must use bounded, nonblocking queues. Native
  hardware streams are created/dropped on their owning thread, including on
  platforms where `cpal::Stream` cannot move across threads.
- `Recognizer::new(RecognizerConfig { model_dir, threads })` verifies both files;
  `.decode(&samples, 16000)` is a synchronous native call for at most 30 seconds.
- `ModelStore::new(directory)` exposes `directory()`, cheap `is_installed()`,
  full `verify()`, `download(&cancel, progress)`, and
  `import_from(source, &cancel, progress)`. The latter two run on a blocking
  worker (`spawn_blocking` in async applications), and return the model path.
  The progress callback receives a fraction from 0.0 to 1.0.
- `CancellationToken::new()` is cloneable and exposes `cancel()` and
  `is_cancelled()`. Model transfers use HTTPS, a pinned source revision, exact
  size and SHA256, temporary sibling files, and atomic publication. Cancelled
  transfers remove their own temporary files, retaining installed files.

## Subtitle behavior and limits

SenseVoice INT8 understands Chinese, English, Japanese, Korean, and Cantonese.
It is an offline sentence recognizer. The provisional display is produced by
periodically decoding a rolling **12 second** window, then correcting the final
utterance on release. It is not a stateful streaming model. The leading `…`
means the preview shows the recent window, not the entire utterance.

Recording memory is capped (120 seconds by default, configurable from 1 to 300).
Final decoding covers all captured samples in at most 20 second segments and
prefers quiet boundaries. Continuous speech without pauses at such boundaries
can split a word; the final transcript can differ from provisional text.
The recognizer is CPU-only, with one to eight threads. A 64-tap anti-alias filter
normalizes microphone rates; stopping can discard its roughly 1 ms filter tail.

## Verified Windows native runtime

From this crate directory, in the same PowerShell process as Cargo:

```powershell
$env:SHERPA_ONNX_LIB_DIR = & .\scripts\prepare-runtime.ps1
cargo test --all-targets
cargo clippy --all-targets -- -D warnings
```

Preparation downloads only the engine and notices, **not** model weights. It
verifies the official ASR-only Windows x64 archive before every extraction:

```
sherpa-onnx-v1.13.7-win-x64-shared-MT-Release-no-tts-lib.tar.bz2
SHA256 ebbcb8e6ef5ba4fb2444810fb7cc8dc0154e66f84a2101bf7c5cbcc16ce497a9
https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.13.7
```

**Bundle every DLL from the returned `lib` directory beside the actual app
executable.** This includes `onnxruntime.dll`, `onnxruntime_providers_shared.dll`,
and `sherpa-onnx-c-api.dll` (plus any C++ API DLL supplied by the archive).
Bundle the generated `runtime/licenses/` directory as third-party notices.
Never ship `runtime/` wholesale: it also contains import libraries and archives.
Tauri `resources/` or PATH alone does not ensure correct DLL resolution: recent
Windows ships an older `System32/onnxruntime.dll`, which is incompatible with
this engine. This crate's `build.rs` also places DLLs beside Cargo test binaries.

The official crate can download its own archive if `SHERPA_ONNX_LIB_DIR` is
absent. Production builds must use the preparation step above to enforce the
pinned checksum and ASR-only artifact.

The C ABI structs and calls come from the same upstream release's maintained
`sherpa-onnx-sys` crate, not hand-authored struct layouts. Runtime 1.13.7 uses
ONNX Runtime 1.27.1; ship them as a matching set.

## Known-answer gate

Set these environment variables to an existing official bundle and WAV, then
run the explicit gate. It never opens a microphone and never downloads weights.

```powershell
$env:AHAKEY_TEST_MODEL_DIR = 'path-to-official-model-directory'
$env:AHAKEY_TEST_ZH_WAV = 'path-to-official-test_wavs\zh.wav'
cargo test --release --test known_answer -- --ignored --nocapture
```

The test requires the exact Chinese sentence `开饭时间早上9点至下午5点。`, measures
native load/inference time, and checks multiple changing provisional results.
Default unit tests cover resampling continuity, alias suppression, long-speech
memory/segment bounds, cancellation after decode, and rejected model imports.

The model pin matches the Windows transition client: model file 239,233,841
bytes, tokens 315,894 bytes; hashes are in `src/model.rs`. Weights are optional
application data. An import reuses this exact existing bundle after verification.

## Other desktop platforms

CPAL and the official bindings have macOS/Linux backends. On those hosts, prepare
the corresponding official **1.13.7** shared library archive, verify its GitHub
release SHA256, and set `SHERPA_ONNX_LIB_DIR` to its `lib` directory before Cargo.
Linux additionally needs ALSA development packages; macOS needs microphone usage
description/permission and signed embedded dylibs in the application bundle.
The upstream binding adds native runtime search paths, but the final installed
app must be tested on each OS. This crate's acceptance currently covers Windows
x64 only; shared source is not evidence of a tested macOS/Linux release.

## Attribution

sherpa-onnx is Apache-2.0, ONNX Runtime is MIT. Exact upstream license copies are
under `licenses/`. Preparation also retrieves the version-pinned, hash-verified
ONNX Runtime third-party notices for the distributable bundle. The selected
ASR-only binary omits unneeded text-to-speech components. SenseVoice weights are
obtained from the official converted model repository pinned in `src/model.rs`;
see [SenseVoice](https://github.com/FunAudioLLM/SenseVoice) and its model license.
