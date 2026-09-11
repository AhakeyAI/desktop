package com.example.ahakey.platform.windows;

import com.example.ahakey.firmware.FirmwareCapabilities;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.model.HIDUsage;
import com.example.ahakey.platform.voice.VoiceButtonEvent;
import com.example.ahakey.platform.voice.VoiceAction;
import com.example.ahakey.service.VoiceInputManager;
import com.example.ahakey.update.SemanticVersion;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WindowsVoiceRelayServiceTest {
    private WindowsVoiceRelayService relay;

    @BeforeEach
    void setUp() {
        relay = WindowsVoiceRelayService.getInstance();
        relay.setOnVoiceAction(null);
        relay.setCustomShortcutEmitterForTest(null);
        relay.setAhaKeyVoiceAvailable(false);
        relay.setFirmwareVersion(new SemanticVersion(1, 4, 8));
        relay.configureVoiceActions(
            com.example.ahakey.platform.voice.VoiceAction.SYSTEM_VOICE,
            com.example.ahakey.platform.voice.VoiceAction.AHAKEY_VOICE,
            350);
    }

    @AfterEach
    void tearDown() {
        relay.setOnVoiceAction(null);
        relay.setCustomShortcutEmitterForTest(null);
        relay.setAhaKeyVoiceAvailable(false);
        relay.setFirmwareVersion(null);
    }

    @Test
    void physicalLongPressDrivesAhaKeyPttExactlyOnce() {
        CountingVoiceInputManager voiceInput = new CountingVoiceInputManager();
        relay.setOnVoiceAction(event -> {
            if (!voiceInput.isActivated()) {
                relay.setAhaKeyVoiceAvailable(false);
                return;
            }
            if (event.type() == VoiceButtonEvent.Type.LONG_PRESS_START) {
                voiceInput.startRecording();
            } else if (event.type() == VoiceButtonEvent.Type.LONG_PRESS_END
                && voiceInput.isRecording()) {
                voiceInput.stopRecording();
            }
        });
        relay.setAhaKeyVoiceAvailable(true);

        List<VoiceButtonEvent> events = relay.classifyPhysicalF18ForTest(
            1_000_000_000L, 1_350_000_000L, true);
        events.forEach(relay::dispatchVoiceEventForTest);

        assertEquals(List.of(
            VoiceButtonEvent.Type.LONG_PRESS_START,
            VoiceButtonEvent.Type.LONG_PRESS_END),
            events.stream().map(VoiceButtonEvent::type).toList());
        assertEquals(1, voiceInput.startCount);
        assertEquals(1, voiceInput.stopCount);
    }

    @Test
    void delayedThresholdAndRepeatDownCannotStartPttTwice() {
        CountingVoiceInputManager voiceInput = new CountingVoiceInputManager();
        relay.setOnVoiceAction(event -> {
            if (event.type() == VoiceButtonEvent.Type.LONG_PRESS_START) {
                voiceInput.startRecording();
            } else if (event.type() == VoiceButtonEvent.Type.LONG_PRESS_END
                && voiceInput.isRecording()) {
                voiceInput.stopRecording();
            }
        });
        relay.setAhaKeyVoiceAvailable(true);

        // The scheduler callback is delayed; release-time classification must
        // still emit one ordered START/END pair. The repeat DOWN is ignored by
        // the shared VoiceButtonStateMachine before this dispatch.
        List<VoiceButtonEvent> events = relay.classifyPhysicalF18ForTest(
            2_000_000_000L, 2_360_000_000L, false, true);
        events.forEach(relay::dispatchVoiceEventForTest);

        assertEquals(2, events.size());
        assertEquals(1, voiceInput.startCount);
        assertEquals(1, voiceInput.stopCount);
    }

    @Test
    void customShortcutShortAndLongStartAreOneShotAndReleaseIsNoOp() {
        List<Integer> emitted = new java.util.ArrayList<>();
        relay.setCustomShortcutEmitterForTest(emitted::add);
        relay.configureVoiceActions(
            VoiceAction.CUSTOM_SHORTCUT, VoiceAction.CUSTOM_SHORTCUT, 500,
            VoiceActionRouterTestSupport.WIN_H,
            VoiceActionRouterTestSupport.CTRL_ALT_A);

        relay.dispatchVoiceEventForTest(
            new VoiceButtonEvent(VoiceButtonEvent.Type.SHORT_PRESS, 1));
        relay.dispatchVoiceEventForTest(
            new VoiceButtonEvent(VoiceButtonEvent.Type.LONG_PRESS_START, 2));
        relay.dispatchVoiceEventForTest(
            new VoiceButtonEvent(VoiceButtonEvent.Type.LONG_PRESS_END, 3));

        assertEquals(List.of(
            VoiceActionRouterTestSupport.WIN_H,
            VoiceActionRouterTestSupport.CTRL_ALT_A), emitted);
    }

    @Test
    void unavailableAhaKeyVoiceDoesNotFallbackToWindowsVoice() {
        List<Integer> emitted = new java.util.ArrayList<>();
        relay.setCustomShortcutEmitterForTest(emitted::add);
        relay.setAhaKeyVoiceAvailable(false);
        relay.dispatchVoiceEventForTest(
            new VoiceButtonEvent(VoiceButtonEvent.Type.LONG_PRESS_START, 1));
        relay.dispatchVoiceEventForTest(
            new VoiceButtonEvent(VoiceButtonEvent.Type.LONG_PRESS_END, 2));
        assertTrue(emitted.isEmpty());
    }

    @Test
    void persistedThresholdCannotChangeRuntime350MillisecondBoundary() {
        relay.configureVoiceActions(
            VoiceAction.CUSTOM_SHORTCUT, VoiceAction.NONE, 500,
            VoiceActionRouterTestSupport.WIN_H,
            VoiceActionRouterTestSupport.WIN_H);
        assertEquals(List.of(VoiceButtonEvent.Type.SHORT_PRESS),
            relay.classifyPhysicalF18ForTest(0, 349_000_000L, false)
                .stream().map(VoiceButtonEvent::type).toList());
        assertEquals(List.of(
            VoiceButtonEvent.Type.LONG_PRESS_START,
            VoiceButtonEvent.Type.LONG_PRESS_END),
            relay.classifyPhysicalF18ForTest(1_000_000_000L, 1_350_000_000L, false)
                .stream().map(VoiceButtonEvent::type).toList());
    }

    @Test
    void firmwareVersionGateOnlyControlsRawF18Routing() {
        relay.setFirmwareVersion(new SemanticVersion(1, 4, 7));
        assertFalse(relay.isRawF18RoutingEnabled());
        assertFalse(relay.acceptsPhysicalF18ForTest());
        assertTrue(FirmwareCapabilities.supportsGif(new SemanticVersion(1, 4, 7)));

        relay.setFirmwareVersion(new SemanticVersion(1, 4, 8));
        assertTrue(relay.isRawF18RoutingEnabled());
        assertTrue(relay.acceptsPhysicalF18ForTest());

        relay.setFirmwareVersion(new SemanticVersion(1, 4, 9));
        assertTrue(relay.isRawF18RoutingEnabled());
        assertTrue(relay.acceptsPhysicalF18ForTest());
    }

    @Test
    void physicalF18IsIndependentOfLegacyPerModeKey1() {
        StudioState state = new StudioState();
        state.getKeyConfig(ModeSlot.MODE0, StudioPart.KEY1).setHidCode(HIDUsage.F17);
        state.getKeyConfig(ModeSlot.MODE1, StudioPart.KEY1).setHidCode(0x04); // A
        state.getKeyConfig(ModeSlot.MODE2, StudioPart.KEY1).setHidCode(HIDUsage.F18);

        for (ModeSlot mode : List.of(ModeSlot.MODE0, ModeSlot.MODE1, ModeSlot.MODE2)) {
            state.setSelectedMode(mode);
            relay.updateRoutes(state);
            assertTrue(relay.acceptsPhysicalF18ForTest(),
                "physical F18 must remain routed in " + mode);
        }
    }

    private static final class CountingVoiceInputManager extends VoiceInputManager {
        private int startCount;
        private int stopCount;
        private boolean recording;

        @Override
        public boolean isActivated() {
            return true;
        }

        @Override
        public void startRecording() {
            startCount++;
            recording = true;
        }

        @Override
        public boolean isRecording() {
            return recording;
        }

        @Override
        public void stopRecording() {
            stopCount++;
            recording = false;
        }
    }

    private static final class VoiceActionRouterTestSupport {
        private static final int WIN_H = 0x800 | 0x0B;
        private static final int CTRL_ALT_A = 0x200 | 0x400 | 0x04;
    }
}
