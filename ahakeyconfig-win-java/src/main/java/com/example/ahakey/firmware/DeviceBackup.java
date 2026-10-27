package com.example.ahakey.firmware;

import java.io.IOException;
import java.util.*;

/** Only immutable values; device facts and PC files are deliberately separate. */
public record DeviceBackup(int schema, String operationId, DeviceMaintenanceCoordinator.Identity source, String targetHash,
                           Set<String> capabilities, List<Key> keys, Side side, Integer brightness, List<Light> lights,
                           Map<String, PcFile> pcFiles) {
    public record Key(int mode, int index, int actionType, String payloadHex, String description) {}
    public record Side(int upBinding, String upHex, int downBinding, String downHex) {}
    public record Light(int mode, int ai, int effect) {}
    public record PcFile(boolean present, String base64) {}
    public DeviceBackup { capabilities = Set.copyOf(capabilities); keys = List.copyOf(keys); lights = List.copyOf(lights); pcFiles = Map.copyOf(pcFiles); }
    public void validate() throws IOException {
        if (schema != 1 || operationId == null || source == null || !targetHash.matches("[a-f0-9]{64}")) throw new IOException("备份身份无效。");
        if (capabilities.contains("keys")) {
            Set<String> selectors = new HashSet<>();
            for (Key key : keys) {
                if (key.mode < 0 || key.mode > 3 || key.index < 0 || key.index > 3 || !selectors.add(key.mode + ":" + key.index)
                        || key.payloadHex == null || !key.payloadHex.matches("(?:[a-f0-9]{2})*") || key.description == null) throw new IOException("备份按键数据无效。");
            }
            for (Key key : keys) {
                int bytes = key.payloadHex.length() / 2;
                if ((key.actionType != 0 && key.actionType != 0x73 && key.actionType != 0x74) || (key.actionType == 0 && bytes != 0)
                        || (key.actionType == 0x74 && bytes % 2 != 0) || key.description.length() > 20
                        || !key.description.matches("[ -~]*") || bytes + key.description.length() > 53)
                    throw new IOException("按键动作无法按原协议可靠恢复。");
            }
            if (selectors.size() != 16) throw new IOException("备份必须包含所有 4 Mode 的普通键。");
        }
        if (capabilities.contains("side") && (side == null || !side.upHex.matches("(?:[a-f0-9]{2})*") || !side.downHex.matches("(?:[a-f0-9]{2})*"))) throw new IOException("侧拨备份不完整。");
        if (side != null) {
            if(side.upBinding<0||side.upBinding>3||side.downBinding<0||side.downBinding>3)throw new IOException("侧拨绑定不支持。");
            try {
                byte[] encoded=com.example.ahakey.protocol.AhaKeyProtocol.setSideSwitchConfig(side.upBinding,HexFormat.of().parseHex(side.upHex),side.downBinding,HexFormat.of().parseHex(side.downHex));
                if (encoded.length>62) throw new IOException("侧拨写帧超过 USB 上限。");
                if ((side.upBinding!=3&&!side.upHex.isEmpty())||(side.downBinding!=3&&!side.downHex.isEmpty()))throw new IOException("侧拨快照含不可恢复的非自定义动作。");
            } catch(IllegalArgumentException e){throw new IOException("侧拨动作无法可靠恢复。",e);}
        }
        if (capabilities.contains("lights")) {
            if (brightness == null || brightness < 1 || brightness > 100) throw new IOException("亮度备份无效。");
            Set<String> selectors = new HashSet<>();
            for (Light l : lights) if (l.mode < 0 || l.mode > 3 || l.ai < 0 || l.ai > 8 || l.effect < 0 || l.effect > 16 || !selectors.add(l.mode + ":" + l.ai)) throw new IOException("灯效备份无效。");
            if (selectors.size() != 36) throw new IOException("备份缺少 4×9 灯效。");
        }
        for (String name : List.of("studio-draft.json", "ai-runtime.json")) {
            PcFile file = pcFiles.get(name);
            if (file == null) throw new IOException("PC 草稿快照缺失。");
            try {
                if (file.present) {
                    var json = new com.fasterxml.jackson.databind.ObjectMapper().readTree(Base64.getDecoder().decode(file.base64));
                    if (json == null || !json.isObject()) throw new IOException("PC 草稿必须是 JSON 对象。");
                }
            }
            catch (Exception e) { throw new IOException("PC 草稿快照损坏。", e); }
        }
    }
}
