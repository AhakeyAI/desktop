# macOS Installation Guide

This guide explains how to build and package the macOS client from source.

## Who this is for

- New contributors who want to run the macOS client locally.
- Maintainers who need to generate a `.dmg` package.

## Before you start

- macOS `15.0+`
- Apple Silicon (`arm64`)
- Xcode `15+` **or** an equivalent Swift toolchain
- Swift `5.9+`

Check your environment:

```bash
sw_vers
uname -m
xcodebuild -version
swift --version
```

## 1) Go to the macOS client directory

```bash
cd platforms/macos/client
```

## 2) Build the app

Choose one of the supported entry points:

```bash
swift build -c release --arch arm64 --product AhaKeyConfig
```

or

```bash
bash scripts/build.sh
```

or

```bash
make build
```

## 3) Run local verification

After building, confirm the build completes without errors and expected outputs are produced under Swift build artifacts.

## 4) Package as `.dmg` (optional)

Use one of the current packaging scripts:

```bash
bash scripts/package_dmg.sh
```

or

```bash
bash scripts/release_dmg.sh
```

## Notes

- Release binaries such as `.app` and `.dmg` are **not** committed to this repository.
- The macOS build and release process is still being standardized; script behavior may evolve.
- For end users, installation packages are distributed through GitHub Releases.

## Quick troubleshooting

- `swift` not found: install Xcode Command Line Tools or a Swift toolchain.
- Wrong architecture: confirm `uname -m` returns `arm64`.
- Build script permission issues: run `chmod +x scripts/*.sh` and retry.
