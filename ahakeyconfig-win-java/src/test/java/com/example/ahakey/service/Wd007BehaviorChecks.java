package com.example.ahakey.service;

import com.example.ahakey.model.*;
import com.example.ahakey.model.connection.DeviceTarget;
import com.example.ahakey.protocol.*;
import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.*;

/** Actual coordinator/transaction/model code with memory-only USB, no native input or device discovery. */
public final class Wd007BehaviorChecks {
    static int checks;
    static void check(boolean value,String name){if(!value)throw new AssertionError(name);checks++;}
    static void await(BooleanSupplier predicate,String name)throws Exception{long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(4);while(!predicate.getAsBoolean()&&System.nanoTime()<end)Thread.sleep(5);check(predicate.getAsBoolean(),name);}
    static Object field(Object object,String name)throws Exception{Field f=BleManager.class.getDeclaredField(name);f.setAccessible(true);return f.get(object);}
    static final BleManager.BleCallback CALLBACK=new BleManager.BleCallback(){public void onConnected(){}public void onDisconnected(){}public void onStatusReceived(DeviceStatus s){}public void onError(String s){System.out.println("fixture message: "+s);}};
    static final class Memory extends UsbHidTransport {
        boolean open;Consumer<byte[]> receive;String id;final Wire owner;
        Memory(Wire owner){this.owner=owner;}
        @Override public void openExact(String path,Consumer<byte[]> consumer){id=path;receive=consumer;open=true;owner.opened.put(path,this);}
        @Override public boolean isOpen(){return open;}
        @Override public String devicePath(){return id;}
        @Override public void close(){open=false;}
        @Override public void cancelPendingIo(){super.cancelPendingIo();}
        void failReader(){open=false;readerTerminatedUnexpectedly();}
        @Override public void sendCommand(byte[] frame){
            owner.frames.add(id+":"+(frame[2]&255));
            if((frame[2]&255)==owner.held){owner.heldRequest=frame.clone();owner.heldMemory=this;return;}
            answer(frame);
        }
        void answer(byte[] f){
            byte[] payload=f[2]==0?new byte[]{80,1,1,2,0,0,(byte)owner.position,35}:f[2]==(byte)0x9F?"\0x1-c582-hw1-p1-1.0.0-r001".getBytes(java.nio.charset.StandardCharsets.US_ASCII):f[2]==(byte)0x88?new byte[]{0,2,f[4],0,0}:new byte[]{0};
            if(f[2]==(byte)0x97&&f.length==5)payload=new byte[]{0,0,2,0,0,2,0};
            if(f[2]==(byte)0x87)payload=new byte[]{0,f[3],f[4],0x73,1,(byte)owner.readbackHid,0};
            receive.accept(AhaKeyProtocol.buildFrame(f[2],payload));
        }
        @Override public void sendData(byte[] bytes){throw new AssertionError("unexpected legacy data upload");}
    }
    static final class Wire extends BleManager {
        List<String> candidates=List.of("A");final Map<String,Memory> opened=new ConcurrentHashMap<>();
        boolean enumerationFails;
        int readbackHid=4;
        final List<String> frames=new CopyOnWriteArrayList<>();volatile int held=-1,position=0;volatile byte[] heldRequest;volatile Memory heldMemory;
        Wire(){super(CALLBACK);}
        Wire(BleCallback callback){super(callback);}
        @Override protected List<String> usbCandidates(){if(enumerationFails)throw new IllegalStateException("incomplete native enumeration");return candidates;}
        @Override protected UsbHidTransport createUsbTransport(){return new Memory(this);}
        @Override public void queryStatus(){} // Explicit queries below exercise the real scheduler deterministically.
    }
    static AhaKeyResponseParser.SideSwitchConfig side(boolean autoUp){
        var auto=new AhaKeyResponseParser.SideSwitchPositionConfig(AhaKeyProtocol.SIDE_SWITCH_BINDING_AUTO,new byte[0]);
        var off=new AhaKeyResponseParser.SideSwitchPositionConfig(AhaKeyProtocol.SIDE_SWITCH_BINDING_DISABLED,new byte[0]);
        return new AhaKeyResponseParser.SideSwitchConfig(0,autoUp?auto:off,autoUp?off:auto);
    }
    static void simulation()throws Exception{
        KeyConfig key=new KeyConfig(0x206,"shortcut");List<String> events=new ArrayList<>();
        KeySimulationService.execute(KeySimulationService.snapshot(key),(hid,down)->events.add(hid+":"+down),ms->events.add("delay:"+ms));
        check(events.equals(List.of("224:true","6:true","6:false","224:false")),"shortcut modifier order and balanced release");
        key.addMacroStep("DOWN_KEY",4);key.addMacroStep("DELAY",7);key.addMacroStep("UP_KEY",4);
        var snapshot=KeySimulationService.snapshot(key);key.setHidCode(99);key.addMacroStep("DOWN_KEY",5);events.clear();
        KeySimulationService.execute(snapshot,(hid,down)->events.add(hid+":"+down),ms->events.add("delay:"+ms));
        check(events.equals(List.of("4:true","delay:21","4:false")),"full immutable macro overrides leftover shortcut");
        events.clear();try{KeySimulationService.execute(snapshot,(hid,down)->{events.add(hid+":"+down);if(down)throw new IOException("partial send");},ms->{});throw new AssertionError("expected failure");}catch(IOException expected){}
        check(events.equals(List.of("4:true","4:false")),"partial native failure still attempts own release");
    }
    static void factsAndDrafts(){
        DeviceStatus status=new DeviceStatus();status.setConnected(true);status.setSwitchState(0);
        check(!status.isAutoApproval(),"unknown saved binding fails closed");status.setSavedBindings(side(false));
        check(!status.isAutoApproval(),"upper physical position does not imply AUTO");status.setSwitchState(1);
        check(status.isAutoApproval()&&status.getSwitchTitle().startsWith("下拨"),"swapped AUTO follows confirmed binding");
        status.setConnected(false);check(!status.isAutoApproval()&&status.getSavedBindings()==null,"disconnect removes approval facts");
        StudioState state=new StudioState();state.selectDevice("USB:A");state.getKeyConfig(StudioPart.KEY2).setHidCode(6);state.markDirty(StudioPart.KEY2);
        state.selectDevice("USB:B");check(state.getKeyConfig(StudioPart.KEY2).getHidCode()==0&&state.getDirtyCount()==0,"B does not inherit A input or dirty state");
        state.getKeyConfig(StudioPart.KEY2).setHidCode(9);state.markDirty(StudioPart.KEY2);state.selectDevice("USB:A");
        check(state.getKeyConfig(StudioPart.KEY2).getHidCode()==6&&state.getDirtyCount()>0,"A in-memory draft restored by exact identity");
        state.selectDevice("BLE:A");check(state.getKeyConfig(StudioPart.KEY2).getHidCode()==0,"unproven transport identities never merge");
    }
    static void coordinator()throws Exception{
        Wire wire=new Wire();ExecutorService workers=Executors.newFixedThreadPool(2);
        try{
            check(!wire.isConnected()&&wire.opened.isEmpty(),"startup does not connect");
            wire.candidates=List.of("A","B");wire.setTargetSelector(list->CompletableFuture.completedFuture(null));wire.connect();
            await(()->!wire.isScanning(),"cancel selection finishes");check(!wire.isConnected()&&wire.opened.isEmpty(),"USB cancel opens no device or BLE fallback");
            wire.setTargetSelector(list->CompletableFuture.completedFuture(list.get(0)));wire.connect();await(wire::isConnected,"explicit selection connects A");
            long a=wire.connectionGeneration();Memory original=wire.opened.get("A");
            wire.confirmSavedBindings(side(true),a);check(wire.refreshAutoApproval(),"approval obtains fresh status");wire.position=1;
            check(!wire.refreshAutoApproval(),"physical change after cached AUTO defers");
            wire.held=0x73;
            var pending=workers.submit(()->{try{wire.sendCommand(AhaKeyProtocol.buildFrame((byte)0x73,new byte[]{0}));return false;}catch(IOException expected){return true;}});
            await(()->wire.heldRequest!=null,"A write is in flight");
            wire.connectSelected(new DeviceTarget("USB","B","same name"));await(()->wire.isConnected()&&wire.targetIdentity().equals("USB:B"),"B connected after A cancellation");
            check(pending.get(1,TimeUnit.SECONDS),"A pending request fails on switch");long b=wire.connectionGeneration();
            original.answer(AhaKeyProtocol.queryDeviceStatus());check(wire.connectionGeneration()==b&&wire.getCachedStatus().getSwitchState()==-1,"A late status cannot become B fact");
            Method open=BleManager.class.getDeclaredMethod("openSelected",DeviceTarget.class,long.class);open.setAccessible(true);
            open.invoke(wire,new DeviceTarget("USB","A","old queued attempt"),0L);
            check(wire.isConnected()&&wire.targetIdentity().equals("USB:B")&&wire.connectionGeneration()==b,"obsolete queued open cannot even disconnect B");
            try(var ignored=wire.bindGeneration(a)){try{wire.sendCommand(AhaKeyProtocol.queryDeviceStatus());throw new AssertionError("old generation sent");}catch(IOException expected){checks++;}}
            wire.held=-1;wire.connectSelected(new DeviceTarget("USB","A","A"));await(()->wire.isConnected()&&wire.targetIdentity().equals("USB:A"),"A may reconnect for recovery presentation");
            int count=wire.frames.size();try{wire.sendCommand(AhaKeyProtocol.queryFirmwareCatalogKey());throw new AssertionError("quarantine bypass");}catch(IOException expected){}
            check(wire.isDisplayWriteUncertain()&&wire.frames.size()==count,"reopening same target cannot erase uncertain transaction");
            var registry=(com.example.ahakey.service.connection.DeviceRecoveryRegistry)field(wire,"recoveryTargets");
            var onDisk=new com.example.ahakey.service.connection.DeviceRecoveryRegistry(Path.of(System.getProperty("user.home"),".ahakey","device-recovery.json"));
            check(onDisk.contains("USB:A")&&!onDisk.absenceObserved("USB:A"),"application restart preserves quarantine");
            registry.observe("USB",Set.of("A"));check(!registry.absenceObserved("USB:A"),"missed short unplug cannot clear recovery");
            wire.disconnect();registry.observe("USB",Set.of());
            check(registry.absenceObserved("USB:A"),"actual observed absence enables safe recovery probe");
            wire.connectSelected(new DeviceTarget("USB","A","A"));
            await(()->wire.isConnected()&&!wire.isDisplayWriteUncertain(),"physical reconnect plus all metadata confirms idle");
            check(wire.frames.stream().filter(f->f.endsWith(":136")).count()==19,"all resource slots probed before write unlock");
            check(!new com.example.ahakey.service.connection.DeviceRecoveryRegistry(Path.of(System.getProperty("user.home"),".ahakey","device-recovery.json")).contains("USB:A"),"confirmed recovery persisted");
        }finally{wire.shutdownTransport();workers.shutdownNow();}
    }
    static void uploadCancel()throws Exception{
        System.setProperty("user.home",Files.createTempDirectory("wd007-upload-").toString());
        Wire wire=new Wire();try{
            wire.connectSelected(new DeviceTarget("USB","A","A"));await(wire::isConnected,"upload fixture connected");wire.readFirmwareCatalogKey();
            AtomicBoolean cancel=new AtomicBoolean();var asset=OledResourceState.Asset.fromBytes(new byte[28672]);
            try{OledUploadService.uploadResource(wire,wire.connectionGeneration(),0,asset,p->cancel.set(true),()->{},p->{},cancel::get);throw new AssertionError("cancel failed");}catch(OledUploadService.UploadFailure expected){}
            check(wire.frames.stream().filter(f->f.endsWith(":139")).count()==1,"cancel stops after acknowledged first chunk");
            check(wire.frames.stream().noneMatch(f->f.endsWith(":140")),"cancel never sends COMMIT or invented ABORT");
            check(wire.isDisplayWriteUncertain(),"unfinished upload quarantines target");
        }finally{wire.shutdownTransport();}
    }
    static void hookMigration()throws Exception{
        String before=System.getProperty("user.home");Path home=Files.createTempDirectory("wd007-hooks-");
        try{
            System.setProperty("user.home",home.toString());Path hooks=home.resolve(".ahakey/hooks");Files.createDirectories(hooks);
            for(String name:List.of("claude","codex"))Files.copy(Path.of("scripts/wd007/fixtures/legacy-"+name+".ps1"),hooks.resolve("ahakey-"+name+".ps1"));
            HookInstaller installer=new HookInstaller(1,s->{});installer.migrateOwnedApprovalScripts();
            for(String name:List.of("claude","codex"))check(!Files.readString(hooks.resolve("ahakey-"+name+".ps1")).contains("\"ask\""),"owned "+name+" wrapper native defer");
            try(var paths=Files.list(hooks)){check(paths.filter(p->p.toString().endsWith(".bak")).count()==2,"both originals backed up");}
            Path custom=hooks.resolve("ahakey-claude.ps1");Files.writeString(custom,"# user-owned changes\n");installer.migrateOwnedApprovalScripts();
            check(Files.readString(custom).equals("# user-owned changes\n"),"unrecognized custom hook untouched");
        }finally{System.setProperty("user.home",before);}
    }
    public static void main(String[] args)throws Exception{System.setProperty("user.home",Files.createTempDirectory("wd007-session-").toString());simulation();factsAndDrafts();coordinator();uploadCancel();hookMigration();System.out.println("PASS "+checks+" WD007 behavior checks; no real device/SendInput/Hook installation");}
}
