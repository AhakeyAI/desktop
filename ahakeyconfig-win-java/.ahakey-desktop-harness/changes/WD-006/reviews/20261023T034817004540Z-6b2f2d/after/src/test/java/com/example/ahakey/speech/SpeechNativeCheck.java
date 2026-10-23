package com.example.ahakey.service;

/** Real JNI + model smoke test, never opens a microphone or an application window. */
public final class SpeechNativeCheck {
    public static void main(String[] args) throws Exception {
        if (args.length != 4) throw new IllegalArgumentException("encoder decoder tokens wav");
        SpeechService service = new SpeechService();
        try {
            service.initialize(args[0], args[1], args[2], 2);
            String text = service.recognizeFromFile(args[3]);
            if (text == null || text.isBlank()) throw new AssertionError("Empty recognition result");
            System.out.println("RECOGNIZED: " + text);
            String repeated = service.recognizeFromFile(args[3]);
            if (!text.equals(repeated)) throw new AssertionError("Repeated recognition differs");
            System.out.println("PASS real Sherpa JNI/WAV repeat and release");
        } finally { service.release(); service.release(); }
    }
}
