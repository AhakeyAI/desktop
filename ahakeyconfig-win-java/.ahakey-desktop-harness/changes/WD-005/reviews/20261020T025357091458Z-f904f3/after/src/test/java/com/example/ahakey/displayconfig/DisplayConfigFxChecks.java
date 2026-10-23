package com.example.ahakey.displayconfig;

import com.example.ahakey.model.*;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.service.*;
import com.example.ahakey.view.CanvasController;
import javafx.application.Platform;
import javafx.fxml.FXMLLoader;
import javafx.scene.Scene;
import javafx.scene.image.ImageView;
import javafx.scene.control.Label;
import javafx.scene.layout.Pane;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.BooleanSupplier;

/** Isolated FX components and fake wire only. Does not construct App or StudioController. */
public final class DisplayConfigFxChecks {
    private static int checks;
    private static DisplayConfigService service;
    private static StudioState studio;
    private static final List<byte[]> requests = new CopyOnWriteArrayList<>();
    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME))
                .setLevel(ch.qos.logback.classic.Level.WARN);
        ((ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger(BleManager.class)).setLevel(ch.qos.logback.classic.Level.WARN);
        Path root = Files.createTempDirectory("wd005-fx-");
        Platform.startup(() -> {});
        try {
            var session = new DisplayConfigChecks.FakeSession();
            session.respond = request -> {
                requests.add(request.clone());
                if (request[2] == (byte)0x88) {
                    byte[] payload = switch (request[3]) {
                        case 0 -> new byte[]{0,0,35};
                        case 1 -> new byte[]{0,1,request[4],request[5],6};
                        case 2 -> new byte[]{0,2,request[4],0,0};
                        case 3 -> new byte[]{0,3,request[4],0,0,0,0,0,0,0,0,0,0};
                        default -> throw new AssertionError("unexpected selector");
                    };
                    session.reply(AhaKeyProtocol.buildFrame((byte)0x88,payload));
                } else session.reply(AhaKeyProtocol.buildFrame(request[2],new byte[]{0}));
            };
            fx(() -> {
                studio = new StudioState(); studio.setSelectedPart(StudioPart.KEY1);
                service = new DisplayConfigService(studio,session.ble,new OledResourceStore(root));
                service.connectionChanged();
            });
            await(() -> studio.displayConfig().ready.get());
            check("A04-no-connect-bulk-read", requests.isEmpty());
            fx(() -> studio.setSelectedPart(StudioPart.OLED));
            await(() -> !studio.displayConfig().loading.get());
            check("A04-OLED-lazy-14-metadata-reads", requests.size() == 14 && requests.stream().allMatch(r -> r[2] == (byte)0x88));
            requests.clear();
            fx(() -> studio.setSelectedPart(StudioPart.LIGHT_BAR));
            await(() -> !studio.displayConfig().loading.get());
            check("A04-light-lazy-10-reads", requests.size() == 10);
            requests.clear();
            fx(() -> {
                studio.displayConfig().editBrightness(67);
                for (int ai=0; ai<9; ai++) studio.displayConfig().editEffect(0,ai,2);
            });
            check("A08-local-edit-zero-commands",requests.isEmpty());
            fx(() -> service.preview(null)); await(() -> !studio.displayConfig().busy.get());
            check("A08-preview-ACK", requests.size()==1 && Arrays.equals(requests.get(0),AhaKeyProtocol.previewBrightness(67)));
            fx(() -> studio.displayConfig().previewUntilNanos.set(System.nanoTime()+2_000_000_000L));
            long[] deadline = {0}; fx(() -> deadline[0] = studio.displayConfig().previewUntilNanos.get());
            session.respond = request -> { requests.add(request.clone()); session.reply(AhaKeyProtocol.buildFrame(request[2],new byte[]{1})); };
            fx(() -> service.saveBrightness()); await(() -> !studio.displayConfig().busy.get());
            fx(() -> check("A08-real-save-FAIL-preserves-remaining-time", studio.displayConfig().devicePreview.get() && studio.displayConfig().previewUntilNanos.get()==deadline[0] && studio.displayConfig().brightnessDirty()));
            requests.clear();
            session.respond = request -> {
                requests.add(request.clone());
                session.reply(AhaKeyProtocol.buildFrame(request[2],new byte[]{(byte)(request[2]==(byte)0x8E && request[3]==1 && request[5]==4 ? 1 : 0)}));
            };
            fx(() -> service.saveModeLights()); await(() -> !studio.displayConfig().busy.get());
            check("A07-fifth-failure-stops-at-five", requests.size()==5);
            fx(() -> {
                for(int ai=0;ai<9;ai++) check("A07-partial-dirty-"+ai,studio.displayConfig().effectDirty(0,ai)==(ai>=4));
                check("A07-partial-keeps-brightness-draft",studio.displayConfig().brightnessDirty());
                check("A08-success-ends-preview",!studio.displayConfig().devicePreview.get());
            });
            requests.clear();
            fx(() -> studio.setSelectedPart(StudioPart.KEY1));
            check("A08-leave-no-STOP",requests.isEmpty());
            session.field("isConnected",false); session.ble.getCachedStatus().setConnected(false);
            fx(() -> { service.connectionChanged(); studio.displayConfig().editBrightness(72); service.saveBrightness(); });
            fx(() -> check("A09-disconnected-edit-not-write", !studio.displayConfig().writeReady.get() && studio.displayConfig().brightness.get()==72 && requests.isEmpty()));
            fx(DisplayConfigFxChecks::canvas);
            System.out.println("PASS " + checks + " isolated FX/service checks; no complete application, hardware or UAT claims");
        } finally {
            fx(() -> { if (service != null) service.close(); });
            Platform.exit();
            try(var paths=Files.walk(root)) { for(Path path:paths.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(path); }
        }
    }
    private static void canvas() throws Exception {
        var spinnerFactory=com.example.ahakey.view.InspectorPane.class.getDeclaredMethod("brightnessSpinner",DisplayConfigState.class);
        spinnerFactory.setAccessible(true);
        var brightness=new DisplayConfigState();
        @SuppressWarnings("unchecked") var spinner=(javafx.scene.control.Spinner<Integer>)spinnerFactory.invoke(null,brightness);
        spinner.getEditor().setText("77"); spinner.commitValue();
        check("A09-brightness-typed-value-committed",brightness.brightness.get()==77);
        spinner.getEditor().setText(""); spinner.commitValue();
        check("A09-brightness-empty-safe",brightness.brightness.get()==77);
        spinner.getEditor().setText("0"); spinner.commitValue();
        check("A09-brightness-min-bound",brightness.brightness.get()==1);
        spinner.getEditor().setText("999"); spinner.commitValue();
        check("A09-brightness-max-bound",brightness.brightness.get()==100);
        var loader = new FXMLLoader(DisplayConfigFxChecks.class.getResource("/fxml/CanvasLayout.fxml"));
        Pane pane = loader.load(); CanvasController controller = loader.getController();
        var state = new StudioState(); controller.setStudioState(state); controller.setDeviceStatus(new DeviceStatus());
        var scene = new Scene(pane,800,600); scene.getStylesheets().add(DisplayConfigFxChecks.class.getResource("/style.css").toExternalForm());
        var image = new java.awt.image.BufferedImage(80,80,java.awt.image.BufferedImage.TYPE_INT_RGB);
        for(int y=0;y<80;y++) for(int x=0;x<80;x++) image.setRGB(x,y,0xff0000);
        var encoded = com.example.ahakey.util.OLEDFrameEncoder.encodeFrame(image);
        var asset = OledResourceState.Asset.fromBytes(com.example.ahakey.util.OLEDFrameEncoder.paddedStream(List.of(encoded)));
        state.displayConfig().put(OledResourceState.empty(0).replace(asset));
        pane.applyCss(); pane.layout();
        var preview = (ImageView)loader.getNamespace().get("oledPreviewImage");
        var badge = (Label)loader.getNamespace().get("oledDraftBadge");
        check("A02-FXML-final-pixels",preview.getImage().getWidth()==160 && preview.getImage().getHeight()==80
                && preview.getImage().getPixelReader().getArgb(0,40)==0xff000000 && preview.getImage().getPixelReader().getArgb(80,40)==0xffff0000);
        check("A03-FXML-draft-badge",badge.isVisible());
        state.displayConfig().put(state.displayConfig().current().applied().clear());
        check("A04-FXML-device-placeholder",!preview.isVisible() && ((Label)loader.getNamespace().get("oledTitle")).getText().equals("设备已有"));
        state.displayConfig().put(OledResourceState.empty(0).replace(asset));
        for(int i=1;i<=8;i++) check("A08-FXML-eight-leds-"+i,loader.getNamespace().get("lightSeg"+i)!=null);
        state.displayConfig().busy.set(true);
        check("A05-FXML-hotspot-locked",((Pane)loader.getNamespace().get("oledCard")).isDisabled());
        state.displayConfig().busy.set(false);
        var snapshot=pane.snapshot(null,null);
        var png=new java.awt.image.BufferedImage((int)snapshot.getWidth(),(int)snapshot.getHeight(),java.awt.image.BufferedImage.TYPE_INT_ARGB);
        for(int y=0;y<png.getHeight();y++) for(int x=0;x<png.getWidth();x++) png.setRGB(x,y,snapshot.getPixelReader().getArgb(x,y));
        Path target=Path.of("target","wd005-ui"); Files.createDirectories(target);
        javax.imageio.ImageIO.write(png,"png",target.resolve("canvas-component.png").toFile());
        controller.stopAnimation();
    }
    private interface Action { void run() throws Exception; }
    private static void fx(Action action) throws Exception {
        FutureTask<Void> task=new FutureTask<>(() -> { action.run(); return null; }); Platform.runLater(task); task.get(30,TimeUnit.SECONDS);
    }
    private static void await(BooleanSupplier condition) throws Exception {
        long until=System.nanoTime()+TimeUnit.SECONDS.toNanos(30);
        while(System.nanoTime()<until) {
            boolean[] done={false}; fx(() -> done[0]=condition.getAsBoolean()); if(done[0]) return; Thread.sleep(10);
        }
        throw new AssertionError("FX work timeout");
    }
    private static void check(String id,boolean condition) { if(!condition) throw new AssertionError(id); checks++; System.out.println("PASS "+id); }
}
