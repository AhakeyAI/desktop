package com.example.ahakey.service;

import com.example.ahakey.model.connection.DeviceTarget;
import com.example.ahakey.protocol.AhaKeyProtocol;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import static com.example.ahakey.service.Wd007BehaviorChecks.*;

/** Real admission, owned-release, observation and generated wrapper paths; memory devices only. */
public final class Wd007SafetyChecks {
    static void set(Object object,String name,Object value)throws Exception{var f=BleManager.class.getDeclaredField(name);f.setAccessible(true);f.set(object,value);}
    static Wire connected()throws Exception{
        System.setProperty("user.home",Files.createTempDirectory("wd007-safety-").toString());
        Wire w=new Wire();w.connectSelected(new DeviceTarget("USB","A","A"));await(w::isConnected,"fixture connected");return w;
    }
    static void queued(boolean timeout)throws Exception{
        Wire w=connected();var pool=Executors.newFixedThreadPool(2);try{
            w.held=0x73;
            var first=pool.submit(()->{try{w.sendCommand(AhaKeyProtocol.buildFrame((byte)0x73,new byte[]{0}));return false;}catch(IOException expected){return true;}});
            await(()->w.heldMemory!=null,"first physical request held");
            var thread=new java.util.concurrent.atomic.AtomicReference<Thread>();
            var second=pool.submit(()->{thread.set(Thread.currentThread());try{w.sendCommand(AhaKeyProtocol.queryDeviceStatus());return false;}catch(IOException expected){return true;}});
            await(()->thread.get()!=null&&thread.get().getState()==Thread.State.TIMED_WAITING,"second request entered ACK wait queue");
            if(!timeout)w.cancelDeviceOperation();
            check(first.get(18,TimeUnit.SECONDS)&&second.get(2,TimeUnit.SECONDS),"both pending operations fail after "+(timeout?"timeout":"cancel"));
            w.heldMemory.answer(w.heldRequest);
            check(w.frames.equals(List.of("A:115")),"queued request never reaches physical sender, even with late ACK");
            check(!w.refreshAutoApproval(),"quarantine cannot auto approve");
        }finally{w.shutdownTransport();pool.shutdownNow();}
    }
    static void releaseAndObservation()throws Exception{
        Wire w=connected();try{
            String attachment=w.draftIdentity();w.observeUsbCandidates(Set.of("A"));
            // Emulate a failed release being safely retired by the actual managed client (null means never had a child).
            set(w,"bridgeSession","dead-session");set(w,"activeTarget",new DeviceTarget("BLE","old","A"));
            w.disconnect();w.candidates=List.of("A","B");w.connectSelected(new DeviceTarget("USB","B","B"));
            await(()->w.isConnected()&&w.targetIdentity().equals("USB:B"),"dead owned bridge does not permanently block USB B");
            w.observeUsbCandidates(Set.of("A","B"));
            w.connectSelected(new DeviceTarget("USB","A","A"));await(()->w.isConnected()&&w.targetIdentity().equals("USB:A"),"manual return same attachment");
            check(!w.draftIdentity().equals(attachment),"new USB configuration session never reuses identity based only on same path");
            w.observeUsbCandidates(Set.of("B"));check(!w.isConnected(),"physical remove disconnects without fallback");
            w.observeUsbCandidates(Set.of("A","B"));check(!w.isConnected(),"new insertion while disconnected never opens");
            w.connectSelected(new DeviceTarget("USB","A","replacement"));await(w::isConnected,"replacement explicitly selected");
            check(!w.draftIdentity().equals(attachment),"no-serial same-path replacement has distinct draft identity");
            check(UsbHidTransport.configurationPaths(List.of("hid#vid_413c&pid_2107&mi_01#a","hid#vid_413c&pid_2107&mi_00#a","hid#vid_other&pid_1")).equals(List.of("hid#vid_413c&pid_2107&mi_01#a")),"only AhaKey configuration interface is a candidate");
            var registry=(com.example.ahakey.service.connection.DeviceRecoveryRegistry)field(w,"recoveryTargets");registry.require("USB:A");
            w.enumerationFails=true;try{w.pollUsbCandidates();throw new AssertionError("failed enumeration accepted");}catch(IllegalStateException expected){}
            check(!registry.absenceObserved("USB:A"),"enumeration failure cannot establish absence");
        }finally{w.shutdownTransport();}
    }
    static void hooks()throws Exception{
        Wire w=connected();HookDispatchServer server=new HookDispatchServer(w,0);try{
            server.start();var f=HookDispatchServer.class.getDeclaredField("serverSocket");f.setAccessible(true);int port=((java.net.ServerSocket)f.get(server)).getLocalPort();
            new HookInstaller(port,s->{}).generateAllScripts();
            Path home=Path.of(System.getProperty("user.home"));
            for(String state:List.of("auto","custom","unknown","written-awaiting-readback")){
                w.confirmSavedBindings(side(true),w.connectionGeneration());w.position=0;
                if(state.equals("custom"))w.position=1;
                if(state.equals("unknown"))w.getCachedStatus().clearSavedBindings();
                if(state.equals("written-awaiting-readback"))w.writeSideSwitchConfig(side(false));
                for(String event:List.of("PermissionRequest","CodexPreToolUse","CodexPermissionRequest")){
                    String name=event.startsWith("Codex")?"codex":"claude";
                    Path log=home.resolve(state+"-"+event+".json");
                    var builder=new ProcessBuilder("powershell.exe","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",home.resolve(".ahakey/hooks/ahakey-"+name+".ps1").toString(),event);
                    builder.environment().put("USERPROFILE",home.toString());builder.redirectErrorStream(true).redirectOutput(log.toFile());
                    Process process=builder.start();try{process.getOutputStream().write("{}".getBytes());process.getOutputStream().close();check(process.waitFor(8,TimeUnit.SECONDS),"generated wrapper terminates");check(process.exitValue()==0,"wrapper exit success");}finally{if(process.isAlive())process.destroyForcibly();}
                    String result=Files.readString(log).trim();
                    check(state.equals("auto")?result.contains("\"behavior\":\"allow\""):result.equals("{}"),"actual generated "+event+" "+state+" => native policy");
                }
                if(state.equals("written-awaiting-readback"))check(!w.getCachedStatus().isAutoApproval(),"write ACK alone cannot restore approval facts");
            }
        }finally{server.stop();w.shutdownTransport();}
    }
    public static void main(String[] args)throws Exception{queued(false);queued(true);releaseAndObservation();hooks();System.out.println("PASS "+checks+" WD007 safety checks; wrappers executed only in temporary USERPROFILE");}
}
