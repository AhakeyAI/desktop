package com.example.ahakey.wd011;

import com.example.ahakey.app.StudioController;import com.example.ahakey.firmware.DeviceMaintenanceChecks;import com.example.ahakey.model.*;import com.example.ahakey.protocol.*;import com.example.ahakey.service.*;import com.example.ahakey.view.*;
import javafx.application.Platform;import javafx.scene.Scene;import javafx.scene.control.*;import javafx.scene.layout.BorderPane;import javafx.stage.*;
import java.nio.file.*;import java.util.*;import java.util.concurrent.*;import java.util.concurrent.atomic.*;

/** Actual Controller dialogs + DisplayConfigService + production transports replaced with memory. */
public final class LosslessUiChecks {
 static int checks;static void check(String s,boolean b){if(!b)throw new AssertionError(s);checks++;}
 static <T>T fx(Callable<T> c)throws Exception{var task=new FutureTask<T>(c);Platform.runLater(task);return task.get(15,TimeUnit.SECONDS);}
 static void waitFor(Callable<Boolean> ready)throws Exception{long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(15);while(!fx(ready)){if(System.nanoTime()>end)throw new AssertionError("UI wait");Thread.sleep(10);}}
 public static void main(String[]args)throws Exception{
  System.setProperty("user.home",Files.createTempDirectory("acr4-ui-").toString());Path out=Path.of(args[0]);Files.createDirectories(out);Platform.startup(()->{});Platform.setImplicitExit(false);
  AtomicReference<DeviceMaintenanceChecks.FixtureBle> fixture=new AtomicReference<>();AtomicReference<StudioController> controller=new AtomicReference<>();AtomicReference<Stage> stage=new AtomicReference<>();
  AtomicInteger caps=new AtomicInteger(),legacyBegins=new AtomicInteger();AtomicReference<LosslessChecks.Device> device=new AtomicReference<>();AtomicBoolean v4=new AtomicBoolean();
  try{
   fx(()->{StudioController c=new StudioController(callback->{try{var b=new DeviceMaintenanceChecks.FixtureBle(callback);DeviceMaintenanceChecks.field(b,"isConnected",false);b.getCachedStatus().setConnected(false);fixture.set(b);return b;}catch(Exception e){throw new RuntimeException(e);}},KimiAhaKeyBridge::new,false);controller.set(c);c.getDisplayConfigService().setErrorHandler(s->{});c.getStudioState().setSelectedPart(StudioPart.OLED);Stage w=new Stage();w.setTitle("ACR4 isolated UI check");w.setScene(new Scene(new BorderPane(new InspectorPane(c)),660,850));w.getScene().getStylesheets().add(LosslessUiChecks.class.getResource("/style.css").toExternalForm());w.show();stage.set(w);return null;});
   var service=controller.get().getDisplayConfigService();var b=fixture.get();waitFor(()->service.state().ready.get());
   b.usb.consumer=req->{try{int op=req[2]&255;if(op==0x9e){caps.incrementAndGet();byte[] response=v4.get()?device.get().exchange(req,15000):LosslessChecks.reply(req[4]&255,2,LosslessUploadProtocol.read(req).getInt(6),new byte[4]);b.reply(response);}
    else if(op==0x88){byte[] payload=switch(req[3]){case 2->new byte[]{0,2,req[4],0,0};case 3->new byte[]{0,3,req[4],0,0,0,0,0,0,0,0,0,0};default->throw new AssertionError("read");};b.reply(AhaKeyProtocol.buildFrame((byte)op,payload));}
    else{if(op==0x8a)legacyBegins.incrementAndGet();b.reply(CommandSessionChecks.ack(op,0));}
   }catch(Exception e){throw new RuntimeException(e);}};
   var asset=OledResourceState.Asset.fromBytes(LosslessChecks.canonical(Files.readAllBytes(LosslessChecks.FIX.resolve("pattern8.cp2"))));
   fx(()->{service.acceptImport(0,asset);return null;});waitFor(()->!service.state().busy.get()&&service.state().current().asset()==asset);
   fx(()->{DeviceMaintenanceChecks.field(b,"isConnected",true);b.getCachedStatus().setConnected(true);service.connectionChanged();return null;});waitFor(()->!service.state().loading.get()&&service.state().writeReady.get());
   for(String scenario:List.of("cancel","accept","changed")){
    fx(()->{service.state().put(OledResourceState.empty(0).replace(asset));return null;});AtomicInteger dialogs=new AtomicInteger();AtomicReference<Throwable> failure=new AtomicReference<>();Set<Window> handled=Collections.newSetFromMap(new IdentityHashMap<>());
    ScheduledExecutorService ticker=Executors.newSingleThreadScheduledExecutor();ticker.scheduleAtFixedRate(()->Platform.runLater(()->{try{
     for(Window window:List.copyOf(Window.getWindows())){if(!window.isShowing()||handled.contains(window)||window.getScene()==null)continue;var node=window.getScene().lookup(".dialog-pane");if(!(node instanceof DialogPane pane))continue;
      handled.add(window);int number=dialogs.incrementAndGet();if(number==2){check("compat message clear",pane.getContentText().contains("兼容原画质"));CompactUiChecks.screenshot(pane,out.resolve("compatibility-"+scenario+".png"));if(scenario.equals("changed"))DeviceMaintenanceChecks.field(b,"connectionGeneration",b.connectionGeneration()+1);}
      ButtonType action=number==2&&scenario.equals("cancel")?ButtonType.CANCEL:ButtonType.OK;((Button)pane.lookupButton(action)).fire();
     }
    }catch(Throwable e){failure.set(e);}}),20,20,TimeUnit.MILLISECONDS);
    int before=legacyBegins.get();try{Platform.runLater(()->controller.get().uploadCurrentOledToDevice());waitFor(()->dialogs.get()>=2&&!service.state().busy.get());}finally{ticker.shutdownNow();}
    check("actual dialogs succeeded",failure.get()==null);check("legacy only after explicit accept",legacyBegins.get()-before==(scenario.equals("accept")?1:0));
    if(scenario.equals("accept"))check("legacy applied with original CRC",fx(()->service.state().current().device().crc()==asset.crc()&&service.state().current().localStatus()==OledResourceState.LocalStatus.APPLIED));
   }
   // Restore a fresh logical test connection, then exercise successful v4 through the same service/UI.
   fx(()->{var reset=BleManager.class.getDeclaredMethod("resetDisplaySession");reset.setAccessible(true);reset.invoke(b);DeviceMaintenanceChecks.field(b,"firmwareIdentity",new BleManager.FirmwareIdentity(b.connectionGeneration(),5,DeviceStatus.IdentityState.SUPPORTED,"X1-C582-HW1-P1-1.0.0-R002"));service.connectionChanged();return null;});waitFor(()->!service.state().loading.get()&&service.state().writeReady.get());
   v4.set(true);device.set(new LosslessChecks.Device(true,"ok",asset));fx(()->{service.state().put(OledResourceState.empty(0).replace(asset));service.upload(service.state().current());return null;});waitFor(()->!service.state().busy.get());
   check("v4 applied",fx(()->service.state().current().localStatus()==OledResourceState.LocalStatus.APPLIED&&service.state().current().uploadIdentity().protocol()==4));
   check("v4 expected expanded identity",fx(()->service.state().current().device().crc()==device.get().encoded.expandedCrc()));check("actual encoding visible",fx(()->service.state().progress.get().contains("RLE")));
   fx(()->{CompactUiChecks.screenshot(stage.get().getScene().getRoot(),out.resolve("lossless-complete.png"));return null;});
   System.out.println("PASS LosslessUiChecks "+checks+" assertions; actual dialogs/controller/service, no hardware");
  }finally{fx(()->{if(stage.get()!=null)stage.get().close();if(controller.get()!=null)controller.get().shutdown();return null;});Platform.exit();}
 }
}
