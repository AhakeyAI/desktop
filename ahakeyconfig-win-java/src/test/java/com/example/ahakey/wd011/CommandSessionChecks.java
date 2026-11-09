package com.example.ahakey.wd011;

import com.example.ahakey.service.*;import com.example.ahakey.protocol.*;import com.example.ahakey.model.*;import com.example.ahakey.firmware.DeviceMaintenanceChecks;
import java.io.*;import java.lang.reflect.*;import java.nio.file.*;import java.util.*;import java.util.concurrent.*;import java.util.concurrent.atomic.*;import java.util.concurrent.locks.ReentrantLock;

public final class CommandSessionChecks {
 static int checks;static final byte[] STATUS=HexFormat.of().parseHex("AABB005832010000010023CCDD");
 static void check(String s,boolean b){if(!b)throw new AssertionError(s);checks++;System.out.println("PASS "+s);}
 interface Action{void run()throws Exception;}
 static void rejects(String s,Action a)throws Exception{try{a.run();throw new AssertionError(s);}catch(AssertionError e){throw e;}catch(Exception e){checks++;}}
 static Object get(Object o,String n)throws Exception{var f=BleManager.class.getDeclaredField(n);f.setAccessible(true);return f.get(o);}
 static void invoke(Object o,String n)throws Exception{var m=BleManager.class.getDeclaredMethod(n);m.setAccessible(true);m.invoke(o);}
 static byte[] ack(int opcode,int status){return new byte[]{(byte)0xaa,(byte)0xbb,(byte)opcode,(byte)status,(byte)0xcc,(byte)0xdd};}
 static void deliver(DeviceMaintenanceChecks.FixtureBle b,byte[] f){try{b.reply(f);}catch(Exception e){throw new RuntimeException(e);}}
 static void waitFor(Callable<Boolean> b)throws Exception{long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(3);while(!b.call()){if(System.nanoTime()>end)throw new AssertionError("wait timed out");Thread.sleep(5);}}
 static void initialRequest()throws Exception{
  var b=new DeviceMaintenanceChecks.FixtureBle();CountDownLatch started=new CountDownLatch(1),acquired=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();
  b.usb.consumer=req->started.countDown();b.sendCommand(AhaKeyProtocol.queryDeviceStatus());check("ordinary physically sent",started.getCount()==0);
  Thread upload=new Thread(()->{try(var lease=b.openDisplayLease(true,0)){acquired.countDown();}catch(Throwable e){error.set(e);}},"upload-waits-ordinary");upload.start();
  Thread.sleep(100);check("upload waits on existing00",acquired.getCount()==1&&b.usb.writes.get()==1);deliver(b,ack(0,0));Thread.sleep(30);check("six-byte00 cannot release",acquired.getCount()==1);
  deliver(b,STATUS);upload.join(2000);check("13byte00 opens upload",!upload.isAlive()&&error.get()==null&&acquired.getCount()==0);
 }
 static void uploadIsolation()throws Exception{
  var b=new DeviceMaintenanceChecks.FixtureBle();var output=new ByteArrayOutputStream();DeviceMaintenanceChecks.field(b,"outputStream",output);
  var packet=BleManager.class.getDeclaredMethod("writePacket",byte.class,byte[].class);packet.setAccessible(true);
  var usb=BleManager.class.getDeclaredMethod("sendUsbCommand",byte[].class);usb.setAccessible(true);
  try(var lease=b.openDisplayLease(true,0)){
   rejects("same-thread00 rejected",()->b.sendCommand(AhaKeyProtocol.queryDeviceStatus()));
   rejects("direct USB rejected",()->usb.invoke(b,(Object)AhaKeyProtocol.queryDeviceStatus()));
   rejects("snapshot rejected",()->b.queryDeviceStatusSnapshot(20,true));
   rejects("mode status rejected",()->invoke(b,"requestModeReadbackStatus"));
   rejects("direct TCP rejected",()->packet.invoke(b,BleTcpPacket.WRITE_COMMAND,AhaKeyProtocol.queryDeviceStatus()));
   rejects("data rejected",()->b.writeData(new byte[4]));rejects("mode rejected",()->b.sendCommand(AhaKeyProtocol.setWorkMode(2)));
   check("runtime not queued",!b.sendRuntimeState((byte)1));b.queryStatus();
   packet.invoke(b,BleTcpPacket.QUERY_BLE_STATUS,null);packet.invoke(b,BleTcpPacket.QUERY_DEVICE_INFO,null);check("local bridge queries live",output.size()>0);
   check("no physical USB leak",b.usb.writes.get()==0);check("rejected attempt not UNKNOWN",!((CommandSessionArbiter)get(b,"commandSession")).uncertain());
   b.usb.consumer=req->deliver(b,ack(req[2],0));OledUploadService.requireAck(b.exchangeDisplay(lease,AhaKeyProtocol.resourceChunk(0,74880,new byte[48])),(byte)0x8b);
  }
  check("release no stale runtime",b.usb.writes.get()==1);
 }
 static void unknownAndGeneration()throws Exception{
  var b=new DeviceMaintenanceChecks.FixtureBle();AtomicLong clock=new AtomicLong();var arbiter=new CommandSessionArbiter(clock::get,100);DeviceMaintenanceChecks.field(b,"commandSession",arbiter);
  b.sendCommand(AhaKeyProtocol.queryDeviceStatus());clock.set(101);rejects("ordinary timeout blocks upload",()->b.openDisplayLease(true,0));deliver(b,STATUS);rejects("late00 never clears UNKNOWN",()->b.sendCommand(AhaKeyProtocol.queryDeviceStatus()));
  invoke(b,"resetDisplaySession");DeviceMaintenanceChecks.field(b,"firmwareIdentity",new BleManager.FirmwareIdentity(b.connectionGeneration(),2,DeviceStatus.IdentityState.SUPPORTED,"X1-C582-HW1-P1-1.0.0-R002"));
  try(var lease=b.openDisplayLease(true,b.connectionGeneration())){check("new generation clears unknown",true);}
 }
 static void twoConsumers()throws Exception{
  var b=new DeviceMaintenanceChecks.FixtureBle();CountDownLatch firstSent=new CountDownLatch(1),secondSent=new CountDownLatch(1);AtomicInteger sent=new AtomicInteger();AtomicReference<Throwable> error=new AtomicReference<>();
  b.usb.consumer=req->{if(sent.incrementAndGet()==1)firstSent.countDown();else {secondSent.countDown();deliver(b,ack(4,0));}};
  Thread a=new Thread(()->{try{b.sendCommandExpecting(AhaKeyProtocol.saveConfig(),(byte)4);}catch(Throwable e){error.set(e);}},"consumer-A");
  Thread c=new Thread(()->{try{b.sendCommandExpecting(AhaKeyProtocol.saveConfig(),(byte)4);}catch(Throwable e){error.set(e);}},"consumer-B");
  a.start();check("first sync send",firstSent.await(2,TimeUnit.SECONDS));c.start();Thread.sleep(50);
  ReentrantLock lock=(ReentrantLock)get(b,"commandLock");lock.lock();try{deliver(b,ack(4,0));rejects("fire-forget cannot steal settled ACK window",()->b.sendCommand(AhaKeyProtocol.saveConfig()));check("second did not clear first ACK",secondSent.getCount()==1);}finally{lock.unlock();}
  a.join(2000);c.join(2000);check("two same-opcode consumers finish",!a.isAlive()&&!c.isAlive()&&error.get()==null&&sent.get()==2);
 }
 static void asyncThenSameOpcodeConsumer()throws Exception{
  var b=new DeviceMaintenanceChecks.FixtureBle();AtomicInteger sends=new AtomicInteger();AtomicReference<Throwable> error=new AtomicReference<>();CountDownLatch second=new CountDownLatch(1),finished=new CountDownLatch(1);
  b.usb.consumer=req->{if(sends.incrementAndGet()==2)second.countDown();};b.sendCommand(AhaKeyProtocol.saveConfig());
  Thread sync=new Thread(()->{try{b.sendCommandExpecting(AhaKeyProtocol.saveConfig(),(byte)4);}catch(Throwable e){error.set(e);}finally{finished.countDown();}},"sync-after-async");sync.start();Thread.sleep(30);deliver(b,ack(4,0));check("second same opcode sent",second.await(2,TimeUnit.SECONDS));Thread.sleep(30);check("old async ACK not consumed as new",finished.getCount()==1);deliver(b,ack(4,0));sync.join(2000);check("new ACK completes",!sync.isAlive()&&error.get()==null);
 }
 static final class RawUsb extends UsbHidTransport {
  final DeviceMaintenanceChecks.FixtureBle b;final CountDownLatch prepare=new CountDownLatch(1),data=new CountDownLatch(1);int dataBytes;final List<Integer> opcodes=new CopyOnWriteArrayList<>();
  RawUsb(DeviceMaintenanceChecks.FixtureBle b){this.b=b;}public boolean isOpen(){return true;}public String devicePath(){return "fixture";}public void sendCommand(byte[] f){opcodes.add(f[2]&255);if((f[2]&255)==0x80)prepare.countDown();}public void sendData(byte[] f){dataBytes+=f.length;data.countDown();}public void close(){}
 }
 static void rawTransaction()throws Exception{
  var b=new DeviceMaintenanceChecks.FixtureBle();var usb=new RawUsb(b);DeviceMaintenanceChecks.field(b,"usbTransport",usb);AtomicReference<Throwable> error=new AtomicReference<>();Thread raw=new Thread(()->{try{b.writeLargeData(0,new byte[4096]);}catch(Throwable e){error.set(e);}},"raw-writer");raw.start();check("80 sent",usb.prepare.await(2,TimeUnit.SECONDS));
  ReentrantLock lock=(ReentrantLock)get(b,"commandLock");lock.lock();try{deliver(b,ack(0x80,0));rejects("00 barred between80ACK andDATA",()->b.sendCommand(AhaKeyProtocol.queryDeviceStatus()));}finally{lock.unlock();}
  check("whole raw block sent",usb.data.await(2,TimeUnit.SECONDS)&&usb.dataBytes==4096);rejects("00 barred while81 pending",()->b.sendCommand(AhaKeyProtocol.queryDeviceStatus()));deliver(b,ack(0x81,0));raw.join(2000);check("raw ends only at81",!raw.isAlive()&&error.get()==null);
 }
 static void waitingAdmissionRecheck()throws Exception{
  var b=new DeviceMaintenanceChecks.FixtureBle();var usb=new RawUsb(b);DeviceMaintenanceChecks.field(b,"usbTransport",usb);b.sendCommand(AhaKeyProtocol.queryDeviceStatus());
  AtomicInteger rejected=new AtomicInteger();AtomicReference<Throwable> error=new AtomicReference<>();
  Thread waiting=new Thread(()->{try{b.sendCommand(AhaKeyProtocol.updateState((byte)1));}catch(IOException e){rejected.incrementAndGet();}},"already-waiting-ordinary");waiting.start();waitFor(()->waiting.getState()==Thread.State.TIMED_WAITING);
  Thread raw=new Thread(()->{try{b.writeLargeData(0,new byte[4096]);}catch(Throwable e){error.set(e);}},"new-raw-owner");raw.start();waitFor(()->get(b,"rawWriteOwner")==raw);
  deliver(b,STATUS);check("raw allowed after initial status",usb.prepare.await(2,TimeUnit.SECONDS));deliver(b,ack(0x80,0));check("new raw data",usb.data.await(2,TimeUnit.SECONDS));deliver(b,ack(0x81,0));waiting.join(2000);raw.join(2000);
  check("queued ordinary rechecks new raw ownership",rejected.get()==1&&!usb.opcodes.contains(0x90)&&error.get()==null&&!raw.isAlive()&&!waiting.isAlive());
  check("admission rejection never poisons writer",!((CommandSessionArbiter)get(b,"commandSession")).uncertain());
 }
 static void k1FullWrite()throws Exception{
  int token=0x1234abcd;byte[] request=K1RouteProtocol.request(0x20,K1RouteProtocol.fields(11).put((byte)2).putShort((short)102).putInt(77).putInt(token).array());
  var arbiter=new CommandSessionArbiter();arbiter.reset(0);arbiter.sent(request);
  check("K1 BEGIN wrong nonce remains pending",!arbiter.receive(K1RouteProtocolChecks.response(0x20,0,K1RouteProtocol.fields(10).putInt(token+1).putInt(token+1).putShort((short)0).array()),0)&&arbiter.pending());
  check("K1 BEGIN nonce is after selector length CRC",arbiter.receive(K1RouteProtocolChecks.response(0x20,0,K1RouteProtocol.fields(10).putInt(token).putInt(token).putShort((short)0).array()),0));
  var callback=new BleManager.BleCallback(){public void onConnected(){}public void onDisconnected(){}public void onStatusReceived(DeviceStatus s){}public void onError(String s){}};
  for(boolean fail:List.of(false,true)){
   var wire=new K1RouteProtocolChecks.Wire(callback);wire.failBegin=fail;var studio=new StudioState();var service=new K1RouteService(studio,wire);
   var write=K1RouteService.class.getDeclaredMethod("write",K1RouteService.Edit.class,long.class);write.setAccessible(true);
   var route=K1Route.ordinary(0x73,new byte[]{4,5});var edit=new K1RouteService.Edit(2,0,route,"saved",true);
   try{
    Action save=()->wire.k1RouteTransaction(0,()->{try{write.invoke(service,edit,0L);return null;}catch(InvocationTargetException e){throw (Exception)e.getCause();}});
    if(fail){rejects("K1 explicit BEGIN failure delivered",save);check("K1 failure no CHUNK or COMMIT",wire.frames.stream().noneMatch(f->f[2]==(byte)0x9e&&(f[4]==0x21||f[4]==0x22)));}
    else {save.run();check("K1 real write BEGIN chunks COMMIT readback",wire.begins==1&&wire.commits==1&&wire.routes[2].equals(route)&&wire.frames.stream().filter(f->f[2]==(byte)0x9e&&f[4]==0x21).count()==3);check("K1 nested description SAVE readback",wire.descriptions[2][0].equals("saved")&&wire.frames.stream().anyMatch(f->f[2]==4)&&wire.frames.stream().anyMatch(f->f[2]==(byte)0x87));}
    check("K1 terminates known after success or explicit fail",!((CommandSessionArbiter)get(wire,"commandSession")).uncertain());
   }finally{service.close();}
  }
 }
 static void syncCompletion()throws Exception{
  for(String scenario:List.of("ok","last-fail","first-fail","last-interrupted")){
   var b=new DeviceMaintenanceChecks.FixtureBle();AtomicInteger count=new AtomicInteger(),completed=new AtomicInteger(),errors=new AtomicInteger();CountDownLatch done=new CountDownLatch(1),lastPending=new CountDownLatch(1);AtomicReference<Thread> writer=new AtomicReference<>();
   b.usb.consumer=req->{writer.set(Thread.currentThread());int n=count.incrementAndGet();if(n==2&&scenario.equals("last-interrupted")){lastPending.countDown();return;}deliver(b,ack(req[2],scenario.equals("first-fail")&&n==1||scenario.equals("last-fail")&&n==2?1:0));};
   DeviceSyncService.writeSequentially(b,List.of(new DeviceSyncService.LabeledCommand(AhaKeyProtocol.setLightBrightness((byte)10),"first"),new DeviceSyncService.LabeledCommand(AhaKeyProtocol.saveConfig(),"save")),()->{completed.incrementAndGet();done.countDown();},()->{errors.incrementAndGet();done.countDown();},s->{});
   if(scenario.equals("last-interrupted")){check("final pending",lastPending.await(2,TimeUnit.SECONDS));check("no early save success",completed.get()==0);writer.get().interrupt();}
   check("sync callback finishes",done.await(2,TimeUnit.SECONDS));check(scenario+" correct result",scenario.equals("ok")?completed.get()==1&&errors.get()==0:completed.get()==0&&errors.get()==1);
   if(scenario.equals("first-fail"))check("no later save",count.get()==1);
   if(scenario.equals("last-interrupted"))rejects("cancelled ordinary prevents upload",()->b.openDisplayLease(true,0));
  }
 }
 public static void main(String[]args)throws Exception{
  System.setProperty("user.home",Files.createTempDirectory("acr4-session-").toString());k1FullWrite();initialRequest();uploadIsolation();unknownAndGeneration();twoConsumers();asyncThenSameOpcodeConsumer();rawTransaction();waitingAdmissionRecheck();syncCompletion();System.out.println("PASS command session "+checks+" assertions; memory transport only");
 }
}
