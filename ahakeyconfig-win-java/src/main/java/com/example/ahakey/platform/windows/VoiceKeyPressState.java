package com.example.ahakey.platform.windows;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/** Explicit voice-key pressed state; independent of unreliable hook flag bits. */
final class VoiceKeyPressState {
    private final Set<Integer> pressed = ConcurrentHashMap.newKeySet();

    boolean firstKeyDown(int virtualKey) {
        return pressed.add(virtualKey);
    }

    boolean firstKeyUp(int virtualKey) {
        return pressed.remove(virtualKey);
    }

    void clear() {
        pressed.clear();
    }
}
