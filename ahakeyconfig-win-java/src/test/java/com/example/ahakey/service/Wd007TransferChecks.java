package com.example.ahakey.service;

import com.example.ahakey.firmware.*;
import com.example.ahakey.model.*;
import com.example.ahakey.model.connection.DeviceTarget;
import com.example.ahakey.protocol.*;
import java.io.IOException;
import java.nio.*;
import java.nio.file.Files;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import static com.example.ahakey.service.Wd007BehaviorChecks.*;

/** Real BLE scheduler/notification path; only native transmission is replaced by an in-memory peripheral. */
public final class Wd007TransferChecks {
    static final class Peripheral extends BleManager {
        final List<byte[]> sent=new CopyOnWriteArrayList<>();
        final List<Integer> slices=new CopyOnWriteArrayList<>();
        final K1Route route=K1RouteProtocolChecks.Wire.consumer(0xe9);
        final CountDownLatch held=new CountDownLatch(1),release=new CountDownLatch(1);
        volatile String fault="";int delayMs,chunks,commits,acknowledged;byte[] uploaded;long crc;
        Peripheral(boolean usb)throws Exception {
            super(CALLBACK);
            DeviceMaintenanceChecks.field(this,"isConnected",true);getCachedStatus().setConnected(true);
            DeviceMaintenanceChecks.field(this,"activeTarget",new DeviceTarget(usb?"USB":"BLE","memory","memory"));
            DeviceMaintenanceChecks.field(this,"firmwareIdentity",new FirmwareIdentity(0,1,DeviceStatus.IdentityState.SUPPORTED,FirmwareCatalog.CATALOG));
            if(usb)DeviceMaintenanceChecks.field(this,"usbTransport",new DeviceMaintenanceChecks.MemoryUsb());
        }
        @Override public void queryStatus(){}
        void notify(long generation,byte[] frame)throws Exception {
            var receive=BleManager.class.getDeclaredMethod("onSessionNotify",long.class,byte[].class);receive.setAccessible(true);
            for(int offset=0;offset<frame.length;offset+=20)receive.invoke(this,generation,Arrays.copyOfRange(frame,offset,Math.min(frame.length,offset+20)));
        }
        @Override protected void transmitFirmware(UsbHidTransport usb,String session,String target,long generation,byte[] frame,boolean data)throws Exception {
            check(!data,"resource upload uses framed acknowledged chunks");sent.add(frame.clone());int opcode=frame[2]&255;
            var fields=ByteBuffer.wrap(frame).order(ByteOrder.LITTLE_ENDIAN);
            if(opcode==0x9e) {
                int nonce=fields.getInt(5),mode=frame[9]&255,offset=frame[10]&255,count=frame[11]&255;
                slices.add(count);byte[] bytes=route.bytes();
                var reply=K1RouteProtocol.fields(12+count).putInt(nonce+(fault.equals("nonce")?1:0))
                        .put((byte)(mode+(fault.equals("mode")?1:0))).put((byte)(offset+(fault.equals("offset")?1:0)))
                        .putShort((short)102).putInt((int)K1RouteProtocol.crc(bytes)+(fault.equals("crc")?1:0)).put(bytes,offset,count).array();
                notify(generation,K1RouteProtocolChecks.response(0x10,0,reply));return;
            }
            if(opcode==0x8a){uploaded=new byte[fields.getInt(4)];crc=Integer.toUnsignedLong(fields.getInt(10));}
            else if(opcode==0x8b) {
                chunks++;int offset=fields.getInt(4),count=frame[8]&255;
                check(offset==acknowledged&&count>0&&count<=48,"contiguous stop-and-wait chunk offsets");
                System.arraycopy(frame,9,uploaded,offset,count);
                if(chunks==2&&!fault.isEmpty()) {
                    held.countDown();
                    if(fault.equals("native-hang")) {
                        // Simulates a driver ignoring interruption; test cleanup explicitly releases it.
                        while(release.getCount()>0)try{release.await();}catch(InterruptedException ignored){}
                    } else return; // Transport wrote but notification was lost.
                }
                if(delayMs>0)Thread.sleep(delayMs);
                acknowledged+=count;
            } else if(opcode==0x8c){commits++;check(acknowledged==uploaded.length&&K1RouteProtocol.crc(uploaded)==crc,"commit only after exact bytes and CRC");}
            else throw new AssertionError("Unexpected opcode "+opcode);
            notify(generation,AhaKeyProtocol.buildFrame(frame[2],new byte[]{0}));
        }
    }
    static void routeReads()throws Exception {
        for(boolean usb:new boolean[]{false,true}) {
            Peripheral p=new Peripheral(usb);
            try(K1RouteService service=new K1RouteService(new StudioState(),p)) {
                K1Route read=p.k1RouteTransaction(0,()->service.read(2,0));
                check(read.equals(p.route),"full route reconstructed with CRC");
                check(p.slices.equals(usb?List.of(42,42,18):List.of(20,20,20,20,20,2)),"transport slice sizes "+p.slices);
                for(String fault:List.of("nonce","mode","offset","crc")){
                    p.fault=fault;
                    try{p.k1RouteTransaction(0,()->service.read(2,0));throw new AssertionError("accepted "+fault);}catch(IOException expected){}
                }
            }finally{p.shutdownTransport();}
        }
    }
    static OledResourceState.Asset asset(int frames) {
        byte[] bytes=new byte[frames*AhaKeyProtocol.OLED_FRAME_SLOT_SIZE];
        for(int f=0;f<frames;f++)for(int i=0;i<AhaKeyProtocol.OLED_FRAME_BYTES;i++)bytes[f*AhaKeyProtocol.OLED_FRAME_SLOT_SIZE+i]=(byte)(i*31+f);
        return OledResourceState.Asset.fromBytes(bytes);
    }
    static void completeLongUpload()throws Exception {
        Peripheral p=new Peripheral(false);p.delayMs=3;var asset=asset(12);AtomicBoolean recorded=new AtomicBoolean();AtomicInteger progress=new AtomicInteger();long at=System.nanoTime();
        try {
            OledUploadService.uploadResource(p,0,1,asset,percent->{},()->recorded.set(true),detail->{
                check(detail.acknowledgedBytes()>progress.getAndSet(detail.acknowledgedBytes()),"progress strictly follows acknowledged payload");
                check(detail.acknowledgedBytes()==p.acknowledged,"UI progress never exceeds ACKed bytes");
            });
            long elapsed=TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-at);
            check(recorded.get()&&p.commits==1&&Arrays.equals(asset.bytes(),p.uploaded),"all actual image bytes reach one confirmed commit");
            check(elapsed>15000&&!p.isDisplayWriteUncertain(),"healthy progressing upload may exceed one response timeout");
            System.out.println("LONG_UPLOAD bytes="+asset.bytes().length+" chunks="+p.chunks+" elapsedMs="+elapsed+" injectedAckDelayMs=3");
        }finally{p.release.countDown();p.shutdownTransport();}
    }
    static void interruptedUpload(String action)throws Exception {
        Peripheral p=new Peripheral(false);p.fault=action.equals("native-hang")?action:"missing-ack";
        var pool=Executors.newSingleThreadExecutor();
        try {
            var result=pool.submit(()->{try{OledUploadService.uploadResource(p,0,1,asset(1),x->{},()->{});return false;}catch(OledUploadService.UploadFailure expected){return !expected.commitUncertain();}});
            check(p.held.await(3,TimeUnit.SECONDS),"second data chunk entered "+action);long at=System.nanoTime();
            if(action.equals("cancel"))p.cancelDeviceOperation(0);
            if(action.equals("disconnect"))p.disconnect();
            check(result.get(action.equals("missing-ack")?18:4,TimeUnit.SECONDS),"unfinished upload returns without commit "+action);
            long elapsed=TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-at);
            if(action.equals("cancel")||action.equals("disconnect"))check(elapsed<1500,"cancel/revoke bound "+action);
            if(action.equals("native-hang"))check(elapsed<3500,"native write deadline");
            check(p.chunks==2&&p.commits==0,"no continuation/retry/commit after "+action);
            var registry=new com.example.ahakey.service.connection.DeviceRecoveryRegistry(java.nio.file.Path.of(System.getProperty("user.home"),".ahakey","device-recovery.json"));
            check(registry.contains("BLE:memory"),"unknown upload remains durably quarantined "+action);
            p.release.countDown();p.notify(0,AhaKeyProtocol.buildFrame((byte)0x8b,new byte[]{0}));
            check(p.sent.size()==3,"late ACK cannot restart upload");
            System.out.println("UPLOAD_FAILURE action="+action+" elapsedMs="+elapsed+" chunks="+p.chunks+" commits="+p.commits);
        }finally{p.release.countDown();pool.shutdownNow();p.shutdownTransport();}
    }
    public static void main(String[] args)throws Exception {
        System.setProperty("user.home",Files.createTempDirectory("wd007-transfer-").toString());
        routeReads();completeLongUpload();
        for(String action:List.of("cancel","disconnect","native-hang","missing-ack"))interruptedUpload(action);
        System.out.println("PASS actual route/upload scheduler and payload checks="+checks+"; memory peripheral only, no GATT hardware");
    }
}
