using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using AhaKey.Integrations;
namespace AhaKey.Integrations.Tests;

// Executes the generated hook against an isolated ephemeral listener, never a host config.
public sealed class NativeHookMetadataTests
{
    [Fact] public async Task GeneratedPowerShellForwardsOnlyOwnershipMetadata()
    {
        if(!OperatingSystem.IsWindows())return;
        var root=Path.Combine(Path.GetTempPath(),"ahakey-hook-metadata",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
        using var listener=new TcpListener(IPAddress.Loopback,0);listener.Start();var port=((IPEndPoint)listener.LocalEndpoint).Port;
        var path=Path.Combine(root,"hook.ps1");File.WriteAllText(path,HookScript.Create(AssistantId.Codex).Replace("'127.0.0.1',8765",$"'127.0.0.1',{port}"));
        using var process=new Process{StartInfo=new("powershell.exe"){UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true}};
        foreach(var arg in new[]{"-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",path,"CodexStop"})process.StartInfo.ArgumentList.Add(arg);
        try
        {
            Assert.True(process.Start());await process.StandardInput.WriteAsync("{\"session_id\":\"test-session\",\"event_id\":\"event-42\",\"prompt\":\"must not be forwarded\",\"tool_input\":{\"secret\":true}}");process.StandardInput.Close();
            using var client=await listener.AcceptTcpClientAsync().WaitAsync(TimeSpan.FromSeconds(10));
            using var reader=new StreamReader(client.GetStream());var line=await reader.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(5));
            using var json=JsonDocument.Parse(line!);Assert.Equal("test-session",json.RootElement.GetProperty("taskId").GetString());Assert.Equal("event-42",json.RootElement.GetProperty("eventId").GetString());
            Assert.Equal(3,json.RootElement.EnumerateObject().Count());Assert.DoesNotContain("prompt",line);Assert.DoesNotContain("secret",line);
            using var writer=new StreamWriter(client.GetStream()){AutoFlush=true};await writer.WriteLineAsync("{}");
            await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));Assert.Equal(0,process.ExitCode);Assert.Equal("{}",(await process.StandardOutput.ReadToEndAsync()).Trim());
        }
        finally{if(!process.HasExited)process.Kill(true);Directory.Delete(root,true);}
    }
}
