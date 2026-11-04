package com.example.ahakey.service;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.util.OLEDFrameEncoder;

import java.nio.file.Path;
import java.util.List;
import java.util.function.Consumer;

public final class OledUploadService {
    private static final int USER_MODE_COUNT = 4;
    private static final int FALLBACK_TOTAL_FRAME_SLOTS = AhaKeyProtocol.OLED_MAX_FRAMES;
    private static final int FACTORY_RESERVED_FRAME_SLOTS = 10;

    public record UploadProgress(int completedFrames, int totalFrames, String detail) {
    }

    public record UploadPlan(int startIndex, int frameCount, int perModeCapacity, int totalCapacity) {
        public long encodedBytes() {
            return (long) frameCount * AhaKeyProtocol.OLED_FRAME_BYTES;
        }
    }

    private OledUploadService() {
    }

    public static int fallbackTotalFrameSlots() {
        return FALLBACK_TOTAL_FRAME_SLOTS;
    }

    public static int factoryReservedFrameSlots() {
        return FACTORY_RESERVED_FRAME_SLOTS;
    }

    public static int perModeCapacity(int totalCapacity) {
        int managedCapacity = Math.min(totalCapacity, AhaKeyProtocol.OLED_MAX_FRAMES);
        int userCapacity = Math.max(0, managedCapacity - FACTORY_RESERVED_FRAME_SLOTS);
        return userCapacity / USER_MODE_COUNT;
    }

    public static int fixedStartIndex(ModeSlot mode, int totalCapacity) {
        return FACTORY_RESERVED_FRAME_SLOTS + mode.getIndex() * perModeCapacity(totalCapacity);
    }

    public static UploadPlan validateUploadPlan(BleManager ble, ModeSlot mode, int frameCount) throws Exception {
        if (frameCount <= 0) {
            throw new IllegalStateException("没有可上传的 OLED 帧。");
        }

        AhaKeyResponseParser.PictureState state = ble.readPictureState(mode.getIndex());
        int reportedCapacity = state != null && state.allModeMaxPic() > 0
            ? state.allModeMaxPic()
            : FALLBACK_TOTAL_FRAME_SLOTS;
        int totalCapacity = Math.min(reportedCapacity, AhaKeyProtocol.OLED_MAX_FRAMES);
        if (totalCapacity <= FACTORY_RESERVED_FRAME_SLOTS) {
            throw new IllegalStateException("设备 Flash 图片分区容量异常，已取消上传。");
        }

        int perMode = perModeCapacity(totalCapacity);
        if (perMode <= 0) {
            throw new IllegalStateException("设备 Flash 图片分区容量异常，无法上传。");
        }
        if (frameCount > perMode) {
            throw new IllegalStateException(
                "当前 GIF 有 " + frameCount + " 帧，超过本模式上限 " + perMode + " 帧。请减少帧数、缩短 GIF 或改用静态图片。"
            );
        }

        int startIndex = fixedStartIndex(mode, totalCapacity);
        int endIndexExclusive = startIndex + frameCount;
        int modeEndExclusive = startIndex + perMode;
        if (startIndex < FACTORY_RESERVED_FRAME_SLOTS ||
            endIndexExclusive > modeEndExclusive ||
            endIndexExclusive > totalCapacity) {
            throw new IllegalStateException("上传内容超过本模式可用空间，已取消上传。");
        }

        long encodedBytes = (long) frameCount * AhaKeyProtocol.OLED_FRAME_BYTES;
        long slotBytes = (long) frameCount * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE;
        long modeBytes = (long) perMode * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE;
        long endAddressExclusive = (long) endIndexExclusive * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE;
        long flashBytes = (long) totalCapacity * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE;
        if (encodedBytes <= 0 || slotBytes > modeBytes || endAddressExclusive > flashBytes) {
            throw new IllegalStateException("上传内容超过当前模式 Flash 分区。");
        }
        return new UploadPlan(startIndex, frameCount, perMode, totalCapacity);
    }

