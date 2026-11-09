package com.example.ahakey.wd011;

import com.example.ahakey.service.*;
import com.example.ahakey.protocol.*;
import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.firmware.DeviceMaintenanceChecks;
import java.io.*;import java.lang.reflect.*;import java.nio.file.*;import java.util.*;import java.util.concurrent.*;import java.util.concurrent.atomic.*;

/** The status packet is captured from extracted production C# OnBleNotify over a real loopback socket. */
public final class BleStatusRecoveryChecks {
 static int checks;static byte[] status;
 static void check(String name,boolean value){if(!value)throw new AssertionError(name);checks++;System.out.println("PASS "+name);}
 interface Task{void run()throws Exception;}
 static void rejects(String name,Task action)throws Exception{try{action.run();throw new AssertionError(name);}catch(AssertionError e){throw e;}catch(Exception expected){checks++;}}
 static Object get(Object value,String name)throws Exception{var f=BleManager.class.getDeclaredField(name);f.setAccessible(true);return f.get(value);}
 static void reset(BleManager b)throws Exception{var m=BleManager.class.getDeclaredMethod("resetDisplaySession");m.setAccessible(true);m.invoke(b);DeviceMaintenanceChecks.field(b,"firmwareIdentity",new BleManager.FirmwareIdentity(b.connectionGeneration(),2,DeviceStatus.IdentityState.SUPPORTED,"X1-C582-HW1-P1-1.0.0-R002"));}
 static void packet(BleManager b,long generation,byte type,byte[] data)throws Exception{var m=BleManager.class.getDeclaredMethod("handleSessionPacket",long.class,byte.class,byte[].class);m.setAccessible(true);m.invoke(b,generation,type,data);}
 static final class Callback implements BleManager.BleCallback {final List<String> errors=new CopyOnWriteArrayList<>();public void onConnected(){}public void onDisconnected(){}public void onStatusReceived(DeviceStatus s){}public void onError(String s){errors.add(s);}}
 static final class Fixture {
  final Callback cb=new Callback();final DeviceMaintenanceChecks.FixtureBle ble;final List<byte[]> writes=new CopyOnWriteArrayList<>();final AtomicLong clock=new AtomicLong();final CommandSessionArbiter arbiter=new CommandSessionArbiter(clock::get,15_000_000_000L);boolean answer;
  Fixture()throws Exception{ble=new DeviceMaintenanceChecks.FixtureBle(cb);ble.usb.opened=false;DeviceMaintenanceChecks.field(ble,"commandSession",arbiter);DeviceMaintenanceChecks.field(ble,"outputStream",new ByteArrayOutputStream(){public synchronized void write(byte[] p)throws IOException{writes.add(p.clone());if(answer&&p[0]==BleTcpPacket.WRITE_COMMAND){try{packet(ble,ble.connectionGeneration(),BleTcpPacket.BLE_NOTIFY,status);}catch(Exception e){throw new IOException(e);}}}});}
  long commands(){return writes.stream().filter(p->p[0]==BleTcpPacket.WRITE_COMMAND).count();}
  void raw()throws Exception{packet(ble,ble.connectionGeneration(),BleTcpPacket.BLE_NOTIFY,status);}
 }
 static void shortWaitThenReply()throws Exception{
  var f=new Fixture();long start=System.nanoTime();rejects("business read times out",()->f.ble.queryDeviceStatusSnapshot(500,true));
  check("business budget approximately500ms",TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-start)>=480);
  check("own request pending but known after business timeout",f.arbiter.pending()&&!f.arbiter.uncertain()&&f.commands()==1);
  for(int i=0;i<3;i++)f.ble.queryStatus();check("poll does not resend pending00 or report permanent failure",f.commands()==1&&f.cb.errors.isEmpty());
  AtomicBoolean acquired=new AtomicBoolean();AtomicReference<Throwable> error=new AtomicReference<>();Thread upload=new Thread(()->{try(var lease=f.ble.openDisplayLease(true,0)){acquired.set(true);}catch(Throwable t){error.set(t);}});upload.start();Thread.sleep(50);
  check("upload cannot overtake short-wait pending",!acquired.get());
  packet(f.ble,0,BleTcpPacket.DEVICE_INFO_RESP,Arrays.copyOfRange(status,3,11));check("bridge cached info never completes pending",f.arbiter.pending());
  packet(f.ble,-1,BleTcpPacket.BLE_NOTIFY,status);check("old generation cannot complete pending",f.arbiter.pending());
  packet(f.ble,0,BleTcpPacket.BLE_NOTIFY,new byte[]{(byte)0xaa,(byte)0xbb,0,0,(byte)0xcc,(byte)0xdd});check("wrong status shape cannot complete pending",f.arbiter.pending());
  packet(f.ble,0,BleTcpPacket.BLE_NOTIFY,new byte[]{(byte)0xaa,(byte)0xbb,4,0,(byte)0xcc,(byte)0xdd});check("wrong opcode cannot complete pending",f.arbiter.pending());
  Thread.sleep(150);f.clock.set(700_000_000L);f.raw();upload.join(2000);
  check("700ms actual bridge packet settles original then permits upload",!upload.isAlive()&&acquired.get()&&error.get()==null&&!f.arbiter.pending()&&!f.arbiter.uncertain());
  check("no duplicated physical status request",f.commands()==1);
 }
 static void cacheOnlyTransportTimeout()throws Exception{
  var f=new Fixture();rejects("short cache-only query returns",()->f.ble.queryDeviceStatusSnapshot(30,true));packet(f.ble,0,BleTcpPacket.DEVICE_INFO_RESP,Arrays.copyOfRange(status,3,11));
  f.clock.set(15_000_000_001L);for(int i=0;i<5;i++)f.ble.queryStatus();check("true transport deadline UNKNOWN",f.arbiter.uncertain());check("UNKNOWN reports once and no background device writes",f.cb.errors.size()==1&&f.commands()==1);
  f.raw();check("late00 cannot undo UNKNOWN",f.arbiter.uncertain());for(int i=0;i<3;i++)f.ble.queryStatus();check("late cache/raw never resets error dedup",f.cb.errors.size()==1&&f.commands()==1);
  rejects("UNKNOWN blocks upload",()->f.ble.openDisplayLease(true,0));reset(f.ble);f.answer=true;f.ble.queryStatus();check("new generation restores physical querying",f.commands()==2&&!f.arbiter.pending()&&!f.arbiter.uncertain());
  f.answer=false;f.ble.queryStatus();f.clock.addAndGet(15_000_000_001L);f.ble.queryStatus();f.ble.queryStatus();check("new generation may report a new failure once",f.cb.errors.size()==2);
 }
 static void waitingCallerCannotPoisonOwner()throws Exception{
  var f=new Fixture();f.ble.sendCommand(AhaKeyProtocol.saveConfig());AtomicReference<Throwable> result=new AtomicReference<>();Thread caller=new Thread(()->{try{f.ble.queryDeviceStatusSnapshot(500,true);}catch(Throwable t){result.set(t);}});caller.start();Thread.sleep(100);caller.interrupt();caller.join(2000);
  check("interrupted admission did not send00",!caller.isAlive()&&result.get()!=null&&f.commands()==1);check("other04 retains owner/deadline without UNKNOWN",f.arbiter.pending()&&!f.arbiter.uncertain());packet(f.ble,0,BleTcpPacket.BLE_NOTIFY,new byte[]{(byte)0xaa,(byte)0xbb,4,0,(byte)0xcc,(byte)0xdd});check("original04 still settles",!f.arbiter.pending()&&!f.arbiter.uncertain());
 }
 static void directFailureStillIsolates()throws Exception{
  var f=new Fixture();DeviceMaintenanceChecks.field(f.ble,"outputStream",new OutputStream(){public void write(int b)throws IOException{throw new IOException("physical write failure");}});rejects("short00 write failure is not business expiration",()->f.ble.queryDeviceStatusSnapshot(500,true));check("write failure still UNKNOWN",f.arbiter.uncertain());
  var g=new Fixture();AtomicReference<Throwable> error=new AtomicReference<>();Thread t=new Thread(()->{try{g.ble.queryDeviceStatusSnapshot(500,true);}catch(Throwable e){error.set(e);}});t.start();while(g.commands()==0)Thread.sleep(2);t.interrupt();t.join(2000);check("interrupted sent read remains UNKNOWN",error.get()!=null&&g.arbiter.uncertain());
 }
 static void sameGenerationLaterRequestWaits()throws Exception{
  var f=new Fixture();rejects("first read business exit",()->f.ble.queryDeviceStatusSnapshot(30,true));AtomicReference<Throwable> error=new AtomicReference<>();Thread other=new Thread(()->{try{f.ble.sendCommandExpecting(AhaKeyProtocol.saveConfig(),(byte)4);}catch(Throwable t){error.set(t);}});other.start();Thread.sleep(50);check("next physical request waits original00",f.commands()==1);f.raw();long end=System.nanoTime()+2_000_000_000L;while(f.commands()<2&&System.nanoTime()<end)Thread.sleep(2);check("next04 sends only after00 settlement",f.commands()==2);packet(f.ble,0,BleTcpPacket.BLE_NOTIFY,new byte[]{(byte)0xaa,(byte)0xbb,4,0,(byte)0xcc,(byte)0xdd});other.join(2000);check("next consumer gets its own response",!other.isAlive()&&error.get()==null);
 }
 static void consecutiveStatusConsumers()throws Exception{
  var f=new Fixture();rejects("first00 business budget",()->f.ble.queryDeviceStatusSnapshot(30,true));AtomicReference<DeviceStatus> result=new AtomicReference<>();AtomicReference<Throwable> error=new AtomicReference<>();
  Thread next=new Thread(()->{try{result.set(f.ble.queryDeviceStatusSnapshot(500,true));}catch(Throwable t){error.set(t);}});next.start();Thread.sleep(50);check("second00 not sent while first pending",f.commands()==1);f.raw();long end=System.nanoTime()+2_000_000_000L;while(f.commands()<2&&System.nanoTime()<end)Thread.sleep(2);check("first00 response only permits second00 send",f.commands()==2);Thread.sleep(50);check("second00 cannot consume first00 queued response",next.isAlive()&&result.get()==null);
  byte[] second=status.clone();second[3]=78;packet(f.ble,0,BleTcpPacket.BLE_NOTIFY,second);next.join(2000);check("second00 receives only its own fresh value",!next.isAlive()&&error.get()==null&&result.get()!=null&&result.get().getBatteryLevel()==78);
 }
 static void generationDuringWait()throws Exception{
  var f=new Fixture();AtomicReference<Throwable> error=new AtomicReference<>();Thread reader=new Thread(()->{try{f.ble.queryDeviceStatusSnapshot(500,true);}catch(Throwable t){error.set(t);}});reader.start();while(f.commands()==0)Thread.sleep(2);reset(f.ble);packet(f.ble,0,BleTcpPacket.BLE_NOTIFY,status);reader.join(2000);check("old waiter fails without poisoning new generation",!reader.isAlive()&&error.get()!=null&&!f.arbiter.uncertain()&&!f.arbiter.pending());f.answer=true;check("new connection has fresh status success",f.ble.queryDeviceStatusSnapshot(500,true).getBatteryLevel()==77);
 }
 public static void main(String[]args)throws Exception{
  System.setProperty("user.home",Files.createTempDirectory("ble-status-check-").toString());byte[] wire=Files.readAllBytes(Path.of(args[0]));check("actual CSharp packet envelope",wire.length==16&&wire[0]==BleTcpPacket.BLE_NOTIFY&&wire[1]==13&&wire[2]==0);status=Arrays.copyOfRange(wire,3,wire.length);check("actual CSharp status valid",AhaKeyProtocol.parseDeviceStatus(status)!=null);
  shortWaitThenReply();cacheOnlyTransportTimeout();waitingCallerCannotPoisonOwner();directFailureStillIsolates();sameGenerationLaterRequestWaits();consecutiveStatusConsumers();generationDuringWait();System.out.println("PASS BLE status recovery "+checks+" assertions; actual CSharp captured packet through real Java TCP handling, memory device only");
 }
}
