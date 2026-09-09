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
}
