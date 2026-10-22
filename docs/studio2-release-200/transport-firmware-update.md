# USB/Bluetooth recovery and firmware workflow (2.0.1 candidate)

USB automatically connects once per attachment and takes priority. On removal,
Studio attempts the selected Bluetooth device. Native link loss clears live
status; retryable acquisition failures use a 30-second cooldown. Explicit
manual disconnect, shutdown and firmware ownership suspend automatic recovery.
Native loss cancels pending reply tasks rather than leaving unobserved faults.

Prepare and flash on the main firmware page verifies an approved package,
requests confirmation with a live compatible USB target, then arms ISP waiting
before the user enters bootloader. ISP is polled at 100ms. Vendor programming
and verification cannot be interrupted. Returning USB identity and firmware/
capabilities must match. DataFlash is preserved. Manual reconnect wait is three
minutes. Advanced Check bootloader only observes and does not hold ISP.

Public packages do not include controlled firmware or vendor tools. Firmware
arming requires the approved package to be present; arbitrary HEX selection
remains inspection only.

Validation: 153 device tests, 14 firmware tests, and EN/RU/ZH/dark WPF replay.
On one authorized X1/CH582M unit, actual USB auto-connect, automatic Bluetooth
recovery after loss, and a complete application flash with vendor verification
and returning-target handshake succeeded. Firmware experiments use a private
approved test image; this does not qualify arbitrary boards or images.
MSI upgrade/clean Windows/signing gates remain separate and unverified here.
