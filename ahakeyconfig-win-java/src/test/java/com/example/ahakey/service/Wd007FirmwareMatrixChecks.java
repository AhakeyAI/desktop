package com.example.ahakey.service;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.*;
import com.example.ahakey.model.connection.DeviceTarget;
import com.example.ahakey.protocol.*;
import com.example.ahakey.service.connection.*;
import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.node.ObjectNode;
import javafx.application.Platform;
import java.io.*;
import java.net.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;
import static com.example.ahakey.service.Wd007BehaviorChecks.*;

/** Candidate command_solve.c shapes: 9F,87,97,88,95,9E. BLE uses real private IPC framing. No HID/GATT. */
public final class Wd007FirmwareMatrixChecks {
    static final ObjectMapper JSON=new ObjectMapper();
    static <T>T fx(Callable<T> call)throws Exception{FutureTask<T> task=new FutureTask<>(call);Platform.runLater(task);return task.get(8,TimeUnit.SECONDS);}
    static Object get(Object object,String name)throws Exception{Class<?> type=object.getClass();while(type!=null){try{var f=type.getDeclaredField(name);f.setAccessible(true);return f.get(object);}catch(NoSuchFieldException e){type=type.getSuperclass();}}throw new NoSuchFieldException(name);}
    static void event(BleManager ble,JsonNode event)throws Exception{var m=BleManager.class.getDeclaredMethod("managedEvent",JsonNode.class);m.setAccessible(true);m.invoke(ble,event);}
    static String authority(BleManager ble)throws Exception{var m=BleManager.class.getDeclaredMethod("bridgeSelectionAuthority");m.setAccessible(true);return (String)m.invoke(ble);}
    static final class Firmware {
        final String key; final List<byte[]> requests=new CopyOnWriteArrayList<>();
        volatile boolean dropIdentity; volatile int metadataState;
        int sleep=5,mode=0,brightness=35;byte[] action={4};
        final byte[] route=K1Route.ordinary(0x73,new byte[]{4}).bytes();
        byte[] routeStage=new byte[102],resource=new byte[0];long routeCrc,resourceCrc;int resourceAt,resourceFrames,resourceEntry;boolean committed;
        byte[] sideReply={0,0,2,2,0,2,0};
        Firmware(String key){this.key=key;}
        synchronized byte[] answer(byte[] f){
            requests.add(f.clone());int op=f[2]&255;byte[] p={0};
            if(op==0x9F){if(dropIdentity)return null;p=key.isEmpty()?new byte[]{0}:("\0"+key).getBytes(java.nio.charset.StandardCharsets.US_ASCII);}
            else if(op==0)p=new byte[]{80,1,1,0,(byte)mode,0,0,(byte)brightness};
            else if(op==0x95){if(f.length==7)sleep=(f[3]&255)|((f[4]&255)<<8);else p=new byte[]{0,(byte)sleep,(byte)(sleep>>8)};}
            else if(op==0x92)mode=f[3]&255;
            else if(op==0x85)brightness=f[3]&255;
            else if(op==0x73 && f[3]==0x73)action=Arrays.copyOfRange(f,6,f.length-2);
            else if(!key.isEmpty()) {
                if(op==0x8E && f[3]==0)brightness=f[4]&255;
                if(op==0x8A){var b=ByteBuffer.wrap(f).order(ByteOrder.LITTLE_ENDIAN);resourceEntry=f[3]&255;resource=new byte[b.getInt(4)];resourceFrames=b.getShort(8)&65535;resourceCrc=Integer.toUnsignedLong(b.getInt(10));resourceAt=0;committed=false;}
                if(op==0x8B){int at=ByteBuffer.wrap(f).order(ByteOrder.LITTLE_ENDIAN).getInt(4),n=f[8]&255;check(at==resourceAt,"OLED chunk contiguous offset");System.arraycopy(f,9,resource,at,n);resourceAt+=n;}
                if(op==0x8C){check(resourceAt==resource.length&&K1RouteProtocol.crc(resource)==resourceCrc,"OLED complete byte stream CRC");committed=true;}
                if(op==0x87){p=new byte[6+action.length];p[1]=f[3];p[2]=f[4];p[3]=0x73;p[4]=(byte)action.length;System.arraycopy(action,0,p,5,action.length);}
                if(op==0x97){if(f.length==5)p=sideReply;else{sideReply=new byte[f.length-3];sideReply[1]=0;sideReply[2]=2;System.arraycopy(f,4,sideReply,3,f.length-6);}}
                if(op==0x88){int kind=f[3]&255;boolean valid=committed&&(f[4]&255)==resourceEntry&&metadataState==0;
                    p=switch(kind){case 0->new byte[]{0,0,(byte)brightness};case 1->new byte[]{0,1,f[4],f[5],1};case 2->new byte[]{0,2,f[4],(byte)(valid?1:0),(byte)(valid?2:metadataState)};case 3->K1RouteProtocol.fields(13).put((byte)0).put((byte)3).put(f[4]).putShort((short)(valid?resourceFrames:0)).putInt(valid?resource.length:0).putInt(valid?(int)resourceCrc:0).array();default->new byte[]{1};};}
                if(op==0x9E){
                    int sub=f[4]&255;var input=ByteBuffer.wrap(f).order(ByteOrder.LITTLE_ENDIAN);int nonce=input.getInt(5);
                    if(sub==0)p=K1RouteProtocol.fields(9).put((byte)0).put((byte)1).put((byte)0).putInt(nonce).put((byte)3).put((byte)4).array();
                    else if(sub==0x10){int offset=f[10]&255,count=f[11]&255;p=K1RouteProtocol.fields(15+count).put((byte)0).put((byte)1).put((byte)sub).putInt(nonce).put(f[9]).put((byte)offset).putShort((short)102).putInt((int)K1RouteProtocol.crc(route)).put(route,offset,count).array();}
                    else if(sub==0x20){int token=input.getInt(12);routeStage=new byte[102];routeCrc=Integer.toUnsignedLong(input.getInt(8));p=K1RouteProtocol.fields(13).put((byte)0).put((byte)1).put((byte)sub).putInt(token).putInt(token).putShort((short)0).array();}
                    else if(sub==0x21){int offset=input.getShort(10)&65535,count=f[12]&255;System.arraycopy(f,13,routeStage,offset,count);p=K1RouteProtocol.fields(11).put((byte)0).put((byte)1).put((byte)sub).putInt(nonce).put(f[9]).putShort((short)(offset+count)).put((byte)count).array();}
                    else if(sub==0x22){check(K1RouteProtocol.crc(routeStage)==routeCrc,"K1 staged CRC validated");System.arraycopy(routeStage,0,route,0,102);p=K1RouteProtocol.fields(12).put((byte)0).put((byte)1).put((byte)sub).putInt(nonce).put(f[9]).putInt((int)routeCrc).array();}
                }
            }
            return AhaKeyProtocol.buildFrame(f[2],p);
        }
        long count(int op){return requests.stream().filter(f->(f[2]&255)==op).count();}
    }
    static final class Fixture extends BleManager implements AutoCloseable {
        final Firmware firmware;final boolean ble;volatile List<String> usb;
        Socket peer;ServerSocket listener;Thread server;volatile String session="",target="",generation="";long sequence;
        final List<String> operations=new CopyOnWriteArrayList<>();
        Fixture(String key,boolean ble,BleCallback callback)throws Exception{
            super(callback);this.firmware=new Firmware(key);this.ble=ble;usb=ble?List.of():List.of("A");
            if(ble){
                var client=(ManagedBridgeClient)get(this,"managedBridge");listener=new ServerSocket(0,1,InetAddress.getLoopbackAddress());
                var socket=new Socket("127.0.0.1",listener.getLocalPort());peer=listener.accept();
                var attach=ManagedBridgeClient.class.getDeclaredMethod("attach",Socket.class);attach.setAccessible(true);attach.invoke(client,socket);
                Object connection=get(client,"connection");var instance=connection.getClass().getDeclaredField("instance");instance.setAccessible(true);instance.set(connection,"fixture");
                client.onEvent(value->{try{event(this,value);}catch(Exception e){throw new RuntimeException(e);}});
                server=new Thread(this::serve);server.setDaemon(true);server.start();
            }
        }
        protected List<String> usbCandidates(){return usb;}
        protected UsbHidTransport createUsbTransport(){return new UsbHidTransport(){boolean open;Consumer<byte[]> receive;String id;
            public void openExact(String path,Consumer<byte[]> consumer){open=true;receive=consumer;id=path;}
            public boolean isOpen(){return open;}public String devicePath(){return id;}public void close(){open=false;}
            public void sendCommand(byte[] f){byte[] reply=firmware.answer(f);if(reply!=null)receive.accept(reply);}
        };}
        public void queryStatus(){} // Test explicitly invokes actual status read.
        synchronized void send(int kind,ObjectNode node)throws Exception{byte[] bytes=JSON.writeValueAsBytes(node);var out=peer.getOutputStream();out.write(kind);out.write(bytes.length&255);out.write(bytes.length>>8);out.write(bytes);out.flush();}
        void serve(){try{var input=new DataInputStream(peer.getInputStream());while(!peer.isClosed()){
            if(input.readUnsignedByte()!=0x10)throw new IOException("envelope");int length=input.readUnsignedByte()|(input.readUnsignedByte()<<8);JsonNode request=JSON.readTree(input.readNBytes(length));
            var reply=ManagedBridgeClient.fields().put("version",1).put("bridgeInstanceId","fixture").put("requestId",request.path("requestId").asText()).put("ok",true);
            byte[] notify=null;
            operations.add(request.path("op").asText());
            switch(request.path("op").asText()){
                case "enumerateConnected"->{reply.put("snapshotId","snapshot");var array=reply.putArray("candidates");for(String id:List.of("A","B"))array.addObject().put("targetId",id).put("name","AhaKey").put("address","MAC-"+id);}
                case "connect"->{target=request.path("targetId").asText();generation=request.path("clientGeneration").asText();session="session-"+target+"-"+generation;reply.put("sessionId",session);}
                case "disconnect"->{session="";reply.put("revoked",true);}
                case "write"->{check(session.equals(request.path("sessionId").asText())&&generation.equals(request.path("clientGeneration").asText()),"BLE write owns exact session/generation");notify=firmware.answer(Base64.getDecoder().decode(request.path("bytes").asText()));}
                default->{}
            }
            send(0x90,reply);
            if(notify!=null)send(0x91,ManagedBridgeClient.fields().put("version",1).put("bridgeInstanceId","fixture").put("eventSeq",++sequence).put("event","notify").put("sessionId",session).put("targetId",target).put("clientGeneration",generation).put("bytes",Base64.getEncoder().encodeToString(notify)));
        }}catch(EOFException|SocketException end){}catch(Exception error){error.printStackTrace();}}
        void connectA()throws Exception{connectSelected(new DeviceTarget(ble?"BLE":"USB","A","AhaKey"));await(()->!isScanning()&&isConnected(),"configuration session opens");}
        public void close()throws Exception{shutdownTransport();if(peer!=null)peer.close();if(listener!=null)listener.close();}
    }
    static void matrix(String key,boolean bluetooth)throws Exception{
        System.setProperty("user.home",Files.createTempDirectory("r6-matrix-").toString());
        try(var f=new Fixture(key,bluetooth,CALLBACK)){
            String emptyAuthority=authority(f);
            f.connectA();check(f.readFirmwareCatalogKey().equals(key),"identity matches exact profile");
            check(f.queryDeviceStatusSnapshot(1000,true).getBatteryLevel()==80,"status parsed");
            check(f.setSleepWaitTimeMinutesAndVerify(30)==30,"sleep save and actual readback");
            check(f.setWorkModeAndVerify(2)==2,"mode save plus status confirmation");
            if(key.isEmpty()){
                check(f.capabilities().legacyWrites()&&!f.isDisplayAdmitted(),"legacy ACK grants only historical writes");
                try{f.readOrdinaryKeyConfig(0,0);throw new AssertionError("legacy gained87");}catch(IOException expected){checks++;}
                try{f.readSideSwitchConfig();throw new AssertionError("legacy gained97");}catch(IOException expected){checks++;}
                try{f.openDisplayLease(true);throw new AssertionError("legacy gained88");}catch(IOException expected){checks++;}
                CountDownLatch saved=new CountDownLatch(1);boolean[] failure={false};
                var state=new StudioState();state.getKeyConfig(StudioPart.KEY1).setHidCode(6);
                DeviceSyncService.writeSequentially(f,DeviceSyncService.commandsForModes(state,ModeSlot.MODE1),saved::countDown,()->{failure[0]=true;saved.countDown();},null);
                check(saved.await(8,TimeUnit.SECONDS)&&!failure[0],"legacy ordinary K1/lights save waits ACKs");
                check(f.firmware.count(0x73)>=8&&f.firmware.count(0x84)==1&&f.firmware.count(0x85)==1&&f.firmware.count(4)==1,"legacy 73/84/85/04 retained");
            }else{
                check(f.isDisplayAdmitted()&&f.isFirmwareCapabilityAdmitted("keys")&&f.isFirmwareCapabilityAdmitted("side"),"formal unified capabilities");
                f.sendCommandExpecting(AhaKeyProtocol.setKeyMapping(0,1,new byte[]{6}), (byte)0x73);f.sendCommandExpecting(AhaKeyProtocol.saveConfig(),(byte)4);
                check(Arrays.equals(f.readOrdinaryKeyConfig(0,1).actionPayload(),new byte[]{6}),"formal ordinary save actual readback");
                var side=f.readSideSwitchConfig();f.writeSideSwitchConfig(new AhaKeyResponseParser.SideSwitchConfig(0,new AhaKeyResponseParser.SideSwitchPositionConfig(1,new byte[0]),side.down()));check(f.readSideSwitchConfig().up().binding()==1,"changed side save and readback");
                StudioState routeState=fx(StudioState::new);K1RouteService routes=fx(()->new K1RouteService(routeState,f));
                try {var route=f.k1RouteTransaction(f.connectionGeneration(),()->routes.read(0,f.connectionGeneration()));check(route.equals(new K1Route(f.firmware.route)),"K1 actual service fragmented read/CRC");
                    CountDownLatch saved=new CountDownLatch(1);String[] error={null};
                    fx(()->{routeState.k1Routes().reset(f.connectionGeneration());routeState.k1Routes().capability.set(K1RouteState.Capability.ROUTE);routeState.applyK1Route(0,route,"");routeState.getKeyConfig(StudioPart.KEY1).setHidCode(9);routeState.markDirty(StudioPart.KEY1);routes.saveDirty(saved::countDown,message->{error[0]=message;saved.countDown();});return null;});
                    check(saved.await(8,TimeUnit.SECONDS)&&error[0]==null&&new K1Route(f.firmware.route).action()[0]==9,"actual K1 saveDirty begin/chunk/commit and authority readback");
                }finally{fx(()->{routes.close();return null;});}
                try(var lease=f.openDisplayLease(true)){
                    OledUploadService.requireAck(f.exchangeDisplay(lease,AhaKeyProtocol.saveDisplayBrightness(40)),(byte)0x8E);
                    check(AhaKeyResponseParser.parseDisplayRead(f.exchangeDisplay(lease,AhaKeyProtocol.displayRead(0)),0).value()==40,"changed brightness actual readback");
                    check(AhaKeyResponseParser.parseDisplayRead(f.exchangeDisplay(lease,AhaKeyProtocol.displayRead(2,0)),2,0)!=null,"display transaction valid metadata");
                }
                byte[] picture=new byte[AhaKeyProtocol.OLED_FRAME_SLOT_SIZE];Arrays.fill(picture,0,AhaKeyProtocol.OLED_FRAME_BYTES,(byte)31);
                OledUploadService.uploadResource(f,f.connectionGeneration(),0,OledResourceState.Asset.fromBytes(picture),percent->{},()->{});
                try(var lease=f.openDisplayLease(false)){var proof=AhaKeyResponseParser.parseDisplayRead(f.exchangeDisplay(lease,AhaKeyProtocol.displayRead(3,0)),3,0);check(proof!=null&&proof.crc()==K1RouteProtocol.crc(picture)&&proof.bytes()==picture.length,"OLED service upload and integrity readback");}
                var registry=(DeviceRecoveryRegistry)get(f,"recoveryTargets");String target=f.targetIdentity();f.requireDisplayRecovery(f.connectionGeneration());f.disconnect();registry.observe(bluetooth?"BLE":"USB",Set.of());
                f.firmware.metadataState=3;f.connectA();check(!registry.contains(target)&&!f.isDisplayWriteUncertain(),"19 INVALID idle resources unblock ordinary operations without upload claim");
                check(f.firmware.count(0x88)>=20,"all19 recovery metadata probed");
            }
            if(bluetooth){
                check(RememberedBleTarget.load().matches("MAC-A")&&!RememberedBleTarget.load().matches("MAC-B"),"common BLE connection persists actual address, not shared name");
                long enumerations=f.operations.stream().filter("enumerateConnected"::equals).count(),connections=f.operations.stream().filter("connect"::equals).count();String session=f.session;
                f.restartManagedBridge(false);
                check(f.operations.contains("showWindow")&&session.equals(f.session)&&f.operations.stream().filter("enumerateConnected"::equals).count()==enumerations&&f.operations.stream().filter("connect"::equals).count()==connections,"ordinary BLE click shows current window without enumerate, restart or reconnect");
                String oldAuthority=authority(f);
                f.connectSelected(new DeviceTarget("BLE","B","AhaKey"));await(()->!f.isScanning()&&f.targetIdentity().equals("BLE:B"),"main window chooses BLE B");long current=f.connectionGeneration();
                for(String staleAuthority:List.of(emptyAuthority,oldAuthority))event(f,ManagedBridgeClient.fields().put("event","selectionRequested").put("selectedTargetId","A").put("address","MAC-A").put("selectionAuthority",staleAuthority));
                check(f.connectionGeneration()==current&&f.targetIdentity().equals("BLE:B")&&!f.isScanning(),"late empty-session and BLE A selection cannot steal current BLE B");
                event(f,ManagedBridgeClient.fields().put("event","selectionRequested").put("selectedTargetId","A").put("address","MAC-A").put("selectionAuthority",authority(f)));
                await(()->!f.isScanning()&&f.targetIdentity().equals("BLE:A"),"current window authority permits explicit selection A");
            }
            long old=f.connectionGeneration();ObjectNode stale=ManagedBridgeClient.fields().put("event","disconnectRequested").put("targetId","A").put("sessionId",f.session).put("clientGeneration",Long.toString(old));
            f.usb=List.of("B");f.connectSelected(new DeviceTarget("USB","B","USB B"));await(()->!f.isScanning()&&f.targetIdentity().equals("USB:B"),"USB B replaces A");
            event(f,stale);check(f.isConnected()&&f.targetIdentity().equals("USB:B"),"late A bridge disconnect cannot retire USB B");
            event(f,ManagedBridgeClient.fields().put("event","disconnectRequested"));check(f.isConnected(),"empty bridge disconnect cannot retire USB");
            check(!f.capabilities().extended()&&!f.capabilities().legacyWrites(),"target switch invalidates capabilities");
            f.usb=List.of();f.pollUsbCandidates();check(!f.isConnected(),"USB unplug remains disconnected");
            if(bluetooth){long count=f.operations.stream().filter("connect"::equals).count();var refresh=BleManager.class.getDeclaredMethod("refreshBridgeChoices",boolean.class);refresh.setAccessible(true);refresh.invoke(f,true);check(!f.isConnected()&&f.operations.stream().filter("connect"::equals).count()==count,"USB removal suppresses remembered BLE takeover");}
            System.out.println("MATRIX PASS "+(key.isEmpty()?"legacy-ACK":key)+" x "+(bluetooth?"BLE private IPC":"USB memory HID"));
        }
    }
    static void controllerLegacy()throws Exception{
        System.setProperty("user.home",Files.createTempDirectory("r6-controller-").toString());Fixture[] holder=new Fixture[1];
        var c=fx(()->new StudioController(cb->{try{return holder[0]=new Fixture("",false,cb);}catch(Exception e){throw new RuntimeException(e);}},b->new KimiAhaKeyBridge(b,0),false));
        try{var f=holder[0];f.connectA();await(()->f.capabilities().legacyWrites(),"actual controller classifies legacy ACK");
            fx(()->{c.getK1RouteService().refresh();return null;});
            check(fx(()->c.getStudioState().k1Routes().capability.get()==K1RouteState.Capability.LEGACY&&!c.getStudioState().k1Routes().confirmed(0)),"legacy K1 editable layer never fabricates observed config");
            fx(()->{var s=c.getStudioState();s.getKeyConfig(StudioPart.KEY1).setHidCode(7);s.markDirty(StudioPart.KEY1);s.displayConfig().editBrightness(44);s.displayConfig().editEffect(0,0,3);var method=StudioController.class.getDeclaredMethod("syncAllModesAfterK1",boolean.class);method.setAccessible(true);method.invoke(c,false);return null;});
            await(()->f.firmware.count(4)>0,"actual controller retains legacy save endpoint");
            check(f.firmware.requests.stream().anyMatch(r->r[2]==0x73&&r[3]==0x73&&r[5]==0&&r[6]==7),"controller sent legacy K1 action");
            check(f.firmware.count(0x84)==1&&f.firmware.count(0x85)==1,"controller saves only edited legacy lights");
            check(f.firmware.count(0x73)==1,"one legacy edit never clears the other fifteen unknown keys or descriptions");
            long g=f.connectionGeneration();try(var binding=f.bindGeneration(g)){f.disconnect();}
            check(!fx(()->c.getDeviceStatus().isConnected()),"bound-generation disconnect clears actual UI");
        }finally{fx(()->{c.shutdown();return null;});}
    }
    static void failures()throws Exception{
        System.setProperty("user.home",Files.createTempDirectory("r6-failure-").toString());
        java.util.concurrent.atomic.AtomicInteger ready=new java.util.concurrent.atomic.AtomicInteger();
        var callback=new BleManager.BleCallback(){public void onConnected(){ready.incrementAndGet();}public void onDisconnected(){}public void onStatusReceived(DeviceStatus s){}public void onError(String s){System.out.println(s);}};
        try(var f=new Fixture("x1-c582-hw1-p1-1.0.1-r001",false,callback)){
            var registry=(DeviceRecoveryRegistry)get(f,"recoveryTargets");registry.require("USB:A");registry.observe("USB",Set.of());f.firmware.metadataState=1;
            f.connectSelected(new DeviceTarget("USB","A","AhaKey"));await(()->!f.isScanning(),"writing metadata failure finishes");
            check(!f.isConnected()&&ready.get()==0&&registry.contains("USB:A"),"recovery failure retains record and never calls onConnected");
            f.firmware.metadataState=0;registry.observe("USB",Set.of());f.connectA();check(ready.get()==1&&!registry.contains("USB:A"),"explicit retry after all19 idle succeeds");
        }
        for(String key:List.of("unknown-catalog","x1-c582-hw1-p1-1.0.1-r001"))try(var f=new Fixture(key,false,CALLBACK)){
            f.connectA();f.firmware.dropIdentity=key.startsWith("x1");
            try{f.readFirmwareCatalogKey();if(f.firmware.dropIdentity)throw new AssertionError("timeout accepted");}catch(IOException e){check(f.firmware.dropIdentity,"only deliberate timeout fails read");}
            check(!f.capabilities().legacyWrites()&&!f.isDisplayAdmitted(),"unknown identity or timeout never becomes legacy/full");
        }
        for(boolean ble:new boolean[]{false,true})try(var f=new Fixture("",ble,CALLBACK)){
            var registry=(DeviceRecoveryRegistry)get(f,"recoveryTargets");String target=(ble?"BLE:":"USB:")+"A";registry.require(target);registry.observe(ble?"BLE":"USB",Set.of());
            f.connectA();check(f.isLegacySaveResultUnknown()&&registry.contains(target)&&f.firmware.count(0x88)==0,"legacy recovery restores command communication, retains unknown save record, no fabricated88");
            f.sendCommandExpecting(AhaKeyProtocol.setKeyMapping(0,0,new byte[]{8}),(byte)0x73);
            try{f.writeData(new byte[]{1});throw new AssertionError("unknown legacy resource state was writable");}catch(IOException expected){checks++;}
            f.disconnect();f.connectA();check(registry.contains(target)&&f.isLegacySaveResultUnknown(),"legacy reconnect repeats live proof and retains uncertainty history");
        }
    }
    static void lightingTargets()throws Exception{
        fx(()->{
            StudioState s=new StudioState();s.selectDevice("BLE:A");
            BleManager legacy=new BleManager(CALLBACK){public FirmwareCapabilities capabilities(){return FirmwareCapabilities.LEGACY;}};
            try(var service=new DisplayConfigService(s,legacy,new OledResourceStore(Files.createTempDirectory("r6-lights-")))){
                service.capabilityChanged();var state=s.displayConfig();
                check(!state.brightnessDirty()&&!state.effectDirty(0,0),"legacy local initialization does not fabricate edits");
                state.editBrightness(44);state.editEffect(0,0,3);s.selectDevice("USB:B#new");service.connectionChanged();state.readBrightness(80);state.readEffect(0,0,16);
                check(state.brightness.get()==80&&state.effect(0,0)==16&&!state.brightnessDirty()&&!state.effectDirty(0,0),"B displays B readback, not A draft");
                s.selectDevice("BLE:A");check(state.brightness.get()==44&&state.effect(0,0)==3&&state.brightnessDirty()&&state.effectDirty(0,0),"returning A retains A user edits");
                state.readEffect(0,1,12);state.invalidateLightingObservations();
                check(state.effect(0,1)==-1&&!state.effectKnownOrEdited(0,1)&&state.brightness.get()==44&&state.brightnessKnownOrEdited(),"same-address new generation drops clean facts but retains explicit edits");
                s.selectDevice("BLE:C");s.updateKeyDescription(StudioPart.KEY2,"only description");
                var commands=DeviceSyncService.legacyEditedCommands(s);check(commands.size()==2&&commands.get(0).data()[3]==0x75,"description-only legacy edit never clears unknown action");
                s.selectDevice("BLE:D");check(DeviceSyncService.legacyEditedCommands(s).isEmpty(),"new target placeholders generate no legacy writes");
            }finally{legacy.shutdownTransport();}
            return null;
        });
    }
    public static void main(String[] args)throws Exception{
        Platform.startup(()->{});Platform.setImplicitExit(false);
        try{for(String key:List.of("x1-c582-hw1-p1-1.0.1-r001","x1-c582-hw2-p1-1.0.1-r001",""))for(boolean ble:new boolean[]{false,true})matrix(key,ble);controllerLegacy();failures();lightingTargets();
            System.out.println("PASS "+checks+" firmware matrix assertions. Offline only, no hardware acceptance.");
        }finally{Platform.exit();}
    }
}
