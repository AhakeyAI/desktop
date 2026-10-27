package com.example.ahakey.firmware;

import com.example.ahakey.service.*;
import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.protocol.*;
import java.io.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import static com.example.ahakey.update.UpdateCenterChecks.*;

public final class DeviceMaintenanceChecks {
    public static final String HASH="a".repeat(64);
    public static DeviceMaintenanceCoordinator.Identity identity(){return new DeviceMaintenanceCoordinator.Identity(0,"USB","fixture-hid","container-A","port-1",FirmwareCatalog.CATALOG);}
    public static class FixtureBle extends BleManager {
        public final MemoryUsb usb=new MemoryUsb();
        public FixtureBle()throws Exception{
            this(new BleCallback(){public void onConnected(){}public void onDisconnected(){}public void onStatusReceived(DeviceStatus s){}public void onError(String s){}});
        }
        public FixtureBle(BleCallback callback)throws Exception{
            super(callback);
            field(this,"usbTransport",usb);field(this,"isConnected",true);getCachedStatus().setConnected(true);
            field(this,"firmwareIdentity",new FirmwareIdentity(0,1,DeviceStatus.IdentityState.SUPPORTED,FirmwareCatalog.CATALOG));
        }
        @Override protected boolean isUsbDevicePresent(){return false;}
        public void reply(byte[] frame)throws Exception{Method m=BleManager.class.getDeclaredMethod("onSessionNotify",long.class,byte[].class);m.setAccessible(true);m.invoke(this,connectionGeneration(),frame);}
    }
    public static final class MemoryUsb extends UsbHidTransport {
        public final AtomicInteger writes=new AtomicInteger();public Consumer<byte[]> consumer=b->{};
        public boolean opened=true;
        public boolean isOpen(){return opened;}public String devicePath(){return "fixture-hid";}
        public void sendCommand(byte[] frame)throws IOException{writes.incrementAndGet();consumer.accept(frame);}
        public void sendData(byte[] data){writes.incrementAndGet();}public void close(){opened=false;}public void open(Consumer<byte[]> callback){throw new AssertionError("No HID open");}
        public void openExact(String path,Consumer<byte[]> callback){if(!path.equals("fixture-hid"))throw new AssertionError("wrong HID");opened=true;}
    }
    public static void field(Object object,String name,Object value)throws Exception{Field f=BleManager.class.getDeclaredField(name);f.setAccessible(true);f.set(object,value);}
    public static void main(String[] args)throws Exception{
        if(args.length>0&&args[0].equals("r6-controller")){controllerRegression();return;}
        FixtureBle ble=new FixtureBle();var gate=ble.maintenance();
        var once=gate.normalTransaction();once.close();once.close();
        try(var stillActive=gate.normalTransaction()){rejects("double close cannot consume another ordinary lease",()->ble.beginMaintenance(identity(),HASH,"test",false));}
        try(var ordinary=gate.normalTransaction()){rejects("whole normal transaction excludes maintenance",()->ble.beginMaintenance(identity(),HASH,"test",false));}
        CountDownLatch atWrite=new CountDownLatch(1),completeWrite=new CountDownLatch(1);
        ble.usb.consumer=b->{atWrite.countDown();try{completeWrite.await();}catch(InterruptedException e){throw new RuntimeException(e);}};
        Method bypass=BleManager.class.getDeclaredMethod("requestModeReadbackStatus");bypass.setAccessible(true);
        var send=CompletableFuture.runAsync(()->{try{bypass.invoke(ble);}catch(Exception e){throw new RuntimeException(e);}});
        check("USB bypass entered physical write",atWrite.await(2,TimeUnit.SECONDS));
        CountDownLatch acquisitionAttempt=new CountDownLatch(1);
        var begin=CompletableFuture.supplyAsync(()->{acquisitionAttempt.countDown();try{return ble.beginMaintenance(identity(),HASH,"test",false);}catch(Exception e){throw new RuntimeException(e);}});
        acquisitionAttempt.await();
        try { begin.get(300,TimeUnit.MILLISECONDS); throw new AssertionError("maintenance interleaved write"); }
        catch(TimeoutException expected){check("maintenance waits across physical USB write",true);}
        completeWrite.countDown();send.get(2,TimeUnit.SECONDS);var op=begin.get(2,TimeUnit.SECONDS);
        ble.usb.consumer=b->{};int writes=ble.usb.writes.get();
        rejects("ordinary command",()->ble.sendCommand(AhaKeyProtocol.queryDeviceStatus()));
        rejects("data bypass",()->ble.writeData(new byte[]{1}));
        rejects("query snapshot USB bypass",()->ble.queryDeviceStatusSnapshot(1,true));
        rejects("mode readback USB bypass",()->bypass.invoke(ble));
        rejects("display lease",()->ble.openDisplayLease(true));
        rejects("sleep setter",()->ble.setSleepWaitTimeMinutesAndVerify(1));
        rejects("mode setter",()->ble.setWorkModeAndVerify(1));
        check("runtime fact not SENT",!ble.sendRuntimeState((byte)1));ble.queryStatus();
        Method packet=BleManager.class.getDeclaredMethod("writePacket",byte.class,byte[].class);packet.setAccessible(true);
        for(byte packetType:new byte[]{BleTcpPacket.QUERY_BLE_STATUS,BleTcpPacket.QUERY_DEVICE_INFO,BleTcpPacket.WRITE_COMMAND,BleTcpPacket.WRITE_DATA})
            rejects("TCP bottom gate "+packetType,()->packet.invoke(ble,packetType,packetType==BleTcpPacket.WRITE_COMMAND?AhaKeyProtocol.queryDeviceStatus():null));
        check("no bypass wrote",ble.usb.writes.get()==writes);
        gate.within(op,()->{ble.sendCommand(AhaKeyProtocol.readSideSwitchConfig());return null;});check("backup read allowed",ble.usb.writes.get()==writes+1);
        rejects("backup token cannot write side",()->gate.within(op,()->{ble.sendCommand(AhaKeyProtocol.setSideSwitchConfig(0,new byte[0],0,new byte[0]));return null;}));
        rejects("backup token cannot save",()->gate.within(op,()->{ble.sendCommand(AhaKeyProtocol.saveConfig());return null;}));
        check("exit excluded",!gate.requestExit(null));long epoch=gate.epoch();gate.finish(op,false);check("epoch invalidates deferred callbacks",epoch!=gate.epoch());
        var other=new DeviceMaintenanceCoordinator.Identity(1,"USB","x","container-B","port-1",FirmwareCatalog.CATALOG);
        check("same port cannot override container conflict",!identity().samePhysicalDevice(other));
        check("same container different port conflict",!identity().samePhysicalDevice(new DeviceMaintenanceCoordinator.Identity(1,"USB","x","container-A","port-2",FirmwareCatalog.CATALOG)));
        var next=ble.beginMaintenance(identity(),HASH,"test",false);gate.processAlive(next,true);gate.uncertain(next);rejects("live tool cannot release",()->gate.finish(next,true));gate.processAlive(next,false);gate.finish(next,true);
        System.out.println("PASS maintenance actual BleManager paths; memory USB only");
    }
    public static <T>T fx(java.util.concurrent.Callable<T> action)throws Exception{
        var task=new FutureTask<T>(action);javafx.application.Platform.runLater(task);return task.get(10,TimeUnit.SECONDS);
    }
    private static Object member(Object o,String name)throws Exception{var f=o.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(o);}
    private static void changed(com.example.ahakey.app.StudioController c)throws Exception{var m=c.getClass().getDeclaredMethod("maintenanceChanged");m.setAccessible(true);m.invoke(c);fx(()->null);}
    private static void awaitController(java.util.concurrent.Callable<Boolean> ready)throws Exception{
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(6);while(!fx(ready)){if(System.nanoTime()>deadline)throw new AssertionError("controller did not reconcile");Thread.sleep(10);}
    }
    private static void notifyChanged(com.example.ahakey.app.StudioController c){try{var m=c.getClass().getDeclaredMethod("maintenanceChanged");m.setAccessible(true);m.invoke(c);}catch(Exception e){throw new RuntimeException(e);}}
    private static void controllerRegression()throws Exception{
        System.setProperty("user.home",java.nio.file.Files.createTempDirectory("r6-controller-home-").toString());
        javafx.application.Platform.startup(()->{});javafx.application.Platform.setImplicitExit(false);
        try{
            for(String scenario:List.of("prepared-cancel","wait-download-cancel","restore","keep-cleared","failure-release","reconnect-failed","stale-callback")){
                com.example.ahakey.app.StudioController[] controller=new com.example.ahakey.app.StudioController[1];FirmwareUpdateChecks.WireDevice[] transport=new FirmwareUpdateChecks.WireDevice[1];BleManager.BleCallback[] callback=new BleManager.BleCallback[1];KimiAhaKeyBridge[] bridge=new KimiAhaKeyBridge[1];
                try{
                    fx(()->{controller[0]=new com.example.ahakey.app.StudioController(cb->{try{callback[0]=cb;return transport[0]=new FirmwareUpdateChecks.WireDevice(cb);}catch(Exception e){throw new RuntimeException(e);}},ble->{try{var ctor=KimiAhaKeyBridge.class.getDeclaredConstructor(BleManager.class,int.class);ctor.setAccessible(true);return bridge[0]=ctor.newInstance(ble,0);}catch(Exception e){throw new RuntimeException(e);}},false);return null;});
                    var c=controller[0];var ble=transport[0];fx(()->{callback[0].onConnected();return null;});fx(()->null);
                    check("initial Kimi listener exists "+scenario,member(bridge[0],"session")!=null);
                    var maintenance=new FirmwareUpdateChecks.WireMaintenance(ble,()->notifyChanged(c));
                    String key="x1-c582-hw1-p1-1.0.0-r002";var target=maintenance.official(key,FirmwareCatalog.ALL);boolean connected;
                    if(scenario.equals("prepared-cancel")){
                        maintenance.service.prepare(target,null,true);fx(()->null);check("preparation pauses existing poll/Kimi",member(bridge[0],"session")==null&&member(c,"pollFuture")==null);maintenance.service.cancel();connected=true;
                    }else if(scenario.equals("wait-download-cancel")){
                        maintenance.service.prepare(target,null,true);maintenance.service.enterDownloadMode();fx(()->null);maintenance.service.cancel();connected=false;
                    }else if(scenario.equals("failure-release")||scenario.equals("reconnect-failed")){
                        maintenance.service.prepare(target,null,true);maintenance.service.enterDownloadMode();ble.downloadMode=true;
                        if(scenario.equals("failure-release")){maintenance.failLaunch=true;rejects("controlled tool startup failure",maintenance.service::flash);}
                        else{maintenance.service.flash();ble.downloadMode=false;ble.container="replacement";rejects("wrong physical reconnect",maintenance.service::checkReconnect);}
                        maintenance.service.acknowledgeFailure();connected=false;
                    }else{
                        maintenance.flashed(target);fx(()->null);check("no ordinary writers during restore decision "+scenario,member(bridge[0],"session")==null&&member(c,"pollFuture")==null&&!c.getStudioState().isCp4cInputConfigEnabled());
                        if(scenario.equals("restore")){check("actual controller attached full restore",maintenance.service.restore().complete());}
                        else if(scenario.equals("stale-callback")){
                            CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);javafx.application.Platform.runLater(()->{entered.countDown();try{release.await();}catch(InterruptedException e){Thread.currentThread().interrupt();}});entered.await();
                            callback[0].onDisconnected();maintenance.service.keepCleared();release.countDown();
                        }else maintenance.service.keepCleared();connected=true;
                    }
                    if(connected){
                        String expected=scenario.equals("prepared-cancel")?FirmwareCatalog.CATALOG:key;
                        awaitController(()->c.getDeviceStatus().isConnected()&&c.getDeviceStatus().getFirmwareCatalogKey().equals(expected)&&c.getStudioState().isCp4cInputConfigEnabled()&&!c.getStudioState().inputReadbackInProgressProperty().get()&&java.util.Arrays.stream(com.example.ahakey.model.ModeSlot.values()).allMatch(c.getStudioState()::isInputModeRead));
                        check("current UI identity and all-mode readback restored "+scenario,ble.keyReads>=16&&c.getDeviceStatus().getFirmwareCatalogKey().equals(expected));
                        check("poll/Kimi restored "+scenario,member(c,"pollFuture")!=null&&member(bridge[0],"session")!=null);
                        if(scenario.equals("restore")){
                            awaitController(()->ble.polls>0);check("restored scheduled poll actually runs",ble.polls>0);
                            var listener=(java.net.ServerSocket)member(member(bridge[0],"session"),"listener");
                            try(var socket=new java.net.Socket("127.0.0.1",listener.getLocalPort())){socket.setSoTimeout(2000);socket.getOutputStream().write(new byte[]{3,0,0});check("restored Kimi listener serves actual query",socket.getInputStream().read()==0x82);}
                        }
                        if(scenario.equals("stale-callback")){fx(()->{callback[0].onDisconnected();return null;});fx(()->null);check("late old disconnect cannot stop current session",c.getDeviceStatus().isConnected()&&member(c,"pollFuture")!=null&&member(bridge[0],"session")!=null);}
                    }else{
                        awaitController(()->!c.getDeviceStatus().isConnected()&&c.getDeviceStatus().getFirmwareCatalogKey().isBlank());
                        check("disconnected release keeps poll/Kimi stopped "+scenario,member(c,"pollFuture")==null&&member(bridge[0],"session")==null&&!c.getStudioState().isCp4cInputConfigEnabled());
                    }
                }finally{if(controller[0]!=null)fx(()->{controller[0].shutdown();return null;});}
            }
            System.out.println("PASS R6 actual controller callbacks + firmware service + transport + ephemeral Kimi lifecycle; no Hook or hardware");
        }finally{javafx.application.Platform.exit();}
    }
}
