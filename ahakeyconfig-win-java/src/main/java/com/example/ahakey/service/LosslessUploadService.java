package com.example.ahakey.service;

import com.example.ahakey.model.OledResourceState.Asset;
import com.example.ahakey.util.LosslessResourceEncoder;
import java.io.IOException;
import java.net.SocketTimeoutException;
import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Consumer;
import java.util.function.LongSupplier;
import static com.example.ahakey.protocol.LosslessUploadProtocol.*;

/** Independent ACR4 transaction. No CP2 fallback is performed by this service. */
public final class LosslessUploadService {
    private static final org.slf4j.Logger logger=org.slf4j.LoggerFactory.getLogger(LosslessUploadService.class);
    public interface Transport { byte[] exchange(byte[] request,long timeoutMillis)throws Exception; boolean usb(); }
    private final Transport transport;
    private final LongSupplier clock;
    private final Runnable pause;
    private long deadline,verified,expanded,beginAt,requestBytes,responseBytes,retryBytes;
    private int entry,token;
    private boolean began,commitAttempted,cleanupUncertain,unanswered;
    public LosslessUploadService(Transport transport){this(transport,System::nanoTime,()->{try{Thread.sleep(50);}catch(InterruptedException e){Thread.currentThread().interrupt();throw new IllegalStateException("上传被中断。",e);}});}
    public LosslessUploadService(Transport transport,LongSupplier clock,Runnable pause){this.transport=transport;this.clock=clock;this.pause=pause;}
    public boolean cleanupUncertain(){return cleanupUncertain;}
    public static void upload(BleManager ble,long generation,int entry,Asset asset,OledUploadService.BeforeCommit beforeCommit,Consumer<OledUploadService.Progress> progress)throws Exception {
        try(BleManager.DisplayLease lease=ble.openDisplayLease(true,generation)){
            LosslessUploadService service=new LosslessUploadService(new Transport(){
                public byte[] exchange(byte[] request,long timeout)throws Exception{return ble.exchangeLossless(lease,request,timeout);}
                public boolean usb(){return ble.isUsbTransportOpen();}
            });
            try{service.upload(entry,asset,beforeCommit,progress);}
            catch(Exception e){if(service.cleanupUncertain)ble.requireDisplayRecovery(generation);throw e;}
        }
    }
    private static int nonce(){int n;do{n=ThreadLocalRandom.current().nextInt();}while(n==0);return n;}
    private Reply ask(int sub,int correlation,byte[] data,boolean retry)throws Exception{
        if(Thread.currentThread().isInterrupted()||clock.getAsLong()>=deadline)throw new IOException("原画质上传已停止或达到时限。");
        byte[] wire=request(sub,correlation,data);requestBytes+=wire.length;if(retry)retryBytes+=wire.length;
        unanswered=true;
        logger.info("ACR4 tx token={} sub={} offset={} requestBytes={} retry={}",Integer.toUnsignedLong(correlation),sub,sub==CHUNK?Integer.toUnsignedLong(read(data).getInt()):-1,wire.length,retry);
        byte[] received=transport.exchange(wire,Math.min(15000,Math.max(1,(deadline-clock.getAsLong())/1_000_000)));
        responseBytes+=received.length;Reply reply=response(received,sub,correlation);unanswered=false;
        logger.info("ACR4 rx token={} sub={} status={} bytes={}",Integer.toUnsignedLong(correlation),sub,reply.status(),received.length);
        return reply;
    }
    private Reply ask(int sub)throws Exception{return ask(sub,token,new byte[0],false);}
    private static void ok(Reply r,String phase)throws IOException{if(r.status()!=0)throw rejected(r.status(),phase);}
    private record State(int state,long offset,int error){}
    private State settled()throws Exception{
        long until=Math.min(deadline,clock.getAsLong()+90_000_000_000L);
        while(clock.getAsLong()<until){
            Reply r;try{r=ask(STATUS);}catch(SocketTimeoutException e){continue;}
            if(r.status()==11)return null;ok(r,"查询上传状态");ByteBuffer b=r.buffer();
            int state=b.get()&255,target=b.get()&255;long offset=Integer.toUnsignedLong(b.getInt()),written=Integer.toUnsignedLong(b.getInt());int error=b.get()&255;
            if(target!=entry||state>4||error>11||written<verified||written>expanded)throw new IOException("无损上传状态不匹配。");
            verified=written;if(state!=2&&state!=3)return new State(state,offset,error);pause.run();
        }throw new IOException("等待设备写入完成超时。");
    }
    private com.example.ahakey.model.OledResourceState.Metadata metadata()throws Exception{
        Reply r=ask(METADATA,nonce(),new byte[]{(byte)entry},false);ok(r,"读取资源校验记录");ByteBuffer b=r.buffer();
        int state=b.get()&255,frames=b.get()&255;long bytes=Integer.toUnsignedLong(b.getInt()),crc=Integer.toUnsignedLong(b.getInt());
        return new com.example.ahakey.model.OledResourceState.Metadata(state==2,state,frames,bytes,crc);
    }
    private void verifyMetadata(LosslessResourceEncoder.Encoded encoded)throws Exception{
        long until=Math.min(deadline,clock.getAsLong()+90_000_000_000L);
        while(clock.getAsLong()<until){
            com.example.ahakey.model.OledResourceState.Metadata m;
            try{m=metadata();}catch(SocketTimeoutException e){continue;}
            if(m.valid()&&m.frames()==encoded.frames()&&m.bytes()==expanded&&m.crc()==encoded.expandedCrc())return;
            if(m.writeState()!=1)throw new IOException("设备保存记录与本次无损资源不匹配。");
            State state=settled();if(state!=null&&state.state()==4)throw new IOException("设备存储故障。");pause.run();
        }throw new IOException("资源保存结果未确认。");
    }
    private void cancel()throws Exception{
        long until=Math.min(deadline,clock.getAsLong()+90_000_000_000L);
        while(clock.getAsLong()<until){
            try{Reply r=ask(CANCEL,token,new byte[0],true);if(r.status()==0){ByteBuffer b=r.buffer();int state=b.get()&255,target=b.get()&255;long written=Integer.toUnsignedLong(b.getInt());if(state!=0||target!=entry||written>expanded)throw new IOException("取消响应无效。");return;}}
            catch(SocketTimeoutException e){/* Query before another cancel. */}
            State state=settled();
            if(state==null){var m=metadata();if(m.writeState()==0||m.writeState()==3)return;break;}
            if(state.state()==4)break;pause.run();
        }throw new IOException("无法确认取消与无效记录已保存。");
    }
    public void upload(int target,Asset asset,OledUploadService.BeforeCommit beforeCommit,Consumer<OledUploadService.Progress> progress)throws Exception{
        if(asset.compact())throw new IllegalArgumentException("ACR4 requires original-quality pixels");
        var encoded=LosslessResourceEncoder.encode(asset.bytes(),target);byte[] object=encoded.object();
        if(!Arrays.equals(encoded.expanded(),LosslessResourceEncoder.expand(object)))throw new IOException("本地无损对象校验失败。");
        entry=target;expanded=encoded.expanded().length;verified=0;began=false;commitAttempted=false;cleanupUncertain=false;token=0;
        deadline=clock.getAsLong()+3_600_000_000_000L;int offset=0;String phase="协商能力";
        try{
            int chunk=capability(ask(CAPS,nonce(),new byte[0],false),transport.usb());
            token=nonce();phase="开始上传";began=true;beginAt=clock.getAsLong();
            byte[] begin=fields(25).put((byte)entry).putInt(object.length).putInt((int)crc(object)).put(object,0,16).array();
            try{Reply r=ask(BEGIN,token,begin,false);ok(r,phase);ByteBuffer b=r.buffer();if(b.getInt()!=16||Integer.toUnsignedLong(b.getInt())!=expanded)throw new IOException("开始上传响应不匹配。");}
            catch(SocketTimeoutException e){State st=settled();if(st==null||st.state()!=1||st.offset()!=16)throw new IOException("开始结果未确认，未重复 BEGIN。");}
            offset=16;progress.accept(new OledUploadService.Progress(offset,object.length,0,encoded.encoding()));phase="传输资源";
            while(offset<object.length){
                int count=Math.min(chunk,object.length-offset),end=offset+count;boolean accepted=false;
                byte[] data=fields(5+count).putInt(offset).put((byte)count).put(object,offset,count).array();
                for(int attempt=0;attempt<5&&!accepted;attempt++){
                    State st;
                    try{Reply r=ask(CHUNK,token,data,attempt>0);if(r.status()==0){ByteBuffer b=r.buffer();if(Integer.toUnsignedLong(b.getInt())==end&&(b.get()&255)==count){accepted=true;break;}}
                        else if(r.status()!=7)throw rejected(r.status(),phase);st=settled();
                    }catch(SocketTimeoutException e){st=settled();}
                    if(st==null||st.state()!=1)throw new IOException("资源块结果未确认。");
                    if(st.offset()==end)accepted=true;else if(st.offset()!=offset)throw new IOException("设备上传偏移不匹配。");
                }
                if(!accepted)throw new IOException("相同资源块重试达到上限。");
                offset=end;long elapsed=(clock.getAsLong()-beginAt)/1_000_000;
                progress.accept(new OledUploadService.Progress(offset,object.length,elapsed,encoded.encoding()));
                logger.info("ACR4 accepted token={} offset={} total={} elapsedMs={}",Integer.toUnsignedLong(token),offset,object.length,elapsed);
            }
            phase="保存本地待确认记录";beforeCommit.persist();phase="确认设备保存";commitAttempted=true;
            try{Reply r=ask(COMMIT);ok(r,phase);ByteBuffer b=r.buffer();if((b.get()&255)!=entry||(b.get()&255)!=asset.frames()||Integer.toUnsignedLong(b.getInt())!=expanded||Integer.toUnsignedLong(b.getInt())!=encoded.expandedCrc())throw new IOException("设备提交校验不匹配。");}
            catch(SocketTimeoutException e){/* Only metadata can resolve COMMIT. */}
            phase="核对设备保存记录";verifyMetadata(encoded);
            progress.accept(new OledUploadService.Progress(offset,object.length,(clock.getAsLong()-beginAt)/1_000_000,encoded.encoding()));
            logger.info("ACR4 complete token={} encodedBytes={} requestBytes={} responseBytes={} retryBytes={} elapsedMs={}",Integer.toUnsignedLong(token),object.length,requestBytes,responseBytes,retryBytes,(clock.getAsLong()-beginAt)/1_000_000);
        }catch(Unsupported e){throw e;}
        catch(Exception original){
            if(began){boolean interrupted=Thread.interrupted();deadline=clock.getAsLong()+120_000_000_000L;
                try{cancel();commitAttempted=false;}
                catch(Exception cleanup){cleanupUncertain=true;logger.warn("ACR4 cleanup UNKNOWN token={} reason={}",Integer.toUnsignedLong(token),cleanup.getMessage());}
                finally{if(interrupted)Thread.currentThread().interrupt();}
            }else cleanupUncertain=unanswered;
            throw new OledUploadService.UploadFailure("原画质无损上传未完成（"+phase+"，已确认 "+offset+"/"+object.length+" 字节）："+original.getMessage()+" 本地资源已保留。"+(cleanupUncertain?"设备结果未确认，请断开并重新连接后同步。":""),original,commitAttempted);
        }
    }
}
