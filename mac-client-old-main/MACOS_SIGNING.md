# macOS Stable Signing

This project now supports stable macOS distribution signing in `build_macos.sh`.

## What changed

- If `CODESIGN_IDENTITY` is set, the build will:
  - sign the nested helper apps first
  - sign the final `Vibecoding Keyboard.app`
  - verify the app signature
  - sign the generated `dmg`
- If `NOTARY_PROFILE` is set, the build will also:
  - submit the `dmg` or `zip` to Apple's notarization service
  - staple the notarization ticket
  - validate the stapled ticket

## Required certificate

For real distribution to other users, use an Apple Developer ID Application certificate, for example:

```text
Developer ID Application: Your Company Name (TEAMID1234)
```

Without that certificate, the app cannot become a trusted stable-distribution build.

## One-time notarization profile setup

Store your notarization credentials in the macOS keychain:

```bash
xcrun notarytool store-credentials vibecoding-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID1234" \
  --password "app-specific-password"
```

## Build a stable signed dmg

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Company Name (TEAMID1234)" \
NOTARY_PROFILE="vibecoding-notary" \
./build_macos.sh
```

## Optional knobs

- `APP_VERSION=1.0.2`
- `CODESIGN_KEYCHAIN=/path/to/custom.keychain-db`
- `NOTARIZE_TARGET=dmg`
- `NOTARIZE_TARGET=zip`

## Current machine status

At the time this workflow was added, the local machine had:

- `0 valid identities found`

So the build pipeline is ready for stable signing, but an actual Developer ID certificate still needs to be installed before it can produce a trusted signed release.
