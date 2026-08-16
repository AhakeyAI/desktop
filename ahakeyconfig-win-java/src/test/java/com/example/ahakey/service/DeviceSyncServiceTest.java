package com.example.ahakey.service;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.protocol.AhaKeyProtocol;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class DeviceSyncServiceTest {
    @Test
    void savesOneGlobalVoiceConfigAndSkipsLegacyPerModeKeyOne() {
        StudioState state = new StudioState();
        var commands = DeviceSyncService.commandsForModes(state, ModeSlot.values());

        var voiceCommands = commands.stream()
            .filter(c -> c.data()[2] == AhaKeyProtocol.CMD_VOICE_KEY_CONFIG)
            .toList();
        assertEquals(1, voiceCommands.size());
        assertArrayEquals(
            AhaKeyProtocol.setVoiceKeyConfig(0x4000, 0x0A00),
            voiceCommands.get(0).data()
        );

        boolean writesLegacyKeyOne = commands.stream().anyMatch(c -> {
            byte[] frame = c.data();
            return frame.length >= 8
                && frame[2] == AhaKeyProtocol.CMD_UPDATE_CUSTOM_KEY
                && frame[5] == 0;
        });
        assertFalse(writesLegacyKeyOne);
    }

    @Test
    void legacyDraftMigratesOnlyNewVoiceFieldsToDefaults() {
        StudioState.PersistedDraft legacy = StudioState.PersistedDraft.defaults();
        legacy.voiceKeyShortHid = null;
        legacy.voiceKeyLongHid = null;
        legacy.modes[0].key2Hid = 0x2A;

        StudioState loaded = new StudioState();
        loaded.loadFromPersisted(legacy);

        assertEquals(0x4000, loaded.getVoiceKeyShort().getHidCode());
        assertEquals(0x0A00, loaded.getVoiceKeyLong().getHidCode());
        assertEquals(0x2A, loaded.getKeyConfig(ModeSlot.MODE0,
            com.example.ahakey.model.StudioPart.KEY2).getHidCode());
    }

    @Test
    void unsupportedVoiceExtensionDoesNotBlockOrdinaryConfigurationSave() {
        StudioState state = new StudioState();
        var commands = DeviceSyncService.commandsForModes(
            state, false, ModeSlot.values());

        assertFalse(commands.stream().anyMatch(command ->
            command.data()[2] == AhaKeyProtocol.CMD_VOICE_KEY_CONFIG));
        assertEquals(AhaKeyProtocol.CMD_SAVE_CONFIG,
            commands.get(commands.size() - 1).data()[2]);
        assertFalse(commands.isEmpty());
    }

    @Test
    void waitsForEveryAckBeforeVoiceReadbackAndCompletesSave() throws Exception {
        StudioState state = new StudioState();
        var commands = DeviceSyncService.commandsForModes(state, ModeSlot.values());
        AckingBleManager ble = new AckingBleManager();
        CountDownLatch completed = new CountDownLatch(1);
        CountDownLatch failed = new CountDownLatch(1);

        DeviceSyncService.writeSequentially(
            ble,
            commands,
            completed::countDown,
            failed::countDown,
            message -> { }
        );

        assertTrue(completed.await(5, TimeUnit.SECONDS));
        assertEquals(1, failed.getCount());
        assertEquals(commands.size() + 1, ble.events.size());
        assertEquals(-1, ble.events.get(ble.events.size() - 1));
        for (int index = 0; index < commands.size(); index++) {
            assertEquals(commands.get(index).data()[2] & 0xFF, ble.events.get(index));
        }
    }

    private static final class AckingBleManager extends BleManager {
        private final List<Integer> events = Collections.synchronizedList(new ArrayList<>());

        private AckingBleManager() {
            super(new BleCallback() {
                @Override public void onConnected() { }
                @Override public void onDisconnected() { }
                @Override public void onStatusReceived(
                    com.example.ahakey.model.DeviceStatus status
                ) { }
                @Override public void onError(String message) { }
            });
        }

        @Override
        public void sendCommandExpecting(byte[] command, byte expectedCmd) {
            assertEquals(command[2], expectedCmd);
            events.add(expectedCmd & 0xFF);
        }

        @Override
        public com.example.ahakey.protocol.AhaKeyResponseParser.VoiceKeyConfig
            readVoiceKeyConfig() {
            events.add(-1);
            return new com.example.ahakey.protocol.AhaKeyResponseParser.VoiceKeyConfig(
                new byte[]{(byte) 0xE6},
                new byte[]{(byte) 0xE0, (byte) 0xE3},
                AhaKeyProtocol.VOICE_KEY_LONG_PRESS_MS
            );
        }
    }
}
