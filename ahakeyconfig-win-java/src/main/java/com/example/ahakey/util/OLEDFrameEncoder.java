package com.example.ahakey.util;

import com.example.ahakey.protocol.AhaKeyProtocol;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

public final class OLEDFrameEncoder {
    public static class EncodedFrame {
        public final byte[] rgb565;
        public final BufferedImage preview;

        public EncodedFrame(byte[] rgb565, BufferedImage preview) {
            this.rgb565 = rgb565;
            this.preview = preview;
        }
    }

    private OLEDFrameEncoder() {
    }

    public static void validateGifSourceFileSize(Path path) throws IOException {
        long size = Files.size(path);
        if (size > AhaKeyProtocol.OLED_MAX_SOURCE_FILE_BYTES) {
            throw new IOException("源文件超过 2 MB 上限（当前约 " + (size / 1024) + " KB）。请压缩图片/GIF 后重新选择。");
        }
    }

    public static int frameCount(Path gifPath) throws IOException {
        try (ImageInputStream stream = ImageIO.createImageInputStream(gifPath.toFile())) {
            Iterator<ImageReader> readers = ImageIO.getImageReadersByFormatName("gif");
            if (!readers.hasNext()) {
                return 0;
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(stream, false);
                return reader.getNumImages(true);
            } finally {
                reader.dispose();
            }
        }
    }

    public static List<EncodedFrame> framesFromGif(Path gifPath) throws IOException {
        return framesFromGif(gifPath, AhaKeyProtocol.OLED_MAX_FRAMES);
    }

    public static List<EncodedFrame> framesFromGif(Path gifPath, int maxFrames) throws IOException {
        validateGifSourceFileSize(gifPath);
        if (maxFrames <= 0 || maxFrames > AhaKeyProtocol.OLED_MAX_FRAMES) {
            throw new IOException("GIF 帧数超出可上传范围。");
        }
        List<BufferedImage> images = new ArrayList<>();
        try (ImageInputStream stream = ImageIO.createImageInputStream(gifPath.toFile())) {
            Iterator<ImageReader> readers = ImageIO.getImageReadersByFormatName("gif");
            if (!readers.hasNext()) {
                throw new IOException("无法读取 GIF 文件。");
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(stream, false);
                int count = Math.min(reader.getNumImages(true), maxFrames);
                if (count <= 0) {
                    throw new IOException("GIF 没有可编码的帧。");
                }
                for (int i = 0; i < count; i++) {
                    BufferedImage frame = reader.read(i);
                    if (frame != null) {
                        images.add(frame);
                    }
                }
            } finally {
                reader.dispose();
            }
        }
        if (images.isEmpty()) {
            throw new IOException("GIF 没有可编码的帧。");
        }
        List<EncodedFrame> out = new ArrayList<>(images.size());
        for (BufferedImage image : images) {
            out.add(encodeFrame(image));
        }
        return out;
    }

    public static EncodedFrame encodeFrame(BufferedImage source) {
        int width = AhaKeyProtocol.OLED_WIDTH;
        int height = AhaKeyProtocol.OLED_HEIGHT;
        BufferedImage canvas = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = canvas.createGraphics();
        g.setColor(java.awt.Color.BLACK);
        g.fillRect(0, 0, width, height);
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);

        double scale = Math.min((double) width / source.getWidth(), (double) height / source.getHeight());
        int drawW = (int) Math.round(source.getWidth() * scale);
        int drawH = (int) Math.round(source.getHeight() * scale);
        int x = (width - drawW) / 2;
        int y = (height - drawH) / 2;
        g.drawImage(source, x, y, drawW, drawH, null);
        g.dispose();

        byte[] rgb565 = toRgb565BigEndian(canvas);
        return new EncodedFrame(rgb565, canvas);
    }

    public static EncodedFrame frameFromSingleImage(Path imagePath) throws IOException {
        validateGifSourceFileSize(imagePath);
        BufferedImage source = ImageIO.read(imagePath.toFile());
        if (source == null) {
            throw new IOException("无法读取图片文件：" + imagePath);
        }
        return encodeFrame(source);
    }

    private static byte[] toRgb565BigEndian(BufferedImage image) {
        int w = image.getWidth();
        int h = image.getHeight();
        byte[] data = new byte[w * h * 2];
        int idx = 0;
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int rgb = image.getRGB(x, y);
                int r = (rgb >> 16) & 0xFF;
                int g = (rgb >> 8) & 0xFF;
                int b = rgb & 0xFF;
                int value = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
                data[idx++] = (byte) ((value >> 8) & 0xFF);
                data[idx++] = (byte) (value & 0xFF);
            }
        }
        return data;
    }
}
