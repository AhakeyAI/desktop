package com.example.ahakey.firmware;

import com.example.ahakey.protocol.*;
import com.example.ahakey.service.DeviceSyncService;
import java.nio.file.*;
import java.util.*;
import static com.example.ahakey.update.UpdateCenterChecks.*;

public final class BackupRestoreChecks {
    public static DeviceBackup backup(String operation,DeviceMaintenanceCoordinator.Identity source,String hash,Set<String> capabilities){
        List<DeviceBackup.Key> keys=new ArrayList<>();List<DeviceBackup.Light> lights=new ArrayList<>();
        if(capabilities.contains("keys"))for(int m=0;m<4;m++)for(int k=0;k<4;k++)keys.add(new DeviceBackup.Key(m,k,k==0?0:0x73,k==0?"":"04","Key"+k));
        if(capabilities.contains("lights"))for(int m=0;m<4;m++)for(int a=0;a<9;a++)lights.add(new DeviceBackup.Light(m,a,(m+a)%17));
        return new DeviceBackup(1,operation,source,hash,capabilities,keys,capabilities.contains("side")?new DeviceBackup.Side(0,"",0,""):null,capabilities.contains("lights")?35:null,lights,
                Map.of("studio-draft.json",new DeviceBackup.PcFile(true,Base64.getEncoder().encodeToString("{\"unappliedDraft\":true}".getBytes())),"ai-runtime.json",new DeviceBackup.PcFile(false,"")));
    }
    public static void main(String[] args)throws Exception{
        var source=DeviceMaintenanceChecks.identity();var b=backup(UUID.randomUUID().toString(),source,DeviceMaintenanceChecks.HASH,FirmwareCatalog.ALL);b.validate();
        Path dir=Files.createTempDirectory("backup-checks-");var store=new DeviceBackupStore(dir);var saved=store.save(b);var loaded=store.load(saved);check("4 modes 16 keys and 36 lights",loaded.keys().size()==16&&loaded.lights().size()==36);
        check("draft independent from device",new String(Base64.getDecoder().decode(loaded.pcFiles().get("studio-draft.json").base64())).contains("unappliedDraft"));
        Files.writeString(saved.file(),"corrupt");rejects("corrupt saved backup",()->store.load(saved));
        Path invalid=dir.resolve("pc.json");Files.writeString(invalid,"not json");rejects("corrupt PC not defaults",()->DeviceBackupStore.snapshot(invalid));check("missing PC distinct",!DeviceBackupStore.snapshot(dir.resolve("missing")).present());
        List<String> calls=new ArrayList<>();var fake=new DeviceRestoreService.Device(){public void key(DeviceBackup.Key k){calls.add("key");}public void side(DeviceBackup.Side s){calls.add("side");}public void brightness(int v){calls.add("brightness");}public void light(DeviceBackup.Light l){calls.add("light");}};
        var report=new DeviceRestoreService().restore(b,Set.of("keys"),fake);check("target capabilities crop restore",calls.size()==16&&report.items().stream().filter(i->i.status().equals("SKIPPED")).count()==38);
        calls.clear();var fail=new DeviceRestoreService.Device(){public void key(DeviceBackup.Key k)throws Exception{calls.add("key");if(k.index()==1)throw new java.io.IOException("readback mismatch");}public void side(DeviceBackup.Side s){throw new AssertionError();}public void brightness(int v){throw new AssertionError();}public void light(DeviceBackup.Light l){throw new AssertionError();}};
        report=new DeviceRestoreService().restore(b,FirmwareCatalog.ALL,fail);check("partial failure no retry or later write",!report.complete()&&calls.size()==2&&report.items().get(0).status().equals("CONFIRMED"));
        var ble=new DeviceMaintenanceChecks.FixtureBle();var op=ble.beginMaintenance(source,DeviceMaintenanceChecks.HASH,"test",false);ble.maintenance().stage(op,DeviceMaintenanceCoordinator.Stage.BACKUP,DeviceMaintenanceCoordinator.Stage.RESTORE);
        List<Integer> opcodes=new ArrayList<>();var empty=b.keys().get(0);
        ble.usb.consumer=frame->{try{opcodes.add(frame[2]&255);byte[] payload=frame[2]==(byte)0x87?new byte[]{0,0,0,0,0,4,'K','e','y','0'}:new byte[]{0};ble.reply(AhaKeyProtocol.buildFrame(frame[2],payload));}catch(Exception e){throw new RuntimeException(e);}};
        ble.maintenance().within(op,()->{DeviceRestoreService.ble(ble).key(empty);return null;});check("empty action real encode ACK save readback",opcodes.equals(List.of(0x73,0x73,0x04,0x87)));
        check("ordinary restore whitelist excludes draft lights",DeviceSyncService.restoreKeyCommands(empty).stream().noneMatch(c->c[2]==(byte)0x84||c[2]==(byte)0x85));
        var incomplete=new DeviceBackup(1,b.operationId(),source,b.targetHash(),b.capabilities(),b.keys().subList(0,15),b.side(),b.brightness(),b.lights(),b.pcFiles());rejects("missing mode key blocks erase",incomplete::validate);
        var zero=new DeviceBackup(1,b.operationId(),source,b.targetHash(),b.capabilities(),b.keys(),b.side(),0,b.lights(),b.pcFiles());rejects("brightness zero invalid",zero::validate);
        var invalidPc=new HashMap<>(b.pcFiles());invalidPc.put("studio-draft.json",new DeviceBackup.PcFile(true,""));
        var emptyPc=new DeviceBackup(1,b.operationId(),source,b.targetHash(),b.capabilities(),b.keys(),b.side(),b.brightness(),b.lights(),invalidPc);rejects("empty present PC snapshot blocks erase",emptyPc::validate);
        System.out.println("PASS backup and actual restore transport checks; no device");
    }
}
