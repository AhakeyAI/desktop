package com.example.ahakey.test;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.HIDUsage;
import com.example.ahakey.model.KeyConfig;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.model.VoicePreset;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.service.BleManager;
import com.example.ahakey.util.KeyBindingDiffer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/**
 * 调试工具:读 EEPROM 后模拟 loadEepromIntoStudioState,确认 KEY1 是否被改
 */
public class KeyBindingQueryDemo {
    private static final Logger logger = LoggerFactory.getLogger(KeyBindingQueryDemo.class);

    public static void main(String[] args) {
        CountDownLatch connectLatch = new CountDownLatch(1);
        String[] errorHolder = new String[1];

        BleManager ble = BleManager.fromEnvironment(new BleManager.BleCallback() {
            @Override public void onConnected() { connectLatch.countDown(); }
            @Override public void onDisconnected() { }
            @Override public void onStatusReceived(DeviceStatus status) { }
            @Override public void onError(String message) { errorHolder[0] = message; }
        });

        ble.connect();
        boolean connected;
        try {
            connected = connectLatch.await(15, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return;
        }
        if (!connected) {
            System.out.println("未连接上设备");
            return;
        }
        try { Thread.sleep(500); } catch (InterruptedException ignored) {}

        // 1. 读 KEY1 EEPROM 原始数据
        AhaKeyResponseParser.FullKeyBinding b0 = null;
        try {
            b0 = ble.readKeyBindingFull(0, 0);
        } catch (Exception e) {
            System.out.println("readKeyBindingFull 失败: " + e.getMessage());
        }

        if (b0 != null) {
            System.out.println("EEPROM KEY1 (Mode 0, Key 1):");
            System.out.println("  sub      = 0x" + String.format("%02X", b0.sub() & 0xFF));
            System.out.println("  bindLen  = " + b0.bindLen());
            System.out.print  ("  hidBytes =");
            for (byte hb : b0.hidBytes()) {
                System.out.print(" 0x" + String.format("%02X", hb & 0xFF));
            }
            System.out.println();
        } else {
            System.out.println("EEPROM KEY1 读取失败(返 null)");
        }

        // 2. 模拟 loadEepromIntoStudioState
        StudioState studioState = new StudioState();
        System.out.println();
        System.out.println("=== StudioState 默认 KEY1 ===");
        KeyConfig k1Default = studioState.getKeyConfig(ModeSlot.MODE0, StudioPart.KEY1);
        System.out.println("  voicePreset = " + k1Default.getVoicePreset());
        System.out.println("  hidCode     = 0x" + String.format("%X", k1Default.getHidCode()));
        System.out.println("  description = " + k1Default.getDescription());
        System.out.println("  displaySummary = " + k1Default.getDisplaySummary());

        if (b0 != null) {
            KeyBindingDiffer.applyRevert(b0, k1Default);
            System.out.println();
            System.out.println("=== applyRevert 后 KEY1 ===");
            System.out.println("  voicePreset = " + k1Default.getVoicePreset());
            System.out.println("  hidCode     = 0x" + String.format("%X", k1Default.getHidCode()));
            System.out.println("  description = " + k1Default.getDescription());
            System.out.println("  displaySummary = " + k1Default.getDisplaySummary());
            System.out.println("  formatKeyConfig = " + KeyBindingDiffer.formatKeyConfig(k1Default));
        }

        ble.disconnect();
        System.exit(0);
    }
}
