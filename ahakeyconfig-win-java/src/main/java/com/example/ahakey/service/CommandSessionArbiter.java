package com.example.ahakey.service;

import java.io.IOException;
import java.util.function.LongSupplier;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.protocol.K1RouteProtocol;

/** State only; BleManager holds commandLock and waits on responseReady, never a second lock. */
public final class CommandSessionArbiter {
    private static final org.slf4j.Logger logger=org.slf4j.LoggerFactory.getLogger(CommandSessionArbiter.class);
    private final LongSupplier clock;
    private final long timeoutNanos;
    private long generation, deadline, requestSequence, pendingTicket;
    private byte[] pending;
    private Object owner;
    private Thread acquiring;
    private boolean unknown;
    public CommandSessionArbiter(){this(System::nanoTime,15_000_000_000L);}
    public CommandSessionArbiter(LongSupplier clock,long timeoutNanos){this.clock=clock;this.timeoutNanos=timeoutNanos;}
    public void reset(long generation){this.generation=generation;pending=null;owner=null;acquiring=null;unknown=false;}
    public void requireKnown()throws IOException{expire();if(unknown)throw new IOException("上一条设备命令结果未确认，请断开并重新连接键盘。");}
    public boolean pending(){expire();return pending!=null;}
    public boolean occupied(){return owner!=null||acquiring!=null;}
    public boolean uncertain(){expire();return unknown;}
    public void uncertain(String reason){if(unknown)return;unknown=true;logger.warn("Command session UNKNOWN generation={} reason={}",generation,reason);}
    private void expire(){if(pending!=null&&!unknown&&clock.getAsLong()>=deadline)uncertain("ordinary response timeout opcode="+(pending[2]&255));}
    public void requestOwnership()throws IOException{requireKnown();if(occupied())throw new IOException("设备正在处理其他事务。");acquiring=Thread.currentThread();}
    public void abandonRequest(){if(acquiring==Thread.currentThread())acquiring=null;}
    public void own(Object value)throws IOException{requireKnown();if(acquiring!=Thread.currentThread()||pending!=null)throw new IOException("设备旧命令尚未结束。");owner=value;acquiring=null;}
    public void release(Object value){if(owner==value)owner=null;}
    public void admitOwner(Object value)throws IOException{requireKnown();if(owner!=value||value==null)throw new IOException("上传会话权限已失效。");}
    public void admitOrdinary(boolean existingRaw)throws IOException{
        requireKnown();if(owner!=null||(acquiring!=null&&!existingRaw))throw new IOException("资源事务占用设备命令，操作未排队。");
    }
    public void sent(byte[] request){if(pending!=null)throw new IllegalStateException("ordinary request overlap");pending=request.clone();pendingTicket=++requestSequence;deadline=clock.getAsLong()+timeoutNanos;}
    public long pendingTicket(){return pending==null?0:pendingTicket;}
    public boolean ownsPending(long expectedGeneration,long ticket,byte opcode){
        expire();return pending!=null&&ticket!=0&&generation==expectedGeneration&&pendingTicket==ticket&&pending[2]==opcode;
    }
    public void failedWrite(){uncertain("physical write failed or interrupted");}
    public boolean receive(byte[] frame,long receivedGeneration){
        expire();if(unknown||pending==null||receivedGeneration!=generation||!AhaKeyProtocol.isValidFrame(frame)||frame[2]!=pending[2])return false;
        int opcode=frame[2]&255;
        if(opcode==0){if(frame.length!=13||AhaKeyProtocol.parseDeviceStatus(frame)==null)return false;}
        else if(opcode==0x9e){
            if(!K1RouteProtocol.legacyAck(frame)){
                if(frame.length<12||pending.length<11||frame[4]!=pending[3]||frame[5]!=pending[4])return false;
                // K1 BEGIN places its nonce after selector, length and CRC; other requests lead with it.
                int correlationOffset=pending[3]==1&&pending[4]==0x20?12:5;
                if(pending.length<correlationOffset+6)return false;
                for(int i=0;i<4;i++)if(frame[6+i]!=pending[correlationOffset+i])return false;
            }
        }else if(!ordinaryShape(frame,pending))return false;
        pending=null;return true;
    }
    private static boolean ordinaryShape(byte[] f,byte[] request){
        if(f.length<6)return false;
        int opcode=f[2]&255,status=f[3]&255;
        if(status!=0 && f.length==6)return true; // An explicit failure ends transport, not business success.
        return switch(opcode){
            case 0x83 -> f.length==15&&request.length==6&&f[4]==request[3];
            case 0x87 -> {var key=AhaKeyResponseParser.parseOrdinaryKeyReadback(f);yield key!=null&&request.length==7&&key.mode()==(request[3]&255)&&key.keyIndex()==(request[4]&255);}
            case 0x95 -> status==0&&f.length==(request.length==5?8:6);
            case 0x96 -> status==0&&f.length==(request.length==5?7:6);
            case 0x97 -> request.length==5?AhaKeyResponseParser.parseSideSwitchConfig(f)!=null:f.length==6&&status==0;
            case 0x94 -> status==0&&f.length==16&&request.length>=7&&f[4]==request[3]&&f[5]==request[4];
            case 0x9f -> f.length==6 || AhaKeyResponseParser.parseFirmwareCatalogKey(f)!=null;
            default -> f.length==6;
        };
    }

}
