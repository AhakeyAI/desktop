package com.example.ahakey.service;

import com.example.ahakey.model.*;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.*;
import java.sql.*;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;
import static com.example.ahakey.service.CursorSessionDiscoveryService.Waiting.*;

/** Real SQLite/WAL and runtime service/USB scheduler; no Cursor launch, user DB or physical device. */
public final class CursorWaitingChecks {
    static int checks;
    static void check(boolean value,String name){if(!value)throw new AssertionError(name);checks++;System.out.println("PASS "+name);}
    static void await(java.util.function.BooleanSupplier predicate,String name)throws Exception{long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(4);while(!predicate.getAsBoolean()&&System.nanoTime()<end)Thread.sleep(5);check(predicate.getAsBoolean(),name);}
    static final BleManager.BleCallback CALLBACK=new BleManager.BleCallback(){public void onConnected(){}public void onDisconnected(){}public void onStatusReceived(DeviceStatus s){}public void onError(String s){System.out.println("fixture message: "+s);}};

    static final class Database implements AutoCloseable {
        final Path root,db; final Connection writer;
        Database() throws Exception {
            root=Files.createTempDirectory("cursor-metadata-fixture-");Files.createDirectories(root.resolve("globalStorage"));
            db=root.resolve("globalStorage/state.vscdb");writer=DriverManager.getConnection("jdbc:sqlite:"+db);
            try(var s=writer.createStatement()) {
                s.execute("pragma journal_mode=WAL");s.execute("pragma wal_autocheckpoint=0");
                s.execute("create table composerHeaders(composerId text,isArchived integer,isSubagent integer,value text)");
                s.execute("create table cursorDiskKV(key text primary key,value text)");
            }
        }
        void raw(String id,String json)throws Exception {
            try(var d=writer.prepareStatement("delete from composerHeaders where composerId=?")){d.setString(1,id);d.executeUpdate();}
            insert(id,json);
        }
        void insert(String id,String json)throws Exception {
            try(var s=writer.prepareStatement("insert into composerHeaders values(?,0,0,?)")){s.setString(1,id);s.setString(2,json);s.executeUpdate();}
        }
        void put(String id,boolean waiting)throws Exception{raw(id,"{\"composerId\":\""+id+"\",\"hasBlockingPendingActions\":"+waiting+"}");}
        void generation(String id,String generation)throws Exception {
            identity(id, "{\"composerId\":\""+id+"\",\"chatGenerationUUID\":\""+generation+"\",\"latestChatGenerationUUID\":\""+generation+"\"}");
        }
        void identity(String id,String json)throws Exception {
            try(var q=writer.prepareStatement("insert or replace into cursorDiskKV values(?,?)")) {
                q.setString(1,"composerData:"+id);q.setString(2,json);q.executeUpdate();
            }
        }
        public void close()throws Exception{writer.close();}
    }
    static final class Source extends CursorSessionDiscoveryService {
        volatile CursorProcess process=new CursorProcess("fixture-process-1","3.27.22");
        final AtomicInteger reads=new AtomicInteger();final AtomicBoolean hold=new AtomicBoolean();
        volatile CountDownLatch entered,release;
        @Override public CursorProcess runningCursor(){return process;}
        @Override public Map<String,WaitingState> readRuntimeStates(Path dir,Set<String> ids,String version){
            reads.incrementAndGet();var result=super.readRuntimeStates(dir,ids,version);
            if(hold.compareAndSet(true,false)){entered.countDown();try{if(!release.await(5,TimeUnit.SECONDS))throw new AssertionError("fixture read release timeout");}catch(InterruptedException e){Thread.currentThread().interrupt();}}
            return result;
        }
        void holdNext(){entered=new CountDownLatch(1);release=new CountDownLatch(1);hold.set(true);}
    }
    static final class CaptureWire extends BleManager {
        final List<byte[]> sent=new CopyOnWriteArrayList<>();
        volatile boolean hold99;
        volatile CountDownLatch ackEntered=new CountDownLatch(1),ackRelease=new CountDownLatch(1);
        final MemoryUsb memory = new MemoryUsb();
        CaptureWire(){super(CALLBACK);}
        @Override protected boolean isUsbDevicePresent(){return false;}
        @Override public void connect(){throw new AssertionError("No real connection permitted");}
        @Override public void queryStatus(){}
        void memoryConnect()throws Exception {
            var reset=BleManager.class.getDeclaredMethod("resetDisplaySession");reset.setAccessible(true);reset.invoke(this);
            var transport=BleManager.class.getDeclaredField("usbTransport");transport.setAccessible(true);transport.set(this,memory);
            var connected=BleManager.class.getDeclaredField("isConnected");connected.setAccessible(true);connected.set(this,true);
            memory.open=true;getCachedStatus().setConnected(true);
        }
        final class MemoryUsb extends UsbHidTransport {
            boolean open;
            @Override public void open(java.util.function.Consumer<byte[]> callback){throw new AssertionError("No native HID permitted");}
            @Override public void openExact(String path,java.util.function.Consumer<byte[]> callback){throw new AssertionError("No native HID permitted");}
            @Override public boolean isOpen(){return open;}
            @Override public void close(){open=false;}
            @Override public void sendCommand(byte[] f){
                sent.add(f.clone());
                if(f[2]==(byte)0x99 && hold99) {
                    hold99=false;ackEntered.countDown();
                    try { if(!ackRelease.await(5,TimeUnit.SECONDS))throw new AssertionError("ACK fixture timeout"); }
                    catch(InterruptedException e){Thread.currentThread().interrupt();}
                }
                byte[] payload=f[2]==(byte)0x9f?"\0x1-c582-hw1-p1-1.0.1-r001".getBytes(java.nio.charset.StandardCharsets.US_ASCII):new byte[]{0};
                try {
                    var receive=BleManager.class.getDeclaredMethod("onSessionNotify",long.class,byte[].class);receive.setAccessible(true);
                    receive.invoke(CaptureWire.this,connectionGeneration(),AhaKeyProtocol.buildFrame(f[2],payload));
                } catch(ReflectiveOperationException e){throw new AssertionError(e);}
            }
        }
        int state(int slot){for(int i=sent.size()-1;i>=0;i--)if(sent.get(i)[2]==(byte)0x99)return sent.get(i)[5+3*slot]&255;return -1;}
        long snapshots(){return sent.stream().filter(f->f[2]==(byte)0x99).count();}
    }
    static AiRuntimeSession session(String id){return new AiRuntimeSession("Cursor",id,id,"fixture","","",Instant.EPOCH);}
    static Database currentDb;
    static final Map<String,String> testGenerations=new HashMap<>();
    static void hook(AiRuntimeDisplayService runtime,String id,IDEState state)throws Exception {
        if(state==IDEState.PRE_TOOL_USE || !testGenerations.containsKey(id)) {
            String generation=UUID.randomUUID().toString();testGenerations.put(id,generation);
            currentDb.generation(id,generation);
            runtime.pollCursorWaiting();
        }
        hookGeneration(runtime,id,state,testGenerations.get(id));
    }
    static AiRuntimeDisplayService.Delivery hookGeneration(AiRuntimeDisplayService runtime,String id,IDEState state,String generation)throws Exception {
        var payload=new ObjectMapper().createObjectNode().put("conversation_id",id);
        if(generation!=null)payload.put("generation_id",generation);
        return runtime.handleHookEventResult("Cursor",state,payload);
    }
    static void databaseChecks()throws Exception {
        var source=new CursorSessionDiscoveryService();
        try(var fixture=new Database()) {
            fixture.put("a",false);fixture.put("b",true);
            var before=Files.readAllBytes(fixture.db);var wal=Files.readAllBytes(Path.of(fixture.db+"-wal"));
            var states=source.readWaitingStates(fixture.root,Set.of("a","b"),"3.14.7");
            check(states.get("a").state()==NOT_WAITING&&states.get("b").state()==WAITING,"WAL-only committed true/false visible");
            check(source.readWaitingStates(fixture.root,Set.of("a","b"),"3.27.22").equals(states),"verified 3.27.22 exact parent header schema supported");
            check(Arrays.equals(before,Files.readAllBytes(fixture.db))&&Arrays.equals(wal,Files.readAllBytes(Path.of(fixture.db+"-wal"))),"reader leaves main database and WAL byte-identical");
            fixture.put("a",true);check(source.readWaitingStates(fixture.root,Set.of("a"),"3.14.7").get("a").state()==WAITING,"next WAL commit visible without checkpoint");
            fixture.raw("b","{broken");states=source.readWaitingStates(fixture.root,Set.of("a","b"),"3.14.7");
            check(states.get("a").state()==WAITING&&states.get("b").state()==UNKNOWN,"malformed other slot cannot erase valid wait");
            for(String bad:List.of("{}","{\"composerId\":\"a\"}","{\"composerId\":\"a\",\"hasBlockingPendingActions\":\"true\"}","{\"composerId\":\"other\",\"hasBlockingPendingActions\":true}","{\"composerId\":\"a\",\"hasBlockingPendingActions\":true,\"hasBlockingPendingActions\":false}")) {
                fixture.raw("a",bad);check(source.readWaitingStates(fixture.root,Set.of("a"),"3.14.7").get("a").state()==UNKNOWN,"invalid/missing/ambiguous field is unknown");
            }
            fixture.put("a",true);fixture.insert("a","{\"composerId\":\"a\",\"hasBlockingPendingActions\":false}");
            check(source.readWaitingStates(fixture.root,Set.of("a"),"3.14.7").get("a").state()==UNKNOWN,"duplicate composer rows rejected");
            check(source.readWaitingStates(fixture.root,Set.of("a"),"4.0.0").get("a").state()==UNKNOWN,"unsupported version not inferred");
            check(source.readWaitingStates(fixture.root,Set.of("missing"),"3.14.7").get("missing").state()==UNKNOWN,"absent session not false");
            for(String flag:List.of("isArchived","archived","isSubAgent","isSubagent"))for(String bad:List.of("null","\"false\"","0","{}","[]","true")) {
                fixture.raw("a","{\"composerId\":\"a\",\"hasBlockingPendingActions\":true,\""+flag+"\":"+bad+"}");
                check(source.readWaitingStates(fixture.root,Set.of("a"),"3.14.7").get("a").state()==UNKNOWN,"archive/subagent flag invalid or true cannot become eligible");
            }
            fixture.raw("parent","{\"composerId\":\"parent\",\"hasBlockingPendingActions\":false,\"status\":\"generating\",\"subagentComposerIds\":[\"child\"]}");
            fixture.put("child",true);
            try(var s=fixture.writer.createStatement()){s.execute("update composerHeaders set isSubagent=1 where composerId='child'");}
            states=source.readWaitingStates(fixture.root,Set.of("parent","child"),"3.27.22");
            check(states.get("parent").state()==NOT_WAITING&&states.get("child").state()==UNKNOWN,"child record and parent generating status cannot invent a parent wait");
            fixture.raw("parent","{\"composerId\":\"parent\",\"hasBlockingPendingActions\":true,\"subagentComposerIds\":[\"child\"]}");
            check(source.readWaitingStates(fixture.root,Set.of("parent"),"3.27.22").get("parent").state()==WAITING,"only parent-owned aggregate boolean can indicate parent user action");
        }
        try(var fixture=new Database()) {
            fixture.put("a",true);
            try(var s=fixture.writer.createStatement()){s.execute("pragma wal_checkpoint(TRUNCATE)");s.execute("pragma journal_mode=DELETE");s.execute("begin exclusive");}
            long start=System.nanoTime();var states=source.readWaitingStates(fixture.root,Set.of("a"),"3.14.7");
            check(states.get("a").state()==UNKNOWN&&System.nanoTime()-start<TimeUnit.SECONDS.toNanos(3),"exclusive lock returns bounded unknown");
            try(var s=fixture.writer.createStatement()){s.execute("rollback");}
        }
        Path missing=Files.createTempDirectory("cursor-missing-");
        source.readWaitingStates(missing,Set.of("a"),"3.14.7");check(!Files.exists(missing.resolve("globalStorage/state.vscdb")),"missing source is not created");
        Files.createDirectories(missing.resolve("globalStorage"));Files.writeString(missing.resolve("globalStorage/state.vscdb"),"corrupt database");
        check(source.readWaitingStates(missing,Set.of("a"),"3.14.7").get("a").state()==UNKNOWN,"corrupt database unknown");
    }
    static void runtimeChecks()throws Exception {
        try(var db=new Database()) {
            currentDb=db;testGenerations.clear();
            db.put("a",true);db.put("b",false);db.put("c",false);
            Source source=new Source();CaptureWire wire=new CaptureWire();var runtime=new AiRuntimeDisplayService(wire,source);
            ExecutorService worker=Executors.newSingleThreadExecutor();
            try {
                wire.memoryConnect();await(wire::isConnected,"memory USB connects");wire.readFirmwareCatalogKey();
                runtime.setCursorDataDir(db.root.toString());runtime.displayModeProperty().set(AiRuntimeDisplayMode.MULTI);
                runtime.bindSlot(0,session("a"));runtime.bindSlot(1,session("b"));runtime.markDraftApplied(false,true);
                runtime.pollCursorWaiting();hook(runtime,"a",IDEState.PRE_TOOL_USE);hook(runtime,"b",IDEState.PRE_TOOL_USE);runtime.pollCursorWaiting();
                check(wire.state(0)==1&&wire.state(1)==1,"historical first true and ordinary preToolUse do not light yellow");
                db.put("a",false);runtime.pollCursorWaiting();db.put("a",true);runtime.pollCursorWaiting();
                check(wire.state(0)==2&&wire.state(1)==1,"A waiting and B running encoded in actual 0x99 frame");
                hook(runtime,"b",IDEState.POST_TOOL_USE);hook(runtime,"a",IDEState.POST_TOOL_USE);
                check(wire.state(0)==2&&wire.state(1)==1,"ordinary tool hooks cannot erase confirmed native wait");
                db.put("a",false);runtime.pollCursorWaiting();check(wire.state(0)==1,"new false restores trusted running base");
                db.put("a",true);runtime.pollCursorWaiting();hook(runtime,"a",IDEState.STOP);runtime.pollCursorWaiting();
                check(wire.state(0)==3,"terminal survives residual true");
                db.raw("a","{}");runtime.pollCursorWaiting();db.put("a",true);runtime.pollCursorWaiting();
                check(wire.state(0)==3,"UNKNOWN then old true cannot restore a terminated wait");
                hook(runtime,"a",IDEState.PRE_TOOL_USE);runtime.pollCursorWaiting();
                check(wire.state(0)==1,"new hook alone cannot resurrect residual true");
                db.put("a",false);runtime.pollCursorWaiting();db.put("a",true);runtime.pollCursorWaiting();check(wire.state(0)==2,"new Hook plus new false-to-true re-arms wait");
                db.raw("a","{}");runtime.pollCursorWaiting();check(wire.state(0)==0&&wire.state(1)==1,"unknown waiting slot becomes EMPTY, not green or DONE");
                db.put("a",true);runtime.pollCursorWaiting();check(wire.state(0)==2,"same-process confirmed wait recovers after UNKNOWN without invented false");
                db.put("a",false);runtime.pollCursorWaiting();
                source.holdNext();Future<?> oldFalse=worker.submit(runtime::pollCursorWaiting);check(source.entered.await(2,TimeUnit.SECONDS),"old false read captured");
                db.put("a",true);runtime.pollCursorWaiting();check(wire.state(0)==2,"new sample enters wait");source.release.countDown();oldFalse.get(2,TimeUnit.SECONDS);
                check(wire.state(0)==2,"late old false cannot clear newer wait");
                source.holdNext();Future<?> oldTrue=worker.submit(runtime::pollCursorWaiting);check(source.entered.await(2,TimeUnit.SECONDS),"old true captured");
                hook(runtime,"a",IDEState.STOP);source.release.countDown();oldTrue.get(2,TimeUnit.SECONDS);check(wire.state(0)==3,"sample predating terminal Hook discarded");
                hook(runtime,"a",IDEState.PRE_TOOL_USE);db.put("a",false);runtime.pollCursorWaiting();db.put("a",true);runtime.pollCursorWaiting();
                source.process=new CursorSessionDiscoveryService.CursorProcess("","");runtime.pollCursorWaiting();check(wire.state(0)==0,"process exit clears yellow to unknown");
                source.process=new CursorSessionDiscoveryService.CursorProcess("fixture-process-2","3.27.22");runtime.pollCursorWaiting();
                hook(runtime,"a",IDEState.PRE_TOOL_USE);runtime.pollCursorWaiting();check(wire.state(0)==1,"restarted process historical true is not reused");
                db.put("a",false);runtime.pollCursorWaiting();db.put("a",true);runtime.pollCursorWaiting();check(wire.state(0)==2,"new process observation can re-arm");
                source.holdNext();Future<?> versionChange=worker.submit(runtime::pollCursorWaiting);check(source.entered.await(2,TimeUnit.SECONDS),"pending sample before version change");
                long versionSnapshots=wire.snapshots();source.process=new CursorSessionDiscoveryService.CursorProcess("fixture-process-2","3.14.7");
                source.release.countDown();versionChange.get(2,TimeUnit.SECONDS);check(wire.snapshots()==versionSnapshots,"source version change rejects already sampled old-version result");
                runtime.pollCursorWaiting();check(wire.state(0)==0,"version epoch invalidates previous native confirmation");
                source.process=new CursorSessionDiscoveryService.CursorProcess("fixture-process-3","3.27.22");
                hook(runtime,"a",IDEState.PRE_TOOL_USE);db.put("a",false);runtime.pollCursorWaiting();db.put("a",true);runtime.pollCursorWaiting();
                var factsField=AiRuntimeDisplayService.class.getDeclaredField("liveFacts");factsField.setAccessible(true);
                @SuppressWarnings("unchecked") Map<String,Object> facts=(Map<String,Object>)factsField.get(runtime);
                var ctor=facts.get("Cursor:a").getClass().getDeclaredConstructors()[0];ctor.setAccessible(true);
                facts.put("Cursor:a",ctor.newInstance(IDEState.PRE_TOOL_USE,System.nanoTime()-TimeUnit.MINUTES.toNanos(30),wire.connectionGeneration()));
                runtime.pollCursorWaiting();hook(runtime,"b",IDEState.PRE_TOOL_USE);check(wire.state(0)==2,"confirmed native wait survives 30-minute-old Hook and repeated identical true");
                source.holdNext();Future<?> rebind=worker.submit(runtime::pollCursorWaiting);check(source.entered.await(2,TimeUnit.SECONDS),"pending old-slot read");
                runtime.clearSlot(0);runtime.bindSlot(0,session("c"));runtime.markDraftApplied(false,true);hook(runtime,"c",IDEState.PRE_TOOL_USE);
                source.release.countDown();rebind.get(2,TimeUnit.SECONDS);check(wire.state(0)==1,"rebound slot rejects old sample");
                runtime.pollCursorWaiting();source.holdNext();Future<?> switchMode=worker.submit(runtime::pollCursorWaiting);check(source.entered.await(2,TimeUnit.SECONDS),"pending multi read");
                runtime.displayModeProperty().set(AiRuntimeDisplayMode.SINGLE);long count=wire.snapshots();source.release.countDown();switchMode.get(2,TimeUnit.SECONDS);runtime.pollCursorWaiting();
                check(wire.snapshots()==count,"switch to SINGLE rejects in-flight sample and does not monitor");
                hook(runtime,"c",IDEState.PRE_TOOL_USE);check(wire.snapshots()==count,"SINGLE remains legacy Hook transport");
                runtime.displayModeProperty().set(AiRuntimeDisplayMode.MULTI);runtime.pollCursorWaiting();
                hook(runtime,"c",IDEState.PRE_TOOL_USE);db.put("c",false);runtime.pollCursorWaiting();db.put("c",true);runtime.pollCursorWaiting();check(wire.state(0)==2,"C waits before source change");
                try(var replacement=new Database()) {
                    replacement.put("c",false);replacement.put("b",false);
                    runtime.setCursorDataDir(replacement.root.toString());runtime.pollCursorWaiting();
                    check(wire.state(0)==0,"directory change emits actual EMPTY snapshot instead of leaving physical yellow");
                }
                runtime.setCursorDataDir(db.root.toString());runtime.pollCursorWaiting();hook(runtime,"c",IDEState.PRE_TOOL_USE);
                db.put("c",false);runtime.pollCursorWaiting();db.put("c",true);runtime.pollCursorWaiting();
                source.holdNext();Future<?> reconnect=worker.submit(runtime::pollCursorWaiting);check(source.entered.await(2,TimeUnit.SECONDS),"pending read before reconnect");
                count=wire.snapshots();wire.disconnect();wire.memoryConnect();await(wire::isConnected,"memory reconnect");wire.readFirmwareCatalogKey();
                source.release.countDown();reconnect.get(2,TimeUnit.SECONDS);check(wire.snapshots()==count,"old connection sample not sent to reconnected device");
                runtime.pollCursorWaiting();hook(runtime,"c",IDEState.PRE_TOOL_USE);runtime.pollCursorWaiting();check(wire.state(0)==1,"reconnect does not replay historical true");
                db.put("c",false);runtime.pollCursorWaiting();db.put("c",true);runtime.pollCursorWaiting();
                source.holdNext();Future<?> maintenance=worker.submit(runtime::pollCursorWaiting);check(source.entered.await(2,TimeUnit.SECONDS),"pending read before maintenance");
                var operation=wire.maintenance().begin(null,"","fixture",false);runtime.maintenanceChanged();
                count=wire.snapshots();source.release.countDown();maintenance.get(2,TimeUnit.SECONDS);wire.maintenance().finish(operation,true);runtime.pollCursorWaiting();
                check(wire.snapshots()==count,"maintenance resume cannot replay old waiting sample");
                hook(runtime,"c",IDEState.PRE_TOOL_USE);runtime.pollCursorWaiting();check(wire.state(0)==1,"maintenance requires fresh Hook and new native transition");
                db.put("c",false);runtime.pollCursorWaiting();
                count=wire.snapshots();
                try(var lease=wire.openDisplayLease(true)) {
                    db.put("c",true);runtime.pollCursorWaiting();check(wire.snapshots()==count,"busy device defers native snapshot");
                    runtime.displayModeProperty().set(AiRuntimeDisplayMode.SINGLE);
                    runtime.displayModeProperty().set(AiRuntimeDisplayMode.MULTI);
                }
                check(wire.snapshots()==count,"mode epoch cancels old deferred snapshot even after switching back");
                source.holdNext();runtime.startCursorMonitoring();check(source.entered.await(2,TimeUnit.SECONDS),"production scheduler performs native read");
                long closing=System.nanoTime();runtime.close();check(System.nanoTime()-closing<TimeUnit.SECONDS.toNanos(1),"close does not wait for database read");
                count=wire.snapshots();source.release.countDown();Thread.sleep(700);int reads=source.reads.get();runtime.pollCursorWaiting();
                check(wire.snapshots()==count&&source.reads.get()==reads,"close discards old sample and prevents further reads");
                Thread.sleep(600);check(source.reads.get()==reads,"closed production scheduler never polls again");
            } finally {if(source.release!=null)source.release.countDown();runtime.close();worker.shutdownNow();wire.shutdownTransport();}
        }
    }
    static AiRuntimeDisplayService setup(Database db,Source source,CaptureWire wire)throws Exception {
        wire.memoryConnect();await(wire::isConnected,"fixture connected");wire.readFirmwareCatalogKey();
        var runtime=new AiRuntimeDisplayService(wire,source);runtime.setCursorDataDir(db.root.toString());
        runtime.displayModeProperty().set(AiRuntimeDisplayMode.MULTI);runtime.bindSlot(0,session("a"));runtime.markDraftApplied(false,true);
        runtime.pollCursorWaiting();return runtime;
    }
    static void identityAndGenerationChecks()throws Exception {
        var reader=new CursorSessionDiscoveryService();
        try(var db=new Database()) {
            db.put("a",false);db.generation("a","G0");
            check(reader.readRuntimeStates(db.root,Set.of("a"),"3.27.22").get("a").generation().equals("G0"),"exact SQL identity projection");
            for(String bad:List.of("{}","{bad","{\"composerId\":\"a\",\"latestChatGenerationUUID\":5}",
                    "{\"composerId\":\"a\",\"latestChatGenerationUUID\":\"G0\",\"latestChatGenerationUUID\":\"G1\"}",
                    "{\"composerId\":\"a\",\"chatGenerationUUID\":\"G1\",\"latestChatGenerationUUID\":\"G0\"}",
                    "{\"composerId\":\"b\",\"latestChatGenerationUUID\":\"G0\"}")) {
                db.identity("a",bad);check(reader.readRuntimeStates(db.root,Set.of("a"),"3.27.22").get("a").state()==UNKNOWN,"missing/malformed/conflicting identity is unknown");
            }
            db.identity("a","{\"composerId\":\"a\",\"latestChatGenerationUUID\":\"G0\",\"ignoredContent\":\""+"x".repeat(2*1024*1024)+"\"}");
            long start=System.nanoTime();
            check(reader.readRuntimeStates(db.root,Set.of("a"),"3.27.22").get("a").state()==UNKNOWN
                    && System.nanoTime()-start<TimeUnit.SECONDS.toNanos(1),"oversized composer rejected before JSON traversal within deadline");
            db.put("b",true);db.generation("b","other");db.identity("a","{broken");
            var independent=reader.readRuntimeStates(db.root,Set.of("a","b"),"3.27.22");
            check(independent.get("a").state()==UNKNOWN && independent.get("b").state()==WAITING,"invalid identity in one slot cannot erase another valid slot");
            db.generation("a","G0");Source source=new Source();CaptureWire wire=new CaptureWire();var runtime=setup(db,source,wire);
            try {
                hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,"G0");db.put("a",true);runtime.pollCursorWaiting();
                check(wire.state(0)==2,"current generation waiting established");
                check(hookGeneration(runtime,"a",IDEState.STOP,"unseen-old")==AiRuntimeDisplayService.Delivery.IGNORED&&wire.state(0)==2,"first unfamiliar terminal cannot overwrite WAITING");
                check(hookGeneration(runtime,"a",IDEState.STOP,null)==AiRuntimeDisplayService.Delivery.IGNORED&&wire.state(0)==2,"missing generation cannot terminate identified wait");
                hookGeneration(runtime,"a",IDEState.STOP,"G0");check(wire.state(0)==3,"matching current terminal still completes");
                db.put("a",false);runtime.pollCursorWaiting();
                check(hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,"G1")==AiRuntimeDisplayService.Delivery.PENDING,"new generation candidate waits for independent native identity");
                db.put("a",true);runtime.pollCursorWaiting();check(wire.state(0)==0,"new header with lagging old identity is UNKNOWN");
                hookGeneration(runtime,"a",IDEState.STOP,"G0");check(wire.state(0)==0,"late old stop cannot manufacture DONE during cross-table save lag");
                db.generation("a","G1");runtime.pollCursorWaiting();check(wire.state(0)==2,"fast G1 first true accepted using prior false plus fresh matching Hook and native identity");
                check(hookGeneration(runtime,"a",IDEState.STOP,"G0")==AiRuntimeDisplayService.Delivery.IGNORED&&wire.state(0)==2,"known retired terminal ignored");
                check(hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,"G0")==AiRuntimeDisplayService.Delivery.IGNORED&&wire.state(0)==2,"known retired nonterminal ignored");
                hookGeneration(runtime,"a",IDEState.STOP,"G1");check(wire.state(0)==3,"new current terminal completes normally");
                // New run without requiring the old terminal: native UUID independently advances.
                db.put("a",false);runtime.pollCursorWaiting();hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,"G2");
                db.generation("a","G2");db.put("a",true);runtime.pollCursorWaiting();check(wire.state(0)==2,"subsequent real run remains usable");
                db.put("a",false);runtime.pollCursorWaiting();hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,"G3");
                db.generation("a","G3");db.put("a",true);runtime.pollCursorWaiting();check(wire.state(0)==2,"native next run works even if previous stop was lost");
                db.generation("a","G2");runtime.pollCursorWaiting();check(wire.state(0)==0,"regressed native identity does not resurrect retired run");
            } finally {runtime.close();wire.shutdownTransport();}
        }
    }
    static void legacyBoundaryChecks()throws Exception {
        try(var db=new Database()) {
            db.put("a",false);db.generation("a","current");Source source=new Source();CaptureWire wire=new CaptureWire();
            wire.memoryConnect();await(wire::isConnected,"legacy fixture connected");wire.readFirmwareCatalogKey();
            var runtime=new AiRuntimeDisplayService(wire,source);
            try {
                runtime.setCursorDataDir(db.root.toString());runtime.displayModeProperty().set(AiRuntimeDisplayMode.MULTI);
                runtime.bindSlot(0,session("a"));runtime.markDraftApplied(false,true);
                check(hookGeneration(runtime,"a",IDEState.STOP,null)==AiRuntimeDisplayService.Delivery.IGNORED,"isolated legacy terminal cannot invent DONE");
                check(hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,null)==AiRuntimeDisplayService.Delivery.SENT&&wire.state(0)==1,"pre-native legacy conversation Hook still RUNs");
                check(hookGeneration(runtime,"a",IDEState.STOP,null)==AiRuntimeDisplayService.Delivery.SENT&&wire.state(0)==3,"legacy terminal requires existing same-connection runtime fact");
                hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,null);runtime.pollCursorWaiting();
                db.put("a",true);runtime.pollCursorWaiting();check(wire.state(0)!=2,"legacy nonterminal never anchors native yellow");
                check(hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,null)==AiRuntimeDisplayService.Delivery.IGNORED,"native identity context cannot fall back to missing-ID RUN");
                db.identity("a","{}");runtime.pollCursorWaiting();
                check(hookGeneration(runtime,"a",IDEState.STOP,null)==AiRuntimeDisplayService.Delivery.IGNORED,"native identity failure cannot fall back to missing-ID DONE");
            } finally {runtime.close();wire.shutdownTransport();}
        }
    }
    static void ackAndCancellationChecks()throws Exception {
        try(var db=new Database()) {
            db.put("a",false);db.generation("a","current");Source source=new Source();CaptureWire wire=new CaptureWire();var runtime=setup(db,source,wire);
            ExecutorService pool=Executors.newFixedThreadPool(3);HookDispatchServer server=new HookDispatchServer(wire,runtime,0);
            try {
                hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,"current");server.start();db.put("a",true);wire.hold99=true;
                Future<?> poll=pool.submit(runtime::pollCursorWaiting);check(wire.ackEntered.await(2,TimeUnit.SECONDS),"actual USB 0x99 send waits for fixture ACK");
                Future<String> hook=pool.submit(()->{
                    try(var socket=new java.net.Socket("127.0.0.1",server.getActualPort())) {
                        socket.setSoTimeout(1000);
                        new java.io.PrintWriter(socket.getOutputStream(),true).println("{\"cmd\":\"stop\",\"hookInput\":{\"conversation_id\":\"a\",\"generation_id\":\"current\"}}");
                        return new java.io.BufferedReader(new java.io.InputStreamReader(socket.getInputStream())).readLine();
                    }
                });
                check(hook.get(500,TimeUnit.MILLISECONDS).contains("PENDING"),"actual TCP Hook returns PENDING while observer holds device ACK");
                Future<?> ui=pool.submit(()->runtime.setCursorDataDir(db.root.toString()));
                ui.get(500,TimeUnit.MILLISECONDS);check(!poll.isDone(),"UI directory setter completes while device ACK is still blocked");
                wire.ackRelease.countDown();poll.get(2,TimeUnit.SECONDS);await(()->wire.state(0)==0,"latest invalidated EMPTY drains after ACK");
                runtime.pollCursorWaiting();db.generation("a","next");runtime.pollCursorWaiting();hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,"next");
                var lockField=BleManager.class.getDeclaredField("commandTransactionLock");lockField.setAccessible(true);Object transaction=lockField.get(wire);
                CountDownLatch held=new CountDownLatch(1),release=new CountDownLatch(1);
                Future<?> owner=pool.submit(()->{synchronized(transaction){held.countDown();try{release.await(3,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}}});
                check(held.await(1,TimeUnit.SECONDS),"fixture owns actual device transaction lock");
                long before=wire.snapshots();db.put("a",false);runtime.pollCursorWaiting();db.put("a",true);
                AtomicReference<Thread> sender=new AtomicReference<>();
                Future<?> queued=pool.submit(()->{sender.set(Thread.currentThread());runtime.pollCursorWaiting();});
                await(()->sender.get()!=null&&sender.get().getState()==Thread.State.BLOCKED,"snapshot queued before actual device send");
                runtime.displayModeProperty().set(AiRuntimeDisplayMode.SINGLE);release.countDown();owner.get(2,TimeUnit.SECONDS);queued.get(2,TimeUnit.SECONDS);
                check(wire.snapshots()==before,"mode cancellation inside device lock suppresses queued old frame");
            } finally {wire.ackRelease.countDown();server.stop();runtime.close();pool.shutdownNow();wire.shutdownTransport();}
        }
    }
    static void unavailableNativeKeepsHookChecks()throws Exception {
        for(String version:List.of("3.14.7","unknown-version","3.27.22")) {
            try(var db=new Database()) {
                // No readable native identity is not evidence that ordinary Hook delivery stopped.
                db.raw("a","{}");Source source=new Source();source.process=new CursorSessionDiscoveryService.CursorProcess("fallback-process",version);
                CaptureWire wire=new CaptureWire();wire.memoryConnect();wire.readFirmwareCatalogKey();
                var runtime=new AiRuntimeDisplayService(wire,source);
                try {
                    runtime.setCursorDataDir(db.root.toString());runtime.displayModeProperty().set(AiRuntimeDisplayMode.MULTI);
                    runtime.bindSlot(0,session("a"));runtime.markDraftApplied(false,true);runtime.pollCursorWaiting();
                    check(hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,null)==AiRuntimeDisplayService.Delivery.SENT && wire.state(0)==1,
                        version+" unreadable native preserves ordinary missing-generation RUN");
                    runtime.pollCursorWaiting();
                    check(hookGeneration(runtime,"a",IDEState.STOP,null)==AiRuntimeDisplayService.Delivery.SENT && wire.state(0)==3,
                        version+" unreadable native preserves ordinary missing-generation STOP");
                    check(hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,"fallback-1")==AiRuntimeDisplayService.Delivery.SENT && wire.state(0)==1,
                        version+" unreadable native preserves identified RUN");
                    runtime.pollCursorWaiting();
                    check(hookGeneration(runtime,"a",IDEState.STOP,"unrelated-old")==AiRuntimeDisplayService.Delivery.IGNORED && wire.state(0)==1,
                        version+" unrelated old identified STOP cannot clear current RUN");
                    check(hookGeneration(runtime,"a",IDEState.STOP,"fallback-1")==AiRuntimeDisplayService.Delivery.SENT && wire.state(0)==3,
                        version+" matching identified STOP completes current RUN");
                    check(hookGeneration(runtime,"a",IDEState.PRE_TOOL_USE,"fallback-2")==AiRuntimeDisplayService.Delivery.SENT && wire.state(0)==1,
                        version+" next identified RUN remains usable");
                    check(hookGeneration(runtime,"a",IDEState.STOP,"fallback-1")==AiRuntimeDisplayService.Delivery.IGNORED && wire.state(0)==1,
                        version+" retired identified STOP cannot clear next RUN");
                    runtime.pollCursorWaiting();check(wire.state(0)==1,version+" UNKNOWN metadata does not manufacture WAITING or DONE");
                } finally {runtime.close();wire.shutdownTransport();}
            }
        }
    }
    public static void main(String[] args)throws Exception {
        System.setProperty("user.home",Files.createTempDirectory("wd009-cursor-home-").toString());
        unavailableNativeKeepsHookChecks();databaseChecks();runtimeChecks();identityAndGenerationChecks();legacyBoundaryChecks();ackAndCancellationChecks();System.out.println("PASS "+checks+" Cursor SQLite/WAL + actual runtime/transport checks; synthetic native facts, no real Cursor or hardware PASS");
    }
}
