package com.example.ahakey.wd011;

import com.example.ahakey.model.*;
import com.example.ahakey.model.OledResourceState.Asset;
import com.example.ahakey.protocol.*;
import com.example.ahakey.service.*;
import com.example.ahakey.util.*;
import com.example.ahakey.firmware.DeviceMaintenanceChecks;
import java.io.*;import java.net.SocketTimeoutException;import java.nio.*;import java.nio.file.*;import java.util.*;import java.util.concurrent.atomic.AtomicLong;
import static com.example.ahakey.protocol.LosslessUploadProtocol.*;

public final class LosslessChecks {
 static int checks;static final Path FIX=Path.of("src/test/resources/wd011/acr4");
 static void check(String s,boolean b){if(!b)throw new AssertionError(s);checks++;}
 interface Action{void run()throws Exception;}
 static Exception reject(String s,Action a)throws Exception{try{a.run();throw new AssertionError(s);}catch(AssertionError e){throw e;}catch(Exception e){checks++;return e;}}
 static byte[] canonical(byte[] f){byte[] c=f.clone();for(int n=0;n<c.length/28672;n++)Arrays.fill(c,n*28672+25600,(n+1)*28672,(byte)0);return c;}
 static byte[] reply(int sub,int status,int token,byte[] data){return fields(13+data.length).put(new byte[]{(byte)0xaa,(byte)0xbb,(byte)0x9e,(byte)status,4,(byte)sub,(byte)data.length}).putInt(token).put(data).put((byte)0xcc).put((byte)0xdd).array();}
 static byte[] caps(boolean usb){return fields(14).put(new byte[]{65,67,82,52}).putShort((short)15).putInt(307240).put((byte)(usb?40:128)).put(new byte[]{1,8,12}).array();}
 static void codec()throws Exception{
  var expected=new com.fasterxml.jackson.databind.ObjectMapper().readTree(FIX.resolve("expected.json").toFile());
  for(String name:List.of("pattern8","pattern12","noise8")){
   byte[] cp2=Files.readAllBytes(FIX.resolve(name+".cp2"));var ex=expected.get(name);int entry=ex.path("entry").asInt();
   var e=LosslessResourceEncoder.encode(cp2,entry);byte[] object=e.object(),expanded=e.expanded();
   String hash=HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(object));
   check(name+" object SHA",hash.equalsIgnoreCase(ex.path("object_sha256").asText()));check(name+" object CRC",crc(object)==ex.path("encoded_crc32").asLong());
   check(name+" expanded CRC",e.expandedCrc()==ex.path("expanded_crc32").asLong());check(name+" exact expand",Arrays.equals(expanded,LosslessResourceEncoder.expand(object)));
   check(name+" zero/FF padding ignored",Arrays.equals(object,LosslessResourceEncoder.encode(canonical(cp2),entry).object()));
   for(int f=0;f<e.frames();f++){check(name+" pixel equality "+f,Arrays.equals(Arrays.copyOfRange(cp2,f*28672,f*28672+25600),Arrays.copyOfRange(expanded,f*28672,f*28672+25600)));check("100ms",read(expanded).getShort(f*28672+25608)==100);}
   reject("truncated",()->LosslessResourceEncoder.expand(Arrays.copyOf(object,object.length-1)));
   byte[] bad=object.clone();bad[5]=2;reject("scale",()->LosslessResourceEncoder.expand(bad));
  }
  byte[] twelve=new byte[12*28672];new Random(40).nextBytes(twelve);var max=LosslessResourceEncoder.encode(twelve,1);check("maximum RAW12",max.object().length==307240);reject("default slot12 rejected",()->LosslessResourceEncoder.encode(twelve,0));
  for(int n:new int[]{1,2,127,128,129}){byte[] pixels=new byte[28672];new Random(n).nextBytes(pixels);for(int i=0;i<n;i++){pixels[i*2]=(byte)0xcc;pixels[i*2+1]=(byte)0xdd;}var e=LosslessResourceEncoder.encode(pixels,0);check("token boundary "+n,Arrays.equals(e.expanded(),LosslessResourceEncoder.expand(e.object())));}
 }
 static void framing()throws Exception{
  var usb=UsbHidTransport.class.getDeclaredMethod("extractFrame",byte[].class,int.class,byte[].class);usb.setAccessible(true);
  var assemble=BleManager.class.getDeclaredMethod("reassembleNotifyFrames",byte[].class);assemble.setAccessible(true);
  for(int sub=CAPS;sub<=METADATA;sub++)for(int status:new int[]{0,1,2,3,7,8,10,11}){
   int n=status==0?new int[]{14,8,5,10,6,11,10}[sub-CAPS]:4;byte[] data=new byte[n];for(int i=0;i<n;i++)data[i]=new byte[]{(byte)0xaa,(byte)0xbb,(byte)0xcc,(byte)0xdd}[i%4];
   byte[] frame=reply(sub,status,0xDDCCBBAA,data),req=request(sub,0xDDCCBBAA,new byte[0]);check("exact reply",response(frame,sub,0xDDCCBBAA).status()==status);
   for(int prefix=0;prefix<4;prefix++){byte[] report=new byte[65];System.arraycopy(frame,0,report,prefix,frame.length);check("USB exact",Arrays.equals(frame,(byte[])usb.invoke(null,report,65,req)));}
   var ble=new DeviceMaintenanceChecks.FixtureBle();for(int split=1;split<frame.length;split++){check("fragment pending",((List<?>)assemble.invoke(ble,(Object)Arrays.copyOf(frame,split))).isEmpty());var frames=(List<?>)assemble.invoke(ble,(Object)Arrays.copyOfRange(frame,split,frame.length));check("fragment exact",frames.size()==1&&Arrays.equals((byte[])frames.get(0),frame));}
   byte[] wrong=frame.clone();wrong[4]=3;final int currentSub=sub;reject("wrong version",()->response(wrong,currentSub,0xDDCCBBAA));
  }
  check("18byte CHUNK",reply(CHUNK,0,1,new byte[5]).length==18);reject("wrong nonce",()->response(reply(CAPS,0,2,caps(true)),CAPS,1));
  reject("generic",()->response(new byte[]{(byte)0xaa,(byte)0xbb,(byte)0x9e,0,(byte)0xcc,(byte)0xdd},CAPS,1));
  check("explicit unsupported type",reject("unsupported",()->capability(new Reply(2,new byte[4]),true)) instanceof Unsupported);
  check("BUSY not unsupported",!(reject("busy",()->capability(new Reply(3,new byte[4]),true)) instanceof Unsupported));
 }
 static int subFor(int i){return i;}
 static final class Device implements LosslessUploadService.Transport {
  final boolean usb;final String mode;final LosslessResourceEncoder.Encoded encoded;final AtomicLong clock=new AtomicLong();int offset,entry,begin,commit,metadata,status,cancel,chunks;boolean triggered,active,processing;byte[] last;
  Device(boolean usb,String mode,Asset asset){this.usb=usb;this.mode=mode;encoded=LosslessResourceEncoder.encode(asset.bytes(),0);}
  public boolean usb(){return usb;}
  public byte[] exchange(byte[] req,long timeout)throws Exception{
   clock.addAndGet(1_000_000);int sub=req[4]&255,t=read(req).getInt(6);ByteBuffer b=read(Arrays.copyOfRange(req,10,req.length-2));check("wire bound",req.length<=(usb?57:145));
   if(sub==CAPS){if(mode.equals("unsupported"))return reply(sub,2,t,new byte[4]);if(mode.equals("caps-timeout"))throw new SocketTimeoutException();return reply(sub,0,t,caps(usb));}
   if(sub==BEGIN){begin++;entry=b.get()&255;check("total",b.getInt()==encoded.object().length);check("encoded CRC",Integer.toUnsignedLong(b.getInt())==crc(encoded.object()));byte[] h=new byte[16];b.get(h);check("header once",Arrays.equals(h,Arrays.copyOf(encoded.object(),16)));offset=16;active=true;if(mode.equals("begin-inactive")){active=false;throw new SocketTimeoutException();}if(mode.equals("begin-timeout"))throw new SocketTimeoutException();return reply(sub,0,t,fields(8).putInt(16).putInt(encoded.expanded().length).array());}
   if(sub==CHUNK){chunks++;int start=b.getInt(),count=b.get()&255;byte[] data=new byte[count];b.get(data);check("identical encoded pixels",Arrays.equals(data,Arrays.copyOfRange(encoded.object(),start,start+count)));
    if(!triggered&&!mode.equals("ok")&&!mode.startsWith("commit")&&!mode.startsWith("begin")&&!mode.startsWith("cancel")){
     triggered=true;if(mode.equals("storage"))return reply(sub,10,t,new byte[4]);if(mode.equals("stale"))return reply(sub,0,t,fields(5).putInt(start).put((byte)count).array());if(mode.equals("wrong-offset")){offset=start+1;throw new SocketTimeoutException();}if(mode.equals("timeout-start")){last=data;throw new SocketTimeoutException();}if(mode.equals("timeout-end")){offset=start+count;throw new SocketTimeoutException();}if(mode.equals("processing")){offset=start+count;processing=true;throw new SocketTimeoutException();}
    }
    if(mode.startsWith("cancel"))return reply(sub,10,t,new byte[4]);if(last!=null){check("same retry",Arrays.equals(last,data));last=null;}check("strict offset",offset==start);offset+=count;return reply(sub,0,t,fields(5).putInt(offset).put((byte)count).array());}
   if(sub==STATUS){status++;int state=processing?2:1;processing=false;if(!active)return reply(sub,11,t,new byte[4]);return reply(sub,0,t,fields(11).put((byte)state).put((byte)entry).putInt(offset).putInt(0).put((byte)0).array());}
   if(sub==COMMIT){commit++;active=false;if(mode.equals("commit-timeout"))throw new SocketTimeoutException();return reply(sub,0,t,fields(10).put((byte)entry).put((byte)encoded.frames()).putInt(encoded.expanded().length).putInt((int)encoded.expandedCrc()).array());}
   if(sub==METADATA){metadata++;if(!active&&commit==0)return reply(sub,0,t,new byte[]{3,0,0,0,0,0,0,0,0,0});if(mode.equals("commit-mismatch"))return reply(sub,0,t,fields(10).put((byte)2).put((byte)encoded.frames()).putInt(encoded.expanded().length).putInt(1).array());return reply(sub,0,t,fields(10).put((byte)2).put((byte)encoded.frames()).putInt(encoded.expanded().length).putInt((int)encoded.expandedCrc()).array());}
   if(sub==CANCEL){cancel++;if(!active)return reply(sub,11,t,new byte[4]);if(mode.equals("cancel-lost-invalid")){active=false;throw new SocketTimeoutException();}if(mode.equals("cancel-unknown")){clock.addAndGet(31_000_000_000L);throw new SocketTimeoutException();}active=false;return reply(sub,0,t,fields(6).put((byte)0).put((byte)entry).putInt(0).array());}
   throw new AssertionError("sub");
  }
 }
 static void engines()throws Exception{
  Asset asset=Asset.fromBytes(canonical(Files.readAllBytes(FIX.resolve("pattern8.cp2"))));
  for(boolean usb:new boolean[]{true,false})for(String mode:List.of("ok","timeout-start","timeout-end","stale","processing","begin-timeout","commit-timeout")){
   Device d=new Device(usb,mode,asset);var engine=new LosslessUploadService(d,d.clock::get,()->d.clock.addAndGet(50_000_000));List<Integer> progress=new ArrayList<>();engine.upload(0,asset,()->{},p->progress.add(p.acknowledgedBytes()));check("one BEGIN",d.begin==1);check("one COMMIT",d.commit==1);check("metadata",d.metadata==1);int previous=-1;for(int n:progress){check("never double credit",n>=previous);previous=n;}check("all encoded",previous==d.encoded.object().length);check("no cleanup",d.cancel==0);
  }
  for(String mode:List.of("unsupported","caps-timeout","wrong-offset","storage","cancel-ok","cancel-unknown","cancel-lost-invalid","commit-mismatch","begin-inactive")){
   Device d=new Device(true,mode,asset);var engine=new LosslessUploadService(d,d.clock::get,()->d.clock.addAndGet(50_000_000));Exception e=reject(mode,()->engine.upload(0,asset,()->{},p->{}));
   if(mode.startsWith("caps")||mode.equals("unsupported"))check("no BEGIN on unknown/unsupported",d.begin==0);
   if(mode.equals("unsupported"))check("typed compatibility only",e instanceof Unsupported);
   if(mode.equals("cancel-unknown")||mode.equals("caps-timeout")||mode.equals("commit-mismatch"))check("uncertainty latched",engine.cleanupUncertain());
   if(mode.equals("storage")||mode.equals("cancel-ok")||mode.equals("cancel-lost-invalid"))check("cancel cleans failure",d.cancel>0&&!engine.cleanupUncertain());
  }
  Device localFailure=new Device(true,"ok",asset);var engine=new LosslessUploadService(localFailure,localFailure.clock::get,()->{});
  reject("beforeCommit fails",()->engine.upload(0,asset,()->{throw new IOException("local persistence failure");},p->{}));
  check("local failure cancelled before commit",localFailure.cancel==1&&localFailure.commit==0&&!engine.cleanupUncertain());
 }
 static void persistence()throws Exception{
  var asset=Asset.fromBytes(canonical(Files.readAllBytes(FIX.resolve("pattern8.cp2"))));var prepared=OledResourceState.empty(0).replace(asset).forUpload(false);var done=prepared.applied();
  check("source CRC distinct",done.device().crc()!=asset.crc());check("same asset",done.asset()==asset);check("metadata stable",done.merge(done.device()).localStatus()==OledResourceState.LocalStatus.APPLIED);
  var store=new OledResourceStore(Files.createTempDirectory("acr4-store"));store.load();store.save(done);var reload=new OledResourceStore(store.root()).load().get(0);check("persistent v4 identity",reload.uploadIdentity().equals(done.uploadIdentity()));check("source bytes preserved",Arrays.equals(reload.asset().bytes(),asset.bytes()));check("reconnect stable",reload.merge(done.device()).localStatus()==OledResourceState.LocalStatus.APPLIED);
  store.save(prepared.committing());var pending=new OledResourceStore(store.root()).load().get(0);check("commit pending recovery exact",pending.merge(done.device()).localStatus()==OledResourceState.LocalStatus.APPLIED);check("oldCRC not commit proof",pending.merge(new OledResourceState.Metadata(true,2,asset.frames(),asset.bytes().length,asset.crc())).localStatus()!=OledResourceState.LocalStatus.APPLIED);
  store.save(OledResourceState.empty(1).replace(asset));check("old records work",new OledResourceStore(store.root()).load().get(1).uploadIdentity()==null);
 }
 static void transport()throws Exception{
  Asset asset=Asset.fromBytes(canonical(Files.readAllBytes(FIX.resolve("pattern8.cp2"))));
  for(boolean usb:new boolean[]{true,false}){
   var ble=new DeviceMaintenanceChecks.FixtureBle();Device device=new Device(usb,"ok",asset);
   java.util.function.Consumer<byte[]> send=req->{try{
    rejectsDuringUpload(ble);
    byte[] r=device.exchange(req,15000),wrong=r.clone();wrong[7]^=1;ble.reply(wrong);wrong=r.clone();wrong[4]=3;ble.reply(wrong);ble.reply(r);
   }catch(Exception e){throw new RuntimeException(e);}};
   if(usb)ble.usb.consumer=send;else{ble.usb.opened=false;DeviceMaintenanceChecks.field(ble,"outputStream",new OutputStream(){public void write(int b){throw new AssertionError();}public void write(byte[] b,int off,int n){check("TCP length",n==3+(b[off+1]&255)+((b[off+2]&255)<<8));send.accept(Arrays.copyOfRange(b,off+3,off+n));}});}
   OledUploadService.uploadResource(ble,0,0,asset,p->{},()->{});check("actual v4 chain "+usb,device.commit==1&&device.metadata==1&&!ble.isDisplayWriteUncertain());
  }
  var ble=new DeviceMaintenanceChecks.FixtureBle();var reset=BleManager.class.getDeclaredMethod("resetDisplaySession");reset.setAccessible(true);
  ble.usb.consumer=req->{try{reset.invoke(ble);}catch(Exception e){throw new RuntimeException(e);}};
  reject("generation stop",()->OledUploadService.uploadResource(ble,0,0,asset,p->{},()->{}));check("no BEGIN on changed device",ble.usb.writes.get()==1);
 }
 static void rejectsDuringUpload(BleManager ble)throws Exception{reject("00 no insertion",()->ble.sendCommand(AhaKeyProtocol.queryDeviceStatus()));reject("mode no insertion",()->ble.sendCommand(AhaKeyProtocol.setWorkMode(1)));}
 public static void main(String[]args)throws Exception{System.setProperty("user.home",Files.createTempDirectory("acr4-check-").toString());((ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)).setLevel(ch.qos.logback.classic.Level.WARN);codec();framing();engines();persistence();transport();System.out.println("PASS ACR4 "+checks+" assertions; offline, no hardware IO");}
}
