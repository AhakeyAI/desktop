using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using AhaKey.Core;
namespace AhaKey.Firmware;

public sealed record WchRuntime(string Root,string Executable,string ToolHash)
{
    public const string OfficialPackageUrl="https://www.wch.cn/downloads/WCHISPTool_Setup_exe.html";
    private static readonly (string Path,string Hash)[] Files=[
        ("WCHISPTool_CH57x-59x/WCHISPTool_CH57x-59x.exe","94983AB6D1B66B58C5F6396BCAE80DCB89189C91C7F1D739976B6B8BD31FC29A"),
        ("WCHISPTool_CH57x-59x/WCH55xISPDLL.dll","52354DFBA178B2BE30F72850D13EC2EE5EA12B71151DC5C4FFCD5CEA8AF09761"),
        ("WCHISPTool_CH57x-59x/CH343PT.DLL","160781C0D2C49333E965129B05713B2CB4F662C10E14FA2BDE5D998574192366"),
        ("CH375DLL.dll","0F019B958D4D3F6B8EC0D282EF848A57F0F92A0596D7405B6C58F5AA383A326C")];
    public static WchRuntime? Detect(string root)
    {
        try
        {
            foreach(var (relative,hash) in Files)
            {using var file=File.OpenRead(System.IO.Path.Combine(root,relative));if(Convert.ToHexString(SHA256.HashData(file))!=hash)return null;}
            return new(root,System.IO.Path.Combine(root,Files[0].Path),Files[0].Hash);
        }
        catch(Exception ex)when(ex is IOException or UnauthorizedAccessException){return null;}
    }
}
public sealed record FlashProcessResult(int ExitCode,string Output,bool Exited);
public interface IWchProcessRunner
{
    Task<FlashProcessResult> RunAsync(WchRuntime runtime,string config,string image,string directory,IProgress<string> progress);
}
public sealed class WchFlashTransport(WchRuntime runtime,IWchProcessRunner runner,string journalRoot,
    Func<CancellationToken,Task> waitForBootloader,Func<CancellationToken,Task<FirmwareIdentity>> waitForApplication) : IFlashTransport
{
    public string AvailabilityReason=>WchRuntime.Detect(runtime.Root) is null?"FirmwareComponentMissing":"";
    public Task EnterUpdateModeAsync(CancellationToken ct)=>waitForBootloader(ct);
    public Task<FirmwareIdentity> RebootAndReadIdentityAsync(CancellationToken ct)=>waitForApplication(ct);
    public async Task ProgramAndVerifyAsync(FirmwarePackage package,PackageValidation validation,IProgress<string> progress,CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        if(WchRuntime.Detect(runtime.Root) is null)throw new InvalidOperationException("Vendor runtime changed.");
        var directory=Path.Combine(journalRoot,Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
        var image=Path.Combine(directory,"firmware.hex");File.Copy(package.ImagePath,image);
        var staged=await FirmwarePackageValidator.ValidateAsync(package with{ImagePath=image},ct);
        if(staged.Sha256!=validation.Sha256)throw new InvalidOperationException("Image changed after preflight.");
        var config=Path.Combine(directory,"flash-config.ini");await File.WriteAllTextAsync(config,Configuration(image),new UTF8Encoding(false),ct);
        var result=await runner.RunAsync(runtime,config,image,directory,progress);
        // No success on exit 0 alone; the observed vendor may return 100 after its successful terminal record.
        if(!TerminalSuccess(result))throw new InvalidOperationException("Vendor verification was not confirmed.");
    }
    public static bool TerminalSuccess(FlashProcessResult result)=>result.Exited && result.ExitCode is 0 or 100 &&
        Regex.IsMatch(result.Output,@"(?is)\bFinished\b.*?\bCode\s*[:=]?\s*0\b.*?\bMessage\s*[:=]?\s*Succeed\b") &&
        !Regex.IsMatch(result.Output,@"(?i)\b(?:Failed|Failure|Exception)\b|\bCode\s*[:=]?\s*[1-9]\d*\b");
    public static string Configuration(string image)=>$"""
        [Public]
        MCUName=CH582
        bMCULine=6
        bMCUType=130
        DataFlashFile=.
        swzUserFile1={Path.GetFullPath(image)}
        swzUserFile2=.
        swzUserFile3=.
        swzUserFile4=.
        swzUserFile5=.
        DataFlashFileSel=0
        IsUserFile1Sel=1
        IsUserFile2Sel=0
        IsUserFile3Sel=0
        IsUserFile4Sel=0
        IsUserFile5Sel=0
        [CH57x-58xUICfg]
        bDnInterType=0
        Baud=115200
        DwnldCfgPin=PB22
        BootPinNum=1
        WProtectAddr=.
        IsCodeProtect=1
        IsRSTAsInputPin=0
        ExtRSTPinSel=.
        ExtRSTPinSelNum=1
        IndependentWDGEn=0
        IsSerialNoBtnDwnld=0
        IsClearDataFlash=0
        IsEraseAllCFlash=1
        IsAfterDownRest=0
        bVerifyType=0
        """;
}
