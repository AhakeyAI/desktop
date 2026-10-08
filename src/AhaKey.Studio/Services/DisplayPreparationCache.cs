namespace AhaKey.Studio.Services;

// WPF's renderer requires STA. One worker at a time, frozen results only, bounded cache.
public sealed class DisplayPreparationCache
{
    private readonly SemaphoreSlim worker = new(1);
    private readonly Dictionary<string, PreparedDisplayImage> cache = [];
    public async Task<PreparedDisplayImage> LoadAsync(string path,int capacity,DisplayFitMode fit,string background,CancellationToken ct)
    {
        await worker.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            var file=await Task.Run(()=>new System.IO.FileInfo(path),ct).ConfigureAwait(false);
            string key=$"{path}|{file.Length}|{file.LastWriteTimeUtc.Ticks}|{capacity}|{fit}|{background}";
            ct.ThrowIfCancellationRequested();
            if(cache.TryGetValue(key,out var saved))return saved;
            var done=new TaskCompletionSource<PreparedDisplayImage>(TaskCreationOptions.RunContinuationsAsynchronously);
            var thread=new Thread(()=>
            {
                try{done.SetResult(DisplayImagePreparation.Load(path,capacity,fit,background,ct));}
                catch(OperationCanceledException){done.TrySetCanceled(ct);}
                catch(Exception ex){done.TrySetException(ex);}
            }){IsBackground=true,Name="Display conversion"};
            thread.SetApartmentState(ApartmentState.STA);thread.Start();
            var image=await done.Task.ConfigureAwait(false);ct.ThrowIfCancellationRequested();
            if(cache.Count>=12)cache.Remove(cache.Keys.First());cache[key]=image;return image;
        }
        finally{worker.Release();}
    }
}
