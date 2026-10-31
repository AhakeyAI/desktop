package com.example.ahakey.service;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.connection.DeviceTarget;
import com.example.ahakey.service.connection.DeviceRecoveryRegistry;
import javafx.application.Platform;
import java.nio.file.Files;
import java.util.concurrent.*;
import static com.example.ahakey.service.Wd007BehaviorChecks.*;

public final class Wd007RecoveryControllerChecks {
    static <T>T fx(Callable<T> action)throws Exception{FutureTask<T> task=new FutureTask<>(action);Platform.runLater(task);return task.get(5,TimeUnit.SECONDS);}
    public static void main(String[] args)throws Exception{
        System.setProperty("user.home",Files.createTempDirectory("wd007-recovery-controller-").toString());Platform.startup(()->{});Platform.setImplicitExit(false);
        Wire[] wire=new Wire[1];StudioController controller=fx(()->new StudioController(cb->wire[0]=new Wire(cb),ble->new KimiAhaKeyBridge(ble,0),false));
        try{
            Wire w=wire[0];DeviceRecoveryRegistry registry=(DeviceRecoveryRegistry)field(w,"recoveryTargets");registry.require("USB:A");registry.observe("USB",java.util.Set.of());
            w.held=0x88;w.connectSelected(new DeviceTarget("USB","A","A"));await(()->w.heldMemory!=null,"recovery holds first metadata probe");
            check(w.frames.equals(java.util.List.of("A:159","A:136")),"only identity plus recovery metadata before controller initialization");
            try{w.readFirmwareCatalogKey();throw new AssertionError("ordinary reader bypassed recovery");}catch(java.io.IOException expected){}
            check(w.isDisplayAdmitted()&&w.isDisplayWriteUncertain()&&!w.refreshAutoApproval(),"ordinary reader cannot poison probe identity or approve");
            check(!fx(()->controller.getDeviceStatus().isConnected()),"onConnected initialization is held until recovery proof");
            w.held=-1;w.heldMemory.answer(w.heldRequest);
            await(()->!w.isDisplayWriteUncertain(),"metadata proof clears recovery");
            await(()->w.frames.contains("A:135"),"actual controller input initialization starts after proof");
            var observed=java.util.List.copyOf(w.frames);int firstInput=observed.indexOf("A:135");
            check(observed.subList(0,firstInput).stream().filter(s->s.equals("A:136")).count()==19,"all 19 metadata records precede ordinary key readback");
            check(!registry.contains("USB:A"),"successful proof persisted");
            System.out.println("PASS "+checks+" actual controller quarantine reconnect checks");
        }finally{fx(()->{controller.shutdown();return null;});Platform.exit();}
    }
}
