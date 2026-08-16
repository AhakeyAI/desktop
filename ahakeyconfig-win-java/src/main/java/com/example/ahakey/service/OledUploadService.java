package com.example.ahakey.service;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.util.OLEDFrameEncoder;

import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.locks.ReentrantLock;
import java.util.function.Consumer;

/** Serializes and validates every external-Flash OLED operation. */
public final class OledUploadService {
    private static final int FALLBACK_TOTAL_FRAME_SLOTS = AhaKeyProtocol.GIF_TOTAL_PLANNED_FRAMES;
    private static final int FACTORY_RESERVED_FRAME_SLOTS = 0;
    private static final ReentrantLock GIF_OPERATION_LOCK = new ReentrantLock();

    public record UploadProgress(int completedFrames, int totalFrames, String detail) {}

    public record UploadPlan(int startIndex, int frameCount, int perAssetCapacity,
                             int totalCapacity, AhaKeyResponseParser.GifLayout layout) {
        public long encodedBytes() {
            return (long) frameCount * AhaKeyProtocol.OLED_FRAME_BYTES;
        }
    }

    public record AssetState(int mode, int asset, int startIndex, int frameCount,
                             int frameInterval, int totalFrameSlots) {}

    private OledUploadService() {}

    public static int fallbackTotalFrameSlots() {
        return FALLBACK_TOTAL_FRAME_SLOTS;
    }

    public static int factoryReservedFrameSlots() {
        return FACTORY_RESERVED_FRAME_SLOTS;
    }

    public static int perModeCapacity(int ignoredTotalCapacity) {
        return AhaKeyProtocol.GIF_FRAMES_PER_PROFILE;
    }

    public static int fixedStartIndex(ModeSlot mode, int ignoredTotalCapacity) {
        return AhaKeyProtocol.gifPartitionStart(mode.getIndex(), 0);
    }

    public static boolean isOperationInProgress() {
        return GIF_OPERATION_LOCK.isLocked();
    }

    public static AssetState readAssetState(BleManager ble, ModeSlot mode, int asset) throws Exception {
        if (asset == 0) {
            AhaKeyResponseParser.PictureState state = ble.readPictureState(mode.getIndex());
            if (state == null) throw new IllegalStateException("设备未返回默认动画配置。");
            return new AssetState(state.mode(), 0, state.startIndex(), state.picLength(),
                state.frameInterval(), state.allModeMaxPic());
        }
        AhaKeyResponseParser.AiOledState state = ble.readAiOledState(mode.getIndex(), asset);
        if (state == null) throw new IllegalStateException("设备未返回状态动画配置。");
        return new AssetState(state.mode(), state.asset(), state.startIndex(), state.frameCount(),
            state.frameInterval(), state.totalFrameSlots());
    }

    public static UploadPlan validateUploadPlan(BleManager ble, ModeSlot mode, int frameCount)
        throws Exception {
        return validateUploadPlan(ble, mode, 0, frameCount);
    }

