package com.example.ahakey.service;

import com.example.ahakey.model.*;
import com.example.ahakey.protocol.*;
import com.example.ahakey.util.StudioStore;
import javafx.application.Platform;
import java.io.IOException;
import java.security.SecureRandom;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;
import static com.example.ahakey.model.FactoryResetState.Phase;
import static com.example.ahakey.service.FactoryResetStore.*;

/** Owns restore intent independently of windows. Reconnect/restart paths are query-only. */
public final class FactoryResetService implements AutoCloseable {
    public interface Device {
        Target target(); boolean connected();
        void lock(long generation)throws Exception; void unlock();
        <T>T authorized(long generation,boolean start,Callable<T> action)throws Exception;
        FactoryResetProtocol.Reply exchange(byte[] request,long generation)throws Exception;
        default void prepareDraft()throws Exception{}
        default void localPreparationRecovered()throws Exception{}
        void discardDraft()throws Exception;
        default void discardDraft(long generation)throws Exception{discardDraft();}
        void readback(long generation)throws Exception;
    }
    public record Confirmation(Target target,long durableAttempt,String taskId){}
    public record Association(String taskId,long attempt,Target target){}
    private final Device device;
    private final FactoryResetStore store;
    private final Consumer<Runnable> ui;
    private final FactoryResetState state;
    private final ScheduledExecutorService worker=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"factory-reset");t.setDaemon(true);return t;});
    private final AtomicBoolean running=new AtomicBoolean();
    private final SecureRandom random=new SecureRandom();
    private volatile Pending pending;
    private volatile Target bound;
    private volatile Target quarantined;
    private volatile Phase phase=Phase.IDLE;
    private volatile boolean closed,corrupt,localCleanup;
    private volatile Confirmation confirmation;
    private int polls;
    public FactoryResetService(Device device,FactoryResetStore store,FactoryResetState state,Consumer<Runnable> ui){
        this.device=device;this.store=store;this.state=state;this.ui=ui;
        try{pending=store.load();localCleanup=store.localRecoveryRequired();pending=store.recoverPreparation();if(localCleanup)device.localPreparationRecovered();localCleanup=false;if(pending!=null)publish(Phase.UNKNOWN,"上次设备恢复结果尚未确认，请连接原键盘后查看进度");}
        catch(Exception e){try{localCleanup=localCleanup||store.localRecoveryRequired();}catch(IOException ignored){}if(localCleanup)publish(Phase.UNAVAILABLE,"恢复尚未发送，本地准备回滚未完成；请重试本地清理");else{corrupt=true;publish(Phase.UNKNOWN,"待核实记录损坏，不能关联或自动重试；请保留记录交支持处理");}}
    }
    public FactoryResetState state(){return state;}
    public boolean hasPending(){return pending!=null||corrupt||localCleanup;}
    public boolean requiresLocalCleanup(){return localCleanup||pending!=null&&pending.stage().equals("LOCAL_PREPARING");}
    public Target currentTarget(){return device.connected()?device.target():null;}
    public Target originalTarget(){return pending==null?null:pending.target();}
    public boolean requiresAssociation(){return pending!=null&&(bound==null||!bound.sameConnection(device.target()));}
    public boolean definitelyDifferent(){return pending!=null&&pending.target().definitelyDifferent(currentTarget());}
    public boolean protectCurrentTarget(){return (pending!=null||corrupt||localCleanup)&&device.connected()&&(pending==null||!pending.target().definitelyDifferent(device.target()));}
    public CompletableFuture<Confirmation> prepare(){
        return execute(()->{
            if(corrupt)throw new IOException("待核实记录损坏，不能发起恢复");
            if(requiresLocalCleanup())throw new IOException("请先重试本地准备清理");
            if(pending!=null&&phase!=Phase.INCOMPLETE)throw new IOException("已有恢复任务，请查看进度或重新查询");
            if(!device.connected())throw new IOException("请先连接需要恢复的键盘");
            Target target=device.target();publish(Phase.CHECKING,"正在只读检查恢复能力…");
            var reply=pending==null?query(target):device.authorized(target.generation(),false,()->query(target));
            current(target);
            if(reply.result()!=0||reply.state()==FactoryResetProtocol.State.STORAGE_UNAVAILABLE||reply.state()==FactoryResetProtocol.State.UNSUPPORTED)throw new IOException("设备未提供可用恢复能力或存储不可用");
            if(reply.state()==FactoryResetProtocol.State.IN_PROGRESS)throw new IOException("设备已有恢复正在进行，不能重复发起");
            if(reply.attempt()==0xffffffffL)throw new IOException("恢复次数已到边界，不能发起");
            confirmation=new Confirmation(target,reply.attempt(),UUID.randomUUID().toString());
            publish(Phase.CONFIRM,"等待确认");return confirmation;
        });
    }
    public void cancelConfirmation(){confirmation=null;if(pending==null)publish(Phase.IDLE,"已取消，未发送恢复命令，草稿保留");else publish(Phase.INCOMPLETE,"设备恢复未完成，未重试");}
    public CompletableFuture<Void> confirm(Confirmation accepted){
        return execute(()->{
            if(accepted==null||accepted!=confirmation)throw new IOException("恢复确认已失效");
            current(accepted.target());
            Pending previous=pending;boolean[] sending={false};boolean preparing=false;
            try{
                bound=accepted.target();device.lock(bound.generation());
                device.authorized(bound.generation(),false,()->{
                    var now=query(bound);
                    if(now.result()!=0||now.attempt()!=accepted.durableAttempt()||now.state()==FactoryResetProtocol.State.IN_PROGRESS||now.state()==FactoryResetProtocol.State.STORAGE_UNAVAILABLE||now.state()==FactoryResetProtocol.State.UNSUPPORTED)
                        throw new IOException("设备恢复状态已变化，请重新确认");return null;
                });
                Pending intent=new Pending(1,accepted.taskId(),accepted.target(),accepted.durableAttempt()+1,"LOCAL_PREPARING");
                device.prepareDraft();
                preparing=true;store.beginPreparation(intent,previous);pending=intent;confirmation=null;
                store.prepareRuntime();current(bound);
                // Pending quarantines the old draft; its original bytes and live edits remain intact
                // throughout local preparation. Only the device exchange crosses the send boundary.
                publish(Phase.WAITING,"等待设备确认；保持 USB 供电，关闭窗口不会停止已开始的恢复");
                Target target=bound;
                FactoryResetProtocol.Reply reply;
                try{
                    reply=device.authorized(target.generation(),true,()->{
                        current(target);
                        Pending dispatch=new Pending(1,intent.taskId(),intent.target(),intent.attempt(),"SENDING");
                        store.save(dispatch);pending=dispatch;sending[0]=true;
                        return device.exchange(FactoryResetProtocol.start(random.nextInt(),intent.attempt()),target.generation());
                    });
                }finally{
                    if(sending[0])device.discardDraft(target.generation());
                }
                current(target);
                if(reply.result()==1&&reply.attempt()==accepted.durableAttempt()
                        &&(reply.state()==FactoryResetProtocol.State.NEVER||reply.state()==FactoryResetProtocol.State.COMPLETE||reply.state()==FactoryResetProtocol.State.INCOMPLETE)){
                    pending=new Pending(1,intent.taskId(),intent.target(),reply.attempt(),"REJECTED_NOT_STARTED");store.save(pending);
                    finishReadback(target,false);return null;
                }
                pending=new Pending(1,intent.taskId(),intent.target(),intent.attempt(),"SENT");store.save(pending);
                accept(reply,target);return null;
            }catch(Exception e){
                if(!sending[0]){
                    try{
                        pending=preparing?store.rollbackPreparation(accepted.taskId()):previous;
                        if(pending==null){device.unlock();bound=null;publish(Phase.UNAVAILABLE,"未发送恢复命令，草稿及运行偏好保留："+safe(e));}
                        else publish(Phase.INCOMPLETE,"未发送新的恢复命令，已保留原任务与草稿："+safe(e));
                    }catch(Exception rollback){
                        pending=store.load();localCleanup=store.localRecoveryRequired();publish(Phase.UNAVAILABLE,"未发送恢复命令，草稿保留；本地准备回滚待重试："+safe(rollback));
                    }
                }else publish(Phase.UNKNOWN,"恢复结果未确认："+safe(e)+"；不会自动重发，请重新查询");
                throw e;
            }
        });
    }
    public Association association(){
        Pending p=pending;Target target=currentTarget();
        return p==null||target==null?null:new Association(p.taskId(),p.attempt(),target);
    }
    public CompletableFuture<Void> queryAgain(Association association){
        return execute(()->{
            if(requiresLocalCleanup()){
                pending=store.rollbackPreparation();device.localPreparationRecovered();localCleanup=false;
                if(pending==null){device.unlock();bound=null;publish(Phase.UNAVAILABLE,"未发送恢复命令，本地准备已撤销，草稿保留");}
                else publish(Phase.UNKNOWN,"新恢复未发送，本地准备已撤销；原恢复任务仍待查询");
                return null;
            }
            if(corrupt||pending==null)throw new IOException("没有可关联的有效待核实记录");
            if(!device.connected())throw new IOException("请连接原键盘后重新查询");
            Target target=device.target();
            if(association!=null&&(!association.taskId().equals(pending.taskId())||association.attempt()!=pending.attempt()||!association.target().sameConnection(target)))
                throw new IOException("确认时的任务或连接已改变，请重新核对原设备");
            if(pending.target().definitelyDifferent(target))throw new IOException("已明确是另一台设备，不能关联此恢复任务");
            if(bound==null||!bound.sameConnection(target)){
                if(!pending.target().sameBle(target)&&association==null)throw new IOException("无法自动核对原设备，请确认这是原设备并查询");
                device.lock(target.generation());bound=target;quarantined=null;
            }
            current(target);var reply=device.authorized(target.generation(),false,()->query(target));accept(reply,target);return null;
        });
    }
    public void connectionChanged(){
        if(closed)return;
        worker.execute(()->{
            Target target=currentTarget();
            if(quarantined!=null&&!quarantined.sameConnection(target)){device.unlock();quarantined=null;}
            if(bound!=null&&!bound.sameConnection(target)){device.unlock();bound=null;confirmation=null;if(pending!=null)publish(Phase.UNKNOWN,"连接已改变，恢复结果未确认；仅原设备可重新查询");}
            if(pending!=null&&bound==null&&target!=null&&pending.target().sameBle(target))queryAgain(null);
            else if(protectCurrentTarget()&&bound==null&&quarantined==null){
                try{device.lock(target.generation());quarantined=target;publish(Phase.UNKNOWN,"上次设备恢复结果尚未确认。当前设备身份未核对，暂只读；请查看进度确认原设备后查询");}
                catch(Exception e){publish(Phase.UNKNOWN,"原设备结果待确认；当前事务结束后可查看进度，普通写入已暂停");}
            }
        });
    }
    private FactoryResetProtocol.Reply query(Target target)throws Exception{current(target);var r=device.exchange(FactoryResetProtocol.query(random.nextInt()),target.generation());current(target);return r;}
    private void accept(FactoryResetProtocol.Reply reply,Target target)throws Exception{
        current(target);
        if(pending==null||reply.attempt()!=pending.attempt()){publish(Phase.UNKNOWN,"恢复次数与本任务不符，不能认定本次成功");return;}
        if(reply.result()!=0){publish(Phase.UNKNOWN,"设备拒绝或存储查询失败，恢复结果未确认");return;}
        if(pending.stage().equals("REJECTED_NOT_STARTED")){
            if(reply.state()==FactoryResetProtocol.State.IN_PROGRESS){publish(Phase.UNKNOWN,"设备状态已变化，不能解除只读");return;}
            finishReadback(target,false);return;
        }
        switch(reply.state()){
            case IN_PROGRESS -> {publish(Phase.RESTORING,"设备正在恢复，请保持 USB 供电");if(++polls<=60)worker.schedule(()->queryAgain(null),2,TimeUnit.SECONDS);else publish(Phase.UNKNOWN,"恢复尚未结束，已停止自动查询；可重新查询");}
            case INCOMPLETE -> publish(Phase.INCOMPLETE,"设备报告恢复未完成；可再次确认后重新恢复");
            case COMPLETE -> finishReadback(target,true);
            default -> publish(Phase.UNKNOWN,"设备状态不能证明本次恢复完成："+reply.state());
        }
    }
    private void finishReadback(Target target,boolean restored){
        publish(Phase.READING,restored?"设备已恢复，正在读取配置…":"设备明确拒绝启动恢复；正在重新读取当前配置…");
        try{
            device.authorized(target.generation(),false,()->{device.readback(target.generation());return null;});current(target);
            store.save(new Pending(1,pending.taskId(),pending.target(),pending.attempt(),restored?"COMPLETE_READBACK":"REJECTED_NOT_STARTED"));
            store.finishPreparation();store.clear();pending=null;device.unlock();bound=null;
            publish(restored?Phase.COMPLETE:Phase.UNAVAILABLE,restored?"恢复完成；配置已从设备读回":"设备未启动恢复，当前配置已重新读取。请检查 USB 外部供电及设备状态，再次确认后可重试；未自动重发");
        }catch(Exception e){publish(Phase.READ_FAILED,(restored?"设备已恢复，":"设备未启动恢复，")+"配置读取或记录保存失败："+safe(e)+"；重新读取不会再次恢复");}
    }
    private void current(Target target)throws IOException{if(closed||target==null||!device.connected()||!target.sameConnection(device.target()))throw new IOException("目标或连接代次已改变");}
    private <T>CompletableFuture<T> execute(Callable<T> action){
        CompletableFuture<T> result=new CompletableFuture<>();
        if(closed||!running.compareAndSet(false,true)){result.completeExceptionally(new IOException("恢复任务正在处理，请等待"));return result;}
        ui.accept(()->state.busy.set(true));
        worker.execute(()->{
            T value=null;Exception failure=null;
            try{value=action.call();}
            catch(Exception e){if(phase==Phase.CHECKING)publish(Phase.UNAVAILABLE,"恢复检查未通过："+safe(e)+"；未发送恢复命令");else if(pending!=null&&phase!=Phase.READ_FAILED&&phase!=Phase.UNAVAILABLE&&phase!=Phase.INCOMPLETE)publish(Phase.UNKNOWN,"恢复结果未确认："+safe(e));failure=e;}
            finally{running.set(false);ui.accept(()->state.busy.set(false));}
            if(failure==null)result.complete(value);else result.completeExceptionally(failure);
        });return result;
    }
    private void publish(Phase next,String message){phase=next;Pending p=pending;Target b=bound;Target shown=p!=null?p.target():confirmation==null?currentTarget():confirmation.target();
        ui.accept(()->{state.phase.set(next);state.message.set(message);state.target.set(shown==null?"":shown.display());state.pending.set(p!=null||corrupt||localCleanup);state.readOnly.set(protectCurrentTarget());});
    }
    private static String safe(Exception e){return e.getMessage()==null?"本地或设备请求异常":e.getMessage();}
    @Override public void close(){closed=true;confirmation=null;worker.shutdownNow();/* Intent is already durable; never replay or cancel firmware. */}

    /** Production adapter reads every UI-visible field under the restore-only permission. */
    public static FactoryResetService production(BleManager ble,StudioState studio,DeviceStatus status,K1RouteService k1,DisplayConfigService display,Runnable invalidate,Runnable discardRuntime){
        return production(ble,studio,status,k1,display,invalidate,discardRuntime,new FactoryResetStore(),()->{});
    }
    public static FactoryResetService production(BleManager ble,StudioState studio,DeviceStatus status,K1RouteService k1,DisplayConfigService display,Runnable invalidate,Runnable discardRuntime,FactoryResetStore store){
        return production(ble,studio,status,k1,display,invalidate,discardRuntime,store,()->{});
    }
    public static FactoryResetService production(BleManager ble,StudioState studio,DeviceStatus status,K1RouteService k1,DisplayConfigService display,Runnable invalidate,Runnable discardRuntime,FactoryResetStore store,Runnable recoverRuntime){
        Device device=new Device(){
            public Target target(){return ble.factoryTarget();}
            public boolean connected(){return ble.isConnected()&&ble.getCachedStatus().isConnected();}
            public void lock(long generation)throws Exception{ble.beginFactoryReset(generation);onFx(()->{invalidate.run();studio.factoryReset().readOnly.set(true);});}
            public void unlock(){ble.endFactoryReset();Platform.runLater(()->{studio.factoryReset().readOnly.set(false);display.maintenanceChanged();});}
            public <T>T authorized(long generation,boolean start,Callable<T> work)throws Exception{return ble.maintenance().withinFactory(generation,start,work::call);}
            public FactoryResetProtocol.Reply exchange(byte[] request,long generation)throws Exception{return ble.exchangeFactoryReset(request,generation);}
            public void prepareDraft()throws Exception{StudioStore.prepareForFactoryReset();onFx(()->{});}
            public void localPreparationRecovered()throws Exception{onFx(recoverRuntime);}
            public void discardDraft()throws Exception{discardDraft(ble.connectionGeneration());}
            public void discardDraft(long generation)throws Exception{onFx(()->{if(generation!=ble.connectionGeneration()||!connected())throw new IllegalStateException("恢复目标已改变");discardRuntime.run();studio.discardForFactoryReset(generation);});}
            public void readback(long generation)throws Exception{
                ble.readFirmwareCatalogKey(generation);
                var keys=new ArrayList<AhaKeyResponseParser.OrdinaryKeyReadback>();var routes=new ArrayList<K1Route>();var pictures=new ArrayList<AhaKeyResponseParser.PictureState>();
                for(int mode=0;mode<4;mode++){
                    for(int key=0;key<4;key++)keys.add(ble.readOrdinaryKeyConfig(mode,key));
                    final int m=mode;routes.add(ble.k1RouteTransaction(generation,()->k1.read(m,generation)));
                    var picture=ble.readPictureState(mode);if(picture==null||picture.mode()!=mode)throw new IOException("图片选择读回不匹配");pictures.add(picture);
                }
                var side=ble.readSideSwitchConfig(generation);int sleep=ble.readSleepWaitTimeMinutes();var actual=ble.queryDeviceStatusSnapshot(15000,true);
                int[] brightness=new int[1];int[][] lights=new int[4][9];var metadata=new LinkedHashMap<Integer,OledResourceState.Metadata>();
                ble.readDisplayConfig(generation,lease->{
                    brightness[0]=readDisplay(ble,lease,0).value();
                    for(int mode=0;mode<4;mode++)for(int ai=0;ai<9;ai++)lights[mode][ai]=readDisplay(ble,lease,1,mode,ai).value();
                    for(int entry=0;entry<19;entry++){var a=readDisplay(ble,lease,2,entry);var b=readDisplay(ble,lease,3,entry);metadata.put(entry,new OledResourceState.Metadata(a.value()==1,a.writeState(),b.frames(),b.bytes(),b.crc()));}
                });
                if(generation!=ble.connectionGeneration()||!connected())throw new IOException("读回期间连接已改变");
                onFx(()->{
                    if(generation!=ble.connectionGeneration()||!connected())throw new IllegalStateException("读回目标已改变");
                    studio.discardForFactoryReset(generation);studio.k1Routes().capability.set(K1RouteState.Capability.ROUTE);
                    keys.forEach(studio::applyOrdinaryKeyReadback);
                    for(int m=0;m<4;m++){studio.applyK1Route(m,routes.get(m),keys.get(m*4).description());studio.markInputModeRead(ModeSlot.fromIndex(m));studio.applyFactoryPicture(pictures.get(m));}
                    studio.applySideSwitchReadback(side);studio.setCp4cInputConfigEnabled(true);
                    studio.displayConfig().readBrightness(brightness[0]);
                    for(int m=0;m<4;m++)for(int a=0;a<9;a++)studio.displayConfig().readEffect(m,a,lights[m][a]);
                    metadata.forEach((entry,value)->studio.displayConfig().put(studio.displayConfig().resources.get(entry).merge(value)));
                    status.setConnected(true);status.setWorkMode(actual.getWorkMode());status.setSwitchState(actual.getSwitchState());status.setSavedBindings(side);status.setLightBrightness(brightness[0]);status.setFactorySleepMinutes(sleep);
                    studio.syncStatusProperty().set("恢复配置已读回：四模式按键/K1/拨杆、状态、待机、亮度/灯效、图片选择及19条资源元数据");
                    try{StudioStore.saveStrict(studio.toPersisted());}catch(IOException e){throw new java.io.UncheckedIOException(e);}
                });
            }
        };
        FactoryResetService service=new FactoryResetService(device,store,studio.factoryReset(),Platform::runLater);
        ble.setFactoryConnectionListener(service::connectionChanged);ble.setFactoryWriteGuard(service::protectCurrentTarget);service.connectionChanged();return service;
    }
    private static AhaKeyResponseParser.DisplayRead readDisplay(BleManager ble,BleManager.DisplayLease lease,int kind,int... selectors)throws Exception{
        var value=AhaKeyResponseParser.parseDisplayRead(ble.exchangeDisplay(lease,AhaKeyProtocol.displayRead(kind,selectors)),kind,selectors);
        if(value==null)throw new IOException("显示配置读回不匹配：kind="+kind);return value;
    }
    private static void onFx(Runnable action)throws Exception{
        if(Platform.isFxApplicationThread()){action.run();return;}
        CompletableFuture<Void> done=new CompletableFuture<>();Object gate=new Object();boolean[] state={false,false};
        Platform.runLater(()->{
            synchronized(gate){if(state[1])return;state[0]=true;}
            try{action.run();done.complete(null);}catch(Throwable e){done.completeExceptionally(e);}
        });
        try{done.get(30,TimeUnit.SECONDS);}
        catch(TimeoutException|InterruptedException e){
            synchronized(gate){if(!state[0]){state[1]=true;throw e;}}
            // Once FX mutation starts, do not report failure and allow it to mutate later.
            // Await its outcome before any rollback/unlock; interruption is restored afterwards.
            boolean interrupted=e instanceof InterruptedException;
            try{for(;;)try{done.get();break;}catch(InterruptedException again){interrupted=true;}}
            finally{if(interrupted)Thread.currentThread().interrupt();}
        }
    }
}
