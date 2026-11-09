package com.example.ahakey.protocol;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
import java.util.zip.CRC32;

/** HW1 ACR4 wire contract. The length byte, never an interior delimiter, frames binary replies. */
public final class LosslessUploadProtocol {
    public static final int CAPS=0x40, BEGIN=0x41, CHUNK=0x42, COMMIT=0x43, CANCEL=0x44, STATUS=0x45, METADATA=0x46;
    private static final int[] RESPONSE_SIZES={14,8,5,10,6,11,10};
    public static final class Unsupported extends IOException { public Unsupported() { super("固件明确不支持 ACR4 原画质无损上传。"); } }
    private LosslessUploadProtocol() {}
    public static ByteBuffer fields(int length) { return ByteBuffer.allocate(length).order(ByteOrder.LITTLE_ENDIAN); }
    public static ByteBuffer read(byte[] data) { return ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN); }
    public static long crc(byte[] data) { CRC32 crc=new CRC32();crc.update(data);return crc.getValue(); }
    public static byte[] request(int sub,int token,byte[] fields) {
        if(sub<CAPS||sub>METADATA||fields.length>255||token==0)throw new IllegalArgumentException("ACR4 request");
        ByteBuffer b=fields(12+fields.length);
        b.put((byte)0xAA).put((byte)0xBB).put((byte)0x9E).put((byte)4).put((byte)sub).put((byte)fields.length)
                .putInt(token).put(fields).put((byte)0xCC).put((byte)0xDD);return b.array();
    }
    /** 0 incomplete, -2 malformed, -1 another version; otherwise exact total length. */
    public static int replyLength(byte[] b,int start,int available) {
        if(available<5)return 0;
        if(b[start+2]!=(byte)0x9E||b[start+4]!=4)return -1;
        if(available<7)return 0;
        int sub=b[start+5]&255,status=b[start+3]&255,n=b[start+6]&255;
        if(status>11||sub<CAPS||sub>METADATA||n!=(status==0?RESPONSE_SIZES[sub-CAPS]:4))return -2;
        int length=13+n;
        if(available<length)return 0;
        return b[start+length-2]==(byte)0xCC&&b[start+length-1]==(byte)0xDD?length:-2;
    }
    public record Reply(int status,byte[] fields) {
        public Reply { fields=fields.clone(); }
        @Override public byte[] fields(){return fields.clone();}
        public ByteBuffer buffer(){return read(fields);}
    }
    public static boolean matches(byte[] reply,byte[] request) {
        return reply!=null&&reply.length>=13&&request!=null&&request.length>=12&&reply[4]==4
                &&reply[5]==request[4]&&read(reply).getInt(7)==read(request).getInt(6);
    }
    public static Reply response(byte[] frame,int sub,int token)throws IOException {
        if(frame==null||frame.length<13||frame[0]!=(byte)0xAA||frame[1]!=(byte)0xBB
                ||replyLength(frame,0,frame.length)!=frame.length||(frame[5]&255)!=sub||read(frame).getInt(7)!=token)
            throw new IOException("原画质无损上传响应格式或事务标识不匹配。");
        return new Reply(frame[3]&255,Arrays.copyOfRange(frame,11,frame.length-2));
    }
    public static int capability(Reply reply,boolean usb)throws IOException {
        if(reply.status()==2)throw new Unsupported();
        if(reply.status()!=0)throw rejected(reply.status(),"协商原画质无损上传能力");
        ByteBuffer b=reply.buffer();byte[] magic=new byte[4];b.get(magic);
        int flags=Short.toUnsignedInt(b.getShort());long max=Integer.toUnsignedLong(b.getInt());int chunk=b.get()&255;
        if(!Arrays.equals(magic,new byte[]{65,67,82,52})||flags!=15||max!=307240||chunk!=(usb?40:128)
                ||b.get()!=1||b.get()!=8||b.get()!=12)
            throw new IOException("固件无损上传能力无法确认，未开始写入；请核对配对固件及连接。");
        return chunk;
    }
    public static IOException rejected(int status,String phase) {
        String[] names={"成功","请求格式无效","不支持","设备忙","范围无效","资源过大","事务归属不符","偏移不符","校验失败","解码失败","存储失败","事务不存在"};
        return new IOException(phase+"："+(status>=0&&status<names.length?names[status]:"未知状态")+"。");
    }
}
