package com.example.ahakey.wd010;

import com.example.ahakey.service.*;
import com.example.ahakey.model.*;
import com.example.ahakey.protocol.*;
import com.example.ahakey.firmware.*;
import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import static com.example.ahakey.protocol.FactoryResetProtocol.State;
import static com.example.ahakey.model.FactoryResetState.Phase;

public final class RestoreChecks {
    static int checks;
    static void check(boolean value,String label){checks++;if(!value)throw new AssertionError(label);}
    interface Work{void run()throws Exception;}
    static void rejects(Work work,String label)throws Exception{try{work.run();throw new AssertionError(label);}catch(Exception expected){checks++;}}
    public static byte[] reply(int version,int sub,int nonce,int result,State state,long attempt){return ByteBuffer.allocate(17).order(ByteOrder.LITTLE_ENDIAN).put((byte)0xaa).put((byte)0xbb).put((byte)0x9e).put((byte)result).put((byte)version).put((byte)sub).putInt(nonce).put((byte)state.ordinal()).putInt((int)attempt).put((byte)0xcc).put((byte)0xdd).array();}
    public static void main(String[] args)throws Exception{
        protocol();gates();lifecycle();
        System.out.println("PASS RestoreChecks "+checks+" checks; actual frame extractors/gates plus deterministic failure state machine; no hardware");
    }
    private static void protocol()throws Exception{
        int nonce=0xBBAADDCC;
        check(FactoryResetProtocol.query(nonce).length==11&&FactoryResetProtocol.start(nonce,0xffffffffL)[3]==2,"v1 query and v2 start exact encoding");
        rejects(()->FactoryResetProtocol.start(1,0),"zero attempt");rejects(()->FactoryResetProtocol.start(1,0x100000000L),"overflow");
        var usb=UsbHidTransport.class.getDeclaredMethod("extractFrame",byte[].class,int.class,byte[].class);usb.setAccessible(true);
        var ble=BleManager.class.getDeclaredMethod("reassembleNotifyFrames",byte[].class);ble.setAccessible(true);
        for(int version:new int[]{1,2})for(State state:State.values())for(int result:new int[]{0,1}){
            int sub=version==1?0x30:0x31;byte[] frame=reply(version,sub,nonce,result,state,0xDDCCBBAAL);
            check(FactoryResetProtocol.parse(frame,version,sub,nonce).attempt()==0xDDCCBBAAL,"all states preserve unsigned attempt");
            byte[] request=version==1?FactoryResetProtocol.query(nonce):FactoryResetProtocol.start(nonce,1);
            byte[] report=new byte[65];System.arraycopy(frame,0,report,2,17);check(Arrays.equals(frame,(byte[])usb.invoke(null,report,65,request)),"USB exact binary frame");
            var wire=new DeviceMaintenanceChecks.FixtureBle();
            for(int split=1;split<17;split++){var a=(List<?>)ble.invoke(wire,(Object)Arrays.copyOf(frame,split));var b=(List<?>)ble.invoke(wire,(Object)Arrays.copyOfRange(frame,split,17));check(a.isEmpty()&&b.size()==1&&Arrays.equals(frame,(byte[])b.get(0)),"BLE all splits");}
            byte[] joined=new byte[34];System.arraycopy(frame,0,joined,0,17);System.arraycopy(frame,0,joined,17,17);check(((List<?>)ble.invoke(wire,(Object)joined)).size()==2,"BLE coalesced");
            rejects(()->FactoryResetProtocol.parse(frame,version,sub,nonce+1),"wrong nonce");rejects(()->FactoryResetProtocol.parse(frame,3,sub,nonce),"wrong version");rejects(()->FactoryResetProtocol.parse(frame,version,0x10,nonce),"K1 cross talk");
        }
        rejects(()->FactoryResetProtocol.parse(AhaKeyProtocol.buildFrame((byte)0x9e,new byte[]{0}),1,0x30,1),"old ACK never completion");
        byte[] status={1,1,'A',17,'A','A',':','B','B',':','C','C',':','D','D',':','E','E',':','F','F',1};
        check(BleManager.parseRestoreBleAddress(status).equals("AA:BB:CC:DD:EE:FF"),"bridge address exact bounded format");status[21]=0;check(BleManager.parseRestoreBleAddress(status).isBlank(),"non-target bridge status cannot prove identity");
    }
    private static void gates()throws Exception{
        var pendingUsb=new DeviceMaintenanceChecks.FixtureBle();pendingUsb.setFactoryWriteGuard(()->true);
        rejects(()->pendingUsb.sendCommand(AhaKeyProtocol.saveConfig()),"ambiguous USB pending intent blocks ordinary writes before async quarantine");
        rejects(()->pendingUsb.sendCommand(AhaKeyProtocol.previewBrightness(50)),"ambiguous USB pending intent blocks preview");
        check(pendingUsb.usb.writes.get()==0,"quarantine boundary emits zero writes");
        var ble=new DeviceMaintenanceChecks.FixtureBle();var gate=ble.maintenance();
        try(var transaction=gate.normalTransaction()){rejects(()->ble.beginFactoryReset(0),"normal save excludes reset");}
        ble.beginFactoryReset(0);
        for(byte[] frame:List.of(AhaKeyProtocol.saveConfig(),AhaKeyProtocol.previewBrightness(35),AhaKeyProtocol.setWorkMode(1),FactoryResetProtocol.start(1,1),AhaKeyProtocol.queryDeviceStatus()))rejects(()->ble.sendCommand(frame),"ordinary caller cannot bypass target lock");
        gate.withinFactory(0,false,()->{
            gate.admitFrame(AhaKeyProtocol.querySleepWaitTime(),0);gate.admitFrame(AhaKeyProtocol.readPicState(0),0);gate.admitFrame(AhaKeyProtocol.displayRead(3,18),0);
            rejects(()->gate.admitFrame(FactoryResetProtocol.start(1,1),0),"query permission cannot start");rejects(()->gate.admitFrame(AhaKeyProtocol.saveConfig(),0),"readback permission cannot save old draft");return null;
        });
        gate.withinFactory(0,true,()->{gate.admitFrame(FactoryResetProtocol.start(1,1),0);return null;});
        rejects(()->ble.beginMaintenance(DeviceMaintenanceChecks.identity(),DeviceMaintenanceChecks.HASH,"fixture",false),"firmware maintenance excluded");
        check(ble.usb.writes.get()==0,"denied commands emit no device writes");check(ble.requestApplicationExit(null),"unresolved reset does not block application exit");
        var other=new DeviceMaintenanceCoordinator();other.bindFactory(2);other.releaseFactory();check(other.normalAllowed(),"different connection can be admitted after disassociation");
    }
    private static final class Device implements FactoryResetService.Device {
        FactoryResetStore.Target target=new FactoryResetStore.Target(1,"USB","fixture","","path");
        FactoryResetState state;FactoryResetStore store;long attempt;State observed=State.NEVER;
        String response="complete";boolean locked,failReadback,disconnected;int writes,discards,reads,queries;
        public FactoryResetStore.Target target(){return target;}public boolean connected(){return !disconnected;}
        public void lock(long generation)throws Exception{if(generation!=target.generation())throw new IOException("generation");locked=true;}
        public void unlock(){locked=false;}
        public <T>T authorized(long g,boolean start,Callable<T> action)throws Exception{if(!locked||g!=target.generation())throw new IOException("permission");return action.call();}
        public FactoryResetProtocol.Reply exchange(byte[] request,long generation)throws Exception{
            if(FactoryResetProtocol.isStart(request)){
                check(store.load()!=null&&store.load().stage().equals("SENDING")&&discards==0,"durable quarantine precedes start; live draft retained until send boundary");check(state.phase.get()==Phase.WAITING,"no claim of in-progress before reply");writes++;
                if(response.equals("reject"))return new FactoryResetProtocol.Reply(1,observed,attempt);
                attempt++;observed=response.equals("incomplete")?State.INCOMPLETE:response.equals("progress")?State.IN_PROGRESS:State.COMPLETE;
                if(response.equals("lost"))throw new IOException("reply lost");
            }
            if(FactoryResetProtocol.isRead(request))queries++;
            return new FactoryResetProtocol.Reply(0,observed,attempt);
        }
        public void discardDraft(){discards++;}
        public void readback(long g)throws Exception{reads++;if(failReadback)throw new IOException("partial read failure");}
    }
    private static FactoryResetService service(Device d,Path path)throws Exception{return service(d,new FactoryResetStore(path));}
    private static FactoryResetService service(Device d,FactoryResetStore store)throws Exception{d.store=store;d.state=new FactoryResetState();return new FactoryResetService(d,store,d.state,Runnable::run);}
    private static void lifecycle()throws Exception{
        Path root=Files.createTempDirectory("wd010-restore-");
        Device d=new Device();try(var s=service(d,root.resolve("cancel.json"))){s.prepare().get();s.cancelConfirmation();check(d.writes==0&&d.discards==0&&!s.hasPending(),"cancel has zero writes and preserves drafts");var c=s.prepare().get();d.target=new FactoryResetStore.Target(2,"USB","other","","path");rejects(()->s.confirm(c).get(),"confirmation cannot transfer generation");check(d.writes==0,"changed target zero writes");}
        d=new Device();try(var s=service(d,root.resolve("complete.json"))){s.confirm(s.prepare().get()).get();check(d.writes==1&&d.reads==1&&d.state.phase.get()==Phase.COMPLETE&&!s.hasPending()&&!d.locked,"complete requires readback and clears lock");}
        Device denied=new Device();try(var s=service(denied,new FactoryResetStore(root.resolve("fail-save.json")){public void save(Pending p)throws IOException{throw new IOException("disk unavailable");}})){rejects(()->s.confirm(s.prepare().get()).get(),"atomic save failure");check(denied.writes==0&&denied.discards==0&&!denied.locked,"pre-submit storage failure preserves drafts and emits zero writes");}
        d=new Device();d.response="lost";try(var s=service(d,root.resolve("lost.json"))){rejects(()->s.confirm(s.prepare().get()).get(),"lost reply");check(d.writes==1&&d.locked&&s.hasPending()&&d.state.phase.get()==Phase.UNKNOWN,"unknown retains record and read-only");s.queryAgain(null).get();check(d.writes==1&&d.state.phase.get()==Phase.COMPLETE,"query resolves without write replay");}
        d=new Device();d.failReadback=true;try(var s=service(d,root.resolve("partial.json"))){s.confirm(s.prepare().get()).get();check(d.state.phase.get()==Phase.READ_FAILED&&d.locked,"partial readback cannot unlock");d.failReadback=false;s.queryAgain(null).get();check(d.reads==2&&d.writes==1&&d.state.phase.get()==Phase.COMPLETE,"readback retry does not reset again");}
        d=new Device();d.response="reject";try(var s=service(d,root.resolve("reject.json"))){s.confirm(s.prepare().get()).get();check(d.writes==1&&d.state.phase.get()==Phase.UNAVAILABLE&&!s.hasPending()&&!d.locked,"explicit old-attempt rejection is not unknown forever");d.response="complete";d.discards=0;s.confirm(s.prepare().get()).get();check(d.writes==2&&d.state.phase.get()==Phase.COMPLETE,"manual retry after resolving rejection");}
        d=new Device();d.response="incomplete";try(var s=service(d,root.resolve("incomplete.json"))){s.confirm(s.prepare().get()).get();check(d.state.phase.get()==Phase.INCOMPLETE&&s.hasPending()&&d.locked,"incomplete is durable and read-only");d.response="complete";d.discards=0;s.confirm(s.prepare().get()).get();check(d.writes==2&&d.attempt==2&&d.state.phase.get()==Phase.COMPLETE,"incomplete requires fresh explicit confirmation and next attempt");}
        d=new Device();d.response="lost";try(var s=service(d,root.resolve("wrong-attempt.json"))){rejects(()->s.confirm(s.prepare().get()).get(),"lost start");d.attempt=9;s.queryAgain(null).get();check(d.state.phase.get()==Phase.UNKNOWN&&d.reads==0&&s.hasPending(),"wrong durable attempt cannot complete another task");}
        d=new Device();try(var s=service(d,new FactoryResetStore(root.resolve("clear-fail.json")){public void clear()throws IOException{throw new IOException("clear failed");}})){s.confirm(s.prepare().get()).get();check(d.reads==1&&d.state.phase.get()==Phase.READ_FAILED&&d.locked&&s.hasPending(),"clearing durable record failure cannot unlock even after all reads");}
        d=new Device();d.response="lost";Path restart=root.resolve("restart.json");try(var s=service(d,restart)){rejects(()->s.confirm(s.prepare().get()).get(),"lost reply before restart");}
        d=new Device();d.attempt=1;d.observed=State.COMPLETE;try(var s=service(d,restart)){rejects(()->s.queryAgain(null).get(),"USB restart requires human association");check(d.writes==0&&s.hasPending(),"restart never replays writes");var association=s.association();d.target=new FactoryResetStore.Target(2,"USB","other","","other-path");rejects(()->s.queryAgain(association).get(),"manual association cannot transfer to another USB generation");check(d.queries==0&&d.reads==0&&s.hasPending(),"stale manual confirmation queries no new device");s.queryAgain(s.association()).get();check(d.writes==0&&d.state.phase.get()==Phase.COMPLETE,"manual association queries only");}
        Path wrong=root.resolve("other.json");new FactoryResetStore(wrong).save(new FactoryResetStore.Pending(1,UUID.randomUUID().toString(),new FactoryResetStore.Target(1,"BLE","old","AA:BB:CC:DD:EE:FF",""),1,"SENT"));
        d=new Device();d.target=new FactoryResetStore.Target(2,"BLE","new","11:22:33:44:55:66","");try(var s=service(d,wrong)){rejects(()->s.queryAgain(s.association()).get(),"known other device cannot be manually overridden");check(d.writes==0&&d.reads==0&&!d.locked&&s.hasPending(),"other device remains unrelated");}
        for(String body:List.of("null","{}","{\"schema\":1,\"taskId\":\""+UUID.randomUUID()+"\",\"target\":{},\"attempt\":1}","{\"schema\":\"bad\"}")){
            Path bad=root.resolve("corrupt-"+checks+".json");Files.writeString(bad,body);try(var s=service(new Device(),bad)){check(s.hasPending()&&s.state().message.get().contains("损坏"),"corrupt record does not crash startup");rejects(()->s.prepare().get(),"corrupt record cannot start");}
        }
    }
}
