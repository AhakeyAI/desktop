package com.example.ahakey.firmware;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/** Structural Intel HEX validation used before invoking the programmer. */
public final class IntelHexValidator {
    private IntelHexValidator() {}

    public static void validate(Path path) throws IOException {
        if (!Files.isRegularFile(path)) throw new IOException("固件文件不存在");
        List<String> lines = Files.readAllLines(path, StandardCharsets.US_ASCII);
        boolean eof = false;
        boolean data = false;
        for (int lineNumber = 1; lineNumber <= lines.size(); lineNumber++) {
            String line = lines.get(lineNumber - 1).trim();
            if (line.isEmpty()) continue;
            if (eof) throw new IOException("Intel HEX EOF 后仍有数据（第 " + lineNumber + " 行）");
            if (!line.startsWith(":") || (line.length() & 1) == 0) {
                throw new IOException("Intel HEX 行格式无效（第 " + lineNumber + " 行）");
            }
            byte[] record;
            try {
                record = java.util.HexFormat.of().parseHex(line.substring(1));
            } catch (IllegalArgumentException invalidHex) {
                throw new IOException("Intel HEX 含非十六进制字符（第 " + lineNumber + " 行）");
            }
            if (record.length < 5 || (record[0] & 0xFF) + 5 != record.length) {
                throw new IOException("Intel HEX 字节数不匹配（第 " + lineNumber + " 行）");
            }
            int sum = 0;
            for (byte value : record) sum = (sum + (value & 0xFF)) & 0xFF;
            if (sum != 0) throw new IOException("Intel HEX 校验和错误（第 " + lineNumber + " 行）");
            int type = record[3] & 0xFF;
            if (type == 0) data = true;
            else if (type == 1) {
                if ((record[0] & 0xFF) != 0) throw new IOException("Intel HEX EOF 记录无效");
                eof = true;
            } else if (type > 5) {
                throw new IOException("Intel HEX 记录类型不受支持：" + type);
            }
        }
        if (!data || !eof) throw new IOException("Intel HEX 必须包含数据记录和 EOF 记录");
    }
}
