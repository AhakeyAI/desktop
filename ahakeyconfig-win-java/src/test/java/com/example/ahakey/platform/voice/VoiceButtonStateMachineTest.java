package com.example.ahakey.platform.voice;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class VoiceButtonStateMachineTest {
    @Test
    void shortPressAt349msAndBoundaryAt350ms() {
        VoiceButtonStateMachine machine = new VoiceButtonStateMachine(350);
        machine.onKeyDown(1_000_000_000L);
        assertNull(machine.onThreshold(1_349_000_000L));
        assertEquals(List.of(VoiceButtonEvent.Type.SHORT_PRESS),
            machine.onKeyUp(1_349_000_001L).stream()
                .map(VoiceButtonEvent::type).toList());

        machine.onKeyDown(2_000_000_000L);
        assertEquals(VoiceButtonEvent.Type.LONG_PRESS_START,
            machine.onThreshold(2_350_000_000L).type());
        assertNull(machine.onThreshold(2_351_000_000L));
        assertEquals(List.of(VoiceButtonEvent.Type.LONG_PRESS_END),
            machine.onKeyUp(2_401_000_000L).stream()
                .map(VoiceButtonEvent::type).toList());
    }

    @Test
    void repeatsAndIsolatedKeyUpAreIgnored() {
        VoiceButtonStateMachine machine = new VoiceButtonStateMachine();
        assertEquals(List.of(), machine.onKeyUp(1));
        assertNull(machine.onKeyDown(10));
        assertNull(machine.onKeyDown(20));
        assertEquals(List.of(VoiceButtonEvent.Type.SHORT_PRESS), machine.onKeyUp(30).stream()
            .map(VoiceButtonEvent::type).toList());
        assertEquals(List.of(), machine.onKeyUp(40));
    }

    @Test
    void resetCancelsHeldButton() {
        VoiceButtonStateMachine machine = new VoiceButtonStateMachine();
        machine.onKeyDown(10);
        machine.reset();
        assertEquals(List.of(), machine.onKeyUp(500));
        assertEquals(VoiceButtonStateMachine.State.IDLE, machine.state());
    }

    @Test
    void delayedThresholdAtKeyUpIsCompensatedAsLongStartThenEnd() {
        VoiceButtonStateMachine machine = new VoiceButtonStateMachine(350);
        machine.onKeyDown(1_000_000_000L);

        assertEquals(List.of(
            VoiceButtonEvent.Type.LONG_PRESS_START,
            VoiceButtonEvent.Type.LONG_PRESS_END),
            machine.onKeyUp(1_370_000_000L).stream()
                .map(VoiceButtonEvent::type).toList());
        // A scheduler callback that arrives after UP cannot create a second start.
        assertNull(machine.onThreshold(1_500_000_000L));
    }

    @Test
    void exactThresholdWithoutSchedulerIsLongPress() {
        VoiceButtonStateMachine machine = new VoiceButtonStateMachine(350);
        machine.onKeyDown(2_000_000_000L);
        assertEquals(List.of(
            VoiceButtonEvent.Type.LONG_PRESS_START,
            VoiceButtonEvent.Type.LONG_PRESS_END),
            machine.onKeyUp(2_350_000_000L).stream()
                .map(VoiceButtonEvent::type).toList());
    }
}
