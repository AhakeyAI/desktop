package com.example.ahakey.protocol;

import com.example.ahakey.firmware.DeviceMaintenanceChecks;
import com.example.ahakey.model.K1Route;
import com.example.ahakey.service.BleManager;
import java.util.*;
import java.nio.*;
import static com.example.ahakey.update.UpdateCenterChecks.*;

public final class K1RouteProtocolChecks {
    public static final class Wire extends DeviceMaintenanceChecks.FixtureBle {
        public final K1Route[] routes=new K1Route[4];
        public final String[][] descriptions=new String[4][4];
        public final byte[][][] actions=new byte[4][4][];
        public final int[][] types=new int[4][4];
        public final List<byte[]> frames=new java.util.concurrent.CopyOnWriteArrayList<>();
        public boolean legacy,missingBank,badReadCrc,uncertainCommit,failBegin;public int commits,begins;
        public Runnable onCommit=()->{},onLegacyRead=()->{};
        private byte[] pending;private int token,mode,offset;private long crc;
        public Wire(BleManager.BleCallback callback)throws Exception {
            super(callback);
            for(int m=0;m<4;m++){routes[m]=consumer(0xE9+m);for(int k=0;k<4;k++){actions[m][k]=new byte[]{(byte)(4+m+k)};types[m][k]=0x73;descriptions[m][k]="device-"+m+"-"+k;}}
            usb.consumer=this::respond;
        }
        public static K1Route consumer(int usage){byte[] b=new byte[102];b[0]=1;b[1]=2;b[2]=(byte)usage;b[3]=(byte)(usage>>8);return new K1Route(b);}
        @Override public void queryStatus(){}
        private void respond(byte[] f){try {
            frames.add(f.clone());int opcode=f[2]&255;
            if(opcode!=0x9e){byte[] payload={0};
                if(opcode==0x87){int m=f[3]&255,k=f[4]&255;byte[] desc=descriptions[m][k].getBytes(java.nio.charset.StandardCharsets.US_ASCII),action=actions[m][k];if(action.length+desc.length>53){reply(AhaKeyProtocol.buildFrame((byte)0x87,new byte[]{3}));return;}payload=new byte[6+action.length+desc.length];payload[1]=(byte)m;payload[2]=(byte)k;payload[3]=(byte)types[m][k];payload[4]=(byte)action.length;System.arraycopy(action,0,payload,5,action.length);payload[5+action.length]=(byte)desc.length;System.arraycopy(desc,0,payload,6+action.length,desc.length);if(k==0&&legacy)onLegacyRead.run();}
                else if(opcode==0x73){int m=f[4]&255,k=f[5]&255;byte[] body=Arrays.copyOfRange(f,6,f.length-2);if(f[3]==0x75)descriptions[m][k]=new String(body,java.nio.charset.StandardCharsets.US_ASCII);else{types[m][k]=f[3]&255;actions[m][k]=body;}}
                else if(opcode==0x97)payload=new byte[]{0,0,2,0,0,1,0};
                else if(opcode==0x9f)payload=com.example.ahakey.firmware.FirmwareCatalog.CATALOG.getBytes();
                reply(AhaKeyProtocol.buildFrame(f[2],payload));return;
            }
            int sub=f[4]&255;var b=ByteBuffer.wrap(f,5,f.length-7).slice().order(ByteOrder.LITTLE_ENDIAN);
            if(legacy){reply(AhaKeyProtocol.buildFrame((byte)0x9e,new byte[]{0}));return;}
            int correlation=sub==0x20?b.getInt(7):b.getInt(0);
            if((missingBank&&sub==0x10)||(failBegin&&sub==0x20)){reply(response(sub,1,K1RouteProtocol.fields(4).putInt(correlation).array()));return;}
            byte[] fields;
            switch(sub){
                case 0:fields=K1RouteProtocol.fields(6).putInt(correlation).put((byte)3).put((byte)4).array();break;
                case 0x10:{int m=b.get(4)&255,o=b.get(5)&255,n=b.get(6)&255;byte[] route=routes[m].bytes();fields=K1RouteProtocol.fields(12+n).putInt(correlation).put((byte)m).put((byte)o).putShort((short)102).putInt((int)K1RouteProtocol.crc(route)+(badReadCrc?1:0)).put(route,o,n).array();break;}
                case 0x20:{begins++;mode=b.get()&255;int total=b.getShort()&65535;crc=Integer.toUnsignedLong(b.getInt());token=b.getInt();check("begin is single mode, exact 102 bytes, nonzero token",mode<4&&total==102&&token!=0);pending=new byte[total];offset=0;fields=K1RouteProtocol.fields(10).putInt(token).putInt(token).putShort((short)0).array();break;}
                case 0x21:{int t=b.getInt(),m=b.get()&255,o=b.getShort()&65535,n=b.get()&255;check("chunk token/mode/offset and USB bound",t==token&&m==mode&&o==offset&&n<=47&&f.length<=62);b.get(pending,offset,n);offset+=n;fields=K1RouteProtocol.fields(8).putInt(token).put((byte)mode).putShort((short)offset).put((byte)n).array();break;}
                case 0x22:{commits++;check("commit uses full staged record",b.getInt()==token&&(b.get()&255)==mode&&offset==102&&K1RouteProtocol.crc(pending)==crc);routes[mode]=new K1Route(pending);if(!routes[mode].consumer()){actions[mode][0]=routes[mode].action();types[mode][0]=routes[mode].actionType();}onCommit.run();if(uncertainCommit){reply(response(sub,0,K1RouteProtocol.fields(9).putInt(token+1).put((byte)mode).putInt((int)crc).array()));return;}fields=K1RouteProtocol.fields(9).putInt(token).put((byte)mode).putInt((int)crc).array();break;}
                default:throw new AssertionError("Unexpected K1 subcommand "+sub);
            }
            reply(response(sub,0,fields));
        }catch(Exception e){throw new RuntimeException(e);}}
    }
    public static byte[] response(int sub,int status,byte[] fields){byte[] p=new byte[3+fields.length];p[0]=(byte)status;p[1]=1;p[2]=(byte)sub;System.arraycopy(fields,0,p,3,fields.length);return AhaKeyProtocol.buildFrame((byte)0x9e,p);}
    public static void main(String[] args)throws Exception {
        byte[] action=new byte[98];check("98-byte ordinary payload fits exact record",K1Route.ordinary(0x74,action).bytes().length==102);rejects("99-byte action cannot overflow envelope",()->K1Route.ordinary(0x74,new byte[99]));
        K1Route empty=new K1Route(new byte[102]);check("valid empty ordinary is not missing route bank",!empty.consumer()&&empty.action().length==0);
        byte[] invalid=new byte[102];invalid[101]=1;rejects("nonzero unused padding",()->new K1Route(invalid));
        byte[] cap=response(0,0,K1RouteProtocol.fields(6).putInt(123).put((byte)3).put((byte)4).array());K1RouteProtocol.capability(cap,123);check("capability accepted with exact nonce",true);
        rejects("wrong nonce",()->K1RouteProtocol.capability(cap,124));rejects("generic ACK is not route capability",()->K1RouteProtocol.capability(AhaKeyProtocol.buildFrame((byte)0x9e,new byte[]{0}),123));
        rejects("matching generic FAIL remains unavailable",()->K1RouteProtocol.response(response(0x10,1,K1RouteProtocol.fields(4).putInt(123).array()),0x10,123,54));
        byte[] extra=Arrays.copyOf(cap,cap.length+1);rejects("trailing frame byte",()->K1RouteProtocol.capability(extra,123));
        byte[] unknown=response(0,0,K1RouteProtocol.fields(6).putInt(123).put((byte)7).put((byte)4).array());rejects("unknown capability flags",()->K1RouteProtocol.capability(unknown,123));
        transportChecks();runtimeInterleavingChecks();
        System.out.println("PASS strict K1 v1 frame, real USB/BLE extraction, and SINGLE Hook interleaving");
    }
    private static void transportChecks()throws Exception {
        var usb=com.example.ahakey.service.UsbHidTransport.class.getDeclaredMethod("extractFrame",byte[].class,int.class,byte[].class);usb.setAccessible(true);
        var bleFrames=BleManager.class.getDeclaredMethod("reassembleNotifyFrames",byte[].class);bleFrames.setAccessible(true);
        int correlation=0xBBAADDCC;
        for(int sub:new int[]{0,0x10,0x20,0x21,0x22})for(boolean fail:new boolean[]{false,true})for(int count:sub==0x10?new int[]{1,18,42}:new int[]{0}) {
            byte[] request=K1RouteProtocol.request(0x10,K1RouteProtocol.fields(7).putInt(correlation).put((byte)0).put((byte)0).put((byte)count).array());
            int fieldsLength=fail?4:switch(sub){case 0->6;case 0x10->12+count;case 0x20->10;case 0x21->8;default->9;};
            byte[] fields=new byte[fieldsLength];for(int i=0;i<fields.length;i++)fields[i]=new byte[]{(byte)0xCC,(byte)0xDD,(byte)0xAA,(byte)0xBB}[i%4];
            byte[] reply=response(sub,fail?1:0,fields);String name="sub="+sub+" fail="+fail+" data="+count;
            for(int prefix:new int[]{0,1,2,3}) {
                byte[] report=new byte[65];System.arraycopy(reply,0,report,prefix,reply.length);
                check("USB fixed report preserves embedded markers "+name+" prefix="+prefix,Arrays.equals(reply,(byte[])usb.invoke(null,report,report.length,request)));
                check("USB actual read length rejects truncation "+name,usb.invoke(null,report,prefix+reply.length-1,request)==null);
            }
            var ble=new DeviceMaintenanceChecks.FixtureBle();DeviceMaintenanceChecks.field(ble,"k1ReplyRequest",request);
            for(int split=1;split<reply.length;split++) {
                var first=(List<?>)bleFrames.invoke(ble,(Object)Arrays.copyOf(reply,split));var second=(List<?>)bleFrames.invoke(ble,(Object)Arrays.copyOfRange(reply,split,reply.length));
                check("BLE binary split "+name+" at "+split,first.isEmpty()&&second.size()==1&&Arrays.equals(reply,(byte[])second.get(0)));
            }
            byte[] joined=new byte[reply.length*2];System.arraycopy(reply,0,joined,0,reply.length);System.arraycopy(reply,0,joined,reply.length,reply.length);
            check("BLE coalesced binary replies "+name,((List<?>)bleFrames.invoke(ble,(Object)joined)).size()==2);
            byte[] invalid=reply.clone();invalid[invalid.length-1]=0;
            check("USB rejects invalid bounded footer "+name,usb.invoke(null,invalid,invalid.length,request)==null);
            var invalidBle=new DeviceMaintenanceChecks.FixtureBle();DeviceMaintenanceChecks.field(invalidBle,"k1ReplyRequest",request);
            check("BLE rejects invalid bounded footer "+name,((List<?>)bleFrames.invoke(invalidBle,(Object)invalid)).isEmpty());
        }
        byte[] cap=response(0,0,K1RouteProtocol.fields(6).putInt(0xDDCC).put((byte)3).put((byte)4).array());
        check("exact reported nonce DDCC is a 14-byte reply",Arrays.equals(cap,(byte[])usb.invoke(null,cap,cap.length,null)));
        byte[] legacy=AhaKeyProtocol.buildFrame((byte)0x9E,new byte[]{0});check("exact legacy ACK retained",Arrays.equals(legacy,(byte[])usb.invoke(null,legacy,legacy.length,null)));
        byte[] read=response(0x10,0,new byte[54]);check("read without bounded outstanding request rejected",usb.invoke(null,read,read.length,null)==null);
        for(int n:new int[]{0,43,255}) {byte[] req=K1RouteProtocol.request(0x10,K1RouteProtocol.fields(7).putInt(1).put((byte)0).put((byte)0).put((byte)n).array());check("invalid requested slice bound "+n,usb.invoke(null,read,read.length,req)==null);}
        for(int sub:new int[]{0x23,0xff}){byte[] invalid=response(sub,0,new byte[4]);check("unknown subcommand never delimiter scans",usb.invoke(null,invalid,invalid.length,null)==null);}
    }
    private static void runtimeInterleavingChecks()throws Exception {
        System.setProperty("user.home",java.nio.file.Files.createTempDirectory("r9-k1-hook-").toString());
        for(String outcome:List.of("success","failure","expired","generation")) {
            var ble=new DeviceMaintenanceChecks.FixtureBle();var sent=new java.util.concurrent.CopyOnWriteArrayList<byte[]>();
            var waiting=new java.util.concurrent.CountDownLatch(1);ble.usb.consumer=frame->{sent.add(frame.clone());if(frame[2]==(byte)0x9E)waiting.countDown();};
            var runtime=new com.example.ahakey.service.AiRuntimeDisplayService(ble);runtime.displayModeProperty().set(com.example.ahakey.model.AiRuntimeDisplayMode.SINGLE);
            var lockField=BleManager.class.getDeclaredField("commandLock");lockField.setAccessible(true);var monitorField=BleManager.class.getDeclaredField("commandTransactionLock");monitorField.setAccessible(true);
            var lock=(java.util.concurrent.locks.ReentrantLock)lockField.get(ble);Object monitor=monitorField.get(ble);var idle=new java.util.concurrent.atomic.AtomicBoolean();
            ble.setDisplayIdleListener(()->{check("idle callback outside command and transaction locks",!lock.isHeldByCurrentThread()&&!Thread.holdsLock(monitor));idle.set(true);});
            var transaction=java.util.concurrent.CompletableFuture.runAsync(()->{try{ble.k1RouteTransaction(0,()->{byte[] result=ble.exchangeK1Route(K1RouteProtocol.request(0,K1RouteProtocol.fields(4).putInt(77).array()),0);K1RouteProtocol.capability(result,77);return null;});if(outcome.equals("failure")||outcome.equals("generation"))throw new AssertionError("expected transaction failure");}catch(Exception e){if(!outcome.equals("failure")&&!outcome.equals("generation"))throw new RuntimeException(e);}});
            check("actual K1 wait entered "+outcome,waiting.await(2,java.util.concurrent.TimeUnit.SECONDS));
            rejects("maintenance cannot enter active K1 transaction",()->ble.maintenance().begin(DeviceMaintenanceChecks.identity(),DeviceMaintenanceChecks.HASH,"fixture",false));
            for(var state:List.of(com.example.ahakey.model.IDEState.USER_PROMPT_SUBMIT,com.example.ahakey.model.IDEState.TASK_COMPLETED))check("SINGLE Hook pending during K1 "+outcome+state,runtime.handleHookEventResult("Kimi",state,null)==com.example.ahakey.service.AiRuntimeDisplayService.Delivery.PENDING);
            check("no runtime writes while K1 owns transaction",sent.stream().noneMatch(f->f[2]==(byte)0x90));
            if(outcome.equals("expired"))DeviceMaintenanceChecks.field(ble,"deferredRuntimeAt",System.nanoTime()-java.util.concurrent.TimeUnit.MINUTES.toNanos(6));
            if(outcome.equals("generation")){var reset=BleManager.class.getDeclaredMethod("resetDisplaySession");reset.setAccessible(true);reset.invoke(ble);}
            ble.reply(outcome.equals("failure")?response(0,1,K1RouteProtocol.fields(4).putInt(77).array()):response(0,0,K1RouteProtocol.fields(6).putInt(77).put((byte)3).put((byte)4).array()));
            transaction.get(4,java.util.concurrent.TimeUnit.SECONDS);
            check("success and failed K1 transactions notify safe release "+outcome,idle.get());
            var writes=sent.stream().filter(f->f[2]==(byte)0x90).toList();
            check("release flushes latest once unless expired or cross-generation "+outcome,outcome.equals("expired")||outcome.equals("generation")?writes.isEmpty():writes.size()==1&&writes.get(0)[3]==com.example.ahakey.model.IDEState.TASK_COMPLETED.getCode());
            var op=ble.maintenance().begin(DeviceMaintenanceChecks.identity(),DeviceMaintenanceChecks.HASH,"fixture",false);int before=sent.size();
            DeviceMaintenanceChecks.field(ble,"deferredRuntimeState",(byte)6);DeviceMaintenanceChecks.field(ble,"deferredRuntimeAt",System.nanoTime());var flush=BleManager.class.getDeclaredMethod("flushDeferredRuntimeState");flush.setAccessible(true);flush.invoke(ble);
            ble.maintenance().finish(op,true);flush.invoke(ble);check("maintenance invalidates pending fact without later replay",sent.size()==before);
        }
    }
}
