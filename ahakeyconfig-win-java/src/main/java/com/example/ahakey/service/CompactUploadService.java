package com.example.ahakey.service;

import com.example.ahakey.model.OledResourceState.Asset;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.CompactUploadProtocol;
import java.io.IOException;
import java.net.SocketTimeoutException;
import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Consumer;
import java.util.function.LongSupplier;
import static com.example.ahakey.protocol.CompactUploadProtocol.*;

/** One connection-bound upload. Recovery reads never authorize writing another device or another token. */
public final class CompactUploadService {
    public interface Transport {
        byte[] exchange(byte[] request,long timeoutMillis)throws Exception;
        boolean usb();
    }
    private final Transport transport;
    private final LongSupplier clock;
    private final Runnable pause;
    private long deadline,verified,expanded;
    private int entry,token;
    private boolean began,commitAttempted;
    public CompactUploadService(Transport transport) { this(transport,System::nanoTime,()->{
        try { Thread.sleep(50); } catch(InterruptedException e){Thread.currentThread().interrupt();throw new IllegalStateException("上传被中断。",e);}
    }); }
    /** Clock/pause injection is only for deterministic offline timeout tests. */
    public CompactUploadService(Transport transport,LongSupplier clock,Runnable pause) {
        this.transport=transport;this.clock=clock;this.pause=pause;
    }
    public static void upload(BleManager ble,long generation,int entry,Asset asset,
            OledUploadService.BeforeCommit beforeCommit,Consumer<OledUploadService.Progress> progress)throws Exception {
        try(BleManager.DisplayLease lease=ble.openDisplayLease(true,generation)) {
            CompactUploadService service=new CompactUploadService(new Transport(){
                public byte[] exchange(byte[] request,long timeout)throws Exception{return ble.exchangeCompact(lease,request,timeout);}
                public boolean usb(){return ble.isUsbTransportOpen();}
            });
            try { service.upload(entry,asset,beforeCommit,progress); }
            catch(Exception e) {
                // Set before closing the lease, so deferred runtime writers cannot race an uncertain flash writer.
                if(service.began)ble.requireDisplayRecovery(generation);
                throw e;
            }
        }
    }
    private static int nonce(){int n;do{n=ThreadLocalRandom.current().nextInt();}while(n==0);return n;}
    private void checkTime()throws IOException {
        if(Thread.currentThread().isInterrupted()||clock.getAsLong()>=deadline)throw new IOException("快速上传已达到总时限，结果未确认。");
    }
    private Reply ask(int sub,int correlation,byte[] data)throws Exception {
        checkTime();long remaining=Math.max(1,(deadline-clock.getAsLong())/1_000_000);
        return response(transport.exchange(request(sub,correlation,data),Math.min(15000,remaining)),sub,correlation);
    }
    private Reply ask(int sub)throws Exception{return ask(sub,token,new byte[0]);}
    private static void requireOk(Reply reply,String phase)throws IOException {
        if(reply.status()!=0)throw rejected(reply.status(),phase);
    }
    private record State(int state,long offset,int error){}
    private State settled()throws Exception {
        long until=Math.min(deadline,clock.getAsLong()+90_000_000_000L);
        while(clock.getAsLong()<until) {
            checkTime();Reply reply;
            try { reply=ask(STATUS); }catch(SocketTimeoutException e){continue;}
            if(reply.status()==11)return null;
            requireOk(reply,"查询上传状态");ByteBuffer b=reply.buffer();
            int state=b.get()&255,target=b.get()&255;long offset=Integer.toUnsignedLong(b.getInt()),written=Integer.toUnsignedLong(b.getInt());int error=b.get()&255;
            if(target!=entry||state>4||error>11||written<verified||written>expanded)
                throw new IOException("快速上传状态与当前资源不匹配。");
            verified=written;
            if(state!=2&&state!=3)return new State(state,offset,error);
            pause.run();
        }
        throw new IOException("等待设备完成写入超时，结果未确认。");
    }
    private void metadata(Asset asset)throws Exception {
        long until=Math.min(deadline,clock.getAsLong()+90_000_000_000L);
        do {
            Reply reply;
            try { reply=ask(METADATA,nonce(),new byte[]{(byte)entry}); }
            catch(SocketTimeoutException e){continue;}
            requireOk(reply,"读取资源校验记录");ByteBuffer b=reply.buffer();
            int state=b.get()&255,frames=b.get()&255;long bytes=Integer.toUnsignedLong(b.getInt()),crc=Integer.toUnsignedLong(b.getInt());
            if(state==2&&frames==asset.frames()&&bytes==expanded&&crc==asset.crc())return;
            if(state!=1)throw new IOException("设备保存记录不匹配，不能确认快速上传成功。");
            State current=settled();
            if(current!=null&&current.state()==4)throw new IOException("设备存储故障，请重启设备后重新连接。");
            pause.run();
        }while(clock.getAsLong()<until);
        throw new IOException("设备保存结果尚未确认，请重新连接后同步。");
    }
    public void upload(int target,Asset asset,OledUploadService.BeforeCommit beforeCommit,
            Consumer<OledUploadService.Progress> progress)throws Exception {
        if(!asset.compact()||asset.frames()>AhaKeyProtocol.resourceCapacity(target))throw new IllegalArgumentException("快速资源目标或帧数不适用。");
        byte[] object=asset.compactBytes();entry=target;expanded=asset.bytes().length;verified=0;began=false;commitAttempted=false;
        long start=clock.getAsLong();deadline=start+600_000_000_000L;
        String phase="协商能力";int offset=0;
        try {
            int chunk=capability(ask(CAPS,nonce(),new byte[0]),transport.usb());
            token=nonce();phase="开始上传";
            byte[] begin=fields(25).put((byte)entry).putInt(object.length).putInt((int)crc(object)).put(object,0,16).array();
            began=true;
            try {
                Reply reply=ask(BEGIN,token,begin);requireOk(reply,phase);ByteBuffer b=reply.buffer();
                if(b.getInt()!=16||Integer.toUnsignedLong(b.getInt())!=expanded)throw new IOException("开始上传响应不匹配。");
            }catch(SocketTimeoutException e) {
                State state=settled();
                if(state==null||state.state()!=1||state.offset()!=16)throw new IOException("开始上传结果未确认，未重复开始命令。");
            }
            offset=16;progress.accept(new OledUploadService.Progress(offset,object.length,(clock.getAsLong()-start)/1_000_000));
            phase="传输资源";
            while(offset<object.length) {
                int count=Math.min(chunk,object.length-offset),end=offset+count;boolean accepted=false;
                byte[] data=fields(5+count).putInt(offset).put((byte)count).put(object,offset,count).array();
                for(int attempts=0;attempts<5&&!accepted;attempts++) {
                    State state;
                    try {
                        Reply reply=ask(CHUNK,token,data);
                        if(reply.status()==0) {
                            ByteBuffer b=reply.buffer();long next=Integer.toUnsignedLong(b.getInt());int used=b.get()&255;long written=Integer.toUnsignedLong(b.getInt());
                            if(next==end&&used==count&&written>=verified&&written<=expanded){verified=written;accepted=true;break;}
                        }else if(reply.status()!=7)throw rejected(reply.status(),phase);
                        state=settled();
                    }catch(SocketTimeoutException e){state=settled();}
                    if(state==null||state.state()!=1)throw new IOException("资源块结果未确认，已停止发送。");
                    if(state.offset()==end)accepted=true;
                    else if(state.offset()!=offset)throw new IOException("设备上传偏移不匹配，已停止发送。");
                }
                if(!accepted)throw new IOException("资源块重试已达上限。");
                offset=end;progress.accept(new OledUploadService.Progress(offset,object.length,(clock.getAsLong()-start)/1_000_000));
            }
            phase="保存本地待确认记录";beforeCommit.persist();
            phase="确认设备保存";commitAttempted=true;
            try {
                Reply reply=ask(COMMIT);requireOk(reply,phase);ByteBuffer b=reply.buffer();
                if((b.get()&255)!=entry||(b.get()&255)!=asset.frames()||Integer.toUnsignedLong(b.getInt())!=expanded||Integer.toUnsignedLong(b.getInt())!=asset.crc())
                    throw new IOException("设备提交校验不匹配。");
            }catch(SocketTimeoutException e){/* Never resend COMMIT. Persisted metadata is the authority. */}
            phase="读取设备保存记录";metadata(asset);
        }catch(Exception e) {
            throw new OledUploadService.UploadFailure("快速上传未完成（"+phase+"，已确认 "+offset+"/"+object.length+" 字节）："
                    +(e.getMessage()==null?e.getClass().getSimpleName():e.getMessage())
                    +(began?" 草稿已保留；目标资源可能已无效，请重新连接后同步。":" 未开始写入，可主动选择原画质上传。"),e,commitAttempted);
        }
    }
}
