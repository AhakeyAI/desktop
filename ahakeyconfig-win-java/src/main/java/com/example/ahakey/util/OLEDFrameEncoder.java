package com.example.ahakey.util;

import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.service.GifUploadRules;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import javax.imageio.metadata.IIOMetadata;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;
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

    public record EncodedAnimation(
        List<EncodedFrame> frames,
        int frameIntervalMs,
        long sourceDurationMs,
        boolean optimized
    ) {}

    private OLEDFrameEncoder() {
    }

    public static void validateGifSourceFileSize(Path path) throws IOException {
        long size = Files.size(path);
        if (size > GifUploadRules.MAX_SOURCE_BYTES) {
            throw new IOException("源文件超过 2 MB 上限（当前约 " + (size / 1024) + " KB）。请压缩图片/GIF 后重新选择。");
        }
    }

    public static GifUploadRules.Preflight preflight(Path gifPath, int asset)
        throws IOException {
        long bytes = Files.size(gifPath);
        if (bytes > GifUploadRules.HARD_DECODE_LIMIT_BYTES) {
            throw new IOException("源 GIF 超过 20 MB 安全解码上限。");
        }
        try (ImageInputStream stream = ImageIO.createImageInputStream(gifPath.toFile())) {
            Iterator<ImageReader> readers = ImageIO.getImageReadersByFormatName("gif");
            if (!readers.hasNext()) throw new IOException("无法读取 GIF 文件。");
            ImageReader reader = readers.next();
            try {
                reader.setInput(stream, false);
                int count = reader.getNumImages(true);
                if (count < 1 || count > GifUploadRules.MAX_DECODE_FRAMES) {
                    throw new IOException("GIF 帧数超出安全解码范围（1–"
                        + GifUploadRules.MAX_DECODE_FRAMES + "）。");
                }
                long duration = 0;
                for (int i = 0; i < count; i++) duration += frameDelayMs(reader, i);
                return new GifUploadRules.Preflight(
                    gifPath, bytes, reader.getWidth(0), reader.getHeight(0), count,
                    duration, GifUploadRules.frameLimit(asset));
            } finally {
                reader.dispose();
            }
        }
    }

    public static EncodedAnimation optimizedAnimation(Path gifPath, int asset)
        throws IOException {
        GifUploadRules.Preflight preflight = preflight(gifPath, asset);
        try (ImageInputStream stream = ImageIO.createImageInputStream(gifPath.toFile())) {
            Iterator<ImageReader> readers = ImageIO.getImageReadersByFormatName("gif");
            if (!readers.hasNext()) throw new IOException("无法读取 GIF 文件。");
            ImageReader reader = readers.next();
            try {
                reader.setInput(stream, false);
                int count = reader.getNumImages(true);
                int[] delays = new int[count];
                for (int i = 0; i < count; i++) delays[i] = frameDelayMs(reader, i);
                GifUploadRules.OptimizationPlan plan =
                    GifUploadRules.plan(delays, GifUploadRules.frameLimit(asset));
                List<EncodedFrame> frames = new ArrayList<>(plan.outputFrameCount());
                for (int index : plan.sourceIndices()) {
                    BufferedImage frame = reader.read(index);
                    if (frame == null) throw new IOException("GIF 第 " + index + " 帧无法读取。");
                    frames.add(encodeFrame(frame));
                }
                return new EncodedAnimation(
                    frames, plan.frameIntervalMs(), plan.sourceDurationMs(),
                    preflight.needsOptimization());
            } finally {
                reader.dispose();
            }
        }
    }

    private static int frameDelayMs(ImageReader reader, int imageIndex) {
        try {
            IIOMetadata metadata = reader.getImageMetadata(imageIndex);
            Node root = metadata.getAsTree("javax_imageio_gif_image_1.0");
            Node graphic = findNode(root, "GraphicControlExtension");
            if (graphic != null) {
                NamedNodeMap attributes = graphic.getAttributes();
                Node delay = attributes == null ? null : attributes.getNamedItem("delayTime");
                if (delay != null) {
                    int hundredths = Integer.parseInt(delay.getNodeValue());
                    if (hundredths > 0) return hundredths * 10;
                }
            }
        } catch (Exception ignored) {
            // Malformed/missing timing has a deterministic safe default.
        }
        return GifUploadRules.DEFAULT_FRAME_DELAY_MS;
    }

    private static Node findNode(Node node, String name) {
        if (node == null) return null;
        if (name.equals(node.getNodeName())) return node;
        for (Node child = node.getFirstChild(); child != null; child = child.getNextSibling()) {
            Node found = findNode(child, name);
            if (found != null) return found;
        }
        return null;
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
                int count = reader.getNumImages(true);
                if (count > maxFrames) {
                    throw new IOException("GIF 帧数超过设备上限，请先确认并优化后再上传。");
                }
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
