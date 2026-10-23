package com.example.ahakey.service;

/** CP2 psk_ws2812.c / display_preview.c, 50 ms ticks, reset to firmware static initial phases. */
public final class FirmwareLightSimulator {
    private int position, direction = 1, hue, breath, fade = 1, ripple, comet, cometDir = 1;
    private int scan, scanDir = 1, pulse, warn, success, think, low, charge, approval;
    private final int[][] pixels = new int[8][4];

    public int[] step(int effect, int brightness) {
        if (effect < 0 || effect > 16 || brightness < 1 || brightness > 100) throw new IllegalArgumentException("light parameters");
        for (int[] pixel : pixels) java.util.Arrays.fill(pixel, 0);
        switch (effect) {
            case 0 -> { }
            case 1 -> {
                for (int i = 0; i < 8; i++) {
                    int distance = Math.abs(i - position);
                    if (distance <= 2) set(i, 0x10, 0x20, 0x80, distance == 0 ? 160 : distance == 1 ? 55 : 30);
                }
                move();
            }
            case 2, 3, 4 -> {
                for (int i = 0; i < 8; i++) {
                    int h = (i * 32 + hue) & 255, region = h / 43, remainder = (h - region * 43) * 6;
                    int alpha = 120;
                    if (effect == 2) { int distance = Math.abs(i - position); alpha = distance == 0 ? 150 : distance == 1 ? 55 : distance == 2 ? 30 : 1; }
                    switch (region) {
                        case 0 -> set(i, 120, remainder / 2, 0, alpha);
                        case 1 -> set(i, (255 - remainder) / 2, 120, 0, alpha);
                        case 2 -> set(i, 0, 120, remainder / 2, alpha);
                        case 3 -> set(i, 0, (255 - remainder) / 2, 120, alpha);
                        case 4 -> set(i, remainder / 2, 0, 120, alpha);
                        default -> set(i, 120, 0, (255 - remainder) / 2, alpha);
                    }
                }
                hue = (hue - (effect == 4 ? 2 : 10)) & 255;
                if (effect == 2) move();
            }
            case 5 -> {
                for (int i = 0; i < 8; i++) set(i, 0x10, 0x20, 0x80, breath);
                breath = (breath + fade * 8) & 255;
                if (breath >= 140) { breath = 140; fade = -1; }
                else if (breath <= 20) { breath = 20; fade = 1; }
            }
            case 6 -> {
                int[] alpha = {1, 15, 60, 130};
                for (int i = 0; i < 8; i++) set(i, 0x10, 0x20, 0x80, alpha[Math.min(i, 7 - i)]);
            }
            case 7 -> {
                for (int i = 0; i < 8; i++) {
                    int wave = ripple - Math.min(Math.abs(i - 3), Math.abs(i - 4)) * 28;
                    if (wave >= 0 && wave < 80) set(i, 8, 0x50, 0x60, wave < 32 ? wave * 4 : (80 - wave) * 2);
                }
                ripple += 12; if (ripple >= 150) ripple = 0;
            }
            case 8 -> {
                int[] tail = {160, 90, 45, 20, 8};
                for (int i = 0; i < 8; i++) if (Math.abs(i - comet) < 5) set(i, 0x80, 0x28, 0x10, tail[Math.abs(i - comet)]);
                comet += cometDir; if (comet >= 7) { comet = 7; cometDir = -1; } else if (comet == 0) cometDir = 1;
            }
            case 9 -> {
                set(scan, 0x40, 0x40, 0x50, 140);
                if (scan < 7) set(scan + 1, 8, 0x50, 0x60, 80);
                if (scan > 0) set(scan - 1, 8, 0x50, 0x60, 35);
                scan += scanDir; if (scan >= 7) { scan = 7; scanDir = -1; } else if (scan == 0) scanDir = 1;
            }
            case 10 -> {
                int core = 35 + triangle(pulse) / 4;
                set(3, 0x10, 0x28, 0x80, core); set(4, 0x10, 0x28, 0x80, core);
                set(2, 0x10, 0x28, 0x80, core / 3); set(5, 0x10, 0x28, 0x80, core / 3);
                pulse = (pulse + 6) & 255;
            }
            case 11 -> {
                boolean on = warn % 18 < 5 || (warn + 8) % 18 < 3;
                for (int i = 0; i < 8; i++) if (on) set(i, 0x80, i % 2 == 1 ? 0x10 : 0x30, 0, 150); else set(i, 0x18, 0, 0, 15);
                warn = (warn + 1) & 255;
            }
            case 12 -> {
                for (int i = 0; i < 8; i++) {
                    if (i <= success) set(i, 8, 0x70, 0x24, 100);
                    if (i == success) set(i, 0x30, 0x70, 0x30, 120);
                }
                success++; if (success >= 13) success = 0;
            }
            case 13 -> {
                for (int i = 0; i < 8; i++) set(i, 8, 0x20, 0x80, 20 + triangle(think + i * 24) / 4);
                think = (think + 5) & 255;
            }
            case 14 -> {
                boolean edge = low % 24 < 8;
                for (int i = 0; i < 8; i++) if (i == 0 || i == 7) set(i, 0x80, 0, 0, edge ? 150 : 25); else set(i, 0x18, 0, 0, edge ? 20 : 8);
                low = (low + 1) & 255;
            }
            case 15 -> {
                int fill = charge % 12;
                for (int i = 0; i < 8; i++) if (i < fill) set(i, 8, 0x70, 0x28, 100); else set(i, 0, 0x18, 8, 12);
                if (fill < 8) set(fill, 0x30, 0x70, 0x30, 120);
                charge = (charge + 1) & 255;
            }
            case 16 -> {
                for (int i = 0; i < 8; i++) set(i, 0x80, 0x30, 8, 30 + triangle(approval) / 4);
                if (approval % 64 < 10) { set(3, 0x70, 0x60, 0x30, 120); set(4, 0x70, 0x60, 0x30, 120); }
                approval = (approval + 4) & 255;
            }
        }
        int[] output = new int[8];
        for (int i = 0; i < 8; i++) {
            int[] p = pixels[i];
            int level = p[3] == 0 ? brightness : (p[3] * brightness) >> 8;
            output[i] = ((p[0] * level >> 8) << 16) | ((p[1] * level >> 8) << 8) | (p[2] * level >> 8);
        }
        return output;
    }
    private int triangle(int phase) { phase &= 255; return phase < 128 ? phase * 2 : (255 - phase) * 2; }
    private void set(int i, int r, int g, int b, int alpha) { pixels[i][0] = r; pixels[i][1] = g; pixels[i][2] = b; pixels[i][3] = alpha; }
    private void move() { position += direction; if (position >= 7) { position = 7; direction = -1; } else if (position <= 0) { position = 0; direction = 1; } }
}
