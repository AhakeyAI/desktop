package com.example.ahakey.firmware;

import java.nio.file.Path;

/**
 * Platform-neutral firmware flashing boundary. Windows uses WCHISP; macOS and
 * Linux can provide their own implementation without changing the UI.
 */
public interface FirmwareFlasher {
    record DeviceInfo(boolean bootloaderPresent, String detail) {}

    record FlashResult(boolean success, String stage, String detail) {}

    DeviceInfo detect() throws Exception;

    FlashResult flashAndVerify(Path firmwareHex, ProgressListener listener)
        throws Exception;

    interface ProgressListener {
        void onProgress(String stage, double progress, String detail);
    }
}
