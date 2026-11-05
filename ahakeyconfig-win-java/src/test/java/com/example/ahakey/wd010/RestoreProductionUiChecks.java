package com.example.ahakey.wd010;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.*;
import com.example.ahakey.protocol.*;
import com.example.ahakey.service.*;
import com.example.ahakey.view.*;
import javafx.application.Platform;
import javafx.scene.*;
import javafx.scene.control.*;
import javafx.scene.layout.*;
import javafx.stage.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;

/** Real controller/service/JavaFX with an in-memory USB endpoint; no App.start or native input. */
public final class RestoreProductionUiChecks {
    static int checks;static Stage main;static StudioController controller;static TopBar top;
    static AtomicInteger starts=new AtomicInteger();static AtomicBoolean failLastMetadata=new AtomicBoolean();
    static java.util.List<byte[]> frames=new CopyOnWriteArrayList<>();static long attempt;
    static void check(boolean ok,String name){checks++;if(!ok)throw new AssertionError(name);}
    static <T>T fx(Callable<T> action)throws Exception{FutureTask<T> task=new FutureTask<>(action);Platform.runLater(task);return task.get(20,TimeUnit.SECONDS);}
    static void waitFor(java.util.function.BooleanSupplier condition)throws Exception{long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(15);while(!condition.getAsBoolean()&&System.nanoTime()<end)Thread.sleep(20);check(condition.getAsBoolean(),"condition timed out");}
    static MenuItem menu(String id){for(Node n:top.lookupAll(".menu-bar"))if(n instanceof MenuBar b)for(Menu m:b.getMenus())for(MenuItem item:m.getItems())if(id.equals(item.getId()))return item;throw new AssertionError("menu missing "+id);}
    static Stage window(String title){for(Window w:Window.getWindows())if(w instanceof Stage s&&s.isShowing()&&s.getTitle().equals(title))return s;return null;}
    static void screenshot(Stage stage,Path destination)throws Exception{
        stage.getScene().getRoot().applyCss();stage.getScene().getRoot().layout();var image=stage.getScene().snapshot(null);int width=(int)image.getWidth(),height=(int)image.getHeight();BufferedImage buffer=new BufferedImage(width,height,BufferedImage.TYPE_INT_ARGB);
        for(int y=0;y<height;y++)for(int x=0;x<width;x++)buffer.setRGB(x,y,image.getPixelReader().getArgb(x,y));ImageIO.write(buffer,"png",destination.toFile());
    }
    public static void main(String[] args)throws Exception{
        Path screenshots=Path.of(args[0]).toAbsolutePath();Files.createDirectories(screenshots);
        CountDownLatch ready=new CountDownLatch(1);Platform.startup(ready::countDown);ready.await();Platform.setImplicitExit(false);
        try{
            fx(()->{
                controller=new StudioController(callback->{try{
                    var wire=new K1RouteProtocolChecks.Wire(callback);var original=wire.usb.consumer;
                    wire.routes[3]=new K1Route(new byte[102]);for(int k=0;k<4;k++){wire.actions[3][k]=new byte[0];wire.types[3][k]=0;wire.descriptions[3][k]="";}
                    wire.usb.consumer=f->{try{
                        frames.add(f.clone());int opcode=f[2]&255;
                        if(opcode==0x9e&&(f[4]==0x30||f[4]==0x31)){
                            if(f[4]==0x31){starts.incrementAndGet();attempt++;}
                            int nonce=ByteBuffer.wrap(f).order(ByteOrder.LITTLE_ENDIAN).getInt(5);
                            wire.reply(RestoreChecks.reply(f[3],f[4]&255,nonce,0,attempt==0?FactoryResetProtocol.State.NEVER:FactoryResetProtocol.State.COMPLETE,attempt));
                        }else if(opcode==0x83){byte[] payload=ByteBuffer.allocate(10).order(ByteOrder.LITTLE_ENDIAN).put((byte)0).put(f[3]).putShort((short)(40+(f[3]&255))).putShort((short)0).putShort((short)8).putShort((short)300).array();wire.reply(AhaKeyProtocol.buildFrame((byte)opcode,payload));}
                        else if(opcode==0x95)wire.reply(AhaKeyProtocol.buildFrame((byte)opcode,new byte[]{0,60,0}));
                        else if(opcode==0x00)wire.reply(AhaKeyProtocol.buildFrame((byte)opcode,new byte[]{99,0,1,2,0,1,0,41}));
                        else if(opcode==0x88){int kind=f[3]&255;byte[] p;
                            if(kind==0)p=new byte[]{0,0,41};
                            else if(kind==1)p=new byte[]{0,1,f[4],f[5],(byte)(1+(f[4]&255)+(f[5]&255))};
                            else if(kind==2)p=new byte[]{0,2,f[4],0,0};
                            else {p=new byte[13];p[1]=3;p[2]=f[4];if(failLastMetadata.get()&&(f[4]&255)==18)p=new byte[]{1};}
                            wire.reply(AhaKeyProtocol.buildFrame((byte)opcode,p));
                        }else original.accept(f);
                    }catch(Exception e){throw new RuntimeException(e);}};return wire;
                }catch(Exception e){throw new RuntimeException(e);}},KimiAhaKeyBridge::new,false);
                top=new TopBar(controller,controller.getDeviceStatus(),controller.getStudioState(),controller.getAgentManager());
                main=new Stage();main.setTitle("WD010 isolated UI fixture");BorderPane root=new BorderPane();root.setTop(top);root.setCenter(new HBox(new CanvasPane(controller),new InspectorPane(controller)));root.setBottom(new StatusBar(controller.getDeviceStatus(),controller.getStudioState()));main.setScene(new Scene(root,1400,900));var css=RestoreProductionUiChecks.class.getResource("/style.css");if(css!=null)main.getScene().getStylesheets().add(css.toExternalForm());main.show();return null;
            });
            fx(()->{menu("cloud-account-entry").fire();Stage first=window("云端账号 · AhaType");menu("cloud-account-entry").fire();check(first!=null&&first==window("云端账号 · AhaType"),"account repeated entry reuses window");screenshot(first,screenshots.resolve("account-window.png"));first.hide();menu("factory-reset-entry").fire();return null;});
            waitFor(()->{try{return fx(()->window("确认恢复出厂设置")!=null);}catch(Exception e){throw new RuntimeException(e);}});
            fx(()->{Stage confirm=window("确认恢复出厂设置");screenshot(confirm,screenshots.resolve("factory-confirm.png"));DialogPane pane=(DialogPane)confirm.getScene().getRoot();Button cancel=(Button)pane.lookupButton(ButtonType.CANCEL);check(cancel.isDefaultButton(),"destructive confirmation defaults to cancel");cancel.fire();return null;});
            check(starts.get()==0,"UI cancel emits zero reset writes");
            var service=controller.getFactoryResetService();
            // Trigger the same production adapter without interacting with real hardware.
            failLastMetadata.set(true);frames.clear();var accepted=service.prepare().get(10,TimeUnit.SECONDS);service.confirm(accepted).get(20,TimeUnit.SECONDS);
            fx(()->{check(service.state().phase.get()==FactoryResetState.Phase.READ_FAILED&&service.state().readOnly.get(),"late metadata failure keeps actual UI read-only");check(service.state().pending.get(),"main pending banner remains visible");screenshot(main,screenshots.resolve("main-pending.png"));return null;});
            check(starts.get()==1,"one restore start only");
            check(frames.stream().filter(f->f[2]==(byte)0x87).count()==16,"production reads all 16 ordinary keys");
            check(frames.stream().filter(f->f[2]==(byte)0x9e&&f[4]==0x10).count()==12,"production reads 4 complete K1 routes in 3 slices");
            check(frames.stream().filter(f->f[2]==(byte)0x83).count()==4,"production reads all picture selections including mode zero");
            check(frames.stream().filter(f->f[2]==(byte)0x88&&f[3]==1).count()==36,"production reads all mode/state lights");
            check(frames.stream().filter(f->f[2]==(byte)0x88&&f[3]==2).count()==19&&frames.stream().filter(f->f[2]==(byte)0x88&&f[3]==3).count()==19,"production attempts all 19 basic and integrity metadata");
            failLastMetadata.set(false);frames.clear();
            var ble=controller.getBleManager();com.example.ahakey.firmware.DeviceMaintenanceChecks.field(ble,"firmwareIdentity",new BleManager.FirmwareIdentity(ble.connectionGeneration(),99,DeviceStatus.IdentityState.UNKNOWN,""));
            service.queryAgain(null).get(20,TimeUnit.SECONDS);
            fx(()->{
                var studio=controller.getStudioState();check(service.state().phase.get()==FactoryResetState.Phase.COMPLETE&&!service.state().readOnly.get()&&!service.hasPending(),"all reads unlock without a second reset");
                check(studio.getKeyConfig(ModeSlot.MODE2,StudioPart.KEY4).getDescription().equals("device-2-3"),"UI keys contain actual returned values");
                check(studio.getKeyConfig(ModeSlot.MODE3,StudioPart.KEY4).getHidCode()==0&&studio.k1Routes().confirmed(3),"Mode4 empty ordinary and K1 routes are real successful readbacks");
                check(studio.displayConfig().brightness.get()==41&&studio.displayConfig().effect(3,8)==12,"UI brightness/effect from readback");
                check(controller.getDeviceStatus().factorySleepMinutesProperty().get()==60,"sleep value from actual query");
                check(studio.k1Routes().confirmed(3)&&studio.getSideSwitchConfig().up().binding()==0,"K1 and side state applied");
                screenshot(main,screenshots.resolve("main-readback-complete.png"));return null;
            });
            check(frames.stream().anyMatch(f->f[2]==(byte)0x9f)&&ble.isDisplayAdmitted(),"pending task with UNKNOWN identity obtains real catalog under factory read-only permission");
            check(starts.get()==1&&frames.stream().noneMatch(f->f[2]==(byte)0x9e&&f[4]==0x31),"readback retry is query only");
            check(frames.stream().noneMatch(f->Set.of(0x73,0x04,0x8e,0x89,0x98,0x99).contains(f[2]&255)),"no old draft/display/MULTI writes after reset");
            System.out.println("PASS RestoreProductionUiChecks "+checks+" checks; full production readback and real JavaFX, all transport endpoints in memory");
        }finally{fx(()->{controller.shutdown();for(Window w:new ArrayList<>(Window.getWindows()))w.hide();return null;});Platform.exit();}
    }
}
