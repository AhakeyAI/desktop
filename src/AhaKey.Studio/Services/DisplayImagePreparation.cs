using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using AhaKey.Protocol;
namespace AhaKey.Studio.Services;
public sealed record PreparedDisplayImage(string Name,BitmapSource Preview,IReadOnlyList<byte[]> Frames,DisplayTiming Timing,int SourceFrames)
{public bool IsGif {get;init;}public bool VariableTimingConverted {get;init;}}
public enum DisplayFitMode { Fit, Crop }
public static class DisplayImagePreparation
{
    public static PreparedDisplayImage Load(string path,int limit,DisplayFitMode mode=DisplayFitMode.Fit,string background="#000000",CancellationToken ct=default)
    {
        var file=new FileInfo(path);if(file.Length>20*1024*1024)throw new ArgumentException("Source exceeds 20 MiB decode limit.");
        using var stream=File.OpenRead(path);var decoder=BitmapDecoder.Create(stream,BitmapCreateOptions.PreservePixelFormat,BitmapCacheOption.OnDemand);
        if(decoder.Frames.Count is <1 or >500)throw new ArgumentException("Source exceeds 500 frames.");
        ct.ThrowIfCancellationRequested();
        if(decoder.Frames.Sum(f=>(long)f.PixelWidth*f.PixelHeight)>16*1024*1024)throw new ArgumentException("Decoded frame budget exceeds 64 MiB.");
        bool gif=decoder is GifBitmapDecoder;
        int Read(BitmapMetadata? m,string query,int fallback){try{return m?.GetQuery(query) is {} value?Convert.ToInt32(value):fallback;}catch{return fallback;}}
        var meta=decoder.Metadata as BitmapMetadata;int width=gif?Read(meta,"/logscrdesc/Width",decoder.Frames[0].PixelWidth):decoder.Frames[0].PixelWidth;
        int height=gif?Read(meta,"/logscrdesc/Height",decoder.Frames[0].PixelHeight):decoder.Frames[0].PixelHeight;
        if(width<1||height<1||width>4096||height>4096)throw new ArgumentException("Canvas exceeds 4096 pixels per edge.");
        var delays=decoder.Frames.Select(f=>gif?Read(f.Metadata as BitmapMetadata,"/grctlext/Delay",10)*10:100).ToArray();
        var timing=DisplayTiming.Create(delays,limit);var backgroundBrush=new SolidColorBrush((Color)ColorConverter.ConvertFromString(background));backgroundBrush.Freeze();
        var selected=timing.SourceIndices.ToHashSet();var result=new List<byte[]>();BitmapSource? preview=null;
        var canvas=new byte[checked(width*height*4)];
        for(int index=0;index<decoder.Frames.Count;index++)
        {
            ct.ThrowIfCancellationRequested();var frame=decoder.Frames[index];var fm=frame.Metadata as BitmapMetadata;
            int left=gif?Read(fm,"/imgdesc/Left",0):0,top=gif?Read(fm,"/imgdesc/Top",0):0,disposal=gif?Read(fm,"/grctlext/Disposal",0):0;
            if(left<0||top<0||frame.PixelWidth>width-left||frame.PixelHeight>height-top)throw new ArgumentException("Invalid frame bounds.");
            byte[]? previous=disposal==3?(byte[])canvas.Clone():null;
            var converted=new FormatConvertedBitmap(frame,PixelFormats.Bgra32,null,0);var pixels=new byte[checked(frame.PixelWidth*frame.PixelHeight*4)];converted.CopyPixels(pixels,frame.PixelWidth*4,0);
            for(int y=0;y<frame.PixelHeight;y++)for(int x=0;x<frame.PixelWidth;x++)
            {
                int src=(y*frame.PixelWidth+x)*4,dst=((top+y)*width+left+x)*4,a=pixels[src+3];
                if(a==0)continue;int oldAlpha=canvas[dst+3];int outAlpha=a+(oldAlpha*(255-a)+127)/255;
                for(int c=0;c<3;c++)canvas[dst+c]=(byte)Math.Clamp((pixels[src+c]*a+canvas[dst+c]*oldAlpha*(255-a)/255+outAlpha/2)/outAlpha,0,255);canvas[dst+3]=(byte)outAlpha;
            }
            if(selected.Contains(index))
            {
                var source=BitmapSource.Create(width,height,96,96,PixelFormats.Bgra32,null,canvas,width*4);
                double scale=mode==DisplayFitMode.Crop?Math.Max(160d/width,80d/height):Math.Min(160d/width,80d/height);int targetW=Math.Max(1,(int)Math.Floor(width*scale+0.5)),targetH=Math.Max(1,(int)Math.Floor(height*scale+0.5));
                var visual=new DrawingVisual();RenderOptions.SetBitmapScalingMode(visual,BitmapScalingMode.LowQuality);
                using(var drawing=visual.RenderOpen()){drawing.DrawRectangle(backgroundBrush,null,new Rect(0,0,160,80));drawing.DrawImage(source,new Rect((160-targetW)/2,(80-targetH)/2,targetW,targetH));}
                var bitmap=new RenderTargetBitmap(160,80,96,96,PixelFormats.Pbgra32);bitmap.Render(visual);bitmap.Freeze();
                var rgbBitmap=new FormatConvertedBitmap(bitmap,PixelFormats.Rgb24,null,0);var rgb=new byte[160*80*3];rgbBitmap.CopyPixels(rgb,160*3,0);var encoded=DisplayPixelEncoder.Rgb565(rgb);result.Add(encoded);
                if(preview is null)
                {
                    for(int i=0;i<encoded.Length/2;i++){int pixel=(encoded[i*2]<<8)|encoded[i*2+1];rgb[i*3]=(byte)(((pixel>>11)&31)*255/31);rgb[i*3+1]=(byte)(((pixel>>5)&63)*255/63);rgb[i*3+2]=(byte)((pixel&31)*255/31);}
                    preview=BitmapSource.Create(160,80,96,96,PixelFormats.Rgb24,null,rgb,160*3);preview.Freeze();
                }
            }
            if(disposal==2)for(int y=0;y<frame.PixelHeight;y++)Array.Clear(canvas,((top+y)*width+left)*4,frame.PixelWidth*4);
            else if(previous is not null)canvas=previous;
        }
        return new(Path.GetFileName(path),preview!,result,timing,decoder.Frames.Count){IsGif=gif,VariableTimingConverted=gif&&delays.Distinct().Count()>1};
    }
    public static BitmapSource PreviewFrame(byte[] encoded)
    {
        var rgb=new byte[160*80*3];for(int i=0;i<encoded.Length/2;i++){int p=(encoded[i*2]<<8)|encoded[i*2+1];rgb[i*3]=(byte)(((p>>11)&31)*255/31);rgb[i*3+1]=(byte)(((p>>5)&63)*255/63);rgb[i*3+2]=(byte)((p&31)*255/31);}
        var bitmap=BitmapSource.Create(160,80,96,96,System.Windows.Media.PixelFormats.Rgb24,null,rgb,160*3);bitmap.Freeze();return bitmap;
    }
}
