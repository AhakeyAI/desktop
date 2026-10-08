using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text;
namespace AhaKey.Services;

// Per-user local file ownership plus a current-user-only named pipe; no TCP listener.
public sealed class SingleInstanceOwner : IDisposable
{
    private readonly FileStream? ownership;
    private readonly CancellationTokenSource lifetime=new();
    private readonly string endpoint;
    public bool IsPrimary=>ownership is not null;
    public event Action? ActivationRequested;
    public SingleInstanceOwner(string root)
    {
        Directory.CreateDirectory(root);
        endpoint="AhaKeyStudio-"+Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(root)+Environment.UserName)))[..24];
        try {ownership=new FileStream(Path.Combine(root,"instance.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);}
        catch(IOException ex) when((ex.HResult & 0xFFFF) is 32 or 33) { }
        if(IsPrimary)_=ListenAsync();
    }
    private async Task ListenAsync()
    {
        while(!lifetime.IsCancellationRequested)
        {
            try
            {
                using var pipe=new NamedPipeServerStream(endpoint,PipeDirection.In,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous|PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(lifetime.Token);
                var bytes=new byte[1];using var timeout=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);timeout.CancelAfter(1000);
                if(await pipe.ReadAsync(bytes,timeout.Token)==1 && bytes[0]==1)ActivationRequested?.Invoke();
            }
            catch(OperationCanceledException) { }
            catch(IOException)
            {
                try {await Task.Delay(100,lifetime.Token).ConfigureAwait(false);}
                catch(OperationCanceledException) { }
            }
        }
    }
    public async Task<bool> ActivateAsync()
    {
        try
        {
            using var pipe=new NamedPipeClientStream(".",endpoint,PipeDirection.Out,PipeOptions.Asynchronous|PipeOptions.CurrentUserOnly);
            using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(3));
            await pipe.ConnectAsync(timeout.Token);await pipe.WriteAsync(new byte[]{1},timeout.Token);return true;
        }
        catch(Exception ex) when(ex is IOException or OperationCanceledException or TimeoutException){return false;}
    }
    public void Dispose(){lifetime.Cancel();ownership?.Dispose();}
}
