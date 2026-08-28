package com.example.ahakey.service;

import com.example.ahakey.firmware.FirmwareCapabilities;
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

    public static final class UploadHandle {
        private final Thread worker;

        private UploadHandle(Thread worker) {
            this.worker = worker;
        }

        public void cancel() {
            worker.interrupt();
        }

        public boolean isRunning() {
            return worker.isAlive();
        }
    }

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
            throw new IllegalStateException("当前固件未报告真实 Flash 容量。请先升级到固件 "
                + FirmwareCapabilities.MINIMUM_GIF_VERSION + " 后再写入 GIF。");
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

    public static UploadHandle uploadAsset(
        BleManager ble, ModeSlot mode, int asset, Path path, int ignoredFps,
        Consumer<UploadProgress> onProgress, Consumer<String> onComplete,
        Consumer<String> onError
    ) {
        Thread thread = new Thread(() -> {
            if (!GIF_OPERATION_LOCK.tryLock()) {
                fail(onError, "已有 GIF 写入或清除操作正在进行，请等待完成。");
                return;
            }
            try {
                OLEDFrameEncoder.EncodedAnimation animation;
                try {
                    animation = OLEDFrameEncoder.optimizedAnimation(path, asset);
                } catch (Exception e) {
                    throw stepFailure("解析 GIF", e);
                }
                int count = animation.frames().size();
                String result = ble.executeDeviceTransaction(() -> {
                    UploadPlan plan = validateUploadPlan(ble, mode, asset, count);
                    for (int i = 0; i < animation.frames().size(); i++) {
                        if (Thread.currentThread().isInterrupted()) {
                            throw new InterruptedException("GIF 写入已取消");
                        }
                        if (onProgress != null) onProgress.accept(
                            new UploadProgress(i, count, "写入帧 " + (i + 1) + "/" + count));
                        ble.writeLargeData(
                            (long) (plan.startIndex() + i) * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE,
                            animation.frames().get(i).rgb565);
                        Thread.sleep(25);
                    }
                    int delay = animation.frameIntervalMs();
                    byte[] command = asset == 0
                        ? AhaKeyProtocol.updatePicture(mode.getIndex(), plan.startIndex(), count, delay)
                        : AhaKeyProtocol.setAiOledPicture(
                            mode.getIndex(), asset, plan.startIndex(), count, delay);
                    ble.sendCommandExpecting(command,
                        asset == 0 ? AhaKeyProtocol.CMD_UPDATE_PIC
                            : AhaKeyProtocol.CMD_SET_AI_OLED_CONFIG);
                    ble.sendCommandExpecting(
                        AhaKeyProtocol.saveConfig(), AhaKeyProtocol.CMD_SAVE_CONFIG);
                    AssetState verified = readAssetState(ble, mode, asset);
                    verifyAssetState(verified, plan.startIndex(), count, delay);
                    return String.format(
                        "动画写入并回读完成：%d 帧，间隔 %d ms；Flash ID 0x%04X，容量 %.1f MiB%s",
                        count, delay, plan.layout().flashId(),
                        plan.layout().flashBytes() / 1048576.0,
                        animation.optimized() ? "；已自动优化并保持总时长" : "");
                });
                if (onComplete != null) onComplete.accept(result);
            } catch (Exception e) {
                fail(onError, message(e));
            } finally {
                GIF_OPERATION_LOCK.unlock();
            }
        }, "oled-asset-upload");
        thread.setDaemon(true);
        thread.start();
        return new UploadHandle(thread);
    }

    public static void clearAsset(BleManager ble, ModeSlot mode, int asset,
                                  Consumer<String> onComplete, Consumer<String> onError) {
        Thread thread = new Thread(() -> {
            if (!GIF_OPERATION_LOCK.tryLock()) {
                fail(onError, "已有 GIF 写入或清除操作正在进行，请等待完成。");
                return;
            }
            try {
                ble.executeDeviceTransaction(() -> {
                    if (!ble.isUsbConnected())
                        throw new IllegalStateException("屏幕动画只能通过 USB 修改。");
                    int start = AhaKeyProtocol.gifPartitionStart(mode.getIndex(), asset);
                    byte[] command = asset == 0
                        ? AhaKeyProtocol.updatePicture(mode.getIndex(), start, 0, 0)
                        : AhaKeyProtocol.setAiOledPicture(mode.getIndex(), asset, start, 0, 0);
                    ble.sendCommandExpecting(command,
                        asset == 0 ? AhaKeyProtocol.CMD_UPDATE_PIC : AhaKeyProtocol.CMD_SET_AI_OLED_CONFIG);
                    ble.sendCommandExpecting(AhaKeyProtocol.saveConfig(), AhaKeyProtocol.CMD_SAVE_CONFIG);
                    AssetState verified = readAssetState(ble, mode, asset);
                    verifyAssetState(verified, start, 0, 0);
                    return null;
                });
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
    public static UploadHandle uploadGif(BleManager ble, ModeSlot mode, Path path, int fps,
                                 Consumer<UploadProgress> progress, Consumer<String> complete,
                                 Consumer<String> error) {
        return uploadAsset(ble, mode, 0, path, fps, progress, complete, error);
    }

    public static UploadHandle uploadStaticImage(BleManager ble, ModeSlot mode, Path path,
                                         Consumer<UploadProgress> progress, Consumer<String> complete,
                                         Consumer<String> error) {
        Thread thread = new Thread(() -> {
            if (!GIF_OPERATION_LOCK.tryLock()) {
                fail(error, "已有 GIF 写入或清除操作正在进行，请等待完成。");
                return;
            }
            try {
                OLEDFrameEncoder.EncodedFrame frame = OLEDFrameEncoder.frameFromSingleImage(path);
                if (progress != null) progress.accept(new UploadProgress(0, 1, "写入静态图片"));
                ble.executeDeviceTransaction(() -> {
                    UploadPlan plan = validateUploadPlan(ble, mode, 0, 1);
                    ble.writeLargeData(
                        (long) plan.startIndex() * AhaKeyProtocol.OLED_FRAME_SLOT_SIZE,
                        frame.rgb565);
                    ble.sendCommandExpecting(
                        AhaKeyProtocol.updatePicture(mode.getIndex(), plan.startIndex(), 1, 0),
                        AhaKeyProtocol.CMD_UPDATE_PIC);
                    ble.sendCommandExpecting(
                        AhaKeyProtocol.saveConfig(), AhaKeyProtocol.CMD_SAVE_CONFIG);
                    verifyAssetState(readAssetState(ble, mode, 0), plan.startIndex(), 1, 0);
                    return null;
                });
                if (complete != null)
                    complete.accept(mode.getTitle() + " OLED 图片已保存并回读验证");
            } catch (Exception e) {
                fail(error, message(e));
            } finally {
                GIF_OPERATION_LOCK.unlock();
            }
        }, "oled-static-upload");
        thread.setDaemon(true);
        thread.start();
        return new UploadHandle(thread);
    }

    private static IllegalStateException stepFailure(String step, Exception cause) {
        return new IllegalStateException(step + "失败：" + message(cause), cause);
    }

    static void verifyAssetState(
        AssetState actual, int expectedStart, int expectedCount, int expectedInterval
    ) {
        if (actual == null || actual.startIndex() != expectedStart
            || actual.frameCount() != expectedCount
            || actual.frameInterval() != expectedInterval) {
            throw new IllegalStateException(String.format(
                "动画回读不一致：期望 start=%d/count=%d/interval=%d，实际 %s",
                expectedStart, expectedCount, expectedInterval,
                actual == null ? "无响应" : String.format("start=%d/count=%d/interval=%d",
                    actual.startIndex(), actual.frameCount(), actual.frameInterval())));
        }
    }

    private static String message(Throwable error) {
        return error.getMessage() == null || error.getMessage().isBlank()
            ? error.getClass().getSimpleName() : error.getMessage();
    }

    private static void fail(Consumer<String> onError, String message) {
        if (onError != null) onError.accept(message);
    }
}
