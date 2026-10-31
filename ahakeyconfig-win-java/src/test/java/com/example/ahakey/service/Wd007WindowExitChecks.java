package com.example.ahakey.service;

import com.example.ahakey.App;
import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.OledResourceState;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.stage.*;
import java.nio.file.Files;
import java.util.concurrent.*;
import static com.example.ahakey.service.Wd007BehaviorChecks.*;

/** Production X and menu-exit handlers; only final process termination and USB are replaced. */
public final class Wd007WindowExitChecks {
    static class Probe extends App {final CountDownLatch exited=new CountDownLatch(1);@Override protected void exitRuntime(){exited.countDown();}}
    static <T>T fx(Callable<T> call)throws Exception{var done=new CompletableFuture<T>();Platform.runLater(()->{try{done.complete(call.call());}catch(Throwable e){done.completeExceptionally(e);}});return done.get(8,TimeUnit.SECONDS);}
    static void set(Object value,String name,Object data)throws Exception{var field=App.class.getDeclaredField(name);field.setAccessible(true);field.set(value,data);}
    static void invoke(App app,String name)throws Exception{var method=App.class.getDeclaredMethod(name);method.setAccessible(true);method.invoke(app);}
    public static void main(String[] args)throws Exception{
        System.setProperty("user.home",Files.createTempDirectory("wd007-exit-").toString());
        Platform.startup(()->Platform.setImplicitExit(false));
        Wire wire=new Wire();
        try{
            StudioController controller=fx(()->new StudioController(cb->wire,KimiAhaKeyBridge::new,false));
            wire.connectSelected(new com.example.ahakey.model.connection.DeviceTarget("USB","A","A"));await(wire::isConnected,"exit fixture connected");wire.readFirmwareCatalogKey();
            var service=controller.getDisplayConfigService();
            await(()->service.state().ready.get(),"local library ready");
            Probe app=new Probe();Stage stage=fx(()->{
                service.connectionChanged();var current=service.state().current().replace(OledResourceState.Asset.fromBytes(new byte[28672]));service.state().put(current);
                Stage window=new Stage();window.setScene(new Scene(new Pane(),320,160));set(app,"controller",controller);set(app,"primaryStage",window);invoke(app,"installWindowCloseHandler");
                controller.setApplicationExit(()->{try{invoke(app,"shutdownApplication");}catch(Exception e){throw new RuntimeException(e);}});window.show();return window;
            });
            wire.held=0x8B;fx(()->{service.upload(service.state().current());return null;});await(()->wire.heldRequest!=null,"real display upload awaits chunk ACK");
            fx(()->{stage.fireEvent(new WindowEvent(stage,WindowEvent.WINDOW_CLOSE_REQUEST));return null;});
            long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(2);while(fx(stage::isShowing)&&System.nanoTime()<end)Thread.sleep(5);
            check(!fx(stage::isShowing)&&controller.getStudioState().uploadingOledProperty().get(),"X hides to tray and preserves pending upload");
            long at=System.nanoTime();fx(()->{controller.requestApplicationExit();return null;});
            check(fx(()->true),"FX responsive during exit cleanup");check(app.exited.await(6,TimeUnit.SECONDS),"actual menu exit reaches termination within bounded cleanup");
            check(TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-at)<6000,"exit deadline measured");
            check(wire.frames.stream().noneMatch(f->f.endsWith(":140")),"exit does not COMMIT unfinished upload");
            System.out.println("PASS actual X/upload/menu-exit checks="+checks+"; final System.exit stubbed, no device");
        }finally{fx(()->{for(Window w:java.util.List.copyOf(Window.getWindows()))w.hide();return null;});Platform.exit();}
    }
}
