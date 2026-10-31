package com.example.ahakey.service;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.*;
import com.example.ahakey.model.connection.DeviceTarget;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.service.connection.DeviceRecoveryRegistry;
import javafx.application.Platform;
import java.nio.file.Files;
import java.util.*;
import java.util.concurrent.*;
import static com.example.ahakey.service.Wd007BehaviorChecks.*;
import static com.example.ahakey.service.Wd007RecoveryControllerChecks.fx;

/** Native reader's terminal seam through actual coordinator/controller; no device or enumeration calls. */
public final class Wd007UsbTerminationChecks {
    static final class ReaderProbe extends UsbHidTransport {void failed(){readerTerminatedUnexpectedly();}}
    static Runnable callback(UsbHidTransport transport)throws Exception{
        var field=UsbHidTransport.class.getDeclaredField("disconnectHandler");field.setAccessible(true);return (Runnable)field.get(transport);
    }
    static void connected(StudioController controller,Wire w)throws Exception{
        w.frames.clear();w.connectSelected(new DeviceTarget("USB","A","same path, no serial"));
        await(w::isConnected,"manual configuration connect");
        readback(controller,w);
    }
    static void readback(StudioController controller,Wire w)throws Exception{
        long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);
        while(System.nanoTime()<end){
            if(w.frames.stream().filter(s->s.equals("A:135")).count()>=16&&fx(()->!controller.getStudioState().inputReadbackInProgressProperty().get()&&!controller.getStudioState().k1Routes().busy.get()))return;
            Thread.sleep(10);
        }
        throw new AssertionError("controller did not complete readback");
    }
    static void atomicTermination()throws Exception{
        var workers=Executors.newFixedThreadPool(2);
        try{for(int i=0;i<40;i++){
            ReaderProbe probe=new ReaderProbe();var calls=new java.util.concurrent.atomic.AtomicInteger();probe.onUnexpectedDisconnect(calls::incrementAndGet);var start=new CountDownLatch(1);
            var close=workers.submit(()->{start.await();probe.cancelPendingIo();return null;});
            var fail=workers.submit(()->{start.await();probe.failed();return null;});start.countDown();close.get(2,TimeUnit.SECONDS);fail.get(2,TimeUnit.SECONDS);
            check(calls.get()==(probe.terminatedUnexpectedly()?1:0),"atomic cause and notification agree under simultaneous close/failure "+i);
            boolean cause=probe.terminatedUnexpectedly();probe.cancelPendingIo();probe.failed();
            check(probe.terminatedUnexpectedly()==cause,"terminal cause cannot be overwritten "+i);
        }}finally{workers.shutdownNow();}
    }
    public static void main(String[] args)throws Exception{
        var calls=new java.util.concurrent.atomic.AtomicInteger();ReaderProbe probe=new ReaderProbe();probe.onUnexpectedDisconnect(calls::incrementAndGet);probe.failed();probe.failed();
        check(calls.get()==1,"unexpected terminal step reports once");
        ReaderProbe closing=new ReaderProbe();closing.onUnexpectedDisconnect(calls::incrementAndGet);closing.close();closing.failed();
        check(calls.get()==1,"intentional cancellation does not report unexpected termination");
        atomicTermination();
        System.setProperty("user.home",Files.createTempDirectory("wd007-usb-termination-").toString());Platform.startup(()->{});Platform.setImplicitExit(false);
        Wire[] wires=new Wire[1];StudioController controller=fx(()->new StudioController(cb->wires[0]=new Wire(cb),ble->new KimiAhaKeyBridge(ble,0),false));
        var pool=Executors.newSingleThreadExecutor();
        try{
            Wire w=wires[0];connected(controller,w);String a=w.draftIdentity();
            fx(()->{controller.getStudioState().getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).setHidCode(31);controller.getStudioState().markDirty(StudioPart.KEY2);return null;});
            w.pollUsbCandidates();
            check(a.equals(w.draftIdentity())&&fx(()->controller.getStudioState().getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).getHidCode()==31),"current USB session retains dirty draft during unchanged observation");
            var drafts=StudioState.class.getDeclaredField("deviceDrafts");drafts.setAccessible(true);
            w.disconnect();check(!w.isConnected(),"explicit disconnect stays disconnected");
            w.readbackHid=7;connected(controller,w);String manualReplacement=w.draftIdentity();
            check(!a.equals(manualReplacement)&&fx(()->controller.getStudioState().getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).getHidCode()==7&&!controller.getStudioState().isDirty(StudioPart.KEY2)),"same-path B after intentional disconnect reads B actual configuration without A draft");
            check(w.candidates.equals(List.of("A"))&&fx(()->((Map<?,?>)drafts.get(controller.getStudioState())).containsKey(a)),"no observed absence or serial; A draft remains separately preserved");
            fx(()->{controller.getStudioState().getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).setHidCode(32);controller.getStudioState().markDirty(StudioPart.KEY2);return null;});
            w.disconnect();w.readbackHid=6;connected(controller,w);
            check(!manualReplacement.equals(w.draftIdentity())&&fx(()->controller.getStudioState().getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).getHidCode()==6&&!controller.getStudioState().isDirty(StudioPart.KEY2)&&((Map<?,?>)drafts.get(controller.getStudioState())).containsKey(manualReplacement)),"each explicit USB reconnect reads actual values and preserves old draft without automatic reuse");
            check(!((DeviceRecoveryRegistry)field(w,"recoveryTargets")).absenceObserved("USB:A"),"intentional reconnect does not manufacture physical absence");
            Memory old=w.opened.get("A");Runnable late=callback(old);old.failReader();
            check(!w.isConnected()&&w.getCachedStatus().getSavedBindings()==null,"reader terminal synchronously revokes current connection and approval facts");
            fx(()->null);check(!fx(()->controller.getDeviceStatus().isConnected()),"actual controller shows disconnected after reader failure");
            check(w.candidates.equals(List.of("A")),"enumeration remained identical throughout fast replacement");
            w.pollUsbCandidates();check(!w.isConnected(),"same-path observation never auto reconnects failed reader");
            w.readbackHid=7;connected(controller,w);String b=w.draftIdentity();long generation=w.connectionGeneration();
            check(!a.equals(b)&&fx(()->controller.getStudioState().getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).getHidCode()==7&&!controller.getStudioState().isDirty(StudioPart.KEY2)),"same-path replacement B displays actual readback, not A dirty draft");
            check(fx(()->((Map<?,?>)drafts.get(controller.getStudioState())).containsKey(a)),"A draft record remains preserved");
            late.run();check(w.isConnected()&&w.connectionGeneration()==generation&&w.draftIdentity().equals(b),"late old-reader callback cannot disconnect or retire B");
            fx(()->{controller.getStudioState().getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).setHidCode(44);controller.getStudioState().markDirty(StudioPart.KEY2);return null;});
            Memory queuedReader=w.opened.get("A");
            var commandLock=(java.util.concurrent.locks.ReentrantLock)field(w,"commandLock");
            Thread reader=new Thread(queuedReader::failReader,"fixture-reader-terminal");
            String replacementIdentity;long replacementGeneration;
            commandLock.lock();try{
                reader.start();
                await(()->queuedReader.terminatedUnexpectedly()&&commandLock.hasQueuedThread(reader),"reader cause latched while callback waits on coordinator lock");
                w.frames.clear();w.readbackHid=8;
                long intent=((java.util.concurrent.atomic.AtomicLong)field(w,"connectionIntent")).incrementAndGet();
                var open=BleManager.class.getDeclaredMethod("openSelected",DeviceTarget.class,long.class);open.setAccessible(true);
                open.invoke(w,new DeviceTarget("USB","A","same path race replacement"),intent);
                replacementIdentity=w.draftIdentity();replacementGeneration=w.connectionGeneration();
                check(!replacementIdentity.equals(b)&&w.isConnected(),"replacement consumes old unexpected cause before callback can run");
            }finally{commandLock.unlock();}
            reader.join(2000);check(!reader.isAlive(),"late reader callback completed after replacement");readback(controller,w);
            check(w.isConnected()&&w.connectionGeneration()==replacementGeneration&&w.draftIdentity().equals(replacementIdentity),"late queued callback cannot alter new generation or attachment");
            check(fx(()->controller.getStudioState().getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).getHidCode()==8&&!controller.getStudioState().isDirty(StudioPart.KEY2)&&((Map<?,?>)drafts.get(controller.getStudioState())).containsKey(b)),"actual controller reads replacement value and retains prior dirty draft separately");
            check(!((DeviceRecoveryRegistry)field(w,"recoveryTargets")).absenceObserved("USB:A"),"queued I/O failure is not physical absence evidence");
            w.held=0x73;var pending=pool.submit(()->{try{w.sendCommand(AhaKeyProtocol.buildFrame((byte)0x73,new byte[]{0}));return false;}catch(java.io.IOException expected){return true;}});
            await(()->w.heldMemory!=null,"pending B write held for terminal failure");w.opened.get("A").failReader();
            check(pending.get(2,TimeUnit.SECONDS),"reader failure aborts current outstanding command");
            DeviceRecoveryRegistry registry=(DeviceRecoveryRegistry)field(w,"recoveryTargets");
            check(registry.contains("USB:A")&&!registry.absenceObserved("USB:A"),"I/O failure quarantines uncertain write without claiming physical absence");
            w.pollUsbCandidates();check(!registry.absenceObserved("USB:A")&&!w.isConnected(),"unchanged complete enumeration does not clear quarantine or reconnect");
            w.held=-1;w.connectSelected(new DeviceTarget("USB","A","same path"));await(w::isConnected,"manual reconnect permits recovery presentation");
            check(w.isDisplayWriteUncertain()&&!w.refreshAutoApproval(),"reader failure alone cannot re-admit writes or AUTO");
            System.out.println("PASS "+checks+" IR05 reader/coordinator/controller checks; stable enumeration, no real HID");
        }finally{pool.shutdownNow();fx(()->{controller.shutdown();return null;});Platform.exit();}
    }
}
