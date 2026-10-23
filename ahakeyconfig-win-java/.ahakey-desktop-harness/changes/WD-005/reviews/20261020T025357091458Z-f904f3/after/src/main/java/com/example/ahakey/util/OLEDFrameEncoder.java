package com.example.ahakey.util;

import com.example.ahakey.protocol.AhaKeyProtocol;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.AlphaComposite;
import org.w3c.dom.Node;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

public final class OLEDFrameEncoder {
    private static final long MAX_DECODE_PIXELS = 16_777_216;
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
            throw new IOException("文件不适用：源文件超过 2 MiB 上限（当前约 " + (size / 1024) + " KiB）。");
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
        return framesFromGif(gifPath, 12);
    }

    public static List<EncodedFrame> framesFromGif(Path gifPath, int maxFrames) throws IOException {
        validateGifSourceFileSize(gifPath);
        if (maxFrames <= 0 || maxFrames > 12) {
            throw new IOException("GIF 帧数超出可上传范围。");
        }
        List<EncodedFrame> out = new ArrayList<>();
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
                    throw new IOException("当前 GIF 有 " + count + " 帧，目标位置最多支持 " + maxFrames + " 帧。请减少帧数。");
                }
                if (count <= 0) {
                    throw new IOException("GIF 没有可编码的帧。");
                }
                Node streamMetadata = reader.getStreamMetadata().getAsTree("javax_imageio_gif_stream_1.0");
                Node logical = child(streamMetadata, "LogicalScreenDescriptor");
                int width = attributeInt(logical, "logicalScreenWidth");
                int height = attributeInt(logical, "logicalScreenHeight");
                validateDimensions(width, height);
                BufferedImage canvas = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
                int background = gifBackground(streamMetadata);
                for (int i = 0; i < count; i++) {
                    Node metadata = reader.getImageMetadata(i).getAsTree("javax_imageio_gif_image_1.0");
                    Node descriptor = child(metadata, "ImageDescriptor");
                    Node control = child(metadata, "GraphicControlExtension");
                    int x = attributeInt(descriptor, "imageLeftPosition");
                    int y = attributeInt(descriptor, "imageTopPosition");
                    int w = attributeInt(descriptor, "imageWidth");
                    int h = attributeInt(descriptor, "imageHeight");
                    if (x < 0 || y < 0 || w <= 0 || h <= 0 || (long) x + w > width || (long) y + h > height)
                        throw new IOException("文件不适用：GIF 局部帧超出逻辑画布。");
                    String disposal = attribute(control, "disposalMethod");
                    boolean transparent = "TRUE".equalsIgnoreCase(attribute(control, "transparentColorFlag"));
                    if (i == 0 && !transparent) {
                        Graphics2D fill = canvas.createGraphics();
                        fill.setColor(new java.awt.Color(background, true));
                        fill.fillRect(0, 0, width, height);
                        fill.dispose();
                    }
                    BufferedImage previous = null;
                    if ("restoreToPrevious".equals(disposal)) {
                        previous = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
                        Graphics2D copy = previous.createGraphics();
                        copy.drawImage(canvas, 0, 0, null);
                        copy.dispose();
                    }
                    BufferedImage frame = reader.read(i);
                    if (frame == null) throw new IOException("文件不适用：GIF 帧无法解码。");
                    Graphics2D g = canvas.createGraphics();
                    g.drawImage(frame, x, y, null);
                    g.dispose();
                    out.add(encodeFrame(canvas));
                    if ("restoreToBackgroundColor".equals(disposal)) {
                        g = canvas.createGraphics();
                        g.setComposite(AlphaComposite.Src);
                        g.setColor(new java.awt.Color(transparent ? 0 : background, true));
                        g.fillRect(x, y, w, h);
                        g.dispose();
                    } else if (previous != null) canvas = previous;
                }
            } finally {
                reader.dispose();
            }
        }
        if (out.isEmpty()) {
            throw new IOException("GIF 没有可编码的帧。");
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
        return new EncodedFrame(rgb565, decodeFrame(rgb565, 0));
    }

    public static EncodedFrame frameFromSingleImage(Path imagePath) throws IOException {
        validateGifSourceFileSize(imagePath);
        try (ImageInputStream stream = ImageIO.createImageInputStream(imagePath.toFile())) {
            if (stream == null) throw new IOException("文件不适用：无法打开图片。");
            Iterator<ImageReader> readers = ImageIO.getImageReaders(stream);
            if (!readers.hasNext()) throw new IOException("文件不适用：无法识别图片格式。");
            ImageReader reader = readers.next();
            try {
                reader.setInput(stream, false);
                String format = reader.getFormatName();
                if (!format.equalsIgnoreCase("png") && !format.equalsIgnoreCase("jpeg") && !format.equalsIgnoreCase("jpg"))
                    throw new IOException("文件不适用：仅支持 GIF、PNG 和 JPEG。");
                validateDimensions(reader.getWidth(0), reader.getHeight(0));
                return encodeFrame(reader.read(0));
            } finally { reader.dispose(); }
        }
    }

    public static List<EncodedFrame> importFile(Path path, int maxFrames) throws IOException {
        String name = path.getFileName().toString().toLowerCase(java.util.Locale.ROOT);
        return name.endsWith(".gif") ? framesFromGif(path, maxFrames) : List.of(frameFromSingleImage(path));
    }

    public static byte[] paddedStream(List<EncodedFrame> frames) {
        if (frames.isEmpty() || frames.size() > 12) throw new IllegalArgumentException("frames");
        byte[] bytes = new byte[frames.size() * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE];
        for (int i = 0; i < frames.size(); i++) {
            if (frames.get(i).rgb565.length != AhaKeyProtocol.OLED_FRAME_BYTES) throw new IllegalArgumentException("RGB565 frame");
            System.arraycopy(frames.get(i).rgb565, 0, bytes, i * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE, AhaKeyProtocol.OLED_FRAME_BYTES);
        }
        return bytes;
    }

    public static BufferedImage decodeFrame(byte[] bytes, int offset) {
        if (offset < 0 || bytes.length - offset < AhaKeyProtocol.OLED_FRAME_BYTES) throw new IllegalArgumentException("frame bytes");
        BufferedImage image = new BufferedImage(160, 80, BufferedImage.TYPE_INT_RGB);
        for (int y = 0; y < 80; y++) for (int x = 0; x < 160; x++) {
            int value = ((bytes[offset++] & 255) << 8) | (bytes[offset++] & 255);
            int r = (value >> 11) & 31, g = (value >> 5) & 63, b = value & 31;
            image.setRGB(x, y, ((r * 255 / 31) << 16) | ((g * 255 / 63) << 8) | (b * 255 / 31));
        }
        return image;
    }

    private static void validateDimensions(int width, int height) throws IOException {
        if (width <= 0 || height <= 0 || (long) width * height > MAX_DECODE_PIXELS)
            throw new IOException("文件不适用：解码画布超过 16777216 像素上限。");
    }

    private static Node child(Node node, String name) throws IOException {
        for (Node c = node.getFirstChild(); c != null; c = c.getNextSibling()) if (name.equals(c.getNodeName())) return c;
        throw new IOException("文件不适用：GIF 缺少 " + name + "。");
    }

    private static int gifBackground(Node stream) throws IOException {
        Node table = null;
        for (Node node = stream.getFirstChild(); node != null; node = node.getNextSibling())
            if ("GlobalColorTable".equals(node.getNodeName())) table = node;
        if (table == null) return 0;
        int index = attributeInt(table, "backgroundColorIndex");
        for (Node color = table.getFirstChild(); color != null; color = color.getNextSibling()) {
            if (attributeInt(color, "index") == index)
                return 0xff000000 | (attributeInt(color, "red") << 16) | (attributeInt(color, "green") << 8) | attributeInt(color, "blue");
        }
        throw new IOException("文件不适用：GIF 背景色索引无效。");
    }

    private static String attribute(Node node, String name) throws IOException {
        Node value = node.getAttributes().getNamedItem(name);
        if (value == null) throw new IOException("文件不适用：GIF 缺少 " + name + "。");
        return value.getNodeValue();
    }

    private static int attributeInt(Node node, String name) throws IOException {
        try { return Integer.parseInt(attribute(node, name)); }
        catch (NumberFormatException e) { throw new IOException("文件不适用：GIF 尺寸字段无效。", e); }
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
