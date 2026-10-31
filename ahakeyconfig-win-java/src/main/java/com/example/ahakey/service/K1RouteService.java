package com.example.ahakey.service;

import com.example.ahakey.model.*;
import com.example.ahakey.protocol.K1RouteProtocol;
import javafx.application.Platform;
import java.io.IOException;
import java.security.SecureRandom;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** Device authority is per connection/mode; all edits and UI completion occur on FX. */
public final class K1RouteService implements AutoCloseable {
    private final StudioState studio;
    private final K1RouteState state;
    private final BleManager ble;
    private final SecureRandom random = new SecureRandom();
    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {Thread t=new Thread(r,"k1-route");t.setDaemon(true);return t;});
    private long refreshTicket;
    private boolean closed;
    private record Observed(K1Route route,String description) {}
    private record LegacyObserved(List<com.example.ahakey.protocol.AhaKeyResponseParser.OrdinaryKeyReadback> keys,List<Integer> unavailable) {}
    public K1RouteService(StudioState studio,BleManager ble) {
        this.studio=studio;this.state=studio.k1Routes();this.ble=ble;
        studio.selectedModeProperty().addListener((o,a,b)->refresh());
        studio.selectedPartProperty().addListener((o,a,b)->{if(b==StudioPart.KEY1)refresh();});
    }
    public void connectionChanged() {
        long generation=ble.connectionGeneration();
        boolean changed=state.generation()!=generation||!ble.isConnected()||!ble.getCachedStatus().isConnected();
        if(changed) {
            refreshTicket++;state.reset(generation);state.busy.set(false);
        }
        if(changed&&ble.isConnected()&&ble.getCachedStatus().isConnected())refresh();
    }
    public void refresh() {
        if(closed||!ble.isConnected()||!ble.getCachedStatus().isConnected()||!ble.maintenance().normalAllowed())return;
        long generation=ble.connectionGeneration();if(state.generation()!=generation)state.reset(generation);
        int mode=studio.getSelectedMode().getIndex();long ticket=++refreshTicket;
        state.busy.set(true);state.message.set("正在读取键盘K1设置…");
        worker.execute(()->{
            try {
                Object result=ble.k1RouteTransaction(generation,()->{
                    int nonce=random.nextInt();byte[] reply=ble.exchangeK1Route(K1RouteProtocol.request(0,K1RouteProtocol.fields(4).putInt(nonce).array()),generation);
                    if(K1RouteProtocol.legacyAck(reply)&&ble.isDisplayAdmitted()) {
                        List<com.example.ahakey.protocol.AhaKeyResponseParser.OrdinaryKeyReadback> keys=new ArrayList<>();
                        List<Integer> unavailable=new ArrayList<>();
                        for(int m=0;m<4;m++)try{keys.add(ble.readOrdinaryKeyConfig(m,0));}catch(Exception failure){if(generation!=ble.connectionGeneration())throw failure;unavailable.add(m);}
                        return new LegacyObserved(List.copyOf(keys),List.copyOf(unavailable));
                    }
                    K1RouteProtocol.capability(reply,nonce);
                    Platform.runLater(()->{if(current(generation,ticket))state.capability.set(K1RouteState.Capability.ROUTE);});
                    K1Route route=read(mode,generation);String description=null;
                    try{description=ble.readOrdinaryKeyConfig(mode,0).description();}catch(Exception unavailable){if(generation!=ble.connectionGeneration())throw unavailable;}
                    return new Observed(route,description);
                });
                Platform.runLater(()->{
                    if(!current(generation,ticket))return;
                    if(result instanceof LegacyObserved legacy){state.capability.set(K1RouteState.Capability.LEGACY);for(var key:legacy.keys()){studio.applyOrdinaryKeyReadback(key);state.observedLegacy(key.mode());}for(int missing:legacy.unavailable())state.failed(missing,"旧固件K1无法读取，保持设备当前配置。");state.message.set(legacy.unavailable().contains(mode)?"旧固件K1无法读取，保持设备当前配置。":"旧固件：已读取可确认模式的普通K1配置");}
                    else {Observed observed=(Observed)result;state.capability.set(K1RouteState.Capability.ROUTE);studio.applyK1Route(mode,observed.route(),observed.description());state.message.set(observed.description()==null?"K1动作已读取；描述暂不可读，保持设备端描述。":"已读取键盘当前模式K1设置");}
                });
            }catch(Exception e){Platform.runLater(()->{if(current(generation,ticket))state.failed(mode,"K1配置暂不可读取，无法确认当前设置："+e.getMessage());});}
            finally{Platform.runLater(()->{if(current(generation,ticket))state.busy.set(false);});}
        });
    }
    private boolean current(long generation,long ticket) {return !closed&&generation==ble.connectionGeneration()&&ticket==refreshTicket&&ble.isConnected();}
    public K1Route read(int mode,long generation)throws Exception {
        if(mode<0||mode>3)throw new IOException("K1模式无效");
        byte[] bytes=new byte[K1Route.SIZE];long expected=-1;
        for(int offset=0;offset<bytes.length;){
            int count=Math.min(42,bytes.length-offset),nonce=random.nextInt();
            byte[] req=K1RouteProtocol.request(0x10,K1RouteProtocol.fields(7).putInt(nonce).put((byte)mode).put((byte)offset).put((byte)count).array());
            var b=K1RouteProtocol.response(ble.exchangeK1Route(req,generation),0x10,nonce,12+count);
            if((b.get()&255)!=mode||(b.get()&255)!=offset||(b.getShort()&65535)!=bytes.length)throw new IOException("K1读片目标不匹配");
            long crc=Integer.toUnsignedLong(b.getInt());if(expected!=-1&&expected!=crc)throw new IOException("K1读片快照变化");expected=crc;
            b.get(bytes,offset,count);offset+=count;
        }
        if(K1RouteProtocol.crc(bytes)!=expected)throw new IOException("K1 CRC不匹配");return new K1Route(bytes);
    }
    public record Edit(int mode,long revision,K1Route route,String description,boolean writeDescription) {}
    public record LegacyEdit(int mode,long revision,int type,byte[] action,String description) {}
    public List<LegacyEdit> legacySnapshot() {
        if(state.capability.get()!=K1RouteState.Capability.LEGACY)return List.of();
        List<LegacyEdit> edits=new ArrayList<>();
        for(ModeSlot mode:ModeSlot.values()) {
            if(!state.confirmed(mode.getIndex()))continue;
            KeyConfig key=studio.getKeyConfig(mode,StudioPart.KEY1);
            edits.add(new LegacyEdit(mode.getIndex(),state.edit(mode.getIndex()),key.usesMacro()?0x74:0x73,DeviceSyncService.encodeKeyActionPayload(key),DeviceSyncService.sanitizeDescription(key.getDescription())));
        }
        return List.copyOf(edits);
    }
    public void verifyLegacy(List<LegacyEdit> edits,long generation)throws Exception {
        if(generation!=ble.connectionGeneration())throw new IOException("连接已改变，K1保存未确认");
        for(LegacyEdit edit:edits) {
            var actual=ble.readOrdinaryKeyConfig(edit.mode(),0);
            boolean empty=edit.type()==0x73&&edit.action().length==0&&actual.actionPayload().length==0&&actual.actionType()==0;
            if((!empty&&(edit.type()!=actual.actionType()||!Arrays.equals(edit.action(),actual.actionPayload())))||!edit.description().equals(DeviceSyncService.sanitizeDescription(actual.description())))throw new IOException("旧固件K1保存读回不匹配");
        }
        if(generation!=ble.connectionGeneration())throw new IOException("连接已改变，K1保存未确认");
    }
    public void confirmLegacy(List<LegacyEdit> edits,long generation) {
        if(generation==ble.connectionGeneration()&&state.capability.get()==K1RouteState.Capability.LEGACY)
            for(LegacyEdit edit:edits)state.savedLegacy(edit.mode(),edit.revision());
    }
    public void saveDirty(Runnable done,Consumer<String> error) {
        if(state.busy.get()){error.accept("K1正在读取或保存，请稍后再试");return;}
        if(state.capability.get()==K1RouteState.Capability.LEGACY){done.run();return;}
        List<Edit> edits=new ArrayList<>();
        try {
            for(ModeSlot mode:ModeSlot.values())if(state.dirty(mode.getIndex())) {
                int m=mode.getIndex();
                if(state.capability.get()!=K1RouteState.Capability.ROUTE||!state.confirmed(m))continue; // Other keys may still be saved; preserve this unconfirmed draft.
                KeyConfig key=studio.getKeyConfig(mode,StudioPart.KEY1);
                K1Route route=K1Route.ordinary(key.usesMacro()?0x74:0x73,DeviceSyncService.encodeKeyActionPayload(key));String description=DeviceSyncService.sanitizeDescription(key.getDescription());
                boolean writeDescription=state.descriptionEdited(m)||(state.descriptionKnown(m)&&!description.equals(DeviceSyncService.sanitizeDescription(state.description(m))));
                if(writeDescription&&route.action().length+description.length()>com.example.ahakey.protocol.AhaKeyProtocol.ORDINARY_KEY_READBACK_ACTION_DESC_MAX)
                    throw new IOException("K1描述修改无法回读确认：动作与描述合计最多53字节。请减少宏步骤或描述长度；设备尚未写入。");
                edits.add(new Edit(m,state.edit(m),route,description,writeDescription));
            }
        }catch(Exception e){error.accept(e.getMessage());return;}
        if(edits.isEmpty()){done.run();return;}
        long generation=ble.connectionGeneration(),ticket=++refreshTicket;state.busy.set(true);
        worker.execute(()->{
            String failure=null;
            try {
                for(Edit edit:edits) {
                    ble.k1RouteTransaction(generation,()->{write(edit,generation);return null;});
                    Platform.runLater(()->{if(current(generation,ticket)){if(edit.writeDescription())state.observedDescription(edit.mode(),edit.description());state.saved(edit.mode(),edit.revision(),edit.route());}});
                }
            }catch(Exception e){failure="K1保存未确认，草稿保留："+e.getMessage();}
            String result=failure;
            Platform.runLater(()->{
                if(!current(generation,ticket)){if(ticket==refreshTicket)state.busy.set(false);error.accept("连接已改变，K1保存未确认");return;}
                state.busy.set(false);if(result==null)done.run();else{state.message.set(result);error.accept(result);}
            });
        });
    }
    private void write(Edit edit,long generation)throws Exception {
        byte[] bytes=edit.route().bytes();int token;do{token=random.nextInt();}while(token==0);long crc=K1RouteProtocol.crc(bytes);
        var begin=K1RouteProtocol.response(ble.exchangeK1Route(K1RouteProtocol.request(0x20,K1RouteProtocol.fields(11)
                .put((byte)edit.mode()).putShort((short)bytes.length).putInt((int)crc).putInt(token).array()),generation),0x20,token,10);
        if(begin.getInt()!=token||begin.getShort()!=0)throw new IOException("K1 begin响应不匹配");
        for(int offset=0;offset<bytes.length;){
            int count=Math.min(47,bytes.length-offset);
            var fields=K1RouteProtocol.fields(8+count).putInt(token).put((byte)edit.mode()).putShort((short)offset).put((byte)count).put(bytes,offset,count);
            var ack=K1RouteProtocol.response(ble.exchangeK1Route(K1RouteProtocol.request(0x21,fields.array()),generation),0x21,token,8);
            if((ack.get()&255)!=edit.mode()||(ack.getShort()&65535)!=offset+count||(ack.get()&255)!=count)throw new IOException("K1 chunk响应不匹配");offset+=count;
        }
        Exception uncertain=null;
        try{
            var commit=K1RouteProtocol.response(ble.exchangeK1Route(K1RouteProtocol.request(0x22,K1RouteProtocol.fields(5).putInt(token).put((byte)edit.mode()).array()),generation),0x22,token,9);
            if((commit.get()&255)!=edit.mode()||Integer.toUnsignedLong(commit.getInt())!=crc)throw new IOException("K1 commit响应不匹配");
        }catch(Exception e){uncertain=e;}
        // Resolve an uncertain commit by authority readback; never replay commit.
        try{if(!edit.route().equals(read(edit.mode(),generation)))throw new IOException("K1保存后读回不匹配");}
        catch(Exception e){if(uncertain!=null)e.addSuppressed(uncertain);throw e;}
        if(!edit.writeDescription())return;
        ble.sendCommandExpecting(com.example.ahakey.protocol.AhaKeyProtocol.setKeyDescription(edit.mode(),0,edit.description()),(byte)0x73);
        ble.sendCommandExpecting(com.example.ahakey.protocol.AhaKeyProtocol.saveConfig(),(byte)0x04);
        if(!edit.description().equals(DeviceSyncService.sanitizeDescription(ble.readOrdinaryKeyConfig(edit.mode(),0).description())))throw new IOException("K1描述读回不匹配");
    }
    @Override public void close(){closed=true;refreshTicket++;worker.shutdownNow();}
}
