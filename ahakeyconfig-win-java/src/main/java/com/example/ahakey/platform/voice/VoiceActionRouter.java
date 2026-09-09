package com.example.ahakey.platform.voice;

import java.util.EnumMap;
import java.util.Map;
import java.util.Objects;
import java.util.function.Consumer;

/** Routes semantic press events to platform-independent action executors. */
public final class VoiceActionRouter {
    private final Map<VoiceButtonEvent.Type, VoiceAction> actions =
        new EnumMap<>(VoiceButtonEvent.Type.class);
    private final Map<VoiceAction, Consumer<VoiceButtonEvent>> executors =
        new EnumMap<>(VoiceAction.class);

    public VoiceActionRouter() {
        setActions(VoiceAction.SYSTEM_VOICE, VoiceAction.SYSTEM_VOICE);
    }

    public synchronized void setActions(VoiceAction shortAction, VoiceAction longAction) {
        actions.put(VoiceButtonEvent.Type.SHORT_PRESS,
            Objects.requireNonNull(shortAction, "shortAction"));
        actions.put(VoiceButtonEvent.Type.LONG_PRESS_START,
            Objects.requireNonNull(longAction, "longAction"));
        actions.put(VoiceButtonEvent.Type.LONG_PRESS_END,
            Objects.requireNonNull(longAction, "longAction"));
    }

    public synchronized void setExecutor(VoiceAction action, Consumer<VoiceButtonEvent> executor) {
        Objects.requireNonNull(action, "action");
        if (executor == null) executors.remove(action);
        else executors.put(action, executor);
    }

    public synchronized VoiceAction actionFor(VoiceButtonEvent.Type type) {
        return actions.getOrDefault(type, VoiceAction.NONE);
    }

    /** Returns the selected action; execution is deliberately outside the lock. */
    public void route(VoiceButtonEvent event) {
        if (event == null) return;
        Consumer<VoiceButtonEvent> executor;
        synchronized (this) {
            executor = executors.get(actionFor(event.type()));
        }
        if (executor != null) executor.accept(event);
    }
}
