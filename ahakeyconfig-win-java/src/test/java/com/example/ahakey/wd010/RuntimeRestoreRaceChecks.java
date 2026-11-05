package com.example.ahakey.wd010;

import com.example.ahakey.service.*;
import com.example.ahakey.model.*;
import com.example.ahakey.protocol.*;
import com.example.ahakey.firmware.*;
import javafx.application.Platform;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Pauses real mode threads at the actual transport monitor across a restore epoch. */
public final class RuntimeRestoreRaceChecks {
    static int checks;
    static void check(boolean ok,String label){checks++;if(!ok)throw new AssertionError(label);}
    static <T>T fx(Callable<T> action)throws Exception{FutureTask<T> f=new FutureTask<>(action);Platform.runLater(f);return f.get(10,TimeUnit.SECONDS);}
    public static void main(String[] args)throws Exception{
        CountDownLatch ready=new CountDownLatch(1);Platform.startup(ready::countDown);ready.await();Platform.setImplicitExit(false);
        try{
            for(boolean connect:new boolean[]{false,true}){
                var ble=new DeviceMaintenanceChecks.FixtureBle();var frames=new CopyOnWriteArrayList<byte[]>();ble.usb.consumer=f->{frames.add(f);try{ble.reply(AhaKeyProtocol.buildFrame(f[2],new byte[]{0}));}catch(Exception e){throw new RuntimeException(e);}};
                var runtime=fx(()->new AiRuntimeDisplayService(ble));var lockField=BleManager.class.getDeclaredField("commandTransactionLock");lockField.setAccessible(true);Object lock=lockField.get(ble);AtomicReference<String> result=new AtomicReference<>();
                synchronized(lock){
                    fx(()->{runtime.displayModeProperty().set(connect?AiRuntimeDisplayMode.MULTI:AiRuntimeDisplayMode.SINGLE);if(connect)runtime.onDeviceReady();else runtime.setDisplayMode(AiRuntimeDisplayMode.MULTI,result::set);return null;});
                    String threadName=connect?"ai-runtime-connect-apply":"ai-runtime-mode-send";long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);boolean blocked=false;
                    while(System.nanoTime()<end){blocked=Thread.getAllStackTraces().keySet().stream().anyMatch(t->t.getName().equals(threadName)&&t.getState()==Thread.State.BLOCKED);if(blocked)break;Thread.sleep(5);}check(blocked,"actual display thread waits at transport monitor");
                    ble.maintenance().bindFactory(ble.connectionGeneration());fx(()->{runtime.factoryResetStarted();return null;});ble.maintenance().releaseFactory();
                }
                if(!connect){long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);while(result.get()==null&&System.nanoTime()<end)Thread.sleep(10);check(result.get()!=null,"old callback reports invalidated operation");}
                else {long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);while(Thread.getAllStackTraces().keySet().stream().anyMatch(t->t.getName().equals("ai-runtime-connect-apply")&&t.isAlive())&&System.nanoTime()<end)Thread.sleep(10);}
                check(frames.stream().noneMatch(f->f[2]==(byte)0x98||f[2]==(byte)0x99),"queued old display preference emits no mode or MULTI frame");
                fx(()->{check(runtime.displayModeProperty().get()==AiRuntimeDisplayMode.SINGLE,"old callback cannot restore MULTI preference");return null;});
            }
            System.out.println("PASS RuntimeRestoreRaceChecks "+checks+" checks; actual UI worker, transport lock, restore epoch and callback");
        }finally{Platform.exit();}
    }
}
