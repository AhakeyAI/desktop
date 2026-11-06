package com.example.ahakey.wd011;

import com.example.ahakey.model.OledResourceState;
import com.example.ahakey.model.OledResourceState.Asset;
import com.example.ahakey.protocol.*;
import com.example.ahakey.service.*;
import com.example.ahakey.util.*;
import com.example.ahakey.firmware.DeviceMaintenanceChecks;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.awt.image.BufferedImage;
import java.io.*;
import java.lang.reflect.Method;
import java.net.SocketTimeoutException;
import java.nio.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
import javax.imageio.ImageIO;
import static com.example.ahakey.protocol.CompactUploadProtocol.*;

/** Memory USB/TCP only; no connect, HID enumeration, firmware execution or App.start. */
public final class CompactChecks {
    static int checks;
    static final Path FIXTURES=Path.of("src/test/resources/wd011");
    static void check(String label,boolean condition){if(!condition)throw new AssertionError(label);checks++;}
    interface Action{void run()throws Exception;}
    static Exception reject(String label,Action action)throws Exception {
        try{action.run();throw new AssertionError(label);}catch(AssertionError e){throw e;}catch(Exception e){checks++;return e;}
    }
    static Asset sample()throws Exception{return Asset.fromCompact(Files.readAllBytes(FIXTURES.resolve("animation8/resource.acr")));}
    public static void main(String[] args)throws Exception {
        System.setProperty("user.home",Files.createTempDirectory("wd011-check-home-").toString());
        ((ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)).setLevel(ch.qos.logback.classic.Level.WARN);
        golden();encoding();persistence();framing();engine();transport();
        System.out.println("PASS WD-011 "+checks+" assertions; offline only; no hardware timing/UAT claim");
    }
    static void golden()throws Exception {
        var mapper=new ObjectMapper();
        for(String name:List.of("static","noise","low40","animation8","animation12")) {
            Path dir=FIXTURES.resolve(name);byte[] object=Files.readAllBytes(dir.resolve("resource.acr"));
            var report=mapper.readTree(dir.resolve("encoding.json").toFile());Asset asset=Asset.fromCompact(object);
            check(name+" object CRC",crc(object)==report.path("object_crc32").asLong());
            check(name+" expanded CRC",asset.crc()==report.path("expanded_crc32").asLong());
            check(name+" object bytes",object.length==report.path("object_bytes").asInt());
            byte[] expanded=asset.bytes();
            for(int f=0;f<asset.frames();f++) {
                check(name+" duration",asset.durationMillis(f)==report.path("durations_ms").get(f).asInt());
                BufferedImage golden=ImageIO.read(dir.resolve(String.format("frame-%02d.png",f)).toFile());
                BufferedImage decoded=OLEDFrameEncoder.decodeFrame(expanded,f*28672);
                for(int y=0;y<80;y++)for(int x=0;x<160;x++)check(name+" exact RGB565 pixels",golden.getRGB(x,y)==decoded.getRGB(x,y));
                check(name+" tail magic",new String(expanded,f*28672+25600,4,java.nio.charset.StandardCharsets.US_ASCII).equals("AT03"));
                for(int i=25616;i<28672;i++)check(name+" FF fill",expanded[f*28672+i]==(byte)255);
            }
            byte[] truncated=Arrays.copyOf(object,object.length-1);reject(name+" truncated",()->Asset.fromCompact(truncated));
        }
        byte[] invalid=sample().compactBytes();invalid[48]=0;invalid[49]=0;reject("zero duration",()->Asset.fromCompact(invalid));
        byte[] badFlag=sample().compactBytes();badFlag[7]=0;reject("animation flag",()->Asset.fromCompact(badFlag));
    }
    static void encoding()throws Exception {
        List<OLEDFrameEncoder.EncodedFrame> frames=new ArrayList<>();
        for(int n=0;n<8;n++) {
            BufferedImage source=new BufferedImage(160,80,BufferedImage.TYPE_INT_RGB);
            for(int y=0;y<80;y++)for(int x=0;x<160;x++)source.setRGB(x,y,((x*255/159)<<16)|((y*255/79)<<8)|(n*32));
            var base=OLEDFrameEncoder.encodeFrame(source);frames.add(new OLEDFrameEncoder.EncodedFrame(base.rgb565,base.preview,(n+1)*20));
        }
        byte[] a=CompactResourceEncoder.encode(frames),b=CompactResourceEncoder.encode(frames);Asset asset=Asset.fromCompact(a);
        check("deterministic",Arrays.equals(a,b));check("80x40 8-frame budget",a.length==12864&&a[4]==2&&a[5]==2);
        Set<Integer> colors=new HashSet<>();byte[] bytes=asset.bytes();
        for(int f=0;f<8;f++){check("retained timing",asset.durationMillis(f)==(f+1)*20);for(int i=0;i<25600;i+=2)colors.add(((bytes[f*28672+i]&255)<<8)|(bytes[f*28672+i+1]&255));}
        check("whole animation <=16 colors",colors.size()<=16);
        var original=frames.get(0);reject("13 frames rejected",()->CompactResourceEncoder.encode(Collections.nCopies(13,original)));
        reject("10ms not silently adjusted",()->CompactResourceEncoder.encode(List.of(new OLEDFrameEncoder.EncodedFrame(original.rgb565,original.preview,10))));
        reject("too long not silently adjusted",()->CompactResourceEncoder.encode(List.of(new OLEDFrameEncoder.EncodedFrame(original.rgb565,original.preview,60001))));
        reject("8-frame default slot enforced",()->OledResourceState.empty(0).replace(Asset.fromCompact(Files.readAllBytes(FIXTURES.resolve("animation12/resource.acr")))));
    }
    static void persistence()throws Exception {
        Path root=Files.createTempDirectory("wd011-resource-");var store=new OledResourceStore(root);store.load();
        Asset legacy=Asset.fromBytes(new byte[28672]);store.save(OledResourceState.empty(0).replace(legacy));
        store.save(OledResourceState.empty(1).replace(sample()).applied());
        var loaded=new OledResourceStore(root).load();check("old asset retained",!loaded.get(0).asset().compact());
        check("new object roundtrip",Arrays.equals(loaded.get(1).asset().compactBytes(),sample().compactBytes()));
        check("expanded identity matches",loaded.get(1).device().matches(sample()));
        store.save(loaded.get(1).committing());check("interrupted commit retained",new OledResourceStore(root).load().get(1).commitUncertain());
        byte[] copy=sample().compactBytes();copy[0]=0;check("immutable asset",sample().compactBytes()[0]==65);
        var index=new ObjectMapper().readTree(root.resolve("index.json").toFile());Path encoded=root.resolve(index.path("entries").path("1").path("compactFile").asText());
        byte[] corrupt=Files.readAllBytes(encoded);corrupt[50]^=1;Files.write(encoded,corrupt);
        reject("mismatched encoded/expanded asset rejected",()->new OledResourceStore(root).load());
        check("index failure preserves bytes",Files.exists(root.resolve("index.json")));
    }
    static byte[] reply(int sub,int status,int token,byte[] fields) {
        ByteBuffer b=ByteBuffer.allocate(13+fields.length).order(ByteOrder.LITTLE_ENDIAN);
        b.put(new byte[]{(byte)0xAA,(byte)0xBB,(byte)0x9E,(byte)status,3,(byte)sub,(byte)fields.length}).putInt(token).put(fields).put((byte)0xCC).put((byte)0xDD);return b.array();
    }
    static byte[] capFields(boolean usb){return fields(14).put(new byte[]{65,67,82,51}).putShort((short)15).putInt(50000).put((byte)(usb?40:128)).put(new byte[]{7,8,12}).array();}
    static void framing()throws Exception {
        Method usb=UsbHidTransport.class.getDeclaredMethod("extractFrame",byte[].class,int.class,byte[].class);usb.setAccessible(true);
        Method assemble=BleManager.class.getDeclaredMethod("reassembleNotifyFrames",byte[].class);assemble.setAccessible(true);
        for(int sub=CAPS;sub<=METADATA;sub++)for(int status:new int[]{0,1,2,3,7,8,10,11}) {
            int n=status==0?new int[]{14,8,9,10,6,11,10}[sub-CAPS]:4;
            byte[] content=new byte[n];for(int i=0;i<n;i++)content[i]=new byte[]{(byte)0xAA,(byte)0xBB,(byte)0xCC,(byte)0xDD}[i%4];
            byte[] r=reply(sub,status,0xDDCCBBAA,content),req=request(sub,0xDDCCBBAA,new byte[0]);
            check("strict response",response(r,sub,0xDDCCBBAA).status()==status);
            for(int prefix=0;prefix<4;prefix++) {
                byte[] report=new byte[65];System.arraycopy(r,0,report,prefix,r.length);
                check("USB binary extraction",Arrays.equals(r,(byte[])usb.invoke(null,report,65,req)));
                check("USB truncation",usb.invoke(null,report,prefix+r.length-1,req)==null);
            }
            var ble=new DeviceMaintenanceChecks.FixtureBle();
            for(int split=1;split<r.length;split++) {
                check("fragment waits",((List<?>)assemble.invoke(ble,(Object)Arrays.copyOf(r,split))).isEmpty());
                var completed=(List<?>)assemble.invoke(ble,(Object)Arrays.copyOfRange(r,split,r.length));
                check("fragment exact",completed.size()==1&&Arrays.equals((byte[])completed.get(0),r));
            }
            byte[] joined=new byte[r.length*2];System.arraycopy(r,0,joined,0,r.length);System.arraycopy(r,0,joined,r.length,r.length);
            check("coalesced",((List<?>)assemble.invoke(ble,(Object)joined)).size()==2);
        }
        byte[] cap=reply(CAPS,0,1,capFields(true));reject("wrong nonce",()->response(cap,CAPS,2));reject("wrong sub",()->response(cap,BEGIN,1));
        byte[] version=cap.clone();version[4]=2;reject("wrong version",()->response(version,CAPS,1));
        reject("generic ACK never capability",()->response(new byte[]{(byte)0xAA,(byte)0xBB,(byte)0x9E,0,(byte)0xCC,(byte)0xDD},CAPS,1));
        check("busy accurately reported",reject("busy",()->capability(new Reply(3,new byte[4]),true)).getMessage().contains("设备忙"));
    }
    static final class Device implements CompactUploadService.Transport {
        final boolean usb; final Asset asset; final String mode; final AtomicLong time=new AtomicLong();
        int offset,token,entry,beginCount,commitCount,chunkCount,statusCount,metadataCount;boolean triggered;byte[] lastChunk;
        Device(boolean usb,String mode,Asset asset){this.usb=usb;this.mode=mode;this.asset=asset;}
        public boolean usb(){return usb;}
        public byte[] exchange(byte[] req,long timeout)throws Exception {
            time.addAndGet(1_000_000);int sub=req[4]&255,correlation=read(req).getInt(6);ByteBuffer data=read(Arrays.copyOfRange(req,10,req.length-2));
            check("request bounded",req.length<=(usb?57:145));check("explicit request length",req.length==12+(req[5]&255));
            if(sub==CAPS){if(mode.equals("unsupported"))return reply(sub,2,correlation,new byte[4]);if(mode.equals("generic"))return new byte[]{(byte)0xAA,(byte)0xBB,(byte)0x9E,0,(byte)0xCC,(byte)0xDD};return reply(sub,0,correlation,capFields(usb));}
            if(sub==BEGIN){beginCount++;entry=data.get()&255;check("object size",data.getInt()==asset.transferBytes());check("object CRC",Integer.toUnsignedLong(data.getInt())==crc(asset.compactBytes()));byte[] header=new byte[16];data.get(header);check("header included once",Arrays.equals(header,Arrays.copyOf(asset.compactBytes(),16)));token=correlation;offset=16;if(mode.startsWith("begin"))throw new SocketTimeoutException();return reply(sub,0,correlation,fields(8).putInt(16).putInt(asset.bytes().length).array());}
            if(sub!=METADATA)check("same transaction token",token==correlation);
            if(sub==CHUNK) {
                chunkCount++;int at=data.getInt(),count=data.get()&255;byte[] payload=new byte[count];data.get(payload);
                check("chunk source exact",Arrays.equals(payload,Arrays.copyOfRange(asset.compactBytes(),at,at+count)));
                check("chunk limit",count<=(usb?40:128));
                if(mode.equals("disconnect"))throw new IOException("连接已改变");
                if(mode.equals("crc"))return reply(sub,8,correlation,new byte[4]);
                if(mode.equals("storage"))return reply(sub,10,correlation,new byte[4]);
                if(mode.equals("retryLimit"))throw new SocketTimeoutException();
                if(mode.equals("stale")&&lastChunk!=null&&!triggered){triggered=true;return lastChunk;}
                if(mode.equals("unaccepted")&&!triggered){triggered=true;throw new SocketTimeoutException();}
                check("offset continuity",at==offset);offset+=count;
                if((mode.equals("accepted")||mode.equals("wrongOffset")||mode.equals("fault")||mode.equals("processing"))&&!triggered){triggered=true;throw new SocketTimeoutException();}
                lastChunk=reply(sub,0,correlation,fields(9).putInt(offset).put((byte)count).putInt(0).array());return lastChunk;
            }
            if(sub==STATUS){statusCount++;if(mode.equals("beginInactive"))return reply(sub,11,correlation,new byte[4]);int state=mode.equals("fault")?4:mode.equals("processing")&&statusCount==1?2:1;return reply(sub,0,correlation,fields(11).put((byte)state).put((byte)entry).putInt(mode.equals("wrongOffset")?offset+1:offset).putInt(0).put((byte)0).array());}
            if(sub==COMMIT){commitCount++;check("complete before commit",offset==asset.transferBytes());if(mode.startsWith("commit"))throw new SocketTimeoutException();return reply(sub,0,correlation,fields(10).put((byte)entry).put((byte)asset.frames()).putInt(asset.bytes().length).putInt((int)asset.crc()).array());}
            if(sub==METADATA){metadataCount++;check("metadata target",data.get()==entry);return reply(sub,0,correlation,fields(10).put((byte)2).put((byte)asset.frames()).putInt(asset.bytes().length).putInt((int)asset.crc()+(mode.equals("commitWrong")?1:0)).array());}
            throw new AssertionError("unexpected sub "+sub);
        }
        void run(List<Integer> progress)throws Exception {new CompactUploadService(this,time::get,()->time.addAndGet(50_000_000)).upload(0,asset,()->{},p->progress.add(p.acknowledgedBytes()));}
    }
    static void engine()throws Exception {
        for(boolean usb:new boolean[]{true,false})for(String mode:List.of("normal","accepted","unaccepted","stale","processing","beginAccepted","commitLost")) {
            Device d=new Device(usb,mode,sample());List<Integer> progress=new ArrayList<>();d.run(progress);
            check(mode+" begin not repeated",d.beginCount==1);check(mode+" commit not repeated",d.commitCount==1);check("persisted metadata required",d.metadataCount==1);
            int previous=0;for(int n:progress){check("progress credited once",n>previous);previous=n;}check("complete encoded bytes",previous==sample().transferBytes());
            if(mode.equals("stale"))check("stale chunk resolves via status",d.statusCount>0);
        }
        for(String mode:List.of("unsupported","generic","beginInactive","retryLimit","wrongOffset","fault","crc","storage","disconnect","commitWrong")) {
            Device d=new Device(true,mode,sample());Exception error=reject(mode,()->d.run(new ArrayList<>()));
            check(mode+" typed failure",error instanceof OledUploadService.UploadFailure);
            if(mode.equals("unsupported")||mode.equals("generic"))check("no BEGIN without CAPS",d.beginCount==0);
            if(mode.equals("retryLimit"))check("bounded retries",d.chunkCount==5);
            if(mode.equals("commitWrong"))check("commit uncertainty persisted",((OledUploadService.UploadFailure)error).commitUncertain());
            else check("never commit after precommit failure",d.commitCount==0);
        }
    }
    static void transport()throws Exception {
        for(boolean usb:new boolean[]{true,false}) {
            var ble=new DeviceMaintenanceChecks.FixtureBle();Device device=new Device(usb,"normal",sample());
            java.util.function.Consumer<byte[]> send=req->{try {
                if((req[2]&255)!=0x9E)return;
                if((req[4]&255)==CHUNK) {
                    reject("lease excludes config write",()->ble.sendCommand(AhaKeyProtocol.setWorkMode(2)));
                    reject("lease excludes K1",()->ble.k1RouteTransaction(0,()->null));
                    reject("lease excludes factory reset",()->ble.beginFactoryReset(0));
                    check("runtime deferred",!ble.sendRuntimeState((byte)1));
                }
                byte[] response=device.exchange(req,15000);
                byte[] wrong=response.clone();wrong[7]^=1;ble.reply(wrong); // Stale token cannot satisfy this request.
                ble.reply(response);
            }catch(Exception e){throw new RuntimeException(e);}};
            if(usb)ble.usb.consumer=send;
            else {ble.usb.opened=false;DeviceMaintenanceChecks.field(ble,"outputStream",new OutputStream(){
                public void write(int b){throw new AssertionError("bytewise TCP");}
                public void write(byte[] packet,int off,int length){check("TCP type retained",packet[off]==2);check("TCP size retained",length==3+(packet[off+1]&255)+((packet[off+2]&255)<<8));send.accept(Arrays.copyOfRange(packet,off+3,off+length));}
            });}
            OledUploadService.uploadResource(ble,0,0,sample(),p->{},()->{});
            check("real upload call chain USB="+usb,device.commitCount==1&&!ble.isDisplayWriteUncertain());
        }
        var timeout=new DeviceMaintenanceChecks.FixtureBle();
        try(var lease=timeout.openDisplayLease(true)) {
            reject("real timeout bounded",()->timeout.exchangeCompact(lease,request(CAPS,1,new byte[0]),3));
            check("read timeout alone not write quarantine",!timeout.isDisplayWriteUncertain());
        }
        var changed=new DeviceMaintenanceChecks.FixtureBle();Method reset=BleManager.class.getDeclaredMethod("resetDisplaySession");reset.setAccessible(true);
        changed.usb.consumer=req->{try{reset.invoke(changed);}catch(Exception e){throw new RuntimeException(e);}};
        reject("connection changes stop before BEGIN",()->CompactUploadService.upload(changed,0,0,sample(),()->{},p->{}));
        check("no restart into new generation",changed.usb.writes.get()==1&&changed.connectionGeneration()==1);
        var failed=new DeviceMaintenanceChecks.FixtureBle();Device d=new Device(true,"storage",sample());int[] idle={0};failed.setDisplayIdleListener(()->idle[0]++);
        failed.usb.consumer=req->{try{failed.reply(d.exchange(req,15000));}catch(Exception e){throw new RuntimeException(e);}};
        reject("storage failure stops upload",()->CompactUploadService.upload(failed,0,0,sample(),()->{},p->{}));
        check("quarantine before deferred writes",failed.isDisplayWriteUncertain()&&idle[0]==0);
        var factory = new DeviceMaintenanceChecks.FixtureBle();factory.setFactoryWriteGuard(()->true);
        reject("factory unresolved blocks fast write",()->CompactUploadService.upload(factory,0,0,sample(),()->{},p->{}));
        check("factory blocked before physical request",factory.usb.writes.get()==0);
        var fresh = new DeviceMaintenanceChecks.FixtureBle();
        try(var lease = fresh.openDisplayLease(true)) {
            byte[] request = request(CAPS,0x1234,new byte[0]);
            fresh.usb.consumer = ignored -> {try{fresh.reply(reply(CAPS,0,0x1235,capFields(true)));}catch(Exception e){throw new RuntimeException(e);}};
            reject("wrong nonce never completes transaction",()->fresh.exchangeCompact(lease,request,3));
        }
    }
}
