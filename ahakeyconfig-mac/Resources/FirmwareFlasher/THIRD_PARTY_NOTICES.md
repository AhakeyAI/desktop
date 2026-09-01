# Third-party notices

## wchisp 0.3.0

`wchisp` is a separate command-line executable used by AhaKey Studio for WCH
USB-ISP programming.

- Project: https://github.com/ch32-rs/wchisp
- Release and corresponding source: https://github.com/ch32-rs/wchisp/tree/v0.3.0
- Release commit: `f0f13c4`
- License: GNU General Public License v2.0 (`LICENSE-wchisp.txt`)

The unmodified macOS executables are distributed alongside the application and
are invoked as separate processes. AhaKey Studio validates the target as CH582
before issuing any erase command.

`SOURCE_SHA256SUMS` records the firmware and tool hashes before the application
build re-signs the two executables for distribution. Code signing intentionally
changes executable bytes; the enclosing application signature protects the
packaged copies after signing.
