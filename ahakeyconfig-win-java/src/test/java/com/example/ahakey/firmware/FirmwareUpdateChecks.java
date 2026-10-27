package com.example.ahakey.firmware;

import com.example.ahakey.update.VerifiedDownload;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import static com.example.ahakey.update.UpdateCenterChecks.*;

public final class FirmwareUpdateChecks {
    public static final class Fixture implements FirmwareUpdateService.DeviceIO,FirmwareUpdateService.ToolIO {
        public final DeviceMaintenanceCoordinator gate=new DeviceMaintenanceCoordinator();
        public final List<String> calls=new ArrayList<>();
        public DeviceMaintenanceCoordinator.Identity identity=DeviceMaintenanceChecks.identity();
        public boolean wrongDownload,wrongReconnect,failBackup,notStarted,timedOut;
        public int restores;
        public Runnable duringBackup=()->{};
        public final FirmwareUpdateService service;
        public final FirmwareCatalog.Target target;
        public Fixture()throws Exception{
            Path root=Files.createTempDirectory("firmware-checks-");Path hex=root.resolve("local.hex");Files.writeString(hex,":0100000001FE\n:00000001FF\n");
            target=new FirmwareCatalog().local(hex);service=new FirmwareUpdateService(gate,this,this,root.resolve("work"),()->{});
        }
        public DeviceMaintenanceCoordinator.Identity identity(){return identity;}
        public DeviceMaintenanceCoordinator.Operation begin(DeviceMaintenanceCoordinator.Identity i,String h,String p)throws Exception{return gate.begin(i,h,p,false);}
        public DeviceBackup backup(DeviceMaintenanceCoordinator.Operation op,Set<String> required,Runnable cancel)throws Exception{
            calls.add("backup");duringBackup.run();cancel.run();if(failBackup)throw new java.io.IOException("necessary readback failed");
            return BackupRestoreChecks.backup(op.id().toString(),op.source(),op.targetHash(),required);
        }
        public void disconnect(DeviceMaintenanceCoordinator.Operation op){calls.add("disconnect");}
        public void downloadTarget(DeviceMaintenanceCoordinator.Identity source)throws Exception{calls.add("download identity");if(wrongDownload)throw new java.io.IOException("wrong port");}
        public DeviceMaintenanceCoordinator.Identity reconnect(DeviceMaintenanceCoordinator.Operation op)throws Exception{
            calls.add("reconnect");identity=new DeviceMaintenanceCoordinator.Identity(1,"USB","fixture-hid",wrongReconnect?"other":"container-A","port-1",FirmwareCatalog.CATALOG);
            gate.bindReconnection(op,identity);return identity;
        }
        public DeviceRestoreService.Device restoreDevice(){return new DeviceRestoreService.Device(){public void key(DeviceBackup.Key k){restores++;}public void side(DeviceBackup.Side s){restores++;}public void brightness(int v){restores++;}public void light(DeviceBackup.Light l){restores++;}};}
        public WchRuntimeLocator.Runtime locate(Path p){return new WchRuntimeLocator.Runtime("fixture",Path.of("unused"),Path.of("unused.exe"),Map.of());}
        public WchFlashAdapter.Result execute(WchRuntimeLocator.Runtime runtime,Path hex,String hash,Path directory,String operation,Runnable timeout)throws Exception{
            calls.add(operation);check("frozen file hash at "+operation,VerifiedDownload.sha256(hex).equals(hash));
            if(notStarted)throw new WchFlashAdapter.NotStartedException(new java.io.IOException("fixture prelaunch failure"));
            if(timedOut){timeout.run();return new WchFlashAdapter.Result(false,true,true,-1,"alive");}
            return new WchFlashAdapter.Result(true,false,false,0,"Status=Finished\nCode=0\nMessage=Succeed");
        }
        public void prepared()throws Exception{service.prepare(target,null,true);service.enterDownloadMode();}
    }
    public static void main(String[] args)throws Exception{
        if(args.length>0&&args[0].equals("r6-catalog")){catalogRegression();return;}
        Fixture good=new Fixture();good.prepared();check("backup before download transition",good.calls.equals(List.of("backup","disconnect")));
        check("prepared cancellation allowed",good.service.view().canCancel());good.service.flash();check("write then verify",good.calls.indexOf("download")<good.calls.indexOf("verify"));
        check("no fake reconnect success",good.service.view().state()==FirmwareUpdateService.State.WAIT_RECONNECT&&good.restores==0);good.service.checkReconnect();
        check("restore opt-in",good.restores==0&&good.service.view().state()==FirmwareUpdateService.State.READY_RESTORE);good.service.restore();check("full restore 54 items",good.restores==54&&!good.gate.active());
        Fixture missing=new Fixture();missing.failBackup=true;rejects("required read failure blocks erase",()->missing.prepared());check("no tool started after failed backup",!missing.calls.contains("download")&&!missing.gate.active());
        Fixture risk=new Fixture();rejects("unknown local requires explicit risk",()->risk.service.prepare(risk.target,null,false));check("risk failure before backup",risk.calls.isEmpty());
        Fixture swapped=new Fixture();swapped.prepared();swapped.wrongDownload=true;rejects("wrong download target",()->swapped.service.flash());check("wrong target zero writes",!swapped.calls.contains("download"));swapped.service.cancel();
        Fixture reconnected=new Fixture();reconnected.prepared();reconnected.service.flash();reconnected.wrongReconnect=true;rejects("normal container replacement blocks restore",()->reconnected.service.checkReconnect());check("replacement never restored",reconnected.restores==0&&reconnected.service.view().state()==FirmwareUpdateService.State.UNCERTAIN);
        Fixture beforeStart=new Fixture();beforeStart.prepared();beforeStart.notStarted=true;rejects("known prelaunch failure",()->beforeStart.service.flash());check("known not started can acknowledge",beforeStart.service.view().canRelease());beforeStart.service.acknowledgeFailure();check("known no process released",!beforeStart.gate.active());
        Fixture timeout=new Fixture();timeout.prepared();timeout.timedOut=true;timeout.service.flash();check("timeout alive preserves lock",timeout.gate.active()&&!timeout.service.view().canRelease());rejects("timeout cannot cancel",()->timeout.service.cancel());rejects("timeout cannot release",()->timeout.service.acknowledgeFailure());
        Fixture cancelled=new Fixture();CountDownLatch backupEntered=new CountDownLatch(1),continueBackup=new CountDownLatch(1);
        cancelled.duringBackup=()->{backupEntered.countDown();try{continueBackup.await();}catch(InterruptedException e){throw new RuntimeException(e);}};
        var preparation=CompletableFuture.runAsync(()->{try{cancelled.service.prepare(cancelled.target,null,true);}catch(Exception expected){}});backupEntered.await(2,TimeUnit.SECONDS);
        cancelled.service.requestCancelPreparation();continueBackup.countDown();preparation.get(2,TimeUnit.SECONDS);check("cancel preparation at safe read boundary",!cancelled.gate.active()&&cancelled.service.view().state()==FirmwareUpdateService.State.IDLE&&!cancelled.calls.contains("download"));
        check("legacy numeric never inferred",!new FirmwareCatalog().reliableLegacy("1.0")&&!new FirmwareCatalog().reliableLegacy(""));
        System.out.println("PASS firmware service state machine; fake device and process only");
    }
    public static class WireDevice extends DeviceMaintenanceChecks.FixtureBle {
        public volatile String catalog=FirmwareCatalog.CATALOG,container="container-A";
        public boolean downloadMode,badReadback;public int lightWrites,keyReads,polls;
        public int brightness=37;public final int[][] lights=new int[4][9];
        private final byte[][][] actions=new byte[4][4][];private final String[][] descriptions=new String[4][4];private final int[][] types=new int[4][4];
        private byte[] side={0,0,1,0};
        public WireDevice()throws Exception{this(new com.example.ahakey.service.BleManager.BleCallback(){public void onConnected(){}public void onDisconnected(){}public void onStatusReceived(com.example.ahakey.model.DeviceStatus s){}public void onError(String m){}});}
        public WireDevice(com.example.ahakey.service.BleManager.BleCallback callback)throws Exception{
            super(callback);for(int m=0;m<4;m++){for(int k=0;k<4;k++){actions[m][k]=new byte[]{(byte)(4+k)};types[m][k]=0x73;descriptions[m][k]="Key"+k;}for(int ai=0;ai<9;ai++)lights[m][ai]=(m+ai)%17;}
            usb.consumer=this::respond;getCachedStatus().setFirmwareCatalogKey(catalog);
        }
        public java.util.List<com.example.ahakey.service.UsbHidTransport.MaintenanceDevice> inventory(){return List.of(new com.example.ahakey.service.UsbHidTransport.MaintenanceDevice("fixture-usb",container,"port-1",downloadMode,List.of("fixture-hid")));}
        @Override protected java.util.List<com.example.ahakey.service.UsbHidTransport.MaintenanceDevice> observeMaintenanceDevices(){return inventory();}
        @Override public void queryStatus(){polls++;}
        private void respond(byte[] f){try{
            int op=f[2]&255;byte[] payload={0};
            switch(op){
                case 0x9F:payload=catalog.getBytes(java.nio.charset.StandardCharsets.US_ASCII);break;
                case 0x87:{keyReads++;int m=f[3]&255,k=f[4]&255;byte[] action=actions[m][k],desc=descriptions[m][k].getBytes();payload=new byte[6+action.length+desc.length];payload[1]=(byte)m;payload[2]=(byte)k;payload[3]=(byte)types[m][k];payload[4]=(byte)action.length;System.arraycopy(action,0,payload,5,action.length);payload[5+action.length]=(byte)desc.length;System.arraycopy(desc,0,payload,6+action.length,desc.length);break;}
                case 0x73:{int sub=f[3]&255,m=f[4]&255,k=f[5]&255;byte[] bytes=Arrays.copyOfRange(f,6,f.length-2);if(sub==0x75)descriptions[m][k]=new String(bytes);else{actions[m][k]=bytes;types[m][k]=sub;}break;}
                case 0x97:if(f.length==5){payload=new byte[3+side.length];payload[2]=2;System.arraycopy(side,0,payload,3,side.length);}else side=Arrays.copyOfRange(f,4,f.length-2);break;
                case 0x8E:lightWrites++;if(f[3]==0)brightness=f[4]&255;else lights[f[4]&255][f[5]&255]=f[6]&255;break;
                case 0x88:if(f[3]==0)payload=new byte[]{0,0,(byte)(badReadback?brightness+1:brightness)};else if(f[3]==1)payload=new byte[]{0,1,f[4],f[5],(byte)lights[f[4]&255][f[5]&255]};else payload=new byte[]{1};break;
            }
            reply(com.example.ahakey.protocol.AhaKeyProtocol.buildFrame(f[2],payload));
        }catch(Exception e){throw new RuntimeException(e);}}
        public void erased(){brightness=1;for(int m=0;m<4;m++){Arrays.fill(lights[m],0);for(int k=0;k<4;k++){actions[m][k]=new byte[0];types[m][k]=0;descriptions[m][k]="";}}side=new byte[]{0,0,0,0};}
    }
    public static class WireMaintenance {
        public final WireDevice ble;public final Path root;public final FirmwareUpdateService service;public int launches;public boolean failLaunch;
        public WireMaintenance(WireDevice ble,Runnable changed)throws Exception{
            this.ble=ble;root=Files.createTempDirectory("r6-wire-maintenance-");
            var io=FirmwareUpdateService.deviceIO(ble,ble::inventory,()->List.of("fixture-hid"));
            var tool=new FirmwareUpdateService.ToolIO(){
                public WchRuntimeLocator.Runtime locate(Path p){return new WchRuntimeLocator.Runtime("fixture",Path.of("unused"),Path.of("unused.exe"),Map.of());}
                public WchFlashAdapter.Result execute(WchRuntimeLocator.Runtime r,Path hex,String hash,Path dir,String operation,Runnable timeout)throws Exception{
                    launches++;if(failLaunch)throw new WchFlashAdapter.NotStartedException(new java.io.IOException("fixture failure"));
                    if(operation.equals("download"))ble.erased();return new WchFlashAdapter.Result(true,false,false,0,"fixture completed");
                }};
            service=new FirmwareUpdateService(ble.maintenance(),io,tool,root,changed,ble.firmwareCatalog());
        }
        public FirmwareCatalog.Target official(String key,Set<String> caps)throws Exception{
            Path file=Files.createTempFile(root,"fixture-",".hex");Files.writeString(file,":0100000001FE\n:00000001FF\n");
            var release=new com.example.ahakey.update.ReleaseManifest.FirmwareRelease(key,key,"x1-c582-hw1","p1",java.net.URI.create("https://ahakey.com/fixture.hex"),Files.size(file),VerifiedDownload.sha256(file),List.of(),caps,2);
            return ble.firmwareCatalog().official(release,file);
        }
        public void flashed(FirmwareCatalog.Target target)throws Exception{service.prepare(target,null,true);service.enterDownloadMode();ble.downloadMode=true;service.flash();ble.downloadMode=false;ble.catalog=target.catalog().isBlank()?FirmwareCatalog.CATALOG:target.catalog();service.checkReconnect();}
    }
    private static void catalogRegression()throws Exception{
        System.setProperty("user.home",Files.createTempDirectory("r6-wire-home-").toString());
        WireDevice ble=new WireDevice();WireMaintenance fixture=new WireMaintenance(ble,()->{});
        for(String suffix:List.of("r002","r003")){
            String key="x1-c582-hw1-p1-1.0.0-"+suffix;var target=fixture.official(key,FirmwareCatalog.ALL);int before=ble.lightWrites;
            fixture.flashed(target);check("actual identity published "+suffix,ble.firmwareIdentity().catalogKey().equals(key));
            check("no blanket OLED capability "+suffix,!ble.isDisplayAdmitted());
            var result=fixture.service.restore();check("actual full restore through BleManager "+suffix,result.complete()&&result.items().size()==54&&ble.lightWrites-before==37&&ble.brightness==37);
            fixture.service.prepare(target,null,true);check("second maintenance uses trusted observed source "+suffix,fixture.service.view().state()==FirmwareUpdateService.State.PREPARED);fixture.service.cancel();
            try(var lease=ble.openDisplayLease(true)){rejects("trusted lights do not grant OLED "+suffix,()->ble.exchangeDisplay(lease,com.example.ahakey.protocol.AhaKeyProtocol.displayRead(2,0)));}
        }
        WireDevice subset=new WireDevice();WireMaintenance small=new WireMaintenance(subset,()->{});var target=small.official("x1-c582-hw1-p1-1.0.0-r004",Set.of("keys","side"));small.flashed(target);
        check("subset full supported plan",small.service.restore().complete()&&subset.lightWrites==0);small.service.prepare(target,null,true);small.service.cancel();
        rejects("subset cannot restore lights",()->{try(var lease=subset.openDisplayLease(true)){};});
        var fullAfterSubset=small.official("x1-c582-hw1-p1-1.0.0-r008",FirmwareCatalog.ALL);int subsetLaunches=small.launches;
        rejects("source subset cannot promise missing backup",()->small.service.prepare(fullAfterSubset,null,true));check("source subset refusal before erase",small.launches==subsetLaunches);
        WireDevice changed=new WireDevice();WireMaintenance tamper=new WireMaintenance(changed,()->{});var t=tamper.official("x1-c582-hw1-p1-1.0.0-r005",FirmwareCatalog.ALL);tamper.service.prepare(t,null,true);
        Path plan;try(var paths=Files.walk(tamper.root)){plan=paths.filter(p->p.getFileName().toString().equals("restore-plan.json")).findFirst().orElseThrow();}Files.writeString(plan,"changed");rejects("frozen plan tamper before disconnect",tamper.service::enterDownloadMode);check("tampered plan no flash",tamper.launches==0);tamper.service.cancel();
        WireMaintenance targetTamper=new WireMaintenance(new WireDevice(),()->{});var selected=targetTamper.official("x1-c582-hw1-p1-1.0.0-r009",FirmwareCatalog.ALL);targetTamper.service.prepare(selected,null,true);
        Path frozen;try(var paths=Files.walk(targetTamper.root)){frozen=paths.filter(p->p.getFileName().toString().equals("firmware.hex")).findFirst().orElseThrow();}Files.writeString(frozen,"changed");rejects("frozen target change invalidates confirmation",targetTamper.service::enterDownloadMode);check("changed target no tool execution",targetTamper.launches==0);targetTamper.service.cancel();
        WireDevice generation=new WireDevice();WireMaintenance changedGeneration=new WireMaintenance(generation,()->{});var generationTarget=changedGeneration.official("x1-c582-hw1-p1-1.0.0-r010",FirmwareCatalog.ALL);changedGeneration.flashed(generationTarget);
        DeviceMaintenanceChecks.field(generation,"connectionGeneration",generation.connectionGeneration()+1);rejects("new generation cannot reuse frozen restore identity",changedGeneration.service::restore);check("generation change no restore writes",generation.lightWrites==0);changedGeneration.service.keepCleared();
        WireDevice mismatch=new WireDevice();WireMaintenance fail=new WireMaintenance(mismatch,()->{});var bad=fail.official("x1-c582-hw1-p1-1.0.0-r006",FirmwareCatalog.ALL);fail.flashed(bad);mismatch.badReadback=true;
        check("actual readback failure stays protected",!fail.service.restore().complete()&&mismatch.maintenance().active());fail.service.acknowledgeFailure();
        WireDevice unknown=new WireDevice();WireMaintenance local=new WireMaintenance(unknown,()->{});Path hex=Files.createTempFile(local.root,"unknown-",".hex");Files.writeString(hex,":0100000001FE\n:00000001FF\n");var localTarget=new FirmwareCatalog().local(hex);local.service.prepare(localTarget,null,true);local.service.enterDownloadMode();unknown.downloadMode=true;local.service.flash();unknown.downloadMode=false;unknown.catalog="x1-c582-hw1-p1-unknown";
        rejects("unknown local catalog never guessed",local.service::checkReconnect);check("unknown identity blocks light writes",unknown.lightWrites==0&&!unknown.isFirmwareCapabilityAdmitted("lights"));local.service.acknowledgeFailure();
        System.out.println("PASS R6 production DeviceIO + BleManager + DisplayLease dual catalog, second maintenance, subset and negatives; memory HID only");
    }
}
