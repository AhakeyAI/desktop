package com.example.ahakey.protocol;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class AhaKeyProtocolTest {
    @Test
    void usesBoundedPacedFlashTransfers() {
        assertEquals(4096, AhaKeyProtocol.OLED_CHUNK_SIZE);
        assertEquals(1024, AhaKeyProtocol.OLED_TRANSFER_BATCH_SIZE);
        assertEquals(12, AhaKeyProtocol.OLED_TRANSFER_BATCH_DELAY_MS);
        assertEquals(3, AhaKeyProtocol.OLED_BLOCK_MAX_ATTEMPTS);
        assertEquals(0,
            AhaKeyProtocol.OLED_CHUNK_SIZE % AhaKeyProtocol.OLED_TRANSFER_BATCH_SIZE);
    }

    @Test
    void buildsProtocolV2Commands() {
        assertArrayEquals(
            new byte[]{(byte) 0xAA, (byte) 0xBB, (byte) 0x9F, (byte) 0xCC, (byte) 0xDD},
            AhaKeyProtocol.queryCapabilities()
        );
        assertArrayEquals(
            new byte[]{
                (byte) 0xAA, (byte) 0xBB, (byte) 0x95, 30, 0,
                (byte) 0xCC, (byte) 0xDD
            },
            AhaKeyProtocol.setStandbyTimeoutMinutes(30)
        );
        assertThrows(
            IllegalArgumentException.class,
            () -> AhaKeyProtocol.setStandbyTimeoutMinutes(60)
        );
        assertArrayEquals(
            new byte[]{
                (byte) 0xAA, (byte) 0xBB, (byte) 0x96,
                (byte) 0xA5, 0x5A, (byte) 0xCC, (byte) 0xDD
            },
            AhaKeyProtocol.factoryReset()
        );
    }

    @Test
    void parsesCapabilitiesAndStandbyTimeout() {
        AhaKeyResponseParser.DeviceCapabilities capabilities =
            AhaKeyResponseParser.parseDeviceCapabilities(
                new byte[]{2, 0, 1, 0, 1, 1, 0, 0, 0}
            );

        assertNotNull(capabilities);
        assertEquals(2, capabilities.protocolMajor());
        assertEquals(1, capabilities.hardwareRevision());
        assertTrue(capabilities.supports(AhaKeyProtocol.CAP_STANDBY_TIMEOUT_V2));
        assertEquals(0, capabilities.firmwarePatch());
        AhaKeyResponseParser.DeviceCapabilities v21 =
            AhaKeyResponseParser.parseDeviceCapabilities(
                new byte[]{2, 1, 1, 1, 1, 3, 0, 0, 0, 7}
            );
        assertTrue(v21.supports(AhaKeyProtocol.CAP_FACTORY_RESET_V1));
        assertEquals(7, v21.firmwarePatch());
        assertEquals(
            30,
            AhaKeyResponseParser.parseStandbyTimeoutMinutes(new byte[]{30, 0}).intValue()
        );
    }

    @Test
    void parsesPictureStatePayloadWithoutTreatingModeZeroAsStatus() {
        AhaKeyResponseParser.PictureState state = AhaKeyResponseParser.parsePictureState(
            new byte[]{0, 2, 0, 3, 0, 100, 0, 36, 1}
        );

        assertNotNull(state);
        assertEquals(0, state.mode());
        assertEquals(2, state.startIndex());
        assertEquals(3, state.picLength());
        assertEquals(100, state.frameInterval());
        assertEquals(292, state.allModeMaxPic());
    }

    @Test
    void buildsAndParsesDualVoiceKeyConfiguration() {
        assertArrayEquals(
            new byte[]{
                (byte) 0xAA, (byte) 0xBB, (byte) 0x97,
                1, (byte) 0xE6,
                2, (byte) 0xE0, (byte) 0xE3,
                (byte) 0xCC, (byte) 0xDD
            },
            AhaKeyProtocol.setVoiceKeyConfig(0x4000, 0x0A00)
        );

        AhaKeyResponseParser.VoiceKeyConfig config =
            AhaKeyResponseParser.parseVoiceKeyConfig(
                new byte[]{1, (byte) 0xE6, 2, (byte) 0xE0, (byte) 0xE3, 94, 1}
            );
        assertNotNull(config);
        assertEquals(350, config.longPressMs());
        assertTrue(config.matches(0x4000, 0x0A00));
    }

    @Test
    void supportsDisabledVoiceActionsAndLeftRightModifiers() {
        assertArrayEquals(
            new byte[]{
                (byte) 0xE0, (byte) 0xE3, (byte) 0xE4, (byte) 0xE7, 0x6D
            },
            AhaKeyProtocol.hidCodesForShortcut(0xAA00 | 0x6D)
        );
        assertArrayEquals(
            new byte[]{
                (byte) 0xAA, (byte) 0xBB, (byte) 0x97, 0, 0,
                (byte) 0xCC, (byte) 0xDD
            },
            AhaKeyProtocol.setVoiceKeyConfig(0, 0)
        );
    }

    @Test
    void buildsProtocolV3TaskAndGifCommands() {
        assertArrayEquals(new byte[]{(byte)0xAA, (byte)0xBB, (byte)0x98, 1, (byte)0xCC, (byte)0xDD},
            AhaKeyProtocol.setTaskDisplayMode(1));
        assertArrayEquals(new byte[]{(byte)0xAA, (byte)0xBB, (byte)0x99, 2, 1, 2, 1, (byte)0xCC, (byte)0xDD},
            AhaKeyProtocol.updateTaskSlot(2, 1, 2, true));
        assertEquals(164, AhaKeyProtocol.gifPartitionStart(3, 3));
        assertEquals(44, AhaKeyProtocol.gifPartitionStart(1, 0));
        assertEquals(8, AhaKeyProtocol.gifAssetCapacity(0));
        assertEquals(12, AhaKeyProtocol.gifAssetCapacity(3));
        assertArrayEquals(new byte[]{(byte)0xAA, (byte)0xBB, (byte)0x9A, 0, (byte)0xCC, (byte)0xDD},
            AhaKeyProtocol.taskHeartbeat());
    }

    @Test
    void parsesProtocolV3ModelModeAndGifLayout() {
        var capabilities = AhaKeyResponseParser.parseDeviceCapabilities(
            new byte[]{3, 0, 1, 3, 1, (byte)0xFF, 1, 0, 0, 0, 1});
        assertNotNull(capabilities);
        assertEquals(1, capabilities.deviceModel());
        var mode = AhaKeyResponseParser.parseModeSync(new byte[]{2, 1, 9});
        assertEquals(2, mode.mode());
        assertEquals(1, mode.source());
        var layout = AhaKeyResponseParser.parseGifLayout(new byte[]{4, 4, 12, 0, 100, 7, (byte)160, 80});
        assertEquals(12, layout.maxFrames());
        assertEquals(25600, layout.frameBytes());
        assertEquals(160, layout.width());
        assertEquals(0, layout.flashId());
        assertEquals(0, layout.frameSlots());

        var diagnosticLayout = AhaKeyResponseParser.parseGifLayout(new byte[]{
            4, 4, 12, 0, 100, 7, (byte)160, 80,
            0x16, (byte)0x85, 0, 0, (byte)0x80, 0, 0x24, 1,
            8, 12, 12, 12
        });
        assertEquals(0x8516, diagnosticLayout.flashId());
        assertEquals(8_388_608L, diagnosticLayout.flashBytes());
        assertEquals(292, diagnosticLayout.frameSlots());
        assertEquals(8, diagnosticLayout.capacityForAsset(0));
        assertEquals(12, diagnosticLayout.capacityForAsset(3));
        assertTrue(diagnosticLayout.hasVariableAssetCapacities());
        assertTrue(diagnosticLayout.hasPhysicalFlashDiagnostics());

        var aiState = AhaKeyResponseParser.parseAiOledState(new byte[]{
            2, 3, (byte)0x78, 0, 12, 0, 83, 0, 0x24, 1
        });
        assertEquals(2, aiState.mode());
        assertEquals(3, aiState.asset());
        assertEquals(120, aiState.startIndex());
        assertEquals(12, aiState.frameCount());
        assertEquals(292, aiState.totalFrameSlots());
    }

    @Test
    void parsesProtocol31ConnectionReadinessWithoutMovingLegacyFields() {
        var status = AhaKeyProtocol.parseDeviceStatus(new byte[]{
            (byte)0xAA, (byte)0xBB, 0, 94, 50, 1, 3, 2, 1, 0, 35, 3,
            (byte)0xCC, (byte)0xDD
        });
        assertNotNull(status);
        assertEquals(2, status.getWorkMode());
        assertTrue(status.isConnectionReadinessKnown());
        assertTrue(status.isBleLinkConnected());
        assertTrue(status.isHidInputReady());
    }
}
