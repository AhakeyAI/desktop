package com.example.ahakey.packaging;

import com.example.ahakey.App;
import com.example.ahakey.app.StudioController;
import com.example.ahakey.firmware.*;
import com.example.ahakey.service.*;
import com.example.ahakey.update.*;
import com.example.ahakey.view.UpdateCenterDialog;
import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.Pane;
import javafx.stage.*;
import java.nio.file.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import static com.example.ahakey.update.UpdateCenterChecks.check;

/** Real close handlers and maintenance services with in-memory hardware, never App.start/shutdown. */
public final class WindowCloseChecks {
    private record Context(SimpleFlashChecks.Fixture fixture,UpdateCenterService service,App app,Stage stage) {}
    private static <T>T fx(Callable<T> task)throws Exception {
        var done=new CompletableFuture<T>();Platform.runLater(()->{try{done.complete(task.call());}catch(Throwable e){done.completeExceptionally(e);}});
        return done.get(10,TimeUnit.SECONDS);
    }
    private static void set(Object target,String name,Object value)throws Exception {
        var field=App.class.getDeclaredField(name);field.setAccessible(true);field.set(target,value);
    }
    private static void invoke(App app,String name)throws Exception {
        var method=App.class.getDeclaredMethod(name);method.setAccessible(true);method.invoke(app);
    }
    private static void action(App app,Runnable action)throws Exception {
        var method=App.class.getDeclaredMethod("requestWindowAction",Runnable.class);method.setAccessible(true);method.invoke(app,action);
    }
    private static void failed(SimpleFlashChecks.Fixture fixture)throws Exception {
        fixture.writeFailure=true;fixture.service.prepareSimple(fixture.target,true);fixture.service.detectBoot();
        try{fixture.service.flashSimple();throw new AssertionError("Expected failed fixture");}catch(java.io.IOException expected){}
        check("actual failed service retains gate",fixture.service.view().state()==FirmwareUpdateService.State.FAILED&&fixture.gate.active());
    }
    private static Context context(SimpleFlashChecks.Fixture fixture)throws Exception {
        var ble=new BleManager((BleManager.BleCallback)null);DeviceMaintenanceChecks.field(ble,"maintenance",fixture.gate);
        var service=new UpdateCenterService(ble,fixture.service,Files.createTempDirectory("close-service-"));
        return fx(()->{
            var controller=new StudioController(cb->ble,KimiAhaKeyBridge::new,false) {
                @Override public UpdateCenterService getUpdateCenter(){return service;}
            };
            var app=new App();var stage=new Stage();stage.setScene(new Scene(new Pane(),320,160));
            set(app,"controller",controller);set(app,"primaryStage",stage);invoke(app,"installWindowCloseHandler");stage.show();
            return new Context(fixture,service,app,stage);
        });
    }
    private static void waitFor(Callable<Boolean> condition)throws Exception {
        long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(8);
        while(System.nanoTime()<end){if(condition.call())return;Thread.sleep(10);}throw new AssertionError("close condition timed out");
    }
    private static void hideAll()throws Exception {fx(()->{for(Window w:java.util.List.copyOf(Window.getWindows()))w.hide();return null;});}
    private static boolean noticeShowing(Stage owner){return Window.getWindows().stream().anyMatch(w->w instanceof Stage s&&s.getOwner()==owner&&s.isShowing());}
    public static void main(String[] args)throws Exception {
        Platform.startup(()->Platform.setImplicitExit(false));
        try {
            check("tray supported before testing production X",java.awt.SystemTray.isSupported());
            var ended=new SimpleFlashChecks.Fixture();failed(ended);var c=context(ended);
            fx(()->{c.stage.fireEvent(new WindowEvent(c.stage,WindowEvent.WINDOW_CLOSE_REQUEST));return null;});
            waitFor(()->fx(()->!c.stage.isShowing()));
            check("actual X hides after ended failed attempt cleanup",!ended.gate.active()&&ended.service.view().state()==FirmwareUpdateService.State.IDLE);
            check("X does not reserve application exit",ended.gate.normalAllowed());
            check("explicit tray exit gate admits ended cleanup",c.service.requestClose(null));c.service.close();

            var dialogEnded=new SimpleFlashChecks.Fixture();failed(dialogEnded);var d=context(dialogEnded);
            var dialog=fx(()->{var v=new UpdateCenterDialog(d.stage,d.service);v.show();v.stage().fireEvent(new WindowEvent(v.stage(),WindowEvent.WINDOW_CLOSE_REQUEST));return v;});
            waitFor(()->fx(()->!dialog.stage().isShowing()));
            check("update window close releases ended failed maintenance",!dialogEnded.gate.active());d.service.close();hideAll();

            CountDownLatch cleanupEntered=new CountDownLatch(1),releaseCleanup=new CountDownLatch(1);
            AtomicInteger cleanupCalls=new AtomicInteger();AtomicReference<String> cleanupThread=new AtomicReference<>();
            var unknown=new SimpleFlashChecks.Fixture(){
                @Override public boolean cleanupConfirmed(Path directory){
                    cleanupCalls.incrementAndGet();cleanupThread.set(Thread.currentThread().getName());cleanupEntered.countDown();
                    try{if(!releaseCleanup.await(5,TimeUnit.SECONDS))throw new AssertionError("fixture release missing");}catch(InterruptedException e){throw new RuntimeException(e);}return false;
                }
            };
            unknown.alive=true;failed(unknown);var u=context(unknown);
            fx(()->{u.stage.fireEvent(new WindowEvent(u.stage,WindowEvent.WINDOW_CLOSE_REQUEST));u.stage.fireEvent(new WindowEvent(u.stage,WindowEvent.WINDOW_CLOSE_REQUEST));return null;});
            check("cleanup enters worker",cleanupEntered.await(3,TimeUnit.SECONDS));
            check("FX remains responsive while cleanup waits",fx(()->true));
            check("worker owns cleanup",!cleanupThread.get().contains("JavaFX"));releaseCleanup.countDown();
            waitFor(()->fx(()->noticeShowing(u.stage)));
            check("unknown process stays protected",unknown.gate.active()&&!u.service.requestClose(null));
            check("duplicate X does not enqueue cleanup twice",cleanupCalls.get()==1);
            check("blocked X keeps primary visible",fx(()->u.stage.isShowing()));hideAll();
            var blockedDialog=fx(()->{var v=new UpdateCenterDialog(null,u.service);v.show();return v;});
            for(int i=0;i<2;i++) {
                fx(()->{blockedDialog.stage().fireEvent(new WindowEvent(blockedDialog.stage(),WindowEvent.WINDOW_CLOSE_REQUEST));return null;});
                waitFor(()->!u.service.busy()&&fx(()->noticeShowing(blockedDialog.stage())));
            }
            check("blocked update dialog stays visible",fx(()->blockedDialog.stage().isShowing()));
            check("blocked dialog notice does not stack",fx(()->Window.getWindows().stream().filter(w->w instanceof Stage s&&s.getOwner()==blockedDialog.stage()&&s.isShowing()).count()==1));
            u.service.close();hideAll();

            // A successful worker callback may be queued behind a new maintenance attempt on FX.
            var raced=new SimpleFlashChecks.Fixture();failed(raced);var late=context(raced);AtomicInteger actions=new AtomicInteger();
            fx(()->{
                action(late.app,actions::incrementAndGet);
                long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(3);
                while((raced.gate.active()||late.service.busy())&&System.nanoTime()<end)Thread.sleep(5);
                check("cleanup completed before delayed callback",!raced.gate.active()&&!late.service.busy());
                raced.service.prepareSimple(raced.target,true);raced.service.detectBoot();return null;
            });
            waitFor(()->fx(()->noticeShowing(late.stage)));
            check("late callback cannot hide a new maintenance attempt",actions.get()==0&&raced.gate.active()&&fx(()->late.stage.isShowing()));
            raced.service.exitSimple();late.service.close();hideAll();
            System.out.println("PASS actual close handlers; checks="+UpdateCenterChecks.checks+"; no App.start/shutdown, WCH, device I/O or process kill");
        } finally {hideAll();Platform.exit();}
    }
}
