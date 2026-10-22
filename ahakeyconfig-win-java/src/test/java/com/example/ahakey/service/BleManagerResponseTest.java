package com.example.ahakey.service;

import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertEquals;

class BleManagerResponseTest {
    @Test
    void cachedDeviceInfoCannotReconnectAnOfflineBleDevice() {
        assertFalse(BleManager.shouldAcceptDeviceInfo(false, false, "NONE"));
        assertFalse(BleManager.shouldAcceptDeviceInfo(false, true, "BLE"));
    }

    @Test
    void usbDeviceInfoDoesNotDependOnBleStatus() {
        assertTrue(BleManager.shouldAcceptDeviceInfo(true, false, "NONE"));
    }

    @Test
    void bleUiConnectionUsesLiveConfigurationLinkWithoutRequiringHidReadiness() {
        var status = new com.example.ahakey.model.DeviceStatus();
        status.setConnectionReadinessKnown(true);
        status.setBleLinkConnected(true);
        assertTrue(BleManager.isDeviceReadyForUi(false, status));
    }

    @Test
    void bleUiConnectionRejectsKnownDisconnectedLink() {
        var status = new com.example.ahakey.model.DeviceStatus();
        status.setConnectionReadinessKnown(true);
        status.setBleLinkConnected(false);
        status.setHidInputReady(true);
        assertFalse(BleManager.isDeviceReadyForUi(false, status));
    }

    @Test
    void freshLegacyStatusWithoutReadinessFlagsRemainsCompatible() {
        var status = new com.example.ahakey.model.DeviceStatus();
        assertTrue(BleManager.isDeviceReadyForUi(false, status));
    }

    @Test
    void voiceReadbackIgnoresDelayedEmptyWriteAck() {
        var emptyAck = AhaKeyResponseParser.parseCommandResponse(new byte[]{
            (byte) 0xAA, (byte) 0xBB, AhaKeyProtocol.CMD_VOICE_KEY_CONFIG,
            0, (byte) 0xCC, (byte) 0xDD
        });
        var fullReadback = AhaKeyResponseParser.parseCommandResponse(new byte[]{
            (byte) 0xAA, (byte) 0xBB, AhaKeyProtocol.CMD_VOICE_KEY_CONFIG,
            0, 1, (byte) 0xE6, 2, (byte) 0xE0, (byte) 0xE3, 94, 1,
            (byte) 0xCC, (byte) 0xDD
        });

        assertFalse(BleManager.responseHasMinimumPayload(
            emptyAck, AhaKeyProtocol.CMD_VOICE_KEY_CONFIG, 4));
        assertTrue(BleManager.responseHasMinimumPayload(
            fullReadback, AhaKeyProtocol.CMD_VOICE_KEY_CONFIG, 4));
    }

    @Test
    void describesFlashWriteErrorsWithoutAmbiguousCodeOnlyMessage() {
        assertEquals("外部 Flash 未识别或尚未就绪", BleManager.deviceStatusText(5));
        assertEquals("写入超出实际 Flash 容量", BleManager.deviceStatusText(6));
        assertEquals("Flash 写入地址未按 4K 对齐", BleManager.deviceStatusText(8));
    }
}
