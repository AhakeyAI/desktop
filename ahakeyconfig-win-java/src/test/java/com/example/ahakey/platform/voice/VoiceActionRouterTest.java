package com.example.ahakey.platform.voice;

import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class VoiceActionRouterTest {
    @Test
    void routesShortAndLongActionsWithoutSyntheticKeys() {
        VoiceActionRouter router = new VoiceActionRouter();
        router.setActions(VoiceAction.CUSTOM_SHORTCUT, VoiceAction.AHAKEY_VOICE);
        List<VoiceButtonEvent.Type> events = new ArrayList<>();
        router.setExecutor(VoiceAction.CUSTOM_SHORTCUT, e -> events.add(e.type()));
        router.setExecutor(VoiceAction.AHAKEY_VOICE, e -> events.add(e.type()));
        router.route(new VoiceButtonEvent(VoiceButtonEvent.Type.SHORT_PRESS, 1));
        router.route(new VoiceButtonEvent(VoiceButtonEvent.Type.LONG_PRESS_START, 2));
        router.route(new VoiceButtonEvent(VoiceButtonEvent.Type.LONG_PRESS_END, 3));
        assertEquals(List.of(
            VoiceButtonEvent.Type.SHORT_PRESS,
            VoiceButtonEvent.Type.LONG_PRESS_START,
            VoiceButtonEvent.Type.LONG_PRESS_END), events);
    }

    @Test
    void defaultsUseWinHCustomShortAndAhaKeyVoiceForLong() {
        VoiceActionRouter router = new VoiceActionRouter();
        assertEquals(VoiceAction.CUSTOM_SHORTCUT,
            router.actionFor(VoiceButtonEvent.Type.SHORT_PRESS));
        assertEquals(VoiceAction.AHAKEY_VOICE,
            router.actionFor(VoiceButtonEvent.Type.LONG_PRESS_START));
        assertEquals(VoiceAction.AHAKEY_VOICE,
            router.actionFor(VoiceButtonEvent.Type.LONG_PRESS_END));
    }

    @Test
    void ahaKeyVoiceCannotBeConfiguredAsSilentShortPress() {
        VoiceActionRouter router = new VoiceActionRouter();
        router.setActions(VoiceAction.AHAKEY_VOICE, VoiceAction.AHAKEY_VOICE);
        assertEquals(VoiceAction.CUSTOM_SHORTCUT,
            router.actionFor(VoiceButtonEvent.Type.SHORT_PRESS));
    }

    @Test
    void shortcutParserUsesExistingHidEncodingAndReservesF18() {
        assertEquals(0x800 | 0x0B, VoiceActionRouter.parseShortcut("Win+H"));
        assertEquals(0x200 | 0x400 | 0x04,
            VoiceActionRouter.parseShortcut("Ctrl+Alt+A"));
        assertEquals("Ctrl+Alt+A",
            VoiceActionRouter.formatShortcut(0x200 | 0x400 | 0x04));
        assertEquals(0, VoiceActionRouter.parseShortcut("F18"));
        assertEquals(0, VoiceActionRouter.parseShortcut("Ctrl+F18"));
        assertEquals(0, VoiceActionRouter.parseShortcut("Left Ctrl"));
    }

    @Test
    void legacySystemActionsMigrateToCustomShortcut() {
        VoiceActionRouter router = new VoiceActionRouter();
        router.setActions(VoiceAction.SYSTEM_VOICE, VoiceAction.SYSTEM_VOICE);
        assertEquals(VoiceAction.CUSTOM_SHORTCUT,
            router.actionFor(VoiceButtonEvent.Type.SHORT_PRESS));
        assertEquals(VoiceAction.CUSTOM_SHORTCUT,
            router.actionFor(VoiceButtonEvent.Type.LONG_PRESS_START));
    }
}
