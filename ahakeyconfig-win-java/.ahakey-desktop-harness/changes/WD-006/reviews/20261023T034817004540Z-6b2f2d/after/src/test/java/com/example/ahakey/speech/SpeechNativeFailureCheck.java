package com.example.ahakey.service;

import com.example.ahakey.sherpa.LibraryLoader;

/** Run without the native resource JAR: a missing JNI dependency must remain catchable. */
public final class SpeechNativeFailureCheck {
    public static void main(String[] args) {
        try {
            LibraryLoader.load();
            throw new AssertionError("Expected unavailable native library");
        } catch (UnsatisfiedLinkError expected) {
            if (LibraryLoader.isLoaded()) throw new AssertionError("Failed load marked as loaded");
            System.out.println("PASS missing native DLL is reported as UnsatisfiedLinkError; process remains usable");
        }
    }
}
