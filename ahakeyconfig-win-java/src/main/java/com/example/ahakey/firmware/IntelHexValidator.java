package com.example.ahakey.firmware;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;

/** Structural and absolute-address validation for CH582 Intel HEX images. */
public final class IntelHexValidator {
    private IntelHexValidator() {}

    public static void validate(Path path) throws IOException {
        if (!Files.isRegularFile(path)) throw new IOException("固件文件不存在");
        List<String> lines = Files.readAllLines(path, StandardCharsets.US_ASCII);
        boolean eof = false;
        boolean data = false;
        long linearBase = 0;
        long segmentBase = 0;
        List<long[]> ranges = new ArrayList<>();
        for (int lineNumber = 1; lineNumber <= lines.size(); lineNumber++) {
            String line = lines.get(lineNumber - 1).trim();
            if (line.isEmpty()) continue;
            if (eof) throw new IOException("Intel HEX EOF 后仍有数据（第 " + lineNumber + " 行）");
            if (!line.startsWith(":") || (line.length() & 1) == 0) {
                throw new IOException("Intel HEX 行格式无效（第 " + lineNumber + " 行）");
            }
            byte[] record;
            try {
                record = HexFormat.of().parseHex(line.substring(1));
            } catch (IllegalArgumentException invalidHex) {
                throw new IOException("Intel HEX 含非十六进制字符（第 " + lineNumber + " 行）");
            }
            int count = record.length == 0 ? -1 : record[0] & 0xFF;
            if (record.length < 5 || count + 5 != record.length) {
                throw new IOException("Intel HEX 字节数不匹配（第 " + lineNumber + " 行）");
            }
            int sum = 0;
            for (byte value : record) sum = (sum + (value & 0xFF)) & 0xFF;
            if (sum != 0) throw new IOException("Intel HEX 校验和错误（第 " + lineNumber + " 行）");
            int type = record[3] & 0xFF;
            int address = ((record[1] & 0xFF) << 8) | (record[2] & 0xFF);
            if (type == 0) {
                data = true;
                long absolute = linearBase + segmentBase + address;
                long end = absolute + count - 1L;
                if (absolute < 0 || end < absolute
                    || end > FirmwareCapabilities.MAX_FIRMWARE_ADDRESS) {
                    throw new IOException("Intel HEX 地址超出 CH582 发布范围（第 "
                        + lineNumber + " 行）");
                }
                for (long[] range : ranges) {
                    if (absolute <= range[1] && end >= range[0]) {
                        throw new IOException("Intel HEX 数据地址重叠（第 "
                            + lineNumber + " 行）");
                    }
                }
                ranges.add(new long[]{absolute, end});
            } else if (type == 1) {
                if (count != 0) throw new IOException("Intel HEX EOF 记录无效");
                eof = true;
            } else if (type == 2 || type == 4) {
                if (count != 2) {
                    throw new IOException("Intel HEX 扩展地址记录无效（第 "
                        + lineNumber + " 行）");
                }
                int upper = ((record[4] & 0xFF) << 8) | (record[5] & 0xFF);
                if (type == 2) {
                    segmentBase = ((long) upper) << 4;
                    linearBase = 0;
                } else {
                    linearBase = ((long) upper) << 16;
                    segmentBase = 0;
                }
            } else if (type == 3 || type == 5) {
                if (count != 4) {
                    throw new IOException("Intel HEX 起始地址记录无效（第 "
                        + lineNumber + " 行）");
                }
            } else if (type > 5) {
                throw new IOException("Intel HEX 记录类型不受支持：" + type);
            }
        }
        if (!data || !eof) throw new IOException("Intel HEX 必须包含数据记录和 EOF 记录");
    }
}
