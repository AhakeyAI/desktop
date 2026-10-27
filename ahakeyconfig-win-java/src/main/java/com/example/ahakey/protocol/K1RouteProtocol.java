package com.example.ahakey.protocol;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
import java.util.zip.CRC32;

/** v1 reviewed allocation. Every response is matched to its request, not just its opcode. */
public final class K1RouteProtocol {
    private K1RouteProtocol() {}
    public static long crc(byte[] data) { CRC32 crc = new CRC32(); crc.update(data); return crc.getValue(); }
    public static ByteBuffer fields(int size) { return ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN); }
    public static byte[] request(int sub, byte[] fields) {
        byte[] frame = new byte[7 + fields.length];
        frame[0]=(byte)0xAA; frame[1]=(byte)0xBB; frame[2]=(byte)0x9E; frame[3]=1; frame[4]=(byte)sub;
        System.arraycopy(fields,0,frame,5,fields.length); frame[frame.length-2]=(byte)0xCC; frame[frame.length-1]=(byte)0xDD;
        if(frame.length>62)throw new IllegalArgumentException("K1帧超过62字节"); return frame;
    }
    public static boolean legacyAck(byte[] frame) { return Arrays.equals(frame,new byte[]{(byte)0xAA,(byte)0xBB,(byte)0x9E,0,(byte)0xCC,(byte)0xDD}); }
    /** Framing only: positive exact length, 0 incomplete, -1 other opcode, -2 invalid.
     * Read replies carry no slice length, so their boundary comes from the outstanding request.
     * Correlation, CRC and generation are still checked by the transaction/service. */
    public static int replyLength(byte[] data,int start,int available,byte[] request) {
        if(available<3)return 0;
        if(data[start+2]!=(byte)0x9E)return -1;
        if(available<6)return 0;
        int status=data[start+3]&255,sub=data[start+5]&255;
        if(status==0&&data[start+4]==(byte)0xCC&&data[start+5]==(byte)0xDD)return 6;
        if(status>1||data[start+4]!=1||!java.util.Set.of(0,0x10,0x20,0x21,0x22).contains(sub))return -2;
        int length=12;
        if(status==0) {
            length=switch(sub){case 0->14;case 0x20->18;case 0x21->16;case 0x22->17;default->0;};
            if(sub==0x10) {
                if(request==null||request.length!=14||request[2]!=(byte)0x9E||request[3]!=1||request[4]!=0x10)return -2;
                int offset=request[10]&255,count=request[11]&255;
                if((request[9]&255)>3||offset>=102||count<1||count>42)return -2;
                length=20+Math.min(count,102-offset);
            }
        }
        if(available<length)return 0;
        return data[start+length-2]==(byte)0xCC&&data[start+length-1]==(byte)0xDD?length:-2;
    }
    public static ByteBuffer response(byte[] f,int sub,int correlation,int fieldsLength) throws IOException {
        if(f==null||f.length<12||f.length>62||f[0]!=(byte)0xAA||f[1]!=(byte)0xBB||f[2]!=(byte)0x9E
                ||f[4]!=1||(f[5]&255)!=sub||f[f.length-2]!=(byte)0xCC||f[f.length-1]!=(byte)0xDD)
            throw new IOException("K1响应格式不匹配");
        ByteBuffer b=ByteBuffer.wrap(f,6,f.length-8).slice().order(ByteOrder.LITTLE_ENDIAN);
        if(b.getInt()!=correlation)throw new IOException("K1响应nonce/token不匹配");
        if(f[3]==1&&f.length==12)throw new IOException("K1配置暂不可读取或保存，无法确认当前设置");
        if(f[3]!=0||f.length!=fieldsLength+8)throw new IOException("K1响应状态或长度不匹配");
        return b;
    }
    public static void capability(byte[] frame,int nonce)throws IOException {
        var b=response(frame,0,nonce,6);int flags=b.get()&255,count=b.get()&255;
        if((flags&1)==0||(flags&~3)!=0||count!=4)throw new IOException("K1能力响应无效");
    }
}