    public static UploadPlan validateUploadPlan(BleManager ble, ModeSlot mode, int asset,
                                                int frameCount) throws Exception {
        if (!ble.isUsbConnected()) throw new IllegalStateException("屏幕动画只能通过 USB 写入。");
        if (asset < 0 || asset >= AhaKeyProtocol.GIF_ASSET_COUNT)
            throw new IllegalArgumentException("动画状态无效。");
        if (frameCount <= 0) throw new IllegalStateException("没有可上传的 OLED 帧。");
        int assetCapacity = AhaKeyProtocol.gifAssetCapacity(asset);
        if (frameCount > assetCapacity) {
            throw new IllegalStateException("当前 GIF 有 " + frameCount + " 帧，超过该状态 "
                + assetCapacity + " 帧的上限。");
        }

        AhaKeyResponseParser.GifLayout layout;
        try {
            layout = ble.queryGifLayout();
        } catch (Exception e) {
            throw stepFailure("读取 Flash 布局", e);
        }
        if (layout == null) throw new IllegalStateException("设备未返回 GIF/Flash 布局。");
        if (!layout.hasPhysicalFlashDiagnostics()) {
            throw new IllegalStateException("当前固件未报告真实 Flash 容量。请先升级到固件 1.4.3 后再写入 GIF。");
        }
        if (layout.profiles() != AhaKeyProtocol.GIF_PROFILE_COUNT
            || layout.assetsPerProfile() != AhaKeyProtocol.GIF_ASSET_COUNT
            || !layout.hasVariableAssetCapacities()
            || layout.frameBytes() != AhaKeyProtocol.OLED_FRAME_BYTES
            || layout.sectorsPerFrame() * AhaKeyProtocol.OLED_CHUNK_SIZE
                != AhaKeyProtocol.OLED_FRAME_SLOT_SIZE) {
            throw new IllegalStateException("设备 GIF 布局与客户端不兼容，已阻止写入。");
        }
        for (int index = 0; index < AhaKeyProtocol.GIF_ASSET_COUNT; index++) {
            if (layout.capacityForAsset(index) != AhaKeyProtocol.gifAssetCapacity(index))
                throw new IllegalStateException("设备 GIF 分区容量与客户端不兼容，已阻止写入。");
        }

        int startIndex = AhaKeyProtocol.gifPartitionStart(mode.getIndex(), asset);
        int endIndexExclusive = startIndex + frameCount;
        if (endIndexExclusive > layout.frameSlots()) {
            throw new IllegalStateException(String.format(
                "目标分区需要帧槽 %d–%d，但 Flash 仅有 %d 个帧槽（Flash ID 0x%04X，%.1f MiB）。",
                startIndex, endIndexExclusive - 1, layout.frameSlots(), layout.flashId(),
                layout.flashBytes() / 1048576.0));
        }
        return new UploadPlan(startIndex, frameCount, assetCapacity, layout.frameSlots(), layout);
    }

    public static void uploadAsset(BleManager ble, ModeSlot mode, int asset, Path path, int fps,
                                   Consumer<UploadProgress> onProgress, Consumer<String> onComplete,
                                   Consumer<String> onError) {
        Thread thread = new Thread(() -> {
            if (!GIF_OPERATION_LOCK.tryLock()) {
                fail(onError, "已有 GIF 写入或清除操作正在进行，请等待完成。");
                return;
            }
            try {
                int count;
                List<OLEDFrameEncoder.EncodedFrame> frames;
                try {
                    count = OLEDFrameEncoder.frameCount(path);
                    int capacity = AhaKeyProtocol.gifAssetCapacity(asset);
                    if (count < 1 || count > capacity)
                        throw new IllegalStateException("该状态 GIF 必须为 1–" + capacity + " 帧。");
                    frames = OLEDFrameEncoder.framesFromGif(path, count);
                } catch (Exception e) {
                    throw stepFailure("解析 GIF", e);
                }

                UploadPlan plan = validateUploadPlan(ble, mode, asset, count);
                for (int i = 0; i < frames.size(); i++) {
                    if (onProgress != null)
                        onProgress.accept(new UploadProgress(i, count, "写入帧 " + (i + 1) + "/" + count));
                    try {
                        ble.writeLargeData(
                            (long) (plan.startIndex() + i) * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE,
                            frames.get(i).rgb565);
                        Thread.sleep(25);
                    } catch (Exception e) {
                        throw stepFailure("写入第 " + (i + 1) + " 帧", e);
                    }
                }

                int delay = Math.max(1, 1000 / Math.max(1, fps));
                byte[] command = asset == 0
                    ? AhaKeyProtocol.updatePicture(mode.getIndex(), plan.startIndex(), count, delay)
                    : AhaKeyProtocol.setAiOledPicture(mode.getIndex(), asset, plan.startIndex(), count, delay);
                try {
                    ble.sendCommandExpecting(command,
                        asset == 0 ? AhaKeyProtocol.CMD_UPDATE_PIC : AhaKeyProtocol.CMD_SET_AI_OLED_CONFIG);
                } catch (Exception e) {
                    throw stepFailure("提交动画配置", e);
                }
                try {
                    ble.sendCommandExpecting(AhaKeyProtocol.saveConfig(), AhaKeyProtocol.CMD_SAVE_CONFIG);
                } catch (Exception e) {
                    throw stepFailure("保存动画配置", e);
                }
                if (onComplete != null) onComplete.accept(String.format(
                    "动画写入完成：%d 帧；Flash ID 0x%04X，容量 %.1f MiB",
                    count, plan.layout().flashId(), plan.layout().flashBytes() / 1048576.0));
            } catch (Exception e) {
                fail(onError, message(e));
            } finally {
                GIF_OPERATION_LOCK.unlock();
            }
        }, "oled-asset-upload");
        thread.setDaemon(true);
        thread.start();
    }

