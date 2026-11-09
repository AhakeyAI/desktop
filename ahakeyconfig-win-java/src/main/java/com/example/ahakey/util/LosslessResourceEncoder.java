package com.example.ahakey.util;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.util.Arrays;
import com.example.ahakey.protocol.AhaKeyProtocol;
import static com.example.ahakey.protocol.LosslessUploadProtocol.*;

/** Consumes canonical screen pixels; never resamples or reopens the original GIF. */
public final class LosslessResourceEncoder {
    public static final int PIXEL_BYTES=25600, SLOT_BYTES=28672, MAX_OBJECT=307240;
    public record Encoded(byte[] object, byte[] expanded, int frames, String encoding) {
        public Encoded { object=object.clone();expanded=expanded.clone(); }
        @Override public byte[] object(){return object.clone();}
        @Override public byte[] expanded(){return expanded.clone();}
        public long expandedCrc(){return crc(expanded);}
    }
    private LosslessResourceEncoder() { }
    public static Encoded encode(byte[] canonical,int entry) {
        if(canonical==null||canonical.length==0||canonical.length%SLOT_BYTES!=0)throw new IllegalArgumentException("原画质成品尺寸无效。");
        int n=canonical.length/SLOT_BYTES;
        if(n>AhaKeyProtocol.resourceCapacity(entry))throw new IllegalArgumentException("资源帧数超过目标容量，不会自动删帧。");
        ByteArrayOutputStream raw=new ByteArrayOutputStream(), packed=new ByteArrayOutputStream(), expanded=new ByteArrayOutputStream();
        for(int f=0;f<n;f++) {
            byte[] pixels=Arrays.copyOfRange(canonical,f*SLOT_BYTES,f*SLOT_BYTES+PIXEL_BYTES);
            raw.write(100);raw.write(0);raw.writeBytes(pixels);
            packed.write(100);packed.write(0);packed.writeBytes(rle(pixels));
            expanded.writeBytes(pixels);expanded.writeBytes(tail(f,n));expanded.writeBytes(padding());
        }
        boolean useRle=packed.size()<raw.size();
        ByteBuffer header=fields(16);header.put(new byte[]{65,67,82,52}).put((byte)(useRle?3:1)).put((byte)1).put((byte)n).put((byte)(n>1?1:0)).putShort((short)160).putShort((short)80).putInt(n*SLOT_BYTES);
        ByteArrayOutputStream out=new ByteArrayOutputStream();out.writeBytes(header.array());out.writeBytes(useRle?packed.toByteArray():raw.toByteArray());
        if(out.size()>MAX_OBJECT)throw new IllegalArgumentException("无损对象超过协议容量。");
        return new Encoded(out.toByteArray(),expanded.toByteArray(),n,useRle?"RLE":"RAW");
    }
    private static byte[] padding(){byte[] p=new byte[3056];Arrays.fill(p,(byte)255);return p;}
    private static byte[] tail(int frame,int frames){ByteBuffer b=fields(16);b.put(new byte[]{65,84,48,51,1,(byte)frame,(byte)frames,0}).putShort((short)100).putShort((short)0);b.putInt((int)crc(Arrays.copyOf(b.array(),12)));return b.array();}
    private static boolean equal(byte[] p,int a,int b){return p[a*2]==p[b*2]&&p[a*2+1]==p[b*2+1];}
    private static byte[] rle(byte[] p){
        ByteArrayOutputStream out=new ByteArrayOutputStream();int i=0,n=p.length/2;
        while(i<n){int count=1;while(count<128&&i+count<n&&equal(p,i,i+count))count++;
            if(count>=2){out.write(128+count-1);out.write(p[i*2]);out.write(p[i*2+1]);i+=count;continue;}
            int start=i++;while(i-start<128&&i<n){if(i+1<n&&equal(p,i,i+1))break;i++;}
            out.write(i-start-1);out.write(p,start*2,(i-start)*2);
        }return out.toByteArray();
    }
    public static byte[] expand(byte[] object){
        if(object==null||object.length<16||object.length>MAX_OBJECT)throw new IllegalArgumentException("ACR4 object size");
        ByteBuffer b=read(object);byte[] magic=new byte[4];b.get(magic);
        int enc=b.get()&255,scale=b.get()&255,n=b.get()&255,flags=b.get()&255,w=Short.toUnsignedInt(b.getShort()),h=Short.toUnsignedInt(b.getShort()),total=b.getInt();
        if(!Arrays.equals(magic,new byte[]{65,67,82,52})||(enc!=1&&enc!=3)||scale!=1||n<1||n>12||flags!=(n>1?1:0)||w!=160||h!=80||total!=n*SLOT_BYTES||object.length>16+n*25602||(enc==1&&object.length!=16+n*25602)||(enc==3&&object.length<16+n*302))throw new IllegalArgumentException("ACR4 header");
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        try {for(int f=0;f<n;f++){
            if(Short.toUnsignedInt(b.getShort())!=100)throw new IllegalArgumentException("ACR4 duration");
            byte[] pixels=new byte[PIXEL_BYTES];int at=0;
            if(enc==1){b.get(pixels);}else while(at<pixels.length){int control=b.get()&255,count=(control&127)+1;if(at+count*2>pixels.length)throw new IllegalArgumentException("ACR4 frame overrun");
                if((control&128)!=0){byte hi=b.get(),lo=b.get();for(int j=0;j<count;j++){pixels[at++]=hi;pixels[at++]=lo;}}
                else {b.get(pixels,at,count*2);at+=count*2;}
            }
            out.writeBytes(pixels);out.writeBytes(tail(f,n));out.writeBytes(padding());
        }}catch(java.nio.BufferUnderflowException e){throw new IllegalArgumentException("ACR4 truncated",e);}
        if(b.hasRemaining())throw new IllegalArgumentException("ACR4 trailing bytes");return out.toByteArray();
    }
}
