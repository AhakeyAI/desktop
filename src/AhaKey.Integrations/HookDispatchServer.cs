using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace AhaKey.Integrations;

public sealed class HookDispatchServer(TaskActivityService activity, ApprovalService approvals) : IAsyncDisposable
{
    public const int MaximumMessageBytes = 4096;
    public const int MaximumClients = 8;
    private readonly object sync = new();
    private readonly HashSet<Task> workers = new();
    private CancellationTokenSource? lifetime;
    private TcpListener? listener;
    private Task? acceptTask;
    private Task? stopTask;
    public bool Running { get; private set; }
    public string? ErrorKey { get; private set; }
    public int Port => (listener?.LocalEndpoint as IPEndPoint)?.Port ?? HookContract.Port;
    public TimeSpan ReadTimeout { get; init; } = TimeSpan.FromSeconds(2);
    public event Action? Changed;
    public event Action<HookEvent>? EventReceived;
    // Port 0 is for isolated offline fixtures only; production always calls Start() with 8765.
    public bool Start(int port = HookContract.Port)
    {
        lock (sync)
        {
        if (stopTask is { IsCompleted: false }) return false;
        if (Running) return true;
        try
        {
            listener = new(IPAddress.Loopback, port) { ExclusiveAddressUse = true };
            listener.Start(MaximumClients); lifetime = new(); Running = true; ErrorKey = null;
            acceptTask = AcceptAsync(lifetime.Token);
        }
        catch (SocketException) { listener?.Stop(); listener = null; ErrorKey = "IntegrationPortCollision"; Running = false; }
        Changed?.Invoke(); return Running;
        }
    }
    private async Task AcceptAsync(CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested)
            {
                var client = await listener!.AcceptTcpClientAsync(ct);
                lock (sync)
                {
                    if (workers.Count >= MaximumClients) { client.Dispose(); continue; }
                    var work = HandleAsync(client, ct); workers.Add(work);
                    _ = work.ContinueWith(t => { lock (sync) workers.Remove(t); }, TaskScheduler.Default);
                }
            }
        }
        catch (Exception ex) when (ex is OperationCanceledException or SocketException or ObjectDisposedException) { }
    }
    public static HookEvent Parse(string line)
    {
        string? cmd;string? task=null,eventId=null,outcome=null;
        if (line.StartsWith('{'))
        {
            using var doc = JsonDocument.Parse(line, new() { MaxDepth = 8 });
            if (doc.RootElement.ValueKind != JsonValueKind.Object) throw new FormatException();
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in doc.RootElement.EnumerateObject())
            {
                if (!names.Add(property.Name) || property.Name is not ("cmd" or "taskId" or "sessionId" or "eventId" or "outcome" or "title") || property.Value.ValueKind != JsonValueKind.String)
                    throw new FormatException();
            }
            cmd = doc.RootElement.GetProperty("cmd").GetString();
            static string? Token(JsonElement obj,string name)=>obj.TryGetProperty(name,out var value) && value.GetString() is {Length:>0 and <=256} text
                ?Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(text))):null;
            task=Token(doc.RootElement,"taskId")??Token(doc.RootElement,"sessionId");eventId=Token(doc.RootElement,"eventId");
            outcome=doc.RootElement.TryGetProperty("outcome",out var result)&&result.GetString()=="error"?"error":null;
            // Only opaque ownership hashes survive parsing. title and all prompt content are discarded.
        }
        else cmd = line;
        return cmd is not null && HookContract.Events.TryGetValue(cmd, out var ev) ? ev with{TaskId=task,EventId=eventId,Outcome=outcome} : throw new FormatException();
    }
    private async Task HandleAsync(TcpClient client, CancellationToken ct)
    {
        using (client)
        using (var lifetimeBound = CancellationTokenSource.CreateLinkedTokenSource(ct))
        {
            lifetimeBound.CancelAfter(TimeSpan.FromSeconds(19));
            var stream = client.GetStream();
            try
            {
                using var read = CancellationTokenSource.CreateLinkedTokenSource(lifetimeBound.Token);
                read.CancelAfter(ReadTimeout);
                var buffer = new byte[MaximumMessageBytes]; int count = 0;
                while (true)
                {
                    if (count == buffer.Length) throw new FormatException();
                    int received = await stream.ReadAsync(buffer.AsMemory(count, 1), read.Token);
                    if (received == 0) throw new FormatException();
                    if (buffer[count] == 10) break;
                    count++;
                }
                if (count > 0 && buffer[count - 1] == 13) count--;
                var ev = Parse(new UTF8Encoding(false, true).GetString(buffer, 0, count));
                EventReceived?.Invoke(ev);
                activity.Accept(ev, HookContract.RequiresApproval(ev) ? "pending" : "received");
                var decision = HookContract.RequiresApproval(ev)
                    ? await approvals.DecideAsync(ev, lifetimeBound.Token) : new ApprovalDecision(false, "fail-closed", "received");
                if (HookContract.RequiresApproval(ev)) activity.Accept(ev, decision.Outcome, decision.Source);
                var response = JsonSerializer.Serialize(new { schemaVersion = 1, platform = ev.Integration.ToString().ToLowerInvariant(), @event = ev.NativeEvent, allow = decision.Allow, approvalSource = decision.Source });
                await stream.WriteAsync(Encoding.UTF8.GetBytes(response + "\n"), lifetimeBound.Token);
            }
            catch (Exception ex) when (ex is not OutOfMemoryException)
            {
                // No exception message or raw input can enter application logs.
                try { await stream.WriteAsync("{\"ok\":false,\"error\":\"invalid-or-timeout\"}\n"u8.ToArray(), lifetimeBound.Token); }
                catch (Exception inner) when (inner is not OutOfMemoryException) { }
            }
        }
    }
    public ValueTask DisposeAsync()
    {
        lock (sync)
        {
            if (stopTask is { IsCompleted: false }) return new(stopTask);
            stopTask = StopAsync(); return new(stopTask);
        }
    }
    private async Task StopAsync()
    {
        Running = false; lifetime?.Cancel(); listener?.Stop();
        if (acceptTask is not null) await acceptTask;
        Task[] pending; lock (sync) pending = workers.ToArray();
        await Task.WhenAll(pending); lifetime?.Dispose(); lifetime = null; listener = null; Changed?.Invoke();
    }
}
