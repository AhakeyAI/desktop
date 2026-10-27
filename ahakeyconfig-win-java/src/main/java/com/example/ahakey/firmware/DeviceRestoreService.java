package com.example.ahakey.firmware;

import com.example.ahakey.protocol.*;
import com.example.ahakey.service.*;
import java.io.IOException;
import java.util.*;

public final class DeviceRestoreService {
    public record Item(String name, String status, String detail) {}
    public record Report(List<Item> items) { public Report { items = List.copyOf(items); } public boolean complete() { return items.stream().noneMatch(i -> i.status.equals("FAILED")); } }
    public interface Device {
        void key(DeviceBackup.Key key) throws Exception;
        void side(DeviceBackup.Side side) throws Exception;
        void brightness(int value) throws Exception;
        void light(DeviceBackup.Light light) throws Exception;
    }
    public Report restore(DeviceBackup backup, Set<String> targetCapabilities, Device device) throws IOException {
        backup.validate(); if (targetCapabilities.isEmpty()) throw new IOException("目标能力未知，禁止恢复。");
        List<Item> result = new ArrayList<>();
        for (DeviceBackup.Key key : backup.keys()) attempt(result, "Mode " + (key.mode()+1) + " / Key " + (key.index()+1), targetCapabilities.contains("keys"), () -> device.key(key));
        if (backup.side() != null) attempt(result, "Side switch", targetCapabilities.contains("side"), () -> device.side(backup.side()));
        if (backup.brightness() != null) attempt(result, "Brightness", targetCapabilities.contains("lights"), () -> device.brightness(backup.brightness()));
        for (DeviceBackup.Light light : backup.lights()) attempt(result, "Mode " + (light.mode()+1) + " / AI " + light.ai(), targetCapabilities.contains("lights"), () -> device.light(light));
        return new Report(result);
    }
    @FunctionalInterface private interface Action { void run() throws Exception; }
    private void attempt(List<Item> result, String name, boolean supported, Action action) {
        if (!supported) { result.add(new Item(name, "SKIPPED", "目标能力不支持；原备份保留")); return; }
        // Stop after an uncertain failure. Never automatically repeat a write or contaminate remaining items.
        if (result.stream().anyMatch(i -> i.status.equals("FAILED"))) { result.add(new Item(name, "SKIPPED", "前项失败，未执行")); return; }
        try { action.run(); result.add(new Item(name, "CONFIRMED", "ACK 与读回一致")); }
        catch (Exception e) { result.add(new Item(name, "FAILED", e.getMessage() == null ? e.toString() : e.getMessage())); }
    }
    public static Device ble(BleManager ble) {
        return new Device() {
            public void key(DeviceBackup.Key key) throws Exception {
                for (byte[] command : DeviceSyncService.restoreKeyCommands(key)) ble.sendCommandExpecting(command, command[2]);
                var read = ble.readOrdinaryKeyConfig(key.mode(), key.index());
                if (read.mode() != key.mode() || read.keyIndex() != key.index() || (read.actionType() != key.actionType() && !(key.payloadHex().isEmpty() && (key.actionType()==0 || key.actionType()==0x73) && (read.actionType()==0 || read.actionType()==0x73)))
                        || !HexFormat.of().formatHex(read.actionPayload()).equals(key.payloadHex()) || !read.description().equals(key.description())) throw new IOException("普通键读回不一致。");
            }
            public void side(DeviceBackup.Side side) throws Exception {
                ble.writeSideSwitchConfig(new AhaKeyResponseParser.SideSwitchConfig(0,
                        new AhaKeyResponseParser.SideSwitchPositionConfig(side.upBinding(), HexFormat.of().parseHex(side.upHex())),
                        new AhaKeyResponseParser.SideSwitchPositionConfig(side.downBinding(), HexFormat.of().parseHex(side.downHex()))));
                var read = ble.readSideSwitchConfig();
                if (read.up().binding()!=side.upBinding() || read.down().binding()!=side.downBinding()
                        || !HexFormat.of().formatHex(read.up().actionPayload()).equals(side.upHex()) || !HexFormat.of().formatHex(read.down().actionPayload()).equals(side.downHex())) throw new IOException("侧拨读回不一致。");
            }
            public void brightness(int value) throws Exception { display(AhaKeyProtocol.saveDisplayBrightness(value), 0, value); }
            public void light(DeviceBackup.Light l) throws Exception { display(AhaKeyProtocol.saveDisplayLight(l.mode(),l.ai(),l.effect()), 1, l.effect(), l.mode(), l.ai()); }
            private void display(byte[] save, int kind, int value, int... selectors) throws Exception {
                try (var lease = ble.openDisplayLease(true)) {
                    OledUploadService.requireAck(ble.exchangeDisplay(lease, save), AhaKeyProtocol.CMD_DISPLAY_SAVE);
                    var read = AhaKeyResponseParser.parseDisplayRead(ble.exchangeDisplay(lease, AhaKeyProtocol.displayRead(kind, selectors)), kind, selectors);
                    if (read == null || read.value()!=value) throw new IOException("灯光读回不一致。");
                }
            }
        };
    }
}
