package com.example.ahakey.platform.voice;

/** Desktop-owned action for the physical voice key.  It is deliberately
 * platform neutral: a platform executor decides how an action is performed. */
public enum VoiceAction {
    AHAKEY_VOICE,
    SYSTEM_VOICE,
    CUSTOM_SHORTCUT,
    NONE
}