    public static void clearAsset(BleManager ble, ModeSlot mode, int asset,
                                  Consumer<String> onComplete, Consumer<String> onError) {
        Thread thread = new Thread(() -> {
            if (!GIF_OPERATION_LOCK.tryLock()) {
                fail(onError, "已有 GIF 写入或清除操作正在进行，请等待完成。");
                return;
            }
            try {
                if (!ble.isUsbConnected()) throw new IllegalStateException("屏幕动画只能通过 USB 修改。");
                int start = AhaKeyProtocol.gifPartitionStart(mode.getIndex(), asset);
                byte[] command = asset == 0
                    ? AhaKeyProtocol.updatePicture(mode.getIndex(), start, 0, 0)
                    : AhaKeyProtocol.setAiOledPicture(mode.getIndex(), asset, start, 0, 0);
                try {
                    ble.sendCommandExpecting(command,
                        asset == 0 ? AhaKeyProtocol.CMD_UPDATE_PIC : AhaKeyProtocol.CMD_SET_AI_OLED_CONFIG);
                    ble.sendCommandExpecting(AhaKeyProtocol.saveConfig(), AhaKeyProtocol.CMD_SAVE_CONFIG);
                } catch (Exception e) {
                    throw stepFailure("清除并保存动画配置", e);
                }
                if (onComplete != null) onComplete.accept("该状态动画已清空");
            } catch (Exception e) {
                fail(onError, message(e));
            } finally {
                GIF_OPERATION_LOCK.unlock();
            }
        }, "oled-asset-clear");
        thread.setDaemon(true);
        thread.start();
    }

    // Compatibility entry points used by the older editor.
    public static void uploadGif(BleManager ble, ModeSlot mode, Path path, int fps,
                                 Consumer<UploadProgress> progress, Consumer<String> complete,
                                 Consumer<String> error) {
        uploadAsset(ble, mode, 0, path, fps, progress, complete, error);
    }

    public static void uploadStaticImage(BleManager ble, ModeSlot mode, Path path,
                                         Consumer<UploadProgress> progress, Consumer<String> complete,
                                         Consumer<String> error) {
        Thread thread = new Thread(() -> {
            if (!GIF_OPERATION_LOCK.tryLock()) {
                fail(error, "已有 GIF 写入或清除操作正在进行，请等待完成。");
                return;
            }
            try {
                UploadPlan plan = validateUploadPlan(ble, mode, 0, 1);
                OLEDFrameEncoder.EncodedFrame frame = OLEDFrameEncoder.frameFromSingleImage(path);
                if (progress != null) progress.accept(new UploadProgress(0, 1, "写入静态图片"));
                ble.writeLargeData((long) plan.startIndex() * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE,
                    frame.rgb565);
                ble.sendCommandExpecting(
                    AhaKeyProtocol.updatePicture(mode.getIndex(), plan.startIndex(), 1, 0),
                    AhaKeyProtocol.CMD_UPDATE_PIC);
                if (complete != null) complete.accept(mode.getTitle() + " OLED 图片上传完成");
            } catch (Exception e) {
                fail(error, message(e));
            } finally {
                GIF_OPERATION_LOCK.unlock();
            }
        }, "oled-static-upload");
        thread.setDaemon(true);
        thread.start();
    }

    public static void previewGif(BleManager ble, Path path, int fps,
                                  Consumer<String> complete, Consumer<String> error) {
        uploadAsset(ble, ModeSlot.MODE0, 0, path, fps, null, complete, error);
    }

    private static IllegalStateException stepFailure(String step, Exception cause) {
        return new IllegalStateException(step + "失败：" + message(cause), cause);
    }

    private static String message(Throwable error) {
        return error.getMessage() == null || error.getMessage().isBlank()
            ? error.getClass().getSimpleName() : error.getMessage();
    }

    private static void fail(Consumer<String> onError, String message) {
        if (onError != null) onError.accept(message);
    }
}
