using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AhaKey.Core;
using AhaKey.Firmware;
namespace AhaKey.Core.Tests;
public sealed class Phase9FirmwareTests : IDisposable
{
    private readonly string root=Path.Combine(Path.GetTempPath(),"ahakey-phase9-"+Guid.NewGuid());
    private async Task<FirmwarePackage> Package()
    {
        Directory.CreateDirectory(root);var image=Path.Combine(root,"test.hex");await File.WriteAllTextAsync(image,":0400000001020304F2\n:00000001FF\n");
        var source=new string('a',40);var provenance=Path.Combine(root,"provenance.json");
        await File.WriteAllTextAsync(provenance,JsonSerializer.Serialize(new{sourceCommit=source,firmwareVersion="1.4.8",protocolVersion="3.2",deviceModel="AhaKey-X1",mcu="CH582",sourceTreeClean=true}));
        return new("AhaKey-X1","CH582","1.4.8","3.2",image,Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(image))),source,provenance,"Test fixture only");
    }
    private sealed class Transport : IFlashTransport
    {
        public string AvailabilityReason=>"";public int Writes;public bool WrongIdentity,FailProgram;
        public bool ReceivedCancellableToken;
        public Task EnterUpdateModeAsync(CancellationToken ct)=>Task.CompletedTask;
        public Task ProgramAndVerifyAsync(FirmwarePackage p,PackageValidation v,IProgress<string> progress,CancellationToken ct)
        {Writes++;ReceivedCancellableToken=ct.CanBeCanceled;return FailProgram?Task.FromException(new IOException("fixture")):Task.CompletedTask;}
        public Task<FirmwareIdentity> RebootAndReadIdentityAsync(CancellationToken ct)=>Task.FromResult(new FirmwareIdentity(1,4,8,"3.2",1,WrongIdentity?0u:0x7FFu,"physical",null,IdentitySource.PhysicalTelemetry,FirmwareDialect.WindowsContract32));
    }
    [Theory][InlineData(false,false,FirmwareUpdateState.Completed)][InlineData(true,false,FirmwareUpdateState.RecoveryRequired)][InlineData(false,true,FirmwareUpdateState.RecoveryRequired)]
    public async Task SuccessNeedsPhysicalCapabilitiesAndFailuresPersistRecovery(bool wrong,bool fail,FirmwareUpdateState expected)
    {
        var package=await Package();var transport=new Transport{WrongIdentity=wrong,FailProgram=fail};var path=Path.Combine(root,"journal.json");var coordinator=new FirmwareUpdateCoordinator(transport,path);
        if(wrong||fail)await Assert.ThrowsAnyAsync<Exception>(()=>coordinator.UpdateAsync(package,true,new Progress<string>()));
        else await coordinator.UpdateAsync(package,true,new Progress<string>());
        Assert.Equal(1,transport.Writes);Assert.False(transport.ReceivedCancellableToken);Assert.False(coordinator.Critical);
        Assert.Equal(expected,coordinator.Journal!.State);Assert.Equal(expected,new FirmwareUpdateCoordinator(transport,path).Journal!.State);
    }
    [Fact] public async Task InvalidImageAndNoApprovalNeverProgram()
    {
        var package=await Package();var transport=new Transport();var c=new FirmwareUpdateCoordinator(transport);
        await Assert.ThrowsAsync<InvalidOperationException>(()=>c.UpdateAsync(package,false,new Progress<string>()));
        await File.AppendAllTextAsync(package.ImagePath,"x");await Assert.ThrowsAsync<FormatException>(()=>c.UpdateAsync(package,true,new Progress<string>()));Assert.Equal(0,transport.Writes);
    }
    [Fact] public void RestartOfInterruptedProgrammingRequiresRecovery()
    {
        Directory.CreateDirectory(root);var path=Path.Combine(root,"journal.json");File.WriteAllText(path,JsonSerializer.Serialize(new FirmwareUpdateJournal(Guid.NewGuid(),"1.4.8","hash",FirmwareUpdateState.Programming,DateTimeOffset.UtcNow)));
        Assert.Equal(FirmwareUpdateState.RecoveryRequired,new FirmwareUpdateCoordinator(new Transport(),path).Journal!.State);
    }
    [Theory][InlineData(0,"",false)][InlineData(0,"Finished Code=0 Message=Succeed",true)][InlineData(100,"Finished Code: 0 Message: Succeed",true)][InlineData(1,"Finished Code=0 Message=Succeed",false)][InlineData(0,"Finished Code=14 Message=Failed",false)]
    public void TerminalRecordAndExitedProcessBothRequired(int code,string output,bool expected)
    {Assert.Equal(expected,WchFlashTransport.TerminalSuccess(new(code,output,true)));Assert.False(WchFlashTransport.TerminalSuccess(new(code,output,false)));}
    [Fact] public void OrdinaryFirmwarePlanPreservesDataAndTargetsCh582()
    {var config=WchFlashTransport.Configuration(Path.Combine(root,"image.hex"));Assert.Contains("MCUName=CH582",config);Assert.Contains("DataFlashFileSel=0",config);Assert.Contains("IsClearDataFlash=0",config);Assert.DoesNotContain("factory",config,StringComparison.OrdinalIgnoreCase);}
    public void Dispose(){if(Directory.Exists(root))Directory.Delete(root,true);}
}
