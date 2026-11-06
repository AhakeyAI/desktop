package com.example.ahakey.wd011;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.firmware.DeviceMaintenanceChecks;
import com.example.ahakey.model.*;
import com.example.ahakey.service.*;
import com.example.ahakey.view.*;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.image.ImageView;
import javafx.scene.layout.BorderPane;
import javafx.stage.Stage;
import java.awt.image.BufferedImage;
import java.nio.file.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import javax.imageio.ImageIO;

/** Production dialogs, Inspector and preparation service; transport is replaced before use. */
public final class CompactUiChecks {
    static int checks;
    static <T>T fx(Callable<T> call)throws Exception{FutureTask<T> task=new FutureTask<>(call);Platform.runLater(task);return task.get(20,TimeUnit.SECONDS);}
    static void check(String label,boolean ok){if(!ok)throw new AssertionError(label);checks++;}
    static void await(Callable<Boolean> ready)throws Exception{
        long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
        while(!fx(ready)){if(System.nanoTime()>end)throw new AssertionError("UI timed out");Thread.sleep(10);}
    }
    static void screenshot(javafx.scene.Parent pane,Path output)throws Exception {
        pane.applyCss();pane.layout();var image=pane.snapshot(null,null);BufferedImage png=new BufferedImage((int)image.getWidth(),(int)image.getHeight(),BufferedImage.TYPE_INT_ARGB);
        for(int y=0;y<png.getHeight();y++)for(int x=0;x<png.getWidth();x++)png.setRGB(x,y,image.getPixelReader().getArgb(x,y));ImageIO.write(png,"png",output.toFile());
    }
    public static void main(String[] args)throws Exception {
        System.setProperty("user.home",Files.createTempDirectory("wd011-ui-home-").toString());
        Path output=Path.of(args[0]);Files.createDirectories(output);Platform.startup(()->{});Platform.setImplicitExit(false);
        AtomicReference<DeviceMaintenanceChecks.FixtureBle> wire=new AtomicReference<>();AtomicReference<StudioController> control=new AtomicReference<>();AtomicReference<Stage> main=new AtomicReference<>();
        try {
            fx(()->{
                StudioController controller=new StudioController(callback->{try{
                    var ble=new DeviceMaintenanceChecks.FixtureBle(callback);DeviceMaintenanceChecks.field(ble,"isConnected",false);ble.getCachedStatus().setConnected(false);ble.usb.consumer=f->{throw new AssertionError("preview must not write a device");};wire.set(ble);return ble;
                }catch(Exception e){throw new RuntimeException(e);}},KimiAhaKeyBridge::new,false);
                control.set(controller);controller.getStudioState().setSelectedPart(StudioPart.OLED);
                Stage stage=new Stage();stage.setTitle("WD011 isolated UI check");stage.setScene(new Scene(new BorderPane(new InspectorPane(controller)),650,850));
                stage.getScene().getStylesheets().add(CompactUiChecks.class.getResource("/style.css").toExternalForm());stage.show();main.set(stage);return null;
            });
            var service=control.get().getDisplayConfigService();await(()->service.state().ready.get());
            AtomicReference<OledResourceState.Asset> prepared=new AtomicReference<>();
            fx(()->{service.prepareImport(CompactChecks.FIXTURES.resolve("animation-8.gif"),0,true,prepared::set);return null;});await(()->prepared.get()!=null);
            var asset=prepared.get();check("GIF frames kept",asset.frames()==8);
            for(int f=0;f<8;f++)check("GIF original duration "+f,asset.durationMillis(f)==(f%4+1)*100);
            check("preparation leaves draft empty",fx(()->service.state().current().asset()==null));
            fx(()->{
                var choice=CompactUploadPreviewDialog.modeDialog(main.get());choice.show();check("two options",choice.getItems().size()==2);
                check("default compatible",choice.getSelectedItem().equals("原画质上传"));choice.setSelectedItem("快速上传");screenshot(choice.getDialogPane(),output.resolve("upload-mode.png"));choice.close();
                var preview=new CompactUploadPreviewDialog(main.get(),"Mode 1 · 默认屏幕",asset);preview.show();
                var image=(ImageView)preview.getDialogPane().lookup("#compact-preview-image");
                check("actual decoded preview",image!=null&&image.getImage().getWidth()==160&&!image.isSmooth());
                String details=((Label)preview.getDialogPane().lookup("#compact-preview-details")).getText();
                check("size and original durations visible",details.contains("12864")&&details.contains("100 / 200 / 300 / 400"));
                check("cancel default",((Button)preview.getDialogPane().lookupButton(ButtonType.CANCEL)).isDefaultButton());
                screenshot(preview.getDialogPane(),output.resolve("fast-preview.png"));preview.setResult(false);preview.close();
                check("cancel preview no local replacement",service.state().current().asset()==null);return null;
            });
            fx(()->{service.acceptImport(0,asset);return null;});await(()->service.state().current().asset()==asset&&!service.state().busy.get());
            fx(()->{
                screenshot(main.get().getScene().getRoot(),output.resolve("resource-draft.png"));
                check("persisted mode label in real Inspector",main.get().getScene().getRoot().lookupAll(".label").stream().filter(n->n instanceof Label).map(n->((Label)n).getText()).anyMatch(t->t.contains("16色 / 80×40")));
                check("draft not applied",service.state().current().localStatus()==OledResourceState.LocalStatus.DRAFT);
                return null;
            });
            check("local workflow emits no device write",wire.get().usb.writes.get()==0);
            System.out.println("PASS WD-011 "+checks+" production JavaFX/service assertions; snapshots="+output.toAbsolutePath());
        }finally{fx(()->{if(main.get()!=null)main.get().close();if(control.get()!=null)control.get().shutdown();return null;});Platform.exit();}
    }
}
