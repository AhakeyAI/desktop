package com.example.ahakey.util;

import com.example.ahakey.protocol.CompactUploadProtocol;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.nio.ByteBuffer;
import java.util.*;

/** Deterministic shared-palette encoding; expansion is also the source of the exact device preview. */
public final class CompactResourceEncoder {
    private CompactResourceEncoder() {}
    public static byte[] encode(List<OLEDFrameEncoder.EncodedFrame> frames) {
        if(frames.isEmpty()||frames.size()>12)throw new IllegalArgumentException("快速上传需要 1 至 12 帧。");
        List<int[]> pixels=new ArrayList<>();Map<Integer,Integer> histogram=new TreeMap<>();
        for(var frame:frames) {
            if(frame.durationMillis<20||frame.durationMillis>60000)
                throw new IllegalArgumentException("快速上传支持每帧 20 至 60000 ms；当前帧为 "+frame.durationMillis+" ms，请调整源 GIF。");
            BufferedImage small=new BufferedImage(80,40,BufferedImage.TYPE_INT_RGB);
            Graphics2D g=small.createGraphics();g.setRenderingHint(RenderingHints.KEY_INTERPOLATION,RenderingHints.VALUE_INTERPOLATION_BILINEAR);
            g.drawImage(frame.preview,0,0,80,40,null);g.dispose();
            int[] p=new int[3200];
            for(int y=0;y<40;y++)for(int x=0;x<80;x++) {
                int rgb=small.getRGB(x,y),color=((rgb>>19)&31)<<11|((rgb>>10)&63)<<5|((rgb>>3)&31);
                p[y*80+x]=color;histogram.merge(color,1,Integer::sum);
            }
            pixels.add(p);
        }
        int[] palette=palette(histogram);Map<Integer,Integer> lookup=new HashMap<>();
        for(int color:histogram.keySet()) {
            int best=0,distance=Integer.MAX_VALUE;
            for(int i=0;i<16;i++) { int d=distance(color,palette[i]);if(d<distance){best=i;distance=d;} }
            lookup.put(color,best);
        }
        ByteBuffer out=CompactUploadProtocol.fields(48+frames.size()*1602);
        out.put(new byte[]{65,67,82,51,2,2,(byte)frames.size(),(byte)(frames.size()>1?1:0)});
        out.putShort((short)80).putShort((short)40).putInt(frames.size()*28672);
        for(int color:palette)out.put((byte)(color>>8)).put((byte)color);
        for(int f=0;f<frames.size();f++) {
            out.putShort((short)frames.get(f).durationMillis);int[] p=pixels.get(f);
            for(int i=0;i<p.length;i+=2)out.put((byte)((lookup.get(p[i])<<4)|lookup.get(p[i+1])));
        }
        return out.array();
    }
    private static int component(int c,int channel) {
        return switch(channel){case 0->((c>>11)&31)*255/31;case 1->((c>>5)&63)*255/63;default->(c&31)*255/31;};
    }
    private static int distance(int a,int b) {
        int r=component(a,0)-component(b,0),g=component(a,1)-component(b,1),bl=component(a,2)-component(b,2);
        return r*r+g*g+bl*bl;
    }
    private static int[] palette(Map<Integer,Integer> histogram) {
        List<List<Integer>> boxes=new ArrayList<>();boxes.add(new ArrayList<>(histogram.keySet()));
        while(boxes.size()<16) {
            int choice=-1,axis=0,score=-1;
            for(int i=0;i<boxes.size();i++) {
                var box=boxes.get(i);if(box.size()<2)continue;
                for(int channel=0;channel<3;channel++) {
                    int min=255,max=0;for(int c:box){int value=component(c,channel);min=Math.min(min,value);max=Math.max(max,value);}
                    if(max-min>score){score=max-min;choice=i;axis=channel;}
                }
            }
            if(choice<0)break;
            var box=boxes.remove(choice);final int channel=axis;
            box.sort(Comparator.comparingInt((Integer c)->component(c,channel)).thenComparingInt(Integer::intValue));
            long total=0,weight=0;for(int c:box)total+=histogram.get(c);
            int split=1;for(int i=0;i<box.size()-1;i++){weight+=histogram.get(box.get(i));split=i+1;if(weight*2>=total)break;}
            boxes.add(new ArrayList<>(box.subList(0,split)));boxes.add(new ArrayList<>(box.subList(split,box.size())));
        }
        int[] result=new int[16];
        for(int i=0;i<boxes.size();i++) {
            long r=0,g=0,b=0,n=0;
            for(int c:boxes.get(i)){int w=histogram.get(c);r+=(long)component(c,0)*w;g+=(long)component(c,1)*w;b+=(long)component(c,2)*w;n+=w;}
            result[i]=((int)(r/n)>>3)<<11|((int)(g/n)>>2)<<5|((int)(b/n)>>3);
        }
        return result;
    }
    /** Strict decoder shared by persistence validation, upload identity and preview. No firmware execution. */
    public static byte[] expand(byte[] object) {
        if(object==null||object.length<16||object.length>50000||!Arrays.equals(Arrays.copyOf(object,4),new byte[]{65,67,82,51}))
            throw new IllegalArgumentException("紧凑资源头无效。");
        ByteBuffer b=CompactUploadProtocol.read(object);b.position(4);
        int encoding=b.get()&255,scale=b.get()&255,frames=b.get()&255,flags=b.get()&255;
        int width=Short.toUnsignedInt(b.getShort()),height=Short.toUnsignedInt(b.getShort()),total=b.getInt();
        if((encoding!=1&&encoding!=2)||(scale!=1&&scale!=2&&scale!=4)||frames<1||frames>12
                ||flags!=(frames>1?1:0)||width*scale!=160||height*scale!=80||total!=frames*28672)
            throw new IllegalArgumentException("紧凑资源参数无效。");
        int count=encoding==1?width*height*2:width*height/2;
        if(object.length!=16+(encoding==2?32:0)+frames*(2+count))throw new IllegalArgumentException("紧凑资源长度无效。");
        int[] palette=new int[16];
        if(encoding==2)for(int i=0;i<16;i++)palette[i]=((b.get()&255)<<8)|(b.get()&255);
        byte[] expanded=new byte[total];Arrays.fill(expanded,(byte)0xFF);
        for(int f=0;f<frames;f++) {
            int duration=Short.toUnsignedInt(b.getShort());if(duration<20||duration>60000)throw new IllegalArgumentException("紧凑资源帧时长无效。");
            int start=b.position();
            for(int y=0;y<80;y++)for(int x=0;x<160;x++) {
                int source=(y/scale)*width+x/scale,color;
                if(encoding==1)color=((object[start+source*2]&255)<<8)|(object[start+source*2+1]&255);
                else { int packed=object[start+source/2]&255;color=palette[source%2==0?packed>>4:packed&15]; }
                int at=f*28672+(y*160+x)*2;expanded[at]=(byte)(color>>8);expanded[at+1]=(byte)color;
            }
            b.position(start+count);
            ByteBuffer tail=CompactUploadProtocol.fields(16);
            tail.put(new byte[]{65,84,48,51,1,(byte)f,(byte)frames,0}).putShort((short)duration).putShort((short)0);
            tail.putInt((int)CompactUploadProtocol.crc(Arrays.copyOf(tail.array(),12)));
            System.arraycopy(tail.array(),0,expanded,f*28672+25600,16);
        }
        return expanded;
    }
}
