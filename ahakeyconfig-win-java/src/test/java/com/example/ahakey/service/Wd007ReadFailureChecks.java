package com.example.ahakey.service;

import com.example.ahakey.protocol.*;
import com.example.ahakey.model.connection.DeviceTarget;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import static com.example.ahakey.service.Wd007BehaviorChecks.*;

/** Missing-tail replay through the actual scheduler, reassembler and recovery registry. */
public final class Wd007ReadFailureChecks {
    public static void main(String[] args) throws Exception {
        System.setProperty("user.home",Files.createTempDirectory("wd007-read-failure-").toString());
        Wire wire=new Wire();var pool=Executors.newSingleThreadExecutor();
        try {
            wire.connect();await(wire::isConnected,"memory connected");wire.held=0x9e;
            long generation=wire.connectionGeneration();
            byte[] request=K1RouteProtocol.request(0x10,K1RouteProtocol.fields(7).putInt(123).put((byte)0).put((byte)0).put((byte)42).array());
            long at=System.nanoTime();
            var result=pool.submit(()->{try{wire.k1RouteTransaction(generation,()->wire.exchangeK1Route(request,generation));return false;}catch(Exception expected){System.out.println("READ_FAILURE="+expected);return true;}});
            await(()->wire.heldRequest!=null,"read sent");Memory old=wire.heldMemory;
            byte[] response=new byte[62];response[0]=(byte)0xaa;response[1]=(byte)0xbb;response[2]=(byte)0x9e;response[4]=1;response[5]=0x10;response[6]=123;response[12]=102;response[60]=(byte)0xcc;response[61]=(byte)0xdd;
            for(int offset=0;offset<60;offset+=20)old.receive.accept(Arrays.copyOfRange(response,offset,offset+20));
            check(result.get(18,TimeUnit.SECONDS),"incomplete response must fail");
            System.out.println("TIMEOUT_MS="+TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-at)+" connected="+wire.isConnected()+" writeUncertain="+wire.isDisplayWriteUncertain());
            var registry=new com.example.ahakey.service.connection.DeviceRecoveryRegistry(Path.of(System.getProperty("user.home"),".ahakey","device-recovery.json"));
            check(!registry.contains("USB:A"),"read-only timeout must not persist unknown-write quarantine");
            check(!wire.isConnected()&&wire.connectionGeneration()!=generation,"failed read retires session before accepting more commands");
            int sent=wire.frames.size();try{wire.sendCommand(AhaKeyProtocol.queryFirmwareCatalogKey());throw new AssertionError("failed session reused");}catch(java.io.IOException expected){}
            check(wire.frames.size()==sent,"no implicit retry or new command in failed session");
            wire.held=-1;wire.connectSelected(new DeviceTarget("USB","A","A"));await(wire::isConnected,"explicit reconnect without power cycle");
            long next=wire.connectionGeneration();old.receive.accept(Arrays.copyOfRange(response,60,62));old.answer(AhaKeyProtocol.queryDeviceStatus());
            check(wire.connectionGeneration()==next&&wire.getCachedStatus().getSwitchState()==-1,"late old tail/status cannot enter new session");
            check(wire.readFirmwareCatalogKey().equals("x1-c582-hw1-p1-1.0.0-r001"),"fresh read succeeds without durable quarantine");
            System.out.println("PASS missing tail retires read session, isolates stale callbacks and permits explicit reconnect");
        } finally {pool.shutdownNow();wire.shutdownTransport();}
    }
}
