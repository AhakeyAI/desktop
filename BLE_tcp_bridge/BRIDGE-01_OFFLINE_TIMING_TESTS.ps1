$ErrorActionPreference = 'Stop'
$bridgeRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tcpSource = [IO.File]::ReadAllText((Join-Path $bridgeRoot 'TcpServer.cs'))
$programSource = [IO.File]::ReadAllText((Join-Path $bridgeRoot 'Program.cs'))
$formSource = [IO.File]::ReadAllText((Join-Path $bridgeRoot 'Form1.cs'))

function Get-TypeSource([string]$source, [string]$declaration) {
    $start = $source.IndexOf($declaration, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Could not find production type: $declaration" }
    $open = $source.IndexOf('{', $start)
    $depth = 0
    for ($i = $open; $i -lt $source.Length; $i++) {
        if ($source[$i] -eq '{') { $depth++ }
        if ($source[$i] -eq '}') {
            $depth--
            if ($depth -eq 0) { return $source.Substring($start, $i - $start + 1) }
        }
    }
    throw "Unbalanced production type: $declaration"
}

$fifoSource = Get-TypeSource $tcpSource 'internal sealed class BoundedAsyncFifo<T>'
$mtuSource = Get-TypeSource $tcpSource 'internal static class BridgeMtuPolicy'
$roundSource = Get-TypeSource $tcpSource 'internal static class BridgeRoundIdentity'

$runnerSource = @'
namespace Bridge01OfflineTests {
    internal sealed class Item {
        public string Id;
        public string Client;
        public long Generation;
        public CancellationTokenSource Cancellation = new CancellationTokenSource();
        public Item(string id, string client, long generation) { Id = id; Client = client; Generation = generation; }
    }
    public static class Runner {
        private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
        private static void WaitFor(Func<bool> condition, string message) {
            if (!SpinWait.SpinUntil(condition, 3000)) throw new TimeoutException(message);
        }
        public static string Run() {
            var results = new List<string>();
            Check(BLE_tcp_driver.BridgeMtuPolicy.SelectPayload(23, true, 200) == 20, "MTU 23 fallback");
            Check(BLE_tcp_driver.BridgeMtuPolicy.SelectPayload(62, true, 200) == 59, "MTU 62 payload");
            Check(BLE_tcp_driver.BridgeMtuPolicy.SelectPayload(203, true, 200) == 200, "MTU 203 firmware cap");
            Check(BLE_tcp_driver.BridgeMtuPolicy.SelectPayload(247, true, 200) == 200, "MTU 247 firmware cap");
            Check(BLE_tcp_driver.BridgeMtuPolicy.SelectPayload(517, true, 200) == 200, "MTU 517 firmware cap");
            Check(BLE_tcp_driver.BridgeMtuPolicy.SelectPayload(517, false, 200) == 20, "unavailable MTU fallback");
            foreach (int payloadLength in new[] { 20, 59, 200, 201, 401 }) {
                int limit = payloadLength <= 20 ? 20 : payloadLength <= 59 ? 59 : 200;
                byte[] payload = Enumerable.Range(0, payloadLength).Select(i => (byte)(i % 251)).ToArray();
                var fragments = new List<byte[]>();
                bool sent = BLE_tcp_driver.BridgeMtuPolicy.SendFragmentsAsync(payload, limit,
                    (offset, chunk, fragment, count) => { fragments.Add(chunk); return Task.FromResult(true); },
                    () => true).GetAwaiter().GetResult();
                Check(sent, "fragment transfer result");
                Check(fragments.All(fragment => fragment.Length <= limit), "fragment exceeds limit");
                Check(fragments.SelectMany(fragment => fragment).SequenceEqual(payload), "fragment reconstruction");
            }
            results.Add("PASS MTU 23/62/203/247/517; 20/59/200/201/401-byte fragment boundaries");

            var oldGatt = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            var starts = new ConcurrentQueue<string>();
            var fifo = new BLE_tcp_driver.BoundedAsyncFifo<Item>(4, async item => {
                starts.Enqueue(item.Id);
                if (item.Id == "old") {
                    var canceled = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                    using (item.Cancellation.Token.Register(() => canceled.TrySetResult(true))) {
                        Task winner = await Task.WhenAny(oldGatt.Task, canceled.Task);
                        return winner == oldGatt.Task && await oldGatt.Task;
                    }
                }
                return true;
            }, null);
            var oldItem = new Item("old", "client-a", 1);
            Task<bool> oldCompletion;
            Check(fifo.TryEnqueue(oldItem, out oldCompletion), "enqueue old generation");
            WaitFor(() => starts.Contains("old"), "old GATT did not start");
            var newItem = new Item("new", "client-b", 2);
            Task<bool> newCompletion;
            Check(fifo.TryEnqueue(newItem, out newCompletion), "enqueue new generation");
            oldItem.Cancellation.Cancel();
            Check(!oldCompletion.GetAwaiter().GetResult(), "old generation must cancel");
            Check(newCompletion.GetAwaiter().GetResult(), "new generation must recover");
            oldGatt.TrySetResult(true);
            Thread.Sleep(100);
            Check(starts.Count == 2 && starts.Last() == "new", "late old GATT completion re-entered queue");
            results.Add("PASS delayed old GATT cancellation, new-generation recovery, late completion isolation");

            var blocker = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            var entered = new ManualResetEventSlim(false);
            var queueOrder = new ConcurrentQueue<string>();
            var bounded = new BLE_tcp_driver.BoundedAsyncFifo<Item>(2, async item => {
                queueOrder.Enqueue(item.Id);
                entered.Set();
                return await blocker.Task;
            }, null);
            Task<bool> first;
            Task<bool> second;
            Task<bool> overflow;
            Check(bounded.TryEnqueue(new Item("1", "q", 1), out first), "queue first");
            Check(entered.Wait(3000), "queue worker did not start");
            Check(bounded.TryEnqueue(new Item("2", "q", 1), out second), "queue second");
            Check(!bounded.TryEnqueue(new Item("3", "q", 1), out overflow), "queue capacity was exceeded");
            blocker.TrySetResult(true);
            Check(first.GetAwaiter().GetResult() && second.GetAwaiter().GetResult(), "queued work did not drain");
            Check(queueOrder.SequenceEqual(new[] { "1", "2" }), "queue order changed");
            results.Add("PASS bounded queue rejects overflow and drains in FIFO order");

            int fragmentsSent = 0;
            bool partial = BLE_tcp_driver.BridgeMtuPolicy.SendFragmentsAsync(new byte[401], 200,
                (offset, chunk, fragment, count) => {
                    Interlocked.Increment(ref fragmentsSent);
                    return Task.FromResult(fragment != 2);
                }, () => true).GetAwaiter().GetResult();
            Check(!partial && fragmentsSent == 2, "partial failure must stop later fragments");
            results.Add("PASS partial GATT failure stops remaining fragments without retry");

            var clientStarts = new ConcurrentQueue<string>();
            var clientFifo = new BLE_tcp_driver.BoundedAsyncFifo<Item>(4, async item => {
                clientStarts.Enqueue(item.Id);
                if (item.Id == "active") {
                    var canceled = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                    using (item.Cancellation.Token.Register(() => canceled.TrySetResult(true)))
                    {
                        await canceled.Task;
                        return false;
                    }
                }
                return true;
            }, null);
            var active = new Item("active", "departed", 1);
            var queuedA = new Item("queued-a", "departed", 1);
            var queuedB = new Item("queued-b", "departed", 1);
            Task<bool> activeResult;
            Task<bool> queuedAResult;
            Task<bool> queuedBResult;
            Check(clientFifo.TryEnqueue(active, out activeResult), "enqueue active client write");
            WaitFor(() => clientStarts.Contains("active"), "active client write did not start");
            Check(clientFifo.TryEnqueue(queuedA, out queuedAResult), "enqueue client write A");
            Check(clientFifo.TryEnqueue(queuedB, out queuedBResult), "enqueue client write B");
            int canceledCount = clientFifo.CancelWhere(item => item.Client == "departed", item => item.Cancellation.Cancel());
            active.Cancellation.Cancel();
            Check(canceledCount == 2, "departed client's queued writes were not canceled");
            Check(!activeResult.GetAwaiter().GetResult() && !queuedAResult.GetAwaiter().GetResult()
                && !queuedBResult.GetAwaiter().GetResult(), "departed client writes reported success");
            Check(clientStarts.Count == 1, "departed client's queued request reached transport");
            results.Add("PASS client departure cancels active wait and removes its queued writes");

            int sideEffects = 0;
            Action<long, long> capturedNotification = (generation, round) => {
                if (BLE_tcp_driver.BridgeRoundIdentity.Matches(generation, round, 8, 4)) sideEffects++;
            };
            capturedNotification(7, 3);
            capturedNotification(8, 3);
            Check(sideEffects == 0, "stale notification/discovery callback had side effects");
            capturedNotification(8, 4);
            Check(sideEffects == 1, "current notification was not delivered");
            results.Add("PASS stale notification/late-ACK identity rejected by generation and discovery round");
            return String.Join(Environment.NewLine, results);
        }
    }
}
'@

$sourceGuards = @(
    [pscustomobject]@{ Passed = $tcpSource.Contains('using System.Threading;'); Name = 'TcpServer imports Interlocked namespace' },
    [pscustomobject]@{ Passed = $programSource.Contains('firmwareCharacteristicLimit = 200'); Name = 'firmware characteristic limit is 200 bytes' },
    [pscustomobject]@{ Passed = !$programSource.Contains('_pendingServiceCount'); Name = 'shared service-discovery counter removed' },
    [pscustomobject]@{ Passed = $programSource.Contains('CharacteristicAddedEvent(GattCharacteristic gattCharacteristic, long generation, long discoveryId)'); Name = 'characteristic event carries original identity' },
    [pscustomobject]@{ Passed = $programSource.Contains('Action<long, long, bool> AllCharacteristicsDiscovered'); Name = 'completion event carries original identity and query status' },
    [pscustomobject]@{ Passed = $programSource.Contains('operation.Cancel()') -and $programSource.Contains('cancellationToken.Register'); Name = 'in-flight GATT cancellation is wired' },
    [pscustomobject]@{ Passed = $programSource.Contains('ReceiveNotifyData?.Invoke(sender, data, generation, discoveryId)'); Name = 'notifications carry captured identity' },
    [pscustomobject]@{ Passed = $formSource.Contains('TryDisposeIncompleteDiscovery(generation, discoveryId)'); Name = 'UI disposal is atomically round-guarded' },
    [pscustomobject]@{ Passed = $formSource.Contains('TryAcceptDiscoveredCharacteristic(gattCharacteristic, generation, discoveryId)'); Name = 'UI characteristic mutation is round-guarded' }
)
foreach ($guard in $sourceGuards) {
    if (-not $guard.Passed) { throw "FAIL source guard: $($guard.Name)" }
}

$combinedSource = @"
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
namespace BLE_tcp_driver {
$fifoSource
$mtuSource
$roundSource
}
$runnerSource
"@
Add-Type -TypeDefinition $combinedSource -Language CSharp -ErrorAction Stop
$results = [Bridge01OfflineTests.Runner]::Run()
Write-Output $results
Write-Output ("PASS {0} production source guards" -f $sourceGuards.Count)
