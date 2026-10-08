using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Security.Cryptography;
using AhaKey.Firmware;
namespace AhaKey.Studio.Services;

// All vendor process calls are isolated here. No GUI automation, no process-name killing.
public sealed class WchProcessRunner : IWchProcessRunner
{
    public sealed record Request(string Root,string Config,string Image,string Directory,string Token,string ImageHash);
    public async Task<FlashProcessResult> RunAsync(WchRuntime runtime,string config,string image,string directory,IProgress<string> progress)
    {
        var token=Guid.NewGuid().ToString("N");
        var request=new Request(runtime.Root,config,image,directory,token,Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(image))));
        var path=Path.Combine(directory,"worker.json");await File.WriteAllTextAsync(path,JsonSerializer.Serialize(request));
        var start=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true};
        start.ArgumentList.Add("--firmware-worker");start.ArgumentList.Add(path);start.Environment["AHAKEY_FLASH_WORKER"]=token;
        using var worker=Process.Start(start)??throw new IOException("Flash worker did not start.");
        // Never terminate an owned flash process, including after a diagnostic timeout.
        var wait=worker.WaitForExitAsync();
        if(await Task.WhenAny(wait,Task.Delay(TimeSpan.FromMinutes(5)))!=wait)
            progress.Report("FirmwareWorkerStillRunning");
        await wait;
        if(!File.Exists(Path.Combine(directory,"result.json")))throw new IOException("Flash worker stopped without a verified vendor result; inspect recovery state.");
        var result=JsonSerializer.Deserialize<FlashProcessResult>(await File.ReadAllTextAsync(Path.Combine(directory,"result.json")))??throw new IOException("No vendor result.");
        return result;
    }
    public static async Task<int> RunWorkerAsync(string path)
    {
        var request=JsonSerializer.Deserialize<Request>(await File.ReadAllTextAsync(path))??throw new FormatException();
        if(string.IsNullOrEmpty(request.Token)||Environment.GetEnvironmentVariable("AHAKEY_FLASH_WORKER")!=request.Token)throw new UnauthorizedAccessException();
        var runtime=WchRuntime.Detect(request.Root)??throw new InvalidOperationException("Vendor runtime changed.");
        // Survives a UI-process crash: a second worker cannot own this programmer.
        var firmwareRoot=System.IO.Path.GetFullPath(System.IO.Path.Combine(request.Directory,"..",".."));
        using var workerOwner=new FileStream(System.IO.Path.Combine(firmwareRoot,"worker.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
        using var imageOwner=new FileStream(request.Image,FileMode.Open,FileAccess.Read,FileShare.Read);
        var imageBytes=await File.ReadAllBytesAsync(request.Image);
        if(Convert.ToHexString(SHA256.HashData(imageBytes))!=request.ImageHash)throw new InvalidOperationException("Staged firmware changed.");
        FirmwarePackageValidator.ValidateHex(Encoding.ASCII.GetString(imageBytes));
        if(await File.ReadAllTextAsync(request.Config)!=WchFlashTransport.Configuration(request.Image))throw new InvalidOperationException("Flash configuration changed.");
        AllocConsole();var console=GetConsoleWindow();if(console!=IntPtr.Zero)ShowWindow(console,0);
        try
        {
            var start=new ProcessStartInfo(runtime.Executable){UseShellExecute=false,CreateNoWindow=false,WindowStyle=ProcessWindowStyle.Hidden,WorkingDirectory=runtime.Root,RedirectStandardOutput=true,RedirectStandardError=true};
            // The installed vendor's CH375DLL lives in the package root, separate from the chip tool.
            start.Environment["PATH"]=runtime.Root+";"+Environment.GetEnvironmentVariable("PATH");
            foreach(var arg in new[]{"-c",request.Config,"-o","download","-f",request.Image})start.ArgumentList.Add(arg);
            using var process=Process.Start(start)??throw new IOException("Vendor process did not start.");
            var output=process.StandardOutput.ReadToEndAsync();var error=process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();
            var text=(await output)+"\n"+(await error)+"\n"+ReadConsole();
            // Only sanitized output leaves the isolated worker. Paths are not diagnostic identity.
            text=text.Replace(request.Root,"<vendor>",StringComparison.OrdinalIgnoreCase).Replace(request.Directory,"<operation>",StringComparison.OrdinalIgnoreCase)
                .Replace(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"<user>",StringComparison.OrdinalIgnoreCase);
            if(text.Length>65536)text=text[^65536..];
            var result=new FlashProcessResult(process.ExitCode,text,true);
            await File.WriteAllTextAsync(Path.Combine(request.Directory,"result.json"),JsonSerializer.Serialize(result));
            return WchFlashTransport.TerminalSuccess(result)?0:2;
        }
        finally{FreeConsole();}
    }
    private static string ReadConsole()
    {
        var handle=GetStdHandle(-11);if(!GetConsoleScreenBufferInfo(handle,out var info))return "";
        var count=Math.Min(65536,info.Size.X*(info.Cursor.Y+1));var buffer=new StringBuilder(count);
        return ReadConsoleOutputCharacter(handle,buffer,(uint)count,new Coord(),out _)?buffer.ToString():"";
    }
    [StructLayout(LayoutKind.Sequential)] private struct Coord {public short X,Y;}
    [StructLayout(LayoutKind.Sequential)] private struct Rect {public short Left,Top,Right,Bottom;}
    [StructLayout(LayoutKind.Sequential)] private struct BufferInfo {public Coord Size,Cursor;public short Attributes;public Rect Window;public Coord Maximum;}
    [DllImport("kernel32.dll")] private static extern bool AllocConsole();
    [DllImport("kernel32.dll")] private static extern bool FreeConsole();
    [DllImport("kernel32.dll")] private static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll")] private static extern IntPtr GetStdHandle(int value);
    [DllImport("kernel32.dll")] private static extern bool GetConsoleScreenBufferInfo(IntPtr h,out BufferInfo info);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,EntryPoint="ReadConsoleOutputCharacterW")] private static extern bool ReadConsoleOutputCharacter(IntPtr h,StringBuilder text,uint length,Coord origin,out uint read);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window,int command);
}
