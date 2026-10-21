package com.example.ahakey.displayconfig;

import com.example.ahakey.model.OledResourceState;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.service.BleManager;
import com.example.ahakey.service.FirmwareLightSimulator;
import com.example.ahakey.service.OledResourceStore;
import com.example.ahakey.service.OledUploadService;
import com.example.ahakey.util.OLEDFrameEncoder;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.function.Consumer;
import java.util.zip.CRC32;
import javax.imageio.ImageIO;

/** Offline entry point. Never starts the application, HID enumeration, sockets or device commands. */
public final class DisplayConfigChecks {
    private static int checks;
    private static final String HEX = "D7D10510482228B74A2978BD8272F6A4E32668CF6B4F31F491A8503B0DC11E2E";
    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME))
                .setLevel(ch.qos.logback.classic.Level.WARN);
        ((ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger(BleManager.class)).setLevel(ch.qos.logback.classic.Level.WARN);
        protocol(); image(); gif(); state(); lightState(); persistence(); framing(); transport(); coreRegression(); simulation();
        System.out.println("PASS " + checks + " explicit checks; no hardware/UI/UAT claims");
    }
    private static void check(String id, boolean condition) {
        if (!condition) throw new AssertionError(id);
        checks++; System.out.println("PASS " + id);
    }
    private static void protocol() {
        for (int i = 0; i < 19; i++) check("A01-capacity-" + i, AhaKeyProtocol.resourceCapacity(i) == (i < 16 && i % 4 == 0 ? 8 : 12));
        check("A05-begin-independent-bytes", Arrays.equals(AhaKeyProtocol.resourceBegin(18, 12, 0xDDCCBBAAL),
                new byte[]{(byte)0xAA,(byte)0xBB,(byte)0x8A,18,0,0x40,5,0,12,0,(byte)0xAA,(byte)0xBB,(byte)0xCC,(byte)0xDD,(byte)0xCC,(byte)0xDD}));
        check("A05-chunk-max", AhaKeyProtocol.resourceChunk(0, 0, new byte[48]).length == 59);
        rejects("A05-OFF-preview-rejected", () -> AhaKeyProtocol.previewLight(0, 35));
        rejects("A05-brightness-zero", () -> AhaKeyProtocol.saveDisplayBrightness(0));
        rejects("A01-invalid-entry", () -> AhaKeyProtocol.resourceCapacity(19));
        check("A07-OFF-save-valid", AhaKeyProtocol.saveDisplayLight(3, 8, 0)[6] == 0);
        byte[] integrity = integrity(18, 12, 0xDDCCBBAAL);
        var parsed = AhaKeyResponseParser.parseDisplayRead(integrity, 3, 18);
        check("A04-integrity-u32", parsed != null && parsed.crc() == 0xDDCCBBAAL && parsed.bytes() == 344064);
        check("A04-wrong-target", AhaKeyResponseParser.parseDisplayRead(integrity, 3, 17) == null);
        check("A04-status-only-fail", AhaKeyResponseParser.parseDisplayRead(ack(0x88, 1), 3, 18) == null);
        check("A05-status-range", !AhaKeyResponseParser.isDisplayAck(ack(0x8E, 2), (byte)0x8E));
        CRC32 crc = new CRC32(); crc.update("123456789".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
        check("A05-known-CRC32", crc.getValue() == 0xCBF43926L);
    }
    private static void image() throws Exception {
        BufferedImage image = new BufferedImage(2, 2, BufferedImage.TYPE_INT_ARGB);
        for (int y = 0; y < 2; y++) for (int x = 0; x < 2; x++) image.setRGB(x, y, 0xffff0000);
        var encoded = OLEDFrameEncoder.encodeFrame(image);
        check("A02-size", encoded.rgb565.length == 25600 && encoded.preview.getWidth() == 160 && encoded.preview.getHeight() == 80);
        check("A02-black-bars", encoded.rgb565[0] == 0 && encoded.preview.getRGB(159, 40) == 0xff000000);
        int pixel = (40 * 160 + 80) * 2;
        check("A02-independent-red565", encoded.rgb565[pixel] == (byte)0xF8 && encoded.rgb565[pixel + 1] == 0);
        check("A02-preview-565", encoded.preview.getRGB(80, 40) == 0xffff0000);
        byte[] padded = OLEDFrameEncoder.paddedStream(List.of(encoded));
        check("A05-padding", padded.length == 28672 && Arrays.equals(Arrays.copyOfRange(padded, 25600, padded.length), new byte[3072]));
        BufferedImage transparent = new BufferedImage(160, 80, BufferedImage.TYPE_INT_ARGB);
        check("A02-transparency-black", OLEDFrameEncoder.encodeFrame(transparent).preview.getRGB(80, 40) == 0xff000000);
        Path dir = Files.createTempDirectory("wd005-images-");
        try {
            Path png = dir.resolve("static.png"); ImageIO.write(image, "png", png.toFile());
            check("A02-static-one-frame", OLEDFrameEncoder.importFile(png, 8).size() == 1);
            Path bad = dir.resolve("bad.png"); Files.writeString(bad, "not an image");
            rejects("A02-corrupt-image", () -> OLEDFrameEncoder.importFile(bad, 8));
            Path large = dir.resolve("large.png"); Files.write(large, new byte[2 * 1024 * 1024 + 1]);
            rejects("A02-source-cap", () -> OLEDFrameEncoder.importFile(large, 8));
        } finally { removeTestDirectory(dir); }
    }
    private static OledResourceState.Asset asset() { return OledResourceState.Asset.fromBytes(new byte[28672]); }
    private static void gif() throws Exception {
        Path root = Files.createTempDirectory("wd005-gif-");
        try {
            for (int count : new int[]{8, 9, 12, 13}) {
                Path path = root.resolve(count + ".gif");
                int[][] frames = new int[count][5];
                for (int i = 0; i < count; i++) frames[i] = new int[]{0, 0, 160, 80, i % 3 + 1};
                writeGif(path, frames, new String[count]);
                if (count <= 8) check("A02-GIF-8-full-count", OLEDFrameEncoder.importFile(path, 8).size() == count);
                else if (count == 9) rejectsMessage("A02-GIF-9-default-rejected", "当前 GIF 有 9 帧，目标位置最多支持 8 帧", () -> OLEDFrameEncoder.importFile(path, 8));
                if (count <= 12) check("A02-GIF-state-count-" + count, OLEDFrameEncoder.importFile(path, 12).size() == count);
                else rejectsMessage("A02-GIF-13-rejected", "当前 GIF 有 13 帧", () -> OLEDFrameEncoder.importFile(path, 12));
            }
            Path path = root.resolve("disposal.gif");
            writeGif(path, new int[][]{{0,0,160,80,1}, {40,20,40,40,2}, {80,20,40,40,3}, {0,0,10,10,2}},
                    new String[]{"doNotDispose", "restoreToPrevious", "restoreToBackgroundColor", "doNotDispose"});
            var frames = OLEDFrameEncoder.importFile(path, 8);
            check("A02-GIF-offset-overlay", frames.get(1).preview.getRGB(50,30) == 0xff00ff00 && frames.get(1).preview.getRGB(30,30) == 0xffff0000);
            check("A02-GIF-disposal3-restore", frames.get(2).preview.getRGB(50,30) == 0xffff0000 && frames.get(2).preview.getRGB(90,30) == 0xff0000ff);
            check("A02-GIF-disposal2-transparent-black", frames.get(3).preview.getRGB(90,30) == 0xff000000 && frames.get(3).preview.getRGB(50,30) == 0xffff0000);
            Path basic = root.resolve("no-control.gif");
            Files.write(basic, Base64.getDecoder().decode("R0lGODdhAQABAIAAAAAAAP///ywAAAAAAQABAAACAkQBADs="));
            check("A02-GIF-optional-control", OLEDFrameEncoder.importFile(basic, 8).size() == 1);
        } finally { removeTestDirectory(root); }
    }
    private static void writeGif(Path path, int[][] frames, String[] disposals) throws Exception {
        var writer = ImageIO.getImageWritersByFormatName("gif").next();
        byte[] red = {0, (byte)255, 0, 0}, green = {0, 0, (byte)255, 0}, blue = {0, 0, 0, (byte)255};
        var palette = new java.awt.image.IndexColorModel(2, 4, red, green, blue, 0);
        try (var output = ImageIO.createImageOutputStream(path.toFile())) {
            writer.setOutput(output);
            var stream = writer.getDefaultStreamMetadata(writer.getDefaultWriteParam());
            var tree = (javax.imageio.metadata.IIOMetadataNode)stream.getAsTree("javax_imageio_gif_stream_1.0");
            var screen = (javax.imageio.metadata.IIOMetadataNode)tree.getElementsByTagName("LogicalScreenDescriptor").item(0);
            screen.setAttribute("logicalScreenWidth", "160"); screen.setAttribute("logicalScreenHeight", "80");
            var table = new javax.imageio.metadata.IIOMetadataNode("GlobalColorTable");
            table.setAttribute("sizeOfGlobalColorTable", "4"); table.setAttribute("backgroundColorIndex", "0"); table.setAttribute("sortFlag", "FALSE");
            for (int i = 0; i < 4; i++) {
                var color = new javax.imageio.metadata.IIOMetadataNode("ColorTableEntry");
                color.setAttribute("index", Integer.toString(i)); color.setAttribute("red", Integer.toString(red[i] & 255));
                color.setAttribute("green", Integer.toString(green[i] & 255)); color.setAttribute("blue", Integer.toString(blue[i] & 255));
                table.appendChild(color);
            }
            tree.appendChild(table);
            stream.setFromTree("javax_imageio_gif_stream_1.0", tree);
            writer.prepareWriteSequence(stream);
            for (int i = 0; i < frames.length; i++) {
                int[] f = frames[i];
                var image = new BufferedImage(f[2], f[3], BufferedImage.TYPE_BYTE_INDEXED, palette);
                for (int y = 0; y < f[3]; y++) for (int x = 0; x < f[2]; x++) image.getRaster().setSample(x, y, 0, f[4]);
                var metadata = writer.getDefaultImageMetadata(javax.imageio.ImageTypeSpecifier.createFromRenderedImage(image), writer.getDefaultWriteParam());
                var node = (javax.imageio.metadata.IIOMetadataNode)metadata.getAsTree("javax_imageio_gif_image_1.0");
                var localTables = node.getElementsByTagName("LocalColorTable");
                if (localTables.getLength() > 0) node.removeChild(localTables.item(0));
                var descriptor = (javax.imageio.metadata.IIOMetadataNode)node.getElementsByTagName("ImageDescriptor").item(0);
                descriptor.setAttribute("imageLeftPosition", Integer.toString(f[0])); descriptor.setAttribute("imageTopPosition", Integer.toString(f[1]));
                var control = (javax.imageio.metadata.IIOMetadataNode)node.getElementsByTagName("GraphicControlExtension").item(0);
                control.setAttribute("disposalMethod", disposals[i] == null ? "doNotDispose" : disposals[i]);
                control.setAttribute("transparentColorFlag", "TRUE"); control.setAttribute("transparentColorIndex", "0");
                metadata.setFromTree("javax_imageio_gif_image_1.0", node);
                writer.writeToSequence(new javax.imageio.IIOImage(image, null, metadata), writer.getDefaultWriteParam());
            }
            writer.endWriteSequence();
        } finally { writer.dispose(); }
    }
    private static void lightState() {
        var state = new com.example.ahakey.model.DisplayConfigState();
        check("A07-unknown-not-OFF", state.effect(0,0) == -1);
        state.editBrightness(67); state.readBrightness(35);
        state.editEffect(2,4,0); state.readEffect(2,4,6);
        check("A07-read-protects-draft", state.brightness.get() == 67 && state.effect(2,4) == 0);
        state.previewAccepted(4, 67);
        state.previewUntilNanos.set(System.nanoTime() + 2_000_000_000L);
        long deadline = state.previewUntilNanos.get();
        state.message.set("FAIL");
        check("A08-failure-not-restart", state.devicePreview.get() && state.previewUntilNanos.get() == deadline);
        state.savedEffect(2,4,0);
        check("A07-save-responsibility", state.brightnessDirty() && !state.effectDirty(2,4));
        check("A08-save-ends-preview", !state.devicePreview.get() && state.previewUntilNanos.get() == 0);
        state.savedBrightness(67);
        check("A07-brightness-clean", !state.brightnessDirty());
        Set<Integer> entries = new HashSet<>();
        for (int mode = 0; mode < 4; mode++) {
            state.select(mode,0,0); entries.add(state.selectedEntry.get());
            for (int ai = 0; ai < 3; ai++) { state.select(mode,1,ai); entries.add(state.selectedEntry.get()); state.select(mode,2,ai); entries.add(state.selectedEntry.get()); }
        }
        check("A01-selection-19-unique", entries.size() == 19);
        int frozen = state.selectedEntry.get(); state.busy.set(true); state.select(0,0,0);
        check("A05-busy-freezes-target", state.selectedEntry.get() == frozen);
    }
    private static void state() {
        var draft = OledResourceState.empty(0).replace(asset());
        var metadata = new OledResourceState.Metadata(true, 2, 1, 28672, draft.asset().crc());
        check("A04-refresh-retains-intent", draft.merge(metadata).localStatus() == OledResourceState.LocalStatus.DRAFT);
        check("A03-clear-device-fact", draft.applied().clear().statusText().equals("设备已有"));
        check("A04-offline-not-empty", !draft.applied().unknown().deviceKnown() && draft.applied().unknown().asset() != null);
        check("A04-mismatch-downgrade", draft.applied().merge(new OledResourceState.Metadata(false, 3, 0, 0, 0)).localStatus() == OledResourceState.LocalStatus.DRAFT);
        check("A06-commit-reconcile", draft.failed("unknown", true).merge(metadata).localStatus() == OledResourceState.LocalStatus.APPLIED);
        check("A06-begin-fail-not-applied", draft.failed("FAIL", false).merge(metadata).localStatus() == OledResourceState.LocalStatus.FAILED);
        check("A01-global-name", OledResourceState.empty(16).targetName().equals("全局 MULTI · 运行中"));
        check("A05-only-draft-upload", draft.canUpload() && !draft.applied().canUpload() && !draft.uploading().canUpload());
    }
    private static void persistence() throws Exception {
        Path root = Files.createTempDirectory("wd005-store-");
        try {
            OledResourceStore store = new OledResourceStore(root); store.load();
            var draft = OledResourceState.empty(4).replace(asset()); store.save(draft);
            var restored = new OledResourceStore(root).load().get(4);
            check("A03-restart-no-source", Arrays.equals(restored.asset().bytes(), draft.asset().bytes()) && restored.canUpload());
            store.save(draft.committing());
            restored = new OledResourceStore(root).load().get(4);
            check("A06-crash-before-commit-ack", restored.commitUncertain() && restored.localStatus() == OledResourceState.LocalStatus.FAILED);
            store.save(draft.uploading());
            check("A06-crash-before-commit-send", !new OledResourceStore(root).load().get(4).commitUncertain());
            store.save(draft.clear());
            check("A03-clear-tombstone", store.containsEntry(4) && new OledResourceStore(root).load().get(4).asset() == null);
            Files.writeString(root.resolve("index.json"), "broken index");
            OledResourceStore broken = new OledResourceStore(root);
            rejects("A03-corrupt-index-rejected", broken::load);
            rejects("A03-corrupt-index-not-overwritten", () -> broken.save(draft));
            check("A03-preserve-corrupt-evidence", Files.readString(root.resolve("index.json")).equals("broken index"));
        } finally { removeTestDirectory(root); }
    }
    private static void framing() throws Exception {
        Method bleFrames = BleManager.class.getDeclaredMethod("reassembleNotifyFrames", byte[].class); bleFrames.setAccessible(true);
        Method usbFrame = Class.forName("com.example.ahakey.service.UsbHidTransport").getDeclaredMethod("extractFrame", byte[].class, int.class); usbFrame.setAccessible(true);
        byte[] frame = integrity(18, 12, 0xDDCCBBAAL);
        for (int split = 1; split < frame.length; split++) {
            BleManager ble = new OfflineBleManager(callback());
            List<?> first = (List<?>) bleFrames.invoke(ble, (Object) Arrays.copyOf(frame, split));
            List<?> second = (List<?>) bleFrames.invoke(ble, (Object) Arrays.copyOfRange(frame, split, frame.length));
            check("A05-BLE-split-" + split, first.isEmpty() && second.size() == 1 && Arrays.equals((byte[])second.get(0), frame));
        }
        byte[] report = new byte[65]; System.arraycopy(frame, 0, report, 1, frame.length);
        check("A05-USB-binary-delimiters", Arrays.equals((byte[]) usbFrame.invoke(null, report, report.length), frame));
        byte[] joined = new byte[frame.length + 6]; System.arraycopy(frame, 0, joined, 0, frame.length); System.arraycopy(ack(0x8E, 0), 0, joined, frame.length, 6);
        check("A05-BLE-coalesced", ((List<?>) bleFrames.invoke(new OfflineBleManager(callback()), (Object) joined)).size() == 2);
    }
    private static void transport() throws Exception {
        FakeSession session = new FakeSession();
        List<Integer> opcodes = new ArrayList<>();
        session.respond = request -> {
            opcodes.add(request[2] & 255);
            if (request[2] == (byte)0x8B) {
                try { session.ble.sendCommand(AhaKeyProtocol.setWorkMode(2)); throw new AssertionError("competing write admitted"); }
                catch (IOException expected) { }
            }
            session.reply(ack(request[2] & 255, 0));
        };
        List<Integer> progress = new ArrayList<>();
        OledUploadService.uploadResource(session.ble, 0, 0, asset(), progress::add, () -> {});
        check("A05-real-upload-chain", opcodes.get(0) == 0x8A && opcodes.get(opcodes.size() - 1) == 0x8C && opcodes.size() == 600);
        check("A05-progress-acknowledged", progress.get(progress.size() - 1) == 100);
        for(int frameCount:new int[]{8,12}) {
            byte[] bytes=new byte[28672*frameCount];
            for(int f=0;f<frameCount;f++) for(int i=0;i<25600;i++) bytes[f*28672+i]=(byte)(i*31);
            var content=OledResourceState.Asset.fromBytes(bytes);
            FakeSession full=new FakeSession(); int[] cursor={0}, commits={0};
            int entry=frameCount==8?0:18;
            full.respond=request->{
                int opcode=request[2]&255;
                if(opcode==0x8A) {
                    var header=java.nio.ByteBuffer.wrap(request).order(java.nio.ByteOrder.LITTLE_ENDIAN);
                    if(header.getInt(4)!=bytes.length || Short.toUnsignedInt(header.getShort(8))!=frameCount
                            || Integer.toUnsignedLong(header.getInt(10))!=content.crc()) throw new AssertionError("Begin header");
                } else if(opcode==0x8B) {
                    int offset=java.nio.ByteBuffer.wrap(request).order(java.nio.ByteOrder.LITTLE_ENDIAN).getInt(4),length=request[8]&255;
                    if(offset!=cursor[0] || length<1 || length>48 || request[3]!=entry
                            || !Arrays.equals(Arrays.copyOfRange(request,9,9+length),Arrays.copyOfRange(bytes,offset,offset+length))) throw new AssertionError("Chunk continuity/payload");
                    cursor[0]+=length;
                } else if(opcode==0x8C) { if(cursor[0]!=bytes.length) throw new AssertionError("early Commit"); commits[0]++; }
                else throw new AssertionError("unexpected command");
                full.reply(ack(opcode,0));
            };
            OledUploadService.uploadResource(full.ble,0,entry,content,p->{},()->{});
            check("A05-full-"+frameCount+"-frames-offset-payload-CRC",cursor[0]==bytes.length && commits[0]==1);
        }
        FakeSession disk = new FakeSession();
        int[] idle = {0}; disk.ble.setDisplayIdleListener(() -> idle[0]++);
        disk.respond = request -> disk.reply(ack(request[2] & 255, 0));
        rejects("A06-local-persist-failure", () -> OledUploadService.uploadResource(disk.ble, 0, 0, asset(), p -> {}, () -> { throw new IOException("disk full"); }));
        check("A06-quarantine-before-idle-flush", idle[0] == 0 && disk.ble.isDisplayWriteUncertain());
        FakeSession changed = new FakeSession();
        Method reset = BleManager.class.getDeclaredMethod("resetDisplaySession"); reset.setAccessible(true);
        reset.invoke(changed.ble);
        rejects("A06-reconnect-drops-admission", () -> changed.ble.openDisplayLease(true));
        rejects("A06-frozen-generation", () -> changed.ble.openDisplayLease(false, 0));
        Method notify = BleManager.class.getDeclaredMethod("onSessionNotify", long.class, byte[].class); notify.setAccessible(true);
        notify.invoke(changed.ble, 0L, ack(0x8E,0));
        check("A06-old-generation-not-delivered", changed.ble.connectionGeneration() == 1);
        FakeSession fail = new FakeSession(); fail.respond = request -> fail.reply(ack(request[2] & 255, 1));
        rejects("A06-Begin-FAIL", () -> OledUploadService.uploadResource(fail.ble, 0, 0, asset(), p -> {}, () -> {}));
        FakeSession timeout = new FakeSession(); timeout.respond = request -> {};
        try (var lease = timeout.ble.openDisplayLease(true)) {
            Thread.currentThread().interrupt();
            rejects("A06-interrupted-request", () -> timeout.ble.exchangeDisplay(lease, AhaKeyProtocol.previewBrightness(35)));
            Thread.interrupted();
        }
        // Real timeout: intentionally allow the actual 15-second wait, not a copied/mock timeout implementation.
        try (var lease = timeout.ble.openDisplayLease(true)) {
            rejects("A06-ACK-timeout", () -> timeout.ble.exchangeDisplay(lease, AhaKeyProtocol.saveDisplayBrightness(35)));
        }
        timeout.reply(ack(0x8E, 0));
        rejects("A06-late-ACK-quarantine", () -> timeout.ble.openDisplayLease(true));
        check("A06-write-unknown", timeout.ble.isDisplayWriteUncertain());
    }
    private static void coreRegression() throws Exception {
        check("A10-status-query-wire", Arrays.equals(AhaKeyProtocol.queryDeviceStatus(),hex("aabb00ccdd")));
        check("A10-mode-wire", Arrays.equals(AhaKeyProtocol.setWorkMode(3),hex("aabb9203ccdd")));
        check("A10-key-read-wire", Arrays.equals(AhaKeyProtocol.readOrdinaryKeyConfig(2,3),hex("aabb870203ccdd")));
        check("A10-side-read-wire", Arrays.equals(AhaKeyProtocol.readSideSwitchConfig(),hex("aabb97ccdd")));
        check("A10-sleep-read-wire", Arrays.equals(AhaKeyProtocol.querySleepWaitTime(),hex("aabb95ccdd")));
        check("A10-identity-read-wire", Arrays.equals(AhaKeyProtocol.queryFirmwareCatalogKey(),hex("aabb9fccdd")));
        check("A10-runtime-wire", Arrays.equals(AhaKeyProtocol.updateState((byte)4),hex("aabb9004ccdd")));
        Method reassemble=BleManager.class.getDeclaredMethod("reassembleNotifyFrames",byte[].class); reassemble.setAccessible(true);
        byte[] legacy=hex("aabb9200ccdd");
        List<?> frames=(List<?>)reassemble.invoke(new OfflineBleManager(callback()),(Object)legacy);
        check("A10-legacy-ACK-framing",frames.size()==1 && Arrays.equals((byte[])frames.get(0),legacy));
        check("A10-legacy-ACK-parser",AhaKeyResponseParser.parseCommandResponse(legacy).status()==0);
        var state=new com.example.ahakey.model.StudioState();
        state.updateKeyDescription(com.example.ahakey.model.StudioPart.KEY2,"retained-key");
        String before=new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(state.toPersisted());
        state.displayConfig().editBrightness(81); state.displayConfig().editEffect(0,0,4);
        state.displayConfig().put(OledResourceState.empty(0).replace(asset()));
        check("A10-other-drafts-not-mutated",before.equals(new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(state.toPersisted())));
        var restored=new com.example.ahakey.model.StudioState();
        restored.loadFromPersisted(new com.fasterxml.jackson.databind.ObjectMapper().readValue(before,com.example.ahakey.model.StudioState.PersistedDraft.class));
        check("A10-key-draft-roundtrip",restored.getKeyConfig(com.example.ahakey.model.StudioPart.KEY2).getDescription().equals("retained-key"));
        FakeSession session=new FakeSession(); List<byte[]> requests=new ArrayList<>(); session.respond=requests::add;
        try(var lease=session.ble.openDisplayLease(true)) {
            session.ble.sendCommand(AhaKeyProtocol.queryDeviceStatus());
            for(int opcode:new int[]{0x84,0x85,0x87,0x90,0x91,0x92,0x95,0x96,0x97,0x98,0x99,0x9f})
                rejects("A10-lease-rejects-"+Integer.toHexString(opcode),()->session.ble.sendCommand(AhaKeyProtocol.buildFrame((byte)opcode,new byte[0])));
            rejects("A10-lease-rejects-raw-data",()->session.ble.writeData(new byte[]{1}));
            check("A10-only-status-passes",requests.size()==1 && requests.get(0)[2]==0);
            check("A10-runtime-first-deferred",!session.ble.sendRuntimeState((byte)1));
            check("A10-runtime-latest-deferred",!session.ble.sendRuntimeState((byte)4));
            Field pending=BleManager.class.getDeclaredField("deferredRuntimeState"); pending.setAccessible(true);
            check("A10-runtime-latest-only",(Byte)pending.get(session.ble)==4);
        }
        check("A10-runtime-flushed-once",requests.size()==2 && Arrays.equals(requests.get(1),hex("aabb9004ccdd")));
    }
    private static byte[] hex(String value) { return java.util.HexFormat.of().parseHex(value); }
    private static void simulation() {
        // Literal goldens calculated from pinned psk_ws2812.c initial phases and update_bit integer scaling.
        // They are not generated by FirmwareLightSimulator or reused production helpers.
        int[][] firstTick100 = {
            {0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000},
            {0x03071f,0x01020a,0x000105,0x000000,0x000000,0x000000,0x000000,0x000000},
            {0x1b0000,0x090700,0x020500,0x000000,0x000000,0x000000,0x000000,0x000000},
            {0x150000,0x151100,0x0b1500,0x001505,0x001516,0x000615,0x0a0015,0x150011},
            {0x150000,0x151100,0x0b1500,0x001505,0x001516,0x000615,0x0a0015,0x150011},
            {0x060c32,0x060c32,0x060c32,0x060c32,0x060c32,0x060c32,0x060c32,0x060c32},
            {0x000000,0x000002,0x01020b,0x030619,0x030619,0x01020b,0x000002,0x000000},
            {0x000000,0x000000,0x000000,0x031f25,0x031f25,0x000000,0x000000,0x000000},
            {0x1f0903,0x110502,0x080201,0x030100,0x010000,0x000000,0x000000,0x000000},
            {0x0d0d10,0x00090b,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000},
            {0x000000,0x000000,0x000002,0x000206,0x000206,0x000002,0x000000,0x000000},
            {0x1d0a00,0x1d0300,0x1d0a00,0x1d0300,0x1d0a00,0x1d0300,0x1d0a00,0x1d0300},
            {0x081408,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000},
            {0x000003,0x000106,0x000208,0x00020a,0x00030d,0x00030f,0x00030e,0x00030c},
            {0x1d0000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x1d0000},
            {0x081408,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000},
            {0x050200,0x050200,0x050200,0x141108,0x141108,0x050200,0x050200,0x050200},
        };
        for (int effect=0;effect<firstTick100.length;effect++)
            check("A08-golden-initial-100-"+effect, Arrays.equals(new FirmwareLightSimulator().step(effect,100),firstTick100[effect]));
        var move = new FirmwareLightSimulator();
        for(int tick=0;tick<7;tick++) move.step(1,100);
        check("A08-golden-right-boundary",Arrays.equals(move.step(1,100),new int[]{0,0,0,0,0,0x000105,0x01020a,0x03071f}));
        check("A08-golden-bounce",Arrays.equals(move.step(1,100),new int[]{0,0,0,0,0x000105,0x01020a,0x03071f,0x01020a}));
        check("A08-golden-brightness-35",Arrays.equals(new FirmwareLightSimulator().step(1,35),new int[]{0x01020a,0x000003,0x000002,0,0,0,0,0}));
        // Independent expected output from firmware integer equations at the initial tick, brightness=100.
        check("A08-OFF", Arrays.equals(new FirmwareLightSimulator().step(0, 100), new int[8]));
        check("A08-single-move-initial", Arrays.equals(new FirmwareLightSimulator().step(1, 100), new int[]{0x03071f,0x01020a,0x000105,0,0,0,0,0}));
        check("A08-breath-alpha-zero-firmware-semantics", new FirmwareLightSimulator().step(5, 100)[0] == 0x060c32);
        check("A08-warning-initial", new FirmwareLightSimulator().step(11, 100)[0] == 0x1d0a00);
        for (int effect = 0; effect <= 16; effect++) {
            var simulator = new FirmwareLightSimulator();
            for (int tick = 0; tick < 300; tick++) {
                int[] pixels = simulator.step(effect, 35);
                if (pixels.length != 8 || Arrays.stream(pixels).anyMatch(p -> p < 0 || p > 0xffffff)) throw new AssertionError("A08-range");
            }
            check("A08-eight-lights-range-" + effect, true);
        }
    }
    private static byte[] ack(int opcode, int status) { return AhaKeyProtocol.buildFrame((byte)opcode, new byte[]{(byte)status}); }
    private static byte[] integrity(int entry, int frames, long crc) {
        var data = java.nio.ByteBuffer.allocate(13).order(java.nio.ByteOrder.LITTLE_ENDIAN);
        data.put((byte)0).put((byte)3).put((byte)entry).putShort((short)frames).putInt(frames * 28672).putInt((int)crc);
        return AhaKeyProtocol.buildFrame((byte)0x88, data.array());
    }
    private interface Checked { void run() throws Exception; }
    private static void rejectsMessage(String id, String text, Checked action) {
        try { action.run(); } catch (Exception expected) { check(id, expected.getMessage().contains(text)); return; }
        throw new AssertionError(id + " did not reject");
    }
    private static void rejects(String id, Checked action) {
        try { action.run(); } catch (Exception expected) { check(id, true); return; }
        throw new AssertionError(id + " did not reject");
    }
    private static BleManager.BleCallback callback() {
        return new BleManager.BleCallback() {
            public void onConnected() {} public void onDisconnected() {}
            public void onStatusReceived(com.example.ahakey.model.DeviceStatus status) {}
            public void onError(String message) {}
        };
    }
    static final class FakeSession {
        final OfflineBleManager ble = new OfflineBleManager(callback());
        Consumer<byte[]> respond;
        final Method notify;
        FakeSession() throws Exception {
            this(true);
        }
        FakeSession(boolean admitted) throws Exception {
            ble.usb.commands = request -> respond.accept(request);
            notify = BleManager.class.getDeclaredMethod("processNotifyFrame", byte[].class); notify.setAccessible(true);
            field("isConnected", true); ble.getCachedStatus().setConnected(true);
            field("outputStream", new ByteArrayOutputStream() {
                @Override public synchronized void write(byte[] bytes, int offset, int length) {
                    byte[] request = Arrays.copyOfRange(bytes, offset + 3, offset + length);
                    respond.accept(request);
                }
            });
            if (admitted) identify();
        }
        void identify() throws Exception {
            Consumer<byte[]> previous = respond;
            respond = request -> reply(AhaKeyProtocol.buildFrame((byte)0x9F,
                    ("\0x1-c582-hw1-p1-1.0.0-r001").getBytes(java.nio.charset.StandardCharsets.US_ASCII)));
            try { ble.readFirmwareCatalogKey(); } finally { respond = previous; }
        }
        void useUsb() { ble.usb.open(this::reply); }
        void field(String name, Object value) throws Exception { Field field = BleManager.class.getDeclaredField(name); field.setAccessible(true); field.set(ble, value); }
        void reply(byte[] bytes) { try { notify.invoke(ble, (Object)bytes); } catch (Exception e) { throw new IllegalStateException(e); } }
    }
    private static void removeTestDirectory(Path directory) throws IOException {
        try (var files = Files.walk(directory)) {
            for (Path path : files.sorted(Comparator.reverseOrder()).toList()) Files.delete(path);
        }
    }
}
