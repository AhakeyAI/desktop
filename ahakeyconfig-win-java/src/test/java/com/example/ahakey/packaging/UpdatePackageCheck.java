package com.example.ahakey.packaging;

import com.example.ahakey.firmware.*;
import com.example.ahakey.service.*;
import com.example.ahakey.update.*;
import com.example.ahakey.view.UpdateCenterDialog;
import com.example.ahakey.util.LanguageManager;
import javafx.application.Platform;
import javafx.scene.image.WritableImage;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import java.nio.file.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static com.example.ahakey.update.UpdateCenterChecks.*;

/** Actual JavaFX scene/snapshots, with temporary home and no application/Hook/device startup. */
public final class UpdatePackageCheck {
    public static void main(String[] args)throws Exception{
        if(args[0].equals("r7-inspector")){inspectorChecks(Path.of(args[1]).toAbsolutePath());return;}
        Path out=Path.of(args[0]).toAbsolutePath();Files.createDirectories(out);System.setProperty("user.home",out.resolve("home").toString());
        Platform.startup(()->{});Platform.setImplicitExit(false);
        try{
            for(String language:new String[]{"zh","en"})for(String variant:new String[]{"local-model","lite"}){
                var task=new FutureTask<Void>(()->{
                    LanguageManager.getInstance().switchLanguage(language);
                    var fixture=new FirmwareUpdateChecks.Fixture();var ble=new DeviceMaintenanceChecks.FixtureBle();AtomicInteger fetches=new AtomicInteger();
                    var app=new InstalledAppIdentity("1.0.10",variant,"x64","AhaKeyStudio",InstalledAppIdentity.UPGRADE_CODE,"fixture",true);
                    var service=new UpdateCenterService(ble,fixture.service,out.resolve(language+variant),app,new ReleaseManifestClient(uri->{fetches.incrementAndGet();throw new AssertionError("GUI must not fetch network");}));
                    var dialog=new UpdateCenterDialog(null,service);dialog.stage().show();dialog.content().applyCss();dialog.content().layout();
                    check("two tabs "+language+variant,dialog.content().getTabs().size()==2);check("software default "+language+variant,dialog.content().getSelectionModel().getSelectedIndex()==0);
                    snapshot(dialog, out.resolve(language+"-"+variant+"-software.png"));dialog.content().getSelectionModel().select(1);dialog.content().applyCss();dialog.content().layout();snapshot(dialog,out.resolve(language+"-"+variant+"-firmware.png"));
                    check("GUI no external IO "+language+variant,fetches.get()==0);dialog.stage().hide();service.close();return null;
                });Platform.runLater(task);task.get(20,TimeUnit.SECONDS);
            }
            interactionChecks(out);
        }finally{Platform.exit();}
        System.out.println("PASS actual JavaFX dual tabs x languages x installation variants; screenshots only, no EXE/UAT claim");
    }
    private static <T>T fx(Callable<T> action)throws Exception{
        FutureTask<T> task=new FutureTask<>(action);Platform.runLater(task);return task.get(10,TimeUnit.SECONDS);
    }
    private static java.util.List<javafx.scene.Node> nodes(javafx.scene.Node root){
        var result=new java.util.ArrayList<javafx.scene.Node>();result.add(root);
        if(root instanceof javafx.scene.control.ScrollPane scroll)result.addAll(nodes(scroll.getContent()));
        else if(root instanceof javafx.scene.Parent parent)for(var child:parent.getChildrenUnmodifiable())result.addAll(nodes(child));
        return result;
    }
    private static javafx.scene.control.ButtonBase button(javafx.scene.Node root,String text){
        return nodes(root).stream().filter(n->n instanceof javafx.scene.control.ButtonBase b&&b.getText().equals(text))
                .map(n->(javafx.scene.control.ButtonBase)n).findFirst().orElseThrow(()->new AssertionError("Missing actual button: "+text));
    }
    private static void settled(com.example.ahakey.app.StudioController c)throws Exception{
        long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(8);
        while(System.nanoTime()<end){if(fx(()->c.getStudioState().displayConfig().ready.get()&&!c.getStudioState().displayConfig().loading.get()
                &&!c.getStudioState().displayConfig().busy.get()&&!c.getAiRuntimeDisplayService().modeChangePendingProperty().get()))return;Thread.sleep(20);}
        throw new AssertionError("Inspector did not settle");
    }
    private static void inspectorChecks(Path out)throws Exception{
        Files.createDirectories(out);System.setProperty("user.home",out.resolve("home").toString());
        Platform.startup(()->{});Platform.setImplicitExit(false);
        try{
            for(String scenario:java.util.List.of("all","lights-only","no-lights","unknown","r001")){
                FirmwareUpdateChecks.WireDevice[] wire=new FirmwareUpdateChecks.WireDevice[1];
                var c=fx(()->new com.example.ahakey.app.StudioController(cb->{try{return wire[0]=new FirmwareUpdateChecks.WireDevice(cb);}catch(Exception e){throw new RuntimeException(e);}},KimiAhaKeyBridge::new,false));
                javafx.stage.Stage[] stage=new javafx.stage.Stage[1];
                try{
                    var ble=wire[0];var ops=new java.util.concurrent.CopyOnWriteArrayList<Integer>();var respond=ble.usb.consumer;
                    ble.usb.consumer=f->{ops.add(f[2]&255);respond.accept(f);};
                    String key=scenario.equals("r001")?FirmwareCatalog.CATALOG:"x1-c582-hw1-p1-1.0.0-r002";
                    if(!scenario.equals("unknown")&&!scenario.equals("r001"))new FirmwareUpdateChecks.WireMaintenance(ble,()->{}).official(key,
                            scenario.equals("all")?FirmwareCatalog.ALL:scenario.equals("lights-only")?java.util.Set.of("lights"):java.util.Set.of("keys","side"));
                    ble.catalog=key;ble.readFirmwareCatalogKey();
                    var pane=fx(()->{LanguageManager.getInstance().switchLanguage("zh");c.getAgentManager().setBluetoothOwner(AgentManager.BluetoothOwner.AHAKEY_STUDIO);c.getStudioState().setSelectedPart(com.example.ahakey.model.StudioPart.LIGHT_BAR);
                        c.getDisplayConfigService().capabilityChanged();var p=new com.example.ahakey.view.InspectorPane(c);stage[0]=new javafx.stage.Stage();stage[0].setScene(new javafx.scene.Scene(p,650,900));stage[0].show();return p;});
                    settled(c);boolean lights=!scenario.equals("unknown")&&!scenario.equals("no-lights"),full=scenario.equals("r001");
                    fx(()->{
                        check(scenario+" actual read populated brightness",!lights||(c.getStudioState().displayConfig().brightness.get()==37&&ops.contains(0x88)));
                        if(!lights)check(scenario+" no lights capability means no light read/write",!ops.contains(0x88)&&!ops.contains(0x8E));
                        check(scenario+" brightness save admission",button(pane,LanguageManager.getInstance().getString("display.save-brightness")).isDisabled()!=lights);
                        check(scenario+" light save admission",button(pane,LanguageManager.getInstance().getString("inspector.save-light-config")).isDisabled()!=lights);
                        var previews=nodes(pane).stream().filter(n->n instanceof javafx.scene.control.Button b&&b.getText().equals("预览")).toList();
                        check(scenario+" actual preview buttons exist",previews.size()==10);
                        check(scenario+" preview capability admission",full?!previews.get(0).isDisabled():previews.stream().allMatch(javafx.scene.Node::isDisabled));
                        check(scenario+" MULTI admission",button(pane,"多任务").isDisabled()!=full);
                        if(!full){
                            check(scenario+" visible capability reason",nodes(pane).stream().anyMatch(n->n instanceof javafx.scene.control.Label l&&l.isVisible()&&l.getText().contains("固件")));
                            ops.clear();for(var preview:previews)((javafx.scene.control.Button)preview).fire();button(pane,"多任务").fire();c.getDisplayConfigService().preview(null);
                            check(scenario+" rejected UI and direct preview emits no frame",!ops.contains(0x89)&&!ops.contains(0x98)&&!ops.contains(0x99));
                        }
                        return null;
                    });
                    if(lights){
                        fx(()->{c.getStudioState().displayConfig().editBrightness(61);button(pane,LanguageManager.getInstance().getString("display.save-brightness")).fire();return null;});settled(c);
                        check(scenario+" real brightness write",ble.brightness==61);
                        fx(()->{c.getStudioState().displayConfig().editEffect(0,0,3);button(pane,LanguageManager.getInstance().getString("inspector.save-light-config")).fire();return null;});settled(c);
                        check(scenario+" real light write",ble.lights[0][0]==3&&ops.contains(0x8E));
                    }
                    if(full){
                        ops.clear();fx(()->{button(pane,"预览").fire();return null;});settled(c);check("r001 actual preview frame and accepted state",ops.contains(0x89)&&fx(()->c.getStudioState().displayConfig().devicePreview.get()));
                        fx(()->{button(pane,"多任务").fire();return null;});settled(c);check("r001 actual MULTI mode frame",ops.contains(0x98)&&fx(()->c.getAiRuntimeDisplayService().getDisplayMode()==com.example.ahakey.model.AiRuntimeDisplayMode.MULTI));
                        fx(()->{check("r001 pane Apply remains enabled",!button(pane,"应用到键盘").isDisabled());
                            Platform.runLater(()->{try{var method=pane.getClass().getDeclaredMethod("showAiRuntimeSlotDialog");method.setAccessible(true);method.invoke(pane);}catch(Exception e){throw new RuntimeException(e);}});return null;});
                        fx(()->{var dialog=javafx.stage.Window.getWindows().stream().filter(w->w!=stage[0]&&w.isShowing()).findFirst().orElseThrow();
                            check("r001 dialog Apply remains enabled",!button(dialog.getScene().getRoot(),"应用到键盘").isDisabled());dialog.hide();return null;});
                        new FirmwareUpdateChecks.WireMaintenance(ble,()->{}).official("x1-c582-hw1-p1-1.0.0-r003",java.util.Set.of("lights"));ble.catalog="x1-c582-hw1-p1-1.0.0-r003";ble.readFirmwareCatalogKey();
                        fx(()->{c.getDisplayConfigService().capabilityChanged();return null;});settled(c);
                        fx(()->{check("r001 to lights-only revokes preview and MULTI",button(pane,"预览").isDisabled()&&button(pane,"多任务").isDisabled());return null;});
                    }
                    // A persisted MULTI preference must never admit either real Apply control.
                    if(!full||ble.catalog.endsWith("r003")){
                        fx(()->{c.getAiRuntimeDisplayService().displayModeProperty().set(com.example.ahakey.model.AiRuntimeDisplayMode.MULTI);
                            check(scenario+" pane Apply disabled with stale MULTI",button(pane,"应用到键盘").isDisabled());
                            Platform.runLater(()->{try{var method=pane.getClass().getDeclaredMethod("showAiRuntimeSlotDialog");method.setAccessible(true);method.invoke(pane);}catch(Exception e){throw new RuntimeException(e);}});
                            return null;
                        });
                        fx(()->{
                            var dialog=javafx.stage.Window.getWindows().stream().filter(w->w!=stage[0]&&w.isShowing()).findFirst().orElseThrow();
                            check(scenario+" dialog Apply disabled with stale MULTI",button(dialog.getScene().getRoot(),"应用到键盘").isDisabled());
                            ops.clear();button(pane,"应用到键盘").fire();button(dialog.getScene().getRoot(),"应用到键盘").fire();dialog.hide();
                            check(scenario+" disabled Apply emits no runtime frames",!ops.contains(0x98)&&!ops.contains(0x99));
                            button(pane,"单任务").fire();check(scenario+" local SINGLE fallback retained",c.getAiRuntimeDisplayService().getDisplayMode()==com.example.ahakey.model.AiRuntimeDisplayMode.SINGLE);
                            return null;
                        });
                    }
                    DeviceMaintenanceChecks.field(ble,"isConnected",false);ble.getCachedStatus().setConnected(false);
                    fx(()->{c.getDisplayConfigService().connectionChanged();check(scenario+" disconnect revokes writes",button(pane,"预览").isDisabled()&&button(pane,"多任务").isDisabled()&&button(pane,LanguageManager.getInstance().getString("display.save-brightness")).isDisabled());return null;});
                }finally{fx(()->{if(stage[0]!=null)stage[0].hide();c.shutdown();return null;});}
            }
            System.out.println("PASS R7 actual InspectorPane + Controller + DisplayConfigService + memory wire: five catalogs, preview, both Apply controls, local SINGLE, transition/disconnect");
        }finally{Platform.exit();}
    }
    private static void refresh(UpdateCenterDialog dialog)throws Exception{
        var method=UpdateCenterDialog.class.getDeclaredMethod("refresh");method.setAccessible(true);method.invoke(dialog);
    }
    private static <T>T field(UpdateCenterDialog dialog,String name,Class<T> type)throws Exception{
        var field=UpdateCenterDialog.class.getDeclaredField(name);field.setAccessible(true);return type.cast(field.get(dialog));
    }
    private static void interactionChecks(Path out)throws Exception{
        var firmware=new com.example.ahakey.firmware.SimpleFlashChecks.Fixture();var ble=new DeviceMaintenanceChecks.FixtureBle();
        var service=new UpdateCenterService(ble,firmware.service,out.resolve("events"),app(),new ReleaseManifestClient(uri->{throw new AssertionError("no network");}));
        var dialog=fx(()->{LanguageManager.getInstance().switchLanguage("zh");var d=new UpdateCenterDialog(null,service);d.stage().show();return d;});
        service.chooseLocal(firmware.target.file());awaitIdle(service);
        fx(()->{refresh(dialog);check("unknown local HEX has explicit unknown target version",field(dialog,"selected",javafx.scene.control.Label.class).getText().contains("目标版本未知"));field(dialog,"risk",javafx.scene.control.CheckBox.class).fire();check("risk click authorizes selected target",field(dialog,"risk",javafx.scene.control.CheckBox.class).isSelected());return null;});
        service.chooseLocal(firmware.target.file());awaitIdle(service);
        fx(()->{refresh(dialog);check("changing source clears explicit risk",!field(dialog,"risk",javafx.scene.control.CheckBox.class).isSelected());field(dialog,"risk",javafx.scene.control.CheckBox.class).fire();field(dialog,"detect",javafx.scene.control.Button.class).fire();return null;});awaitIdle(service);
        fx(()->{
            refresh(dialog);check("single detect click freezes and detects boot without preparation step",firmware.service.view().state()==FirmwareUpdateService.State.READY_TO_FLASH);
            check("active session freezes HEX selection",field(dialog,"local",javafx.scene.control.Button.class).isDisabled());
            check("only relevant primary action visible",field(dialog,"flash",javafx.scene.control.Button.class).isVisible()&&!field(dialog,"detect",javafx.scene.control.Button.class).isVisible()&&!field(dialog,"driver",javafx.scene.control.Button.class).isVisible());
            dialog.content().getSelectionModel().select(1);dialog.content().applyCss();dialog.content().layout();snapshot(dialog,out.resolve("zh-simple-ready.png"));
            dialog.stage().setIconified(true);check("minimize does not cancel or release",!firmware.calls.contains("request cleanup")&&firmware.gate.active());
            var event=new javafx.stage.WindowEvent(dialog.stage(),javafx.stage.WindowEvent.WINDOW_CLOSE_REQUEST);dialog.stage().getOnCloseRequest().handle(event);check("ordinary close protects active operation without cancelling",event.isConsumed()&&dialog.stage().isShowing()&&!firmware.calls.contains("request cleanup"));
            field(dialog,"flash",javafx.scene.control.Button.class).fire();return null;
        });awaitIdle(service);
        fx(()->{refresh(dialog);check("actual flash button reaches wait-version step",firmware.service.view().state()==FirmwareUpdateService.State.WAIT_RECONNECT&&field(dialog,"reconnect",javafx.scene.control.Button.class).isVisible());field(dialog,"reconnect",javafx.scene.control.Button.class).fire();return null;});awaitIdle(service);
        check("actual reconnect button requires observed version then completes",firmware.service.view().state()==FirmwareUpdateService.State.COMPLETE&&!firmware.gate.active());
        fx(()->{refresh(dialog);field(dialog,"detect",javafx.scene.control.Button.class).fire();return null;});awaitIdle(service);
        firmware.writeFailure=true;fx(()->{refresh(dialog);field(dialog,"flash",javafx.scene.control.Button.class).fire();return null;});awaitIdle(service);
        fx(()->{refresh(dialog);check("failure exposes explicit exit",firmware.service.view().state()==FirmwareUpdateService.State.FAILED&&field(dialog,"release",javafx.scene.control.Button.class).isVisible());check("failure UI omits vendor diagnostics",!field(dialog,"firmwareStatus",javafx.scene.control.Label.class).getText().contains("fixture terminal"));dialog.content().applyCss();dialog.content().layout();snapshot(dialog,out.resolve("zh-simple-failed.png"));field(dialog,"release",javafx.scene.control.Button.class).fire();return null;});awaitIdle(service);
        check("explicit GUI exit releases confirmed cleanup and resets HEX selection",!firmware.gate.active()&&firmware.service.view().state()==FirmwareUpdateService.State.IDLE&&service.selectedFirmware()==null);
        fx(()->{dialog.stage().hide();return null;});service.close();
        CountDownLatch read=new CountDownLatch(1),closed=new CountDownLatch(1);
        byte[] manifest=manifest("a".repeat(64),1).getBytes();
        var client=new ReleaseManifestClient(uri->new ReleaseManifestClient.Response(200,manifest.length,new java.io.ByteArrayInputStream(manifest)));
        var dependencies=new UpdateCenterService.Dependencies(()->new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,-1,new java.io.InputStream(){
            public int read()throws java.io.IOException{read.countDown();try{closed.await();}catch(InterruptedException e){throw new java.io.IOException(e);}throw new java.io.IOException("closed");}
            public void close(){closed.countDown();}
        })),p->{throw new AssertionError("cancelled download must not inspect");},new WindowsUpdateInstaller((c,l)->{throw new AssertionError("no installation");}));
        var downloading=new UpdateCenterService(ble,new FirmwareUpdateChecks.Fixture().service,out.resolve("download-events"),app(),client,dependencies);
        var downloadDialog=fx(()->{var d=new UpdateCenterDialog(null,downloading);d.stage().show();return d;});
        downloading.check();awaitIdle(downloading);fx(()->{refresh(downloadDialog);check("software UI displays actual target version",field(downloadDialog,"softwareStatus",javafx.scene.control.Label.class).getText().contains("1.0.11"));return null;});downloading.downloadSoftware();check("GUI download fixture reading",read.await(2,TimeUnit.SECONDS));
        fx(()->{var event=new javafx.stage.WindowEvent(downloadDialog.stage(),javafx.stage.WindowEvent.WINDOW_CLOSE_REQUEST);downloadDialog.stage().getOnCloseRequest().handle(event);check("download close consumed before hiding",event.isConsumed()&&downloadDialog.stage().isShowing());return null;});
        awaitIdle(downloading);check("GUI close actually cancels stream",closed.getCount()==0&&downloading.view().state()==UpdateCenterService.State.CANCELLED);
        fx(()->{refresh(downloadDialog);downloadDialog.stage().hide();return null;});downloading.close();
    }
    private static void snapshot(UpdateCenterDialog dialog,Path path)throws Exception{
        WritableImage image=dialog.content().snapshot(null,null);int w=(int)image.getWidth(),h=(int)image.getHeight();BufferedImage buffered=new BufferedImage(w,h,BufferedImage.TYPE_INT_ARGB);
        for(int y=0;y<h;y++)for(int x=0;x<w;x++)buffered.setRGB(x,y,image.getPixelReader().getArgb(x,y));ImageIO.write(buffered,"png",path.toFile());
    }
}
