# PR #76 review fixes — 2026-09-29

Base: `dfbb005defa5cd26180771b6d6c1c28509e59e78`.

## Changes

- Returning BLE ownership to Studio rearms the 4/8/15/30-second retry timer, including an initial scan that finds no keyboard or an ownership lock that is still busy. Suppressed owners do not restart a queued retry.
- Codex installation calculates trust keys from the actual TOML event-group indices. It removes only AhaKey-managed groups and their trust records; when later user groups shift index, their state keys shift with them without changing their hashes or enabled flags. Reinstall and uninstall preserve user hooks in the same config file.
- The installer shares the byte-oriented TOML scanner with policy migration. Headers and marker-looking comments inside multiline strings do not count as hooks. Ambiguous/unclosed markers and unsupported inline hook layouts stop installation before writing.
- VibeBar's rendered-frame callbacks synchronize the presentation screen after DynamicNotchKit rebuilds its window on another display.
- Real Codex validation found an additional trust mismatch: `UserPromptSubmit` and `Stop` ignore `matcher`, so their normalized hash must omit it. The production builder and hash now agree with Codex. See [official matcher rules](https://learn.chatgpt.com/docs/hooks#matcher-patterns).

## Verification

The original regressions were observed failing before their fixes:

- `swift test --filter 'CodexHookTrustTests|BLEStatePublicationTests'`: same-config user trust disappeared; returning ownership left no retry scheduled.
- `cd vibebar && swift test --filter VibeBarControllerTests`: reported screen was not adopted.
- Real `hooks/list` initially returned `modified` for `UserPromptSubmit` and `Stop`; the matcher-normalization regression test also failed before the hash fix.

After fixing:

- macOS tests: 109 tests passed across App (19), Shared (71), and Agent (19). The full suite passed before the final two Agent integration tests were added; the entire Agent policy suite was rerun with those two tests and passed.
- VibeBar: all 8 tests passed.
- `swift build -c release --arch arm64` and `swift build -c release --arch x86_64` passed (including App and Agent).
- `zsh -n ahakeyconfig-mac/scripts/build.sh` and `git diff --check` passed.
- Standards and Spec were independently re-reviewed with no further actionable findings.

Run the real Codex check from the repository root:

```sh
python3 ahakeyconfig-mac/scripts/verify-codex-hook-trust.py
```

The script compiles the production Swift installer, uses a temporary `CODEX_HOME`, and launches `codex app-server --stdio` against an intentionally unavailable local model endpoint. Test hooks only append markers to temporary files; `UserPromptSubmit` blocks the turn before inference. No user config, user authentication, real Agent/socket, or keyboard is used. The fake Agent path includes spaces and an apostrophe to exercise command quoting.

[Recorded result](codex-hook-smoke.json), using `codex-cli 0.155.0-alpha.16.4`:

| Operation | Hooks discovered | Trusted |
|---|---:|---:|
| Install beside an existing user hook | 7 | 7 |
| Reinstall | 7 | 7 |
| Uninstall AhaKey hooks | 1 user hook | 1 |

Actual Codex execution produced all three expected markers: the existing user hook, `CodexSessionStart`, and `CodexUserPromptSubmit`. Agent tests separately exercise the real PermissionRequest/SessionStart handler and policy writer against a temporary config: automatic mode writes `never` and returns `allow`; manual writes `on-request` without `allow`; an unknown lever state does not grant approval or rewrite policy.

These are source/build and isolated runtime checks. This follow-up does not replace the installed AhaKey app, reinstall hooks into the user's real Codex config, or repeat BLE/multi-display hardware testing.
