using System.Collections.Concurrent;
using System.Collections.Immutable;
using System.IO;
using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Channels;
using AhaKey.Device.Ble;
using AhaKey.Protocol;
using AhaKey.Services;
namespace AhaKey.Studio.Services;

// Explicit maintenance CLI, separate from DeviceManager/configuration/normal startup.
public static class LegacyProtocolCharacterization
{
    private sealed class QueryRecord
    {
        public required string Purpose {get;init;}
        public required string Tx {get;init;}
        public required int TxLength {get;init;}
        public DateTimeOffset WriteStartedAt {get;init;}
        public DateTimeOffset? WriteCompletedAt {get;set;}
        public DateTimeOffset? ResponseAt {get;set;}
        public double? ResponseLatencyFromStartMs {get;set;}
        public double? ResponseLatencyFromGattCompletionMs {get;set;}
        public string? Rx {get;set;}
        public int? RxLength {get;set;}
        public string? PayloadAfterStatus {get;set;}
        public byte? StatusCode {get;set;}
        public GattResult? GattResult {get;set;}
        public string? Error {get;set;}
        public string? Classification {get;set;}
        public object? Parsed {get;set;}
    }
    public static async Task RunAsync(string output)
    {
        var settingsStore=new SettingsStore();var settings=settingsStore.Load();
        if(settings.BleDeviceName!="AhaKey AE1E" || string.IsNullOrEmpty(settings.BleDeviceId))throw new InvalidOperationException("Previously selected AE1E identity required.");
        var marker=Path.Combine(settingsStore.Root,"phase31","9d-attempt.txt");
        if(File.Exists(marker))throw new InvalidOperationException("An earlier 9D attempt is reserved. Never retry.");
        if(Process.GetProcessesByName("BLE_tcp_driver").Length>0 || IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners().Any(x=>x.Port==9000))throw new InvalidOperationException("Legacy bridge must be absent.");
        Directory.CreateDirectory(output);
        var evidenceFile=Path.Combine(output,"physical-session.json");
        if(File.Exists(evidenceFile))throw new IOException("Do not overwrite prior evidence.");
        var session=new WindowsGattSession(Guid.NewGuid(),new LegacyCharacterizationPermit(marker));
        var contract=GattContract.WindowsObserved;
        var notifications=Channel.CreateUnbounded<BleNotification>();
        var raw=new ConcurrentQueue<BleNotification>();var queries=new List<QueryRecord>();
        var connectedBeforeTeardown=false;var operationalAfter=false;string? failure=null;
        var options=new JsonSerializerOptions{WriteIndented=true,Converters={new JsonStringEnumConverter()}};
        void Save()=>File.WriteAllText(evidenceFile,JsonSerializer.Serialize(new {
            Phase="3.1",SessionId=session.Id,Identity="User-selected AhaKey; Windows identity and address omitted",
            Transport="Direct in-process Windows BLE",SourceGate="docs/studio2-phase31/source-safety-gate.md",
            Queries=queries,Notifications=raw.Select(n=>new {n.SessionId,n.ArrivedAt,Hex=Convert.ToHexString(n.Bytes.AsSpan()),Length=n.Bytes.Length}).ToArray(),
            OperationalAfter=operationalAfter,NativeConnectedBeforeTeardown=connectedBeforeTeardown,
            Teardown=session.TeardownResult,Failure=failure,
            Note="Status 00 has no status code. Latency is host UTC notification arrival minus native write start/completion. IDs are random session IDs, not Windows identifiers."
        },options));
        async Task<byte[]?> Query(ImmutableArray<byte> tx,string purpose)
        {
            using var deadline=new CancellationTokenSource(TimeSpan.FromSeconds(8));
            var q=new QueryRecord{Purpose=purpose,Tx=Convert.ToHexString(tx.AsSpan()),TxLength=tx.Length,WriteStartedAt=DateTimeOffset.UtcNow};queries.Add(q);Save();
            try {
                q.GattResult=await session.WriteCommandAsync(contract.Service,contract.Command,tx,deadline.Token);
                q.WriteCompletedAt=DateTimeOffset.UtcNow;q.GattResult.RequireSuccess("Query");
                while(true) {
                    var n=await notifications.Reader.ReadAsync(deadline.Token);
                    if(n.SessionId!=session.Id || n.ArrivedAt<q.WriteStartedAt || n.Bytes.Length<3 || n.Bytes[2]!=tx[2])continue;
                    q.ResponseAt=n.ArrivedAt;q.ResponseLatencyFromStartMs=(n.ArrivedAt-q.WriteStartedAt).TotalMilliseconds;
                    q.ResponseLatencyFromGattCompletionMs=(n.ArrivedAt-q.WriteCompletedAt.Value).TotalMilliseconds;
                    q.Rx=Convert.ToHexString(n.Bytes.AsSpan());q.RxLength=n.Bytes.Length;
                    if(tx[2]!=0 && n.Bytes.Length>=6){q.StatusCode=n.Bytes[3];q.PayloadAfterStatus=Convert.ToHexString(n.Bytes.AsSpan()[4..^2]);}
                    if(tx[2]==0)q.Parsed=AhaKeyProtocol.DecodeStatus(n.Bytes.AsSpan());
                    if(tx[2]==0x9F)q.Parsed=AhaKeyProtocol.DecodeCapabilities(n.Bytes.AsSpan());
                    if(tx[2]==0x9D)q.Classification=LegacyQueryClassifier.Classify(n.Bytes.AsSpan()).ToString();
                    return n.Bytes.ToArray();
                }
            } catch(OperationCanceledException){q.Error="TIMEOUT; no retry";if(tx[2]==0x9D)q.Classification=LegacyQueryResult.TIMEOUT.ToString();return null;}
            catch(Exception ex){q.Error=ex.GetType().Name;if(tx[2]==0x9D)q.Classification=LegacyQueryResult.UNKNOWN_RESPONSE.ToString();return null;}
            finally {Save();}
        }
        try {
            using var setup=new CancellationTokenSource(TimeSpan.FromSeconds(35));
            await session.AcquireAsync(settings.BleDeviceId,setup.Token);
            contract.Validate(await session.DiscoverGattAsync(setup.Token));
            (await session.SubscribeAsync(contract.Service,contract.Notify,n=>{raw.Enqueue(n);notifications.Writer.TryWrite(n);},setup.Token)).RequireSuccess("Subscribe");
            var status=await Query(AhaKeyProtocol.Query(ReadOnlyQuery.PhysicalStatus),"Baseline physical status");
            if(status is null || AhaKeyProtocol.DecodeStatus(status) is not {FirmwareMajor:1,FirmwareMinor:0})throw new InvalidOperationException("Unexpected physical firmware evidence; probe aborted.");
            var caps=await Query(AhaKeyProtocol.Query(ReadOnlyQuery.Capabilities),"Baseline capability response");
            if(caps is null || !caps.AsSpan().SequenceEqual(new byte[]{0xAA,0xBB,0x9F,0,0xCC,0xDD}))throw new InvalidOperationException("Unexpected 9F shape; probe aborted.");
            await Query(LegacyCharacterizationPermit.Request,"ONE fixed resource=2 index=0 offset=0 characterization query");
            var after=await Query(AhaKeyProtocol.Query(ReadOnlyQuery.PhysicalStatus),"Post-query operational status; no configuration scan");
            operationalAfter=after is not null && AhaKeyProtocol.DecodeStatus(after) is {FirmwareMajor:1,FirmwareMinor:0};
            connectedBeforeTeardown=session.NativeConnected;
        } catch(Exception ex){failure=ex.GetType().Name;}
        finally {await session.DisposeAsync();Save();}
        if(!operationalAfter || session.TeardownResult?.Success!=true || failure is not null)throw new InvalidOperationException("Characterization evidence requires review.");
    }
}
