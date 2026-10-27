package com.example.ahakey.firmware;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.BitSet;
import java.util.HexFormat;

public final class IntelHexValidator {
    public static final int CODE_BYTES = 448 * 1024;
    public record Result(int bytes, int firstAddress, int lastAddress) {}
    public static Result validate(Path file) throws IOException {
        if (Files.size(file) > 4 * 1024 * 1024) throw new IOException("HEX 文件过大。");
        return validate(Files.readString(file, StandardCharsets.US_ASCII));
    }
    public static Result validate(String text) throws IOException {
        BitSet written = new BitSet(CODE_BYTES);
        long base = 0;
        boolean eof = false;
        int count = 0;
        for (String line : text.split("\\R")) {
            if (line.isBlank()) continue;
            if (eof || !line.startsWith(":")) throw new IOException("HEX EOF 或记录格式无效。");
            byte[] record;
            try { record = HexFormat.of().parseHex(line.substring(1)); }
            catch (IllegalArgumentException e) { throw new IOException("HEX 记录不是十六进制。", e); }
            if (record.length < 5 || record.length != (record[0] & 255) + 5) throw new IOException("HEX 长度错误。");
            int sum = 0; for (byte b : record) sum += b & 255;
            if ((sum & 255) != 0) throw new IOException("HEX 校验和错误。");
            int n = record[0] & 255, address = (record[1] & 255) * 256 + (record[2] & 255), type = record[3] & 255;
            switch (type) {
                case 0 -> {
                    long start = base + address, end = start + n;
                    if (end > CODE_BYTES || start < 0 || address + n > 65536) throw new IOException("HEX 超出 CH582 CodeFlash 范围。");
                    for (int i = (int) start; i < end; i++) {
                        if (written.get(i)) throw new IOException("HEX 地址重叠。");
                        written.set(i); count++;
                    }
                }
                case 1 -> { if (n != 0 || address != 0) throw new IOException("HEX EOF 错误。"); eof = true; }
                case 2, 4 -> {
                    if (n != 2 || address != 0) throw new IOException("HEX 扩展地址错误。");
                    base = ((record[4] & 255L) * 256 + (record[5] & 255L)) << (type == 2 ? 4 : 16);
                    if (base >= CODE_BYTES) throw new IOException("HEX 扩展地址越界。");
                }
                case 3, 5 -> {
                    if (n != 4 || address != 0) throw new IOException("HEX 入口记录错误。");
                    long entry = type == 5 ? ((record[4] & 255L) << 24) | ((record[5] & 255L) << 16) | ((record[6] & 255L) << 8) | (record[7] & 255L)
                            : (((record[4] & 255L) * 256 + (record[5] & 255L)) << 4) + (record[6] & 255L) * 256 + (record[7] & 255L);
                    if (entry >= CODE_BYTES) throw new IOException("HEX 入口超出 CodeFlash。");
                }
                default -> throw new IOException("HEX 记录类型不支持。");
            }
        }
        if (!eof || count == 0) throw new IOException("HEX 缺少 EOF 或程序数据。");
        return new Result(count, written.nextSetBit(0), written.length() - 1);
    }
}
