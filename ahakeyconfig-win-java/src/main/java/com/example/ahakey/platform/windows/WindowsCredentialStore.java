package com.example.ahakey.platform.windows;

import com.sun.jna.platform.win32.Crypt32Util;
import java.io.IOException;

/** User-scoped DPAPI. Never falls back to plaintext or logs secret material. */
public class WindowsCredentialStore {
    public byte[] protect(byte[] plain) throws IOException {
        try { return Crypt32Util.cryptProtectData(plain); }
        catch (RuntimeException | LinkageError e) { throw new IOException("Windows 凭据保护失败"); }
    }
    public byte[] unprotect(byte[] encrypted) throws IOException {
        try { return Crypt32Util.cryptUnprotectData(encrypted); }
        catch (RuntimeException | LinkageError e) { throw new IOException("Windows 凭据读取失败"); }
    }
}
