package com.example.ahakey.service;

import com.example.ahakey.model.connection.DeviceTarget;
import com.example.ahakey.service.connection.ManagedBridgeClient;
import com.example.ahakey.service.connection.ManagedBridgeClientChecks.StubbornProcess;
import java.net.*;
import java.nio.file.Files;
import java.util.List;
import static com.example.ahakey.service.Wd007BehaviorChecks.*;

/** Simulated process liveness only; actual private client/release barrier and USB selection. */
public final class Wd007BridgeRetirementChecks {
    static void owner(ManagedBridgeClient client,Process process)throws Exception{var f=ManagedBridgeClient.class.getDeclaredField("ownedProcess");f.setAccessible(true);f.set(client,process);}
    static void attach(ManagedBridgeClient client,Socket socket)throws Exception{var m=ManagedBridgeClient.class.getDeclaredMethod("attach",Socket.class);m.setAccessible(true);m.invoke(client,socket);}
    public static void main(String[] args)throws Exception{
        System.setProperty("user.home",Files.createTempDirectory("wd007-release-retry-").toString());Wire w=new Wire();StubbornProcess old=new StubbornProcess(),replacement=new StubbornProcess();
        try(var listener=new ServerSocket(0,2,InetAddress.getLoopbackAddress());var oldSocket=new Socket("127.0.0.1",listener.getLocalPort());var oldPeer=listener.accept();var newSocket=new Socket("127.0.0.1",listener.getLocalPort());var newPeer=listener.accept()){
            ManagedBridgeClient client=(ManagedBridgeClient)field(w,"managedBridge");owner(client,old);attach(client,oldSocket);Object oldIdentity=client.ownerIdentity();oldSocket.close();
            Wd007SafetyChecks.set(w,"activeTarget",new DeviceTarget("BLE","old-A","A"));Wd007SafetyChecks.set(w,"bridgeSession","old-session");w.disconnect();
            await(()->{try{return ((java.util.concurrent.CompletableFuture<?>)field(w,"bridgeRelease")).isCompletedExceptionally();}catch(Exception e){throw new RuntimeException(e);}},"owned process remains alive after bounded release");
            w.candidates=List.of("B");w.connectSelected(new DeviceTarget("USB","B","B"));await(()->!w.isScanning(),"first explicit retry finishes");
            check(!w.isConnected()&&!client.ownerRetired(oldIdentity),"live old owner still blocks new connection");
            owner(client,replacement);attach(client,newSocket);Object newIdentity=client.ownerIdentity();
            old.alive=false;
            w.connectSelected(new DeviceTarget("USB","B","B"));await(w::isConnected,"later explicit connect retires historical failed barrier after actual exit");
            check(w.targetIdentity().equals("USB:B")&&client.ownerRetired(oldIdentity),"B connected without restarting Studio");
            check(!newSocket.isClosed()&&!client.ownerRetired(newIdentity)&&replacement.destroys==0,"retiring old barrier leaves replacement process and connection untouched");
            check(!((java.util.concurrent.CompletableFuture<?>)field(w,"bridgeRelease")).isCompletedExceptionally(),"failed release barrier replaced after positive retirement proof");
            System.out.println("PASS "+checks+" late process exit/replacement checks; Process substitutes and loopback only");
        }finally{old.alive=false;replacement.alive=false;w.shutdownTransport();}
    }
}