    public static void uploadGif(
        BleManager ble,
        ModeSlot mode,
        Path gifPath,
        int fps,
        Consumer<UploadProgress> onProgress,
        Consumer<String> onComplete,
        Consumer<String> onError
    ) {
        new Thread(() -> {
            try {
                int frameCount = OLEDFrameEncoder.frameCount(gifPath);
                UploadPlan plan = validateUploadPlan(ble, mode, frameCount);
                List<OLEDFrameEncoder.EncodedFrame> frames = OLEDFrameEncoder.framesFromGif(gifPath, plan.frameCount());
                int startIndex = plan.startIndex();
                int delayMs = Math.max(1, 1000 / Math.max(1, fps));
                int total = frames.size();

                for (int i = 0; i < total; i++) {
                    long address = (long) (startIndex + i) * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE;
                    if (onProgress != null) {
                        onProgress.accept(new UploadProgress(i, total, "写入帧 " + (i + 1) + "/" + total));
                    }
                    ble.writeLargeData(address, frames.get(i).rgb565);
                    Thread.sleep(100);
                }

                ble.sendCommandExpecting(
                    AhaKeyProtocol.updatePicture(mode.getIndex(), startIndex, total, delayMs),
                    AhaKeyProtocol.CMD_UPDATE_PIC
                );

                if (onComplete != null) {
                    onComplete.accept(mode.getTitle() + " OLED GIF 上传完成：" + total + " 帧");
                }
            } catch (Exception e) {
                String errorMsg = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
                if (onError != null) {
                    onError.accept(errorMsg);
                }
            }
        }, "oled-upload").start();
    }

    public static void uploadStaticImage(
        BleManager ble,
        ModeSlot mode,
        Path imagePath,
        Consumer<UploadProgress> onProgress,
        Consumer<String> onComplete,
        Consumer<String> onError
    ) {
        new Thread(() -> {
            try {
                UploadPlan plan = validateUploadPlan(ble, mode, 1);
                OLEDFrameEncoder.EncodedFrame frame = OLEDFrameEncoder.frameFromSingleImage(imagePath);
                int startIndex = plan.startIndex();

                long address = (long) startIndex * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE;
                if (onProgress != null) {
                    onProgress.accept(new UploadProgress(0, 1, "写入静态图片"));
                }
                ble.writeLargeData(address, frame.rgb565);

                ble.sendCommandExpecting(
                    AhaKeyProtocol.updatePicture(mode.getIndex(), startIndex, 1, 0),
                    AhaKeyProtocol.CMD_UPDATE_PIC
                );

                if (onComplete != null) {
                    onComplete.accept(mode.getTitle() + " OLED 图片上传完成");
                }
            } catch (Exception e) {
                String errorMsg = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
                if (onError != null) {
                    onError.accept(errorMsg);
                }
            }
        }, "oled-upload").start();
    }

    public static void previewGif(
        BleManager ble,
        Path gifPath,
        int fps,
        Consumer<String> onComplete,
        Consumer<String> onError
    ) {
        new Thread(() -> {
            try {
                int maxFrames = perModeCapacity(FALLBACK_TOTAL_FRAME_SLOTS);
                int frameCount = OLEDFrameEncoder.frameCount(gifPath);
                if (frameCount > maxFrames) {
                    throw new IllegalStateException("预览 GIF 帧数过多，请减少到 " + maxFrames + " 帧以内。");
                }
                List<OLEDFrameEncoder.EncodedFrame> frames = OLEDFrameEncoder.framesFromGif(gifPath, frameCount);
                int delayMs = Math.max(1, 1000 / Math.max(1, fps));
                int total = frames.size();
                int startIndex = FACTORY_RESERVED_FRAME_SLOTS;

                for (int i = 0; i < total; i++) {
                    ble.writeLargeData((long) (startIndex + i) * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE, frames.get(i).rgb565);
                }

                ble.sendCommandExpecting(
                    AhaKeyProtocol.updatePicture(0, startIndex, total, delayMs),
                    AhaKeyProtocol.CMD_UPDATE_PIC
                );

                if (onComplete != null) {
                    onComplete.accept("OLED 预览已发送：" + total + " 帧");
                }
            } catch (Exception e) {
                String errorMsg = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
                if (onError != null) {
                    onError.accept("预览失败：" + errorMsg);
                }
            }
        }, "oled-preview").start();
    }
}
