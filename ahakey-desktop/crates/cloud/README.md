# Native cloud speech

`ahakey-cloud` connects to Doubao v3 ASR only when the caller explicitly starts
a cloud session. It has no microphone capture, subprocess, automatic provider
fallback, Tauri dependency, or settings serialization.

## Integration

1. Save the user's token through `CredentialStore::new(app_data_directory).save(&token)`.
   Keep `load()` inside the native backend and expose only `has_token()` to the UI.
2. From a Tokio runtime, call `CloudSession::start(CloudConfig { app_id,
   resource_id }, store.load()?, callback)` after the user selects cloud speech
   and starts recording.
3. Feed 16 kHz mono signed PCM16 little-endian samples through
   `try_send_pcm16(&samples)`. Each chunk contains 1 to 3200 samples. Split
   larger capture buffers; do not drop data when the queue reports an error.
4. On release, stop capture and await `finish()`. The session emits partial
   text, then exactly one final result on success, or one sanitized error on
   failure. Silence can produce an empty final; a failed session does not emit
   a fake final transcript. `wait(self)` joins task completion.
5. `cancel()` interrupts all network waits and suppresses future callbacks.
   Dropping the session cancels it. Callbacks should enqueue quickly; a final
   handler may safely cancel or drop its own session.

The endpoint is fixed to
`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`. Request headers,
configuration, gzip framing, sequence flags and audio encoding follow the
[official v3 protocol](https://www.volcengine.com/docs/6561/1354869), matching
the repository's existing Java protocol implementation.

Limits: 80 queued packets, 3200 samples per packet, five minutes per recording,
1 MiB compressed WebSocket message/frame and decompressed JSON body, 15 seconds
to connect, 10 seconds per send, and 20 seconds for a final response after the
last audio frame. Credentials and raw server error bodies are never included
in library errors. Account, network and resource authorization still require
testing with a user-configured account.

## Native credential storage

- Windows: current-user DPAPI, encrypted file under the supplied app data
  directory, atomic replacement. No plaintext file is created.
- macOS: Keychain using the maintained `keyring` crate.
- Linux: Secret Service using `keyring`; building requires the system D-Bus
  development library and use requires an available unlocked Secret Service.

There is no plaintext fallback. macOS/Linux use service `AhaKey Studio` and
account `doubao-access-token`, independent of the installed application path.
The Windows path belongs to the caller so isolated tests never touch real
user credentials. macOS/Linux backends require native-host acceptance; Windows
compilation does not establish their runtime availability.

## Verification

Run `cargo test --manifest-path Cargo.toml` and
`cargo clippy --manifest-path Cargo.toml --all-targets -- -D warnings`.
Windows tests exercise actual DPAPI with isolated fake tokens. Loopback
WebSocket tests verify headers, wire audio, fragmented frames, duplicate final
suppression, bounded queues, cancellation and connection/final timeouts.
These tests never read existing account credentials or call the cloud API.
