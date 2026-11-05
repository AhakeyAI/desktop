package com.example.ahakey.wd010;

import com.example.ahakey.model.*;
import com.example.ahakey.protocol.*;
import com.example.ahakey.service.*;
import com.example.ahakey.firmware.*;
import com.example.ahakey.util.*;
import javafx.application.Platform;
import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Production adapter, real atomic files and FX queue; only USB transport is replaced. */
public final class RestorePreparationChecks {
    static int checks;static Path home,draft,runtime;static byte[] originalDraft,originalRuntime;
    static void check(boolean ok,String name){checks++;if(!ok)throw new AssertionError(name);}
    static <T>T fx(Callable<T> work)throws Exception{var f=new FutureTask<T>(work);Platform.runLater(f);return f.get(10,TimeUnit.SECONDS);}
    static void rejected(CompletableFuture<?> f)throws Exception{try{f.get(40,TimeUnit.SECONDS);throw new AssertionError("expected prepare failure");}catch(ExecutionException expected){checks++;}}
    static class Store extends FactoryResetStore {
        boolean failWrite,failClear,failSending,failSent,failRollback,failFx;
        CountDownLatch fxEntered,fxRelease;
        Store(){super(FactoryResetStore.defaultPath());}
        @Override protected void writeRuntime(byte[] bytes)throws IOException{super.writeRuntime(bytes);if(failWrite)throw new IOException("fixture after atomic runtime write");}
        @Override protected void restoreRuntime(DeviceBackup.PcFile saved)throws IOException{if(failRollback)throw new IOException("fixture rollback unavailable");super.restoreRuntime(saved);}
        @Override protected void clearPreparation()throws IOException{if(failClear)throw new IOException("fixture preparation cleanup");super.clearPreparation();}
        @Override public void save(Pending p)throws IOException{if(failSending&&p.stage().equals("SENDING"))throw new IOException("fixture send-marker save");if(failSent&&p.stage().equals("SENT"))throw new IOException("fixture post-send save");super.save(p);}
    }
    static final class Fixture implements AutoCloseable {
        final DeviceMaintenanceChecks.FixtureBle ble;final StudioState studio;final AiRuntimeDisplayService ai;final DisplayConfigService display;
        final AtomicInteger starts=new AtomicInteger(),queries=new AtomicInteger(),invalidations=new AtomicInteger();final FactoryResetService service;
        Fixture(Store store)throws Exception{this(store,false,()->{});}
        Fixture(Store store,boolean saved,Runnable afterLoad)throws Exception{
            ble=new DeviceMaintenanceChecks.FixtureBle();
            ble.usb.consumer=f->{try{if(f[2]==(byte)0x9e&&(f[4]==0x30||f[4]==0x31)){boolean start=f[4]==0x31;if(start)starts.incrementAndGet();else queries.incrementAndGet();int nonce=ByteBuffer.wrap(f).order(ByteOrder.LITTLE_ENDIAN).getInt(5);ble.reply(RestoreChecks.reply(f[3],f[4]&255,nonce,0,start?FactoryResetProtocol.State.IN_PROGRESS:FactoryResetProtocol.State.NEVER,start?1:0));}else throw new AssertionError("unexpected device command");}catch(Exception e){throw new RuntimeException(e);}};
            studio=fx(()->{var s=new StudioState();if(saved)s.loadFromPersisted(StudioStore.loadOrDefault(store));else{s.getKeyConfig(StudioPart.KEY2).setHidCode(63);s.markDirty(StudioPart.KEY2);s.displayConfig().editBrightness(77);}return s;});
            ai=fx(()->new AiRuntimeDisplayService(ble));display=new DisplayConfigService(studio,ble);afterLoad.run();
            service=fx(()->FactoryResetService.production(ble,studio,new DeviceStatus(),new K1RouteService(studio,ble),display,()->{if(store.fxEntered!=null){store.fxEntered.countDown();try{store.fxRelease.await();}catch(InterruptedException e){Thread.currentThread().interrupt();throw new IllegalStateException(e);}}if(store.failFx)throw new IllegalStateException("fixture FX action failure");invalidations.incrementAndGet();},ai::factoryResetStarted,store,ai::factoryPreparationRecovered));
        }
        void preserved()throws Exception{
            check(starts.get()==0,"production preparation failure sends no reset");
            check(Arrays.equals(Files.readAllBytes(draft),originalDraft),"original persisted draft bytes retained");
            check(Arrays.equals(Files.readAllBytes(runtime),originalRuntime),"runtime preference bytes rolled back");
            check(fx(()->studio.getKeyConfig(StudioPart.KEY2).getHidCode()==63&&studio.getDirtyCount()>0&&studio.displayConfig().brightnessDirty()),"live key and display drafts survive failure");
            check(fx(()->ai.displayModeProperty().get()==AiRuntimeDisplayMode.MULTI),"live runtime preference unchanged");
        }
        public void close()throws Exception{service.close();fx(()->{display.close();ai.close();return null;});}
    }
    static void resetFiles()throws Exception{
        Files.createDirectories(draft.getParent());Files.write(draft,originalDraft);Files.write(runtime,originalRuntime);
    }
    public static void main(String[] args)throws Exception{
        home=Path.of(System.getProperty("user.home")).toAbsolutePath();if(!home.toString().contains("wd010"))throw new AssertionError("isolated home required");
        draft=home.resolve(".ahakey/studio-draft.json");runtime=home.resolve(".ahakey/ai-runtime.json");
        originalDraft="{\"revision\":27,\"modes\":[]}".getBytes();originalRuntime="{\"displayMode\":\"MULTI\",\"codexDataDir\":\"fixture-preserved\"}".getBytes();resetFiles();
        CountDownLatch ready=new CountDownLatch(1);Platform.startup(ready::countDown);ready.await();Platform.setImplicitExit(false);
        try{
            // An undeletable/invalid draft directory is rejected before any mutation. There is
            // no pre-send delete anymore: quarantine retains original bytes until readback replaces them.
            try(var f=new Fixture(new Store())){
                Files.delete(draft);Files.createDirectory(draft);Files.writeString(draft.resolve("marker"),"retained");
                rejected(f.service.confirm(f.service.prepare().get()));check(Files.exists(draft.resolve("marker"))&&f.starts.get()==0&&!f.service.hasPending()&&f.ble.maintenance().normalAllowed(),"unreadable draft rejected with no deletion or permanent lock");
                Files.delete(draft.resolve("marker"));Files.delete(draft);resetFiles();
            }
            for(String mode:List.of("after-runtime-write","sending-save","cleanup","fx-error")){
                Store store=new Store();store.failWrite=mode.equals("after-runtime-write")||mode.equals("cleanup");store.failFx=mode.equals("fx-error");store.failSending=mode.equals("sending-save");store.failClear=mode.equals("cleanup");
                try(var f=new Fixture(store)){
                    rejected(f.service.confirm(f.service.prepare().get()));f.preserved();
                    if(store.failClear){
                        check(f.service.hasPending()&&f.service.requiresLocalCleanup(),"journal cleanup failure retains reachable local action even after pending cleared");
                        DeviceMaintenanceChecks.field(f.ble,"isConnected",false);f.ble.getCachedStatus().setConnected(false);int before=f.queries.get();store.failClear=false;
                        f.service.queryAgain(null).get();check(f.queries.get()==before,"local cleanup works disconnected without device query or association");
                    }
                    check(!f.service.hasPending()&&f.ble.maintenance().normalAllowed(),"known unsent failure converges and unlocks");
                }
            }
            // Simulate process termination after preference preparation but before SENDING.
            Store restart=new Store();var target=new FactoryResetStore.Target(0,"USB","fixture","","fixture-hid");
            restart.beginPreparation(new FactoryResetStore.Pending(1,UUID.randomUUID().toString(),target,1,"LOCAL_PREPARING"),null);restart.prepareRuntime();
            StudioStore.loadOrDefault();check(restart.load()==null&&Arrays.equals(Files.readAllBytes(runtime),originalRuntime),"startup rolls back provably unsent preparation before loading draft/runtime");
            // Actual startup ordering: draft loader, runtime loader, then production restore service.
            for(boolean secondAttempt:new boolean[]{false,true}){
                var saved=new StudioState();saved.getKeyConfig(StudioPart.KEY2).setHidCode(63);saved.getKeyConfig(StudioPart.KEY2).setDescription("restart-preserved");StudioStore.saveStrict(saved.toPersisted());originalDraft=Files.readAllBytes(draft);
                Store interrupted=new Store();interrupted.beginPreparation(new FactoryResetStore.Pending(1,UUID.randomUUID().toString(),target,1,"LOCAL_PREPARING"),null);interrupted.prepareRuntime();interrupted.failRollback=true;
                try(var f=new Fixture(interrupted,true,()->{if(secondAttempt)interrupted.failRollback=false;})){
                    check(fx(()->f.studio.getKeyConfig(StudioPart.KEY2).getHidCode()==63),"failed startup rollback still loads original live draft");
                    if(!secondAttempt){
                        check(f.service.requiresLocalCleanup(),"startup rollback remains retryable");DeviceMaintenanceChecks.field(f.ble,"isConnected",false);f.ble.getCachedStatus().setConnected(false);interrupted.failRollback=false;
                        fx(()->{var dialog=new com.example.ahakey.view.FactoryResetDialog(null,f.service);dialog.show();for(var w:javafx.stage.Window.getWindows())if(w instanceof javafx.stage.Stage stage&&stage.getTitle().contains("进度"))for(var n:stage.getScene().getRoot().lookupAll(".button"))if(n instanceof javafx.scene.control.Button button&&button.getText().equals("重试本地清理"))button.fire();return null;});
                        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);while(f.service.hasPending()&&System.nanoTime()<deadline)Thread.sleep(10);fx(()->null);
                    }
                    check(!f.service.hasPending()&&f.starts.get()==0&&f.queries.get()==0,"startup cleanup resolves without any device traffic");
                    check(fx(()->f.ai.displayModeProperty().get()==AiRuntimeDisplayMode.MULTI),"startup or delayed cleanup restores live runtime preference");
                    fx(()->{f.studio.setSelectedMode(ModeSlot.MODE1);StudioStore.save(f.studio.toPersisted());return null;});
                    var reloaded=new StudioState();reloaded.loadFromPersisted(StudioStore.loadOrDefault());check(reloaded.getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).getHidCode()==63,"later ordinary save and restart retain original key");
                }
                resetFiles();
            }
            try(var f=new Fixture(new Store())){
                var accepted=f.service.prepare().get();CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
                Platform.runLater(()->{entered.countDown();try{release.await();}catch(InterruptedException e){Thread.currentThread().interrupt();}});entered.await();
                var attempt=f.service.confirm(accepted);rejected(attempt);release.countDown();fx(()->null);
                f.preserved();check(f.invalidations.get()==0&&!f.service.hasPending()&&f.ble.maintenance().normalAllowed(),"30s FX queue timeout cancels callback; releasing FX cannot mutate late");
            }
            Store activeFx=new Store();activeFx.failFx=true;activeFx.fxEntered=new CountDownLatch(1);activeFx.fxRelease=new CountDownLatch(1);
            try(var f=new Fixture(activeFx)){
                var attempt=f.service.confirm(f.service.prepare().get());check(activeFx.fxEntered.await(3,TimeUnit.SECONDS),"FX preparation action has actually started");
                Thread.sleep(31000);check(!attempt.isDone()&&!f.ble.maintenance().normalAllowed(),"started FX action cannot time out and unlock while still running");
                activeFx.fxRelease.countDown();rejected(attempt);f.preserved();check(!f.service.hasPending()&&f.ble.maintenance().normalAllowed(),"started FX failure settles before rollback/unlock");
            }finally{activeFx.fxRelease.countDown();}
            Store sent=new Store();sent.failSent=true;
            try(var f=new Fixture(sent)){
                rejected(f.service.confirm(f.service.prepare().get()));check(f.starts.get()==1&&f.service.hasPending()&&sent.load().stage().equals("SENDING"),"post-send save failure stays ambiguous with durable send marker");
                int before=f.starts.get();f.service.queryAgain(null).get();check(f.starts.get()==before&&f.service.hasPending(),"post-send uncertainty queries only and cannot rollback/replay");
            }
            System.out.println("PASS RestorePreparationChecks "+checks+" checks; real production adapter/files/FX timeout, in-memory transport only");
        }finally{Platform.exit();}
    }
}
