package com.example.ahakey.protocol;

import java.io.IOException;
import java.nio.*;

/** Firmware 0x9E restore allocation: v1 query, v2 start, exact 17 byte replies. */
public final class FactoryResetProtocol {
    private FactoryResetProtocol(){}
    public enum State { NEVER, IN_PROGRESS, INCOMPLETE, COMPLETE, STORAGE_UNAVAILABLE, UNSUPPORTED }
    public record Reply(int result,State state,long attempt){}
    public static byte[] query(int nonce){return K1RouteProtocol.request(0x30,K1RouteProtocol.fields(4).putInt(nonce).array());}
    public static byte[] start(int nonce,long expected){
        if(expected<1||expected>0xffffffffL)throw new IllegalArgumentException("恢复次数已达边界，不能发起");
        byte[] frame=K1RouteProtocol.request(0x31,K1RouteProtocol.fields(8).putInt(nonce).putInt((int)expected).array());frame[3]=2;return frame;
    }
    public static Reply parse(byte[] f,int version,int sub,int nonce) throws IOException {
        if(f==null||f.length!=17||f[0]!=(byte)0xaa||f[1]!=(byte)0xbb||f[2]!=(byte)0x9e||f[4]!=version||(f[5]&255)!=sub||f[15]!=(byte)0xcc||f[16]!=(byte)0xdd||(f[3]&255)>1)
            throw new IOException("恢复回复版本、长度或子命令不匹配");
        ByteBuffer b=ByteBuffer.wrap(f).order(ByteOrder.LITTLE_ENDIAN);
        if(b.getInt(6)!=nonce)throw new IOException("恢复回复 nonce 不匹配");
        int state=f[10]&255;if(state>=State.values().length)throw new IOException("未知恢复状态");
        return new Reply(f[3]&255,State.values()[state],Integer.toUnsignedLong(b.getInt(11)));
    }
    public static boolean isRead(byte[] f){return f!=null&&f.length==11&&f[2]==(byte)0x9e&&f[3]==1&&f[4]==0x30;}
    public static boolean isStart(byte[] f){return f!=null&&f.length==15&&f[2]==(byte)0x9e&&f[3]==2&&f[4]==0x31;}
    /** Fixed picture-state readback contains binary u16 fields that may include footer bytes. */
    public static int pictureReplyLength(byte[] data,int start,int available){
        if(available<3)return 0;if(data[start+2]!=(byte)0x83)return -1;
        if(available<4)return 0;int length=data[start+3]==0?15:6;
        if(available<length)return 0;
        return data[start+length-2]==(byte)0xcc&&data[start+length-1]==(byte)0xdd?length:-2;
    }
}
