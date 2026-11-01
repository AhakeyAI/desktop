using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Drawing;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;

namespace BLE_tcp_driver {
    // UI owns only user intent. No BleCore, TCP listener, or firmware writer exists here.
    internal sealed class ManagedBridgeWindow : Form {
        private readonly ListBox devices = new ListBox { Dock=DockStyle.Fill };
        private readonly Label status = new Label { Dock=DockStyle.Bottom,Height=65,Text="正在连接 AhaKey Studio…",AutoEllipsis=true };
        private readonly NotifyIcon tray;
        private readonly Action<string,Dictionary<string,object>> intent;
        private bool exiting;
        private string selectionAuthority="";
        private Button connect;
        private sealed class Choice {
            public string Id,Name,Address;
            public override string ToString() { return Name+"  ["+Address+"]"; }
        }
        public ManagedBridgeWindow(Action<string,Dictionary<string,object>> intent) {
            this.intent=intent;Text="AhaKey 蓝牙桥";Size=new Size(550,350);MinimumSize=new Size(420,260);
            var actions=new FlowLayoutPanel { Dock=DockStyle.Top,Height=40 };
            var refresh=new Button { Text="刷新设备",AutoSize=true };
            connect=new Button { Text="连接所选键盘",AutoSize=true,Enabled=false };
            var disconnect=new Button { Text="断开配置连接",AutoSize=true };
            refresh.Click+=(s,e)=>intent("refreshRequested",new Dictionary<string,object>());
            connect.Click+=(s,e)=>{
                var item=devices.SelectedItem as Choice;if(item==null){status.Text="请先选择键盘。";return;}
                status.Text="已请求连接 "+item.Name+"…";
                intent("selectionRequested",new Dictionary<string,object>{{"selectedTargetId",item.Id},{"address",item.Address},{"selectionAuthority",selectionAuthority}});
            };
            disconnect.Click+=(s,e)=>intent("disconnectRequested",new Dictionary<string,object>());
            actions.Controls.AddRange(new Control[]{refresh,connect,disconnect});Controls.Add(devices);Controls.Add(status);Controls.Add(actions);
            tray=new NotifyIcon { Icon=SystemIcons.Application,Text="AhaKey 蓝牙桥",Visible=true };
            var menu=new ContextMenuStrip();menu.Items.Add("显示蓝牙桥",null,(s,e)=>Reveal());
            menu.Items.Add("隐藏窗口",null,(s,e)=>Hide());tray.ContextMenuStrip=menu;tray.DoubleClick+=(s,e)=>Reveal();
            FormClosing+=(s,e)=>{if(!exiting && e.CloseReason==CloseReason.UserClosing){e.Cancel=true;Hide();}};
            FormClosed+=(s,e)=>{tray.Visible=false;tray.Dispose();};
        }
        public void Reveal() { Show();WindowState=FormWindowState.Normal;Activate(); }
        public void SetStatus(string text) { status.Text=text; }
        public void SetAuthority(string value) { selectionAuthority=value;connect.Enabled=value.Length>0; }
        public void SetChoices(List<Dictionary<string,object>> choices) {
            string selected=(devices.SelectedItem as Choice)?.Id;
            devices.BeginUpdate();devices.Items.Clear();
            foreach(var row in choices){var item=new Choice {Id=(string)row["targetId"],Name=(string)row["name"],Address=(string)row["address"]};devices.Items.Add(item);if(item.Id==selected)devices.SelectedItem=item;}
            devices.EndUpdate();
        }
        public void ExitOwner() { exiting=true;Close(); }
    }
    internal sealed class SelectionSnapshot<T> {
        private Dictionary<string,T> candidates=new Dictionary<string,T>();
        public string Id { get; private set; } = "";
        public string Publish(Dictionary<string,T> found,bool observationOnly,bool sessionActive) {
            if(!observationOnly && !sessionActive){candidates=new Dictionary<string,T>(found);Id=Guid.NewGuid().ToString("N");}
            return Id;
        }
        public bool Contains(string id,string target){return id==Id && candidates.ContainsKey(target);}
    }
    // Studio-only control plane. The legacy Form/TCP listener never starts in this mode.
    internal sealed class ManagedBridge {
        private readonly BleCore core = new BleCore();
        private readonly object gate = new object(), outputGate = new object();
        private readonly string instance = Guid.NewGuid().ToString("N");
        private readonly string token = Environment.GetEnvironmentVariable("AHAKEY_BRIDGE_TOKEN");
        private readonly HashSet<string> requestIds = new HashSet<string>();
        private readonly SelectionSnapshot<DeviceInformation> selection=new SelectionSnapshot<DeviceInformation>();
        private readonly BoundedAsyncFifo<Write> writes;
        private string session = "", target = "", clientGeneration = "";
        private long epoch, eventSequence;
        private TcpClient owner;
        private CancellationTokenSource cancellation = new CancellationTokenSource();
        private bool authenticated;
        private int outstanding;
        private ManagedBridgeWindow window;
        private long uiSequence;
        private void Ui(Action action) {
            var current=window;if(current==null||current.IsDisposed)return;
            try { current.BeginInvoke(action); } catch(InvalidOperationException) { }
        }
        private sealed class Write {
            public string Session;
            public long Generation;
            public GattCharacteristic Characteristic;
            public byte[] Bytes;
            public CancellationToken Token;
        }
        public ManagedBridge() {
            writes = new BoundedAsyncFifo<Write>(24, SendWrite, (w,e) => {});
            core.ReceiveNotifyData += (sender, data, generation, discovery) => {
                lock (gate) {
                    if (session.Length == 0 || !core.IsCurrentConnection(generation)) return;
                    Event("notify", Map("bytes", Convert.ToBase64String(data)));
                }
            };
            core.DeviceDisconnected += device => {
                long captured=Interlocked.Read(ref epoch);
                // BleCore invokes this while holding its discovery lock. Never acquire gate on that stack.
                _ = Task.Run(() => { lock(gate) {if(captured!=epoch || !ReferenceEquals(device,core.CurrentDevice))return;Event("sessionDisconnected",Map());Revoke();} });
            };
        }
        public static void Run(string[] args) {
            int index = Array.IndexOf(args, "--port"); int port;
            if (index < 0 || index + 1 >= args.Length || !int.TryParse(args[index + 1], out port) || port < 1 || port > 65535) return;
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            var bridge=new ManagedBridge();
            bridge.window=new ManagedBridgeWindow((name,fields)=>{lock(bridge.gate){if(bridge.authenticated)bridge.Event(name,fields);}});
            bool started=false;
            bridge.window.Shown+=(s,e)=>{if(started)return;started=true;Task.Run(async()=>{try{await bridge.RunAsync(port);}finally{bridge.Ui(()=>bridge.window.ExitOwner());}});};
            Application.Run(bridge.window);
        }
        private async Task RunAsync(int port) {
            if (string.IsNullOrEmpty(token)) return;
            var listener = new TcpListener(IPAddress.Loopback, port);
            try {
                listener.Start(1);
                var accept = listener.AcceptTcpClientAsync();
                if (await Task.WhenAny(accept, Task.Delay(5000)) != accept) return;
                owner = await accept; listener.Stop(); owner.NoDelay = true; owner.SendTimeout = 2000;
                var stream = owner.GetStream();
                while (true) {
                    byte[] header = authenticated ? await Read(stream,3) : await Deadline(Read(stream,3),2000);
                    int length = header[1] | header[2] << 8;
                    if (header[0] != 0x10 || length < 2 || length > 16384) throw new IOException("BAD_FRAME");
                    var data = new JavaScriptSerializer().DeserializeObject(Encoding.UTF8.GetString(await Deadline(Read(stream, length),2000))) as Dictionary<string, object>;
                    if (data == null || Int(data, "version") != 1) throw new IOException("BAD_VERSION");
                    string id = Text(data, "requestId"), op = Text(data, "op");
                    if (!requestIds.Add(id) || requestIds.Count > 100000) { Reply(id, false, "DUPLICATE_REQUEST"); continue; }
                    if (!authenticated) {
                        if (op != "hello" || Text(data, "ownerToken") != token) throw new IOException("OWNER_MISMATCH");
                        authenticated = true;
                        Reply(id, true, "OK", Map("capabilities", new[]{"enumerate-connected","select-target","release-session","session-writes","visible-window"}));
                        continue;
                    }
                    if (Text(data,"bridgeInstanceId") != instance) { Reply(id, false, "INSTANCE_CHANGED"); continue; }
                    // Cancellation is handled here, never queued behind a GATT write.
                    if (op == "disconnect" || op == "cancelRequest" || op == "shutdown") {
                        lock (gate) {
                            if (op == "disconnect" && session.Length != 0 && Text(data,"sessionId") != session) { Reply(id,false,"SESSION_CHANGED"); continue; }
                            Revoke();
                        }
                        Reply(id,true,"REVOKED",Map("revoked",true));
                        if (op == "shutdown") return;
                        continue;
                    }
                    if (Interlocked.Increment(ref outstanding) > 24) { Interlocked.Decrement(ref outstanding); Reply(id,false,"BUSY"); continue; }
                    _ = Task.Run(async () => {
                        try { await Handle(id, op, data); }
                        catch (Exception e) { Reply(id,false,e is TimeoutException ? "TIMEOUT" : e.Message); }
                        finally { Interlocked.Decrement(ref outstanding); }
                    });
                }
            } catch (Exception) { }
            finally { listener.Stop(); lock(gate) Revoke(); owner?.Close(); }
        }
        private async Task Handle(string id, string op, Dictionary<string,object> data) {
            if(op=="showWindow") {Ui(()=>window.Reveal());Reply(id,true,"OK");return;}
            if(op=="studioStatus") {
                string message=Text(data,"message"),authority=Text(data,"selectionAuthority");long sequence=Convert.ToInt64(data["sequence"]);
                lock(gate){if(sequence>uiSequence){uiSequence=sequence;Ui(()=>{if(sequence==Interlocked.Read(ref uiSequence)){window.SetStatus(message);window.SetAuthority(authority);}});}}
                Reply(id,true,"OK");return;
            }
            if (op == "enumerateConnected") {
                bool observationOnly=data.ContainsKey("observationOnly") && data["observationOnly"] is bool && (bool)data["observationOnly"];
                long captured; lock(gate) { captured=epoch; }
                var found = await Deadline(DeviceInformation.FindAllAsync(BluetoothLEDevice.GetDeviceSelectorFromConnectionStatus(BluetoothConnectionStatus.Connected),
                    new[]{"System.Devices.Aep.DeviceAddress","System.Devices.Aep.IsConnected"}).AsTask(), 4500);
                var list = new List<Dictionary<string,object>>();
                var discovered=new Dictionary<string,DeviceInformation>();
                lock (gate) {
                    if (captured!=epoch) throw new IOException("CANCELLED");
                    foreach (var d in found) {
                        object connected;
                        if (!d.Name.StartsWith("AhaKey",StringComparison.OrdinalIgnoreCase)
                            || !d.Properties.TryGetValue("System.Devices.Aep.IsConnected",out connected) || !(connected is bool) || !(bool)connected) continue;
                        discovered[d.Id]=d;
                        object address;d.Properties.TryGetValue("System.Devices.Aep.DeviceAddress",out address);
                        list.Add(Map("targetId",d.Id,"name",d.Name,"address",address as string??"","observedConnected",true,"serviceEvidence","connect-verifies-services"));
                    }
                    Reply(id,true,"OK",Map("snapshotId",selection.Publish(discovered,observationOnly,session.Length!=0),"candidates",list));
                    if(!observationOnly)Ui(()=>window.SetChoices(list));
                }
                return;
            }
            if (op == "connect") {
                string wanted=Text(data,"targetId"), generation=Text(data,"clientGeneration"); long captured;
                lock(gate) {
                    if(session.Length!=0 || !selection.Contains(Text(data,"snapshotId"),wanted)) throw new IOException("TARGET_CHANGED");
                    captured=Interlocked.Increment(ref epoch); session="connecting"; target=wanted; clientGeneration=generation;
                }
                BluetoothLEDevice device=null;
                try {
                    var opening=BluetoothLEDevice.FromIdAsync(wanted).AsTask();
                    try { device=await Deadline(opening,4000); }
                    catch { _ = opening.ContinueWith(t=>{if(t.Status==TaskStatus.RanToCompletion)t.Result?.Dispose();}); throw; }
                    if(device==null || device.ConnectionStatus!=BluetoothConnectionStatus.Connected || !device.Name.StartsWith("AhaKey",StringComparison.OrdinalIgnoreCase)) throw new IOException("TARGET_NOT_CONNECTED");
                    var ready=new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                    Action<long,long,bool> callback=(g,d,ok)=>{
                        if(ok) core.TryConfirmReady(g,d,(dev,ch)=>ready.TrySetResult(true));
                        else ready.TrySetResult(false);
                    };
                    core.AllCharacteristicsDiscovered+=callback;
                    try {
                        lock(gate) { if(captured!=epoch)throw new IOException("CANCELLED"); core.ConnectManagedDevice(device); device=null; }
                        if(!await Deadline(ready.Task,14000)) throw new IOException("SERVICE_UNAVAILABLE");
                        lock(gate) {
                            if(captured!=epoch || !core.GetBleStatusInfo().IsTargetDevice) throw new IOException("SESSION_CHANGED");
                            session=Guid.NewGuid().ToString("N");
                            Reply(id,true,"READY",Map("sessionId",session,"targetId",target,"clientGeneration",generation));
                        }
                    } finally { core.AllCharacteristicsDiscovered-=callback; }
                } catch { lock(gate) {if(captured==epoch)Revoke();} throw; }
                finally { device?.Dispose(); }
                return;
            }
            if(op=="write") {
                Write write;
                lock(gate) {
                    if(session.Length==0 || session=="connecting" || Text(data,"sessionId")!=session || Text(data,"targetId")!=target || Text(data,"clientGeneration")!=clientGeneration) throw new IOException("SESSION_CHANGED");
                    byte[] bytes=Convert.FromBase64String(Text(data,"bytes"));
                    string channel=Text(data,"channel");
                    if(bytes.Length==0 || bytes.Length>4096 || (channel!="command" && channel!="data")) throw new IOException("BAD_WRITE");
                    write=new Write{Session=session,Generation=core.ConnectionGeneration,Bytes=bytes,
                        Characteristic=channel=="command"?core.CurrentWriteCharacteristic:core.CurrentDataCharacteristic,Token=cancellation.Token};
                }
                Task<bool> completion;
                if(!writes.TryEnqueue(write,out completion))throw new IOException("BUSY");
                if(!await Deadline(completion,10000))throw new IOException("WRITE_UNCONFIRMED");
                Reply(id,true,"TRANSPORT_WRITTEN",Map("transportWritten",true)); return;
            }
            throw new IOException("UNKNOWN_OPERATION");
        }
        private async Task<bool> SendWrite(Write w) {
            using(var timeout=CancellationTokenSource.CreateLinkedTokenSource(w.Token)) {
                timeout.CancelAfter(5000);
                int pdu; string source; int size=core.GetMaxGattWritePayload(w.Generation,out pdu,out source);
                return await BridgeMtuPolicy.SendFragmentsAsync(w.Bytes,size,async(offset,bytes,index,count)=>{
                    if(!Current(w)||timeout.IsCancellationRequested)return false;
                    var result=await core.WriteDataToCharacteristicAsync(w.Characteristic,bytes,w.Generation,timeout.Token);
                    return result.Success && Current(w) && !timeout.IsCancellationRequested;
                },()=>Current(w)&&!timeout.IsCancellationRequested);
            }
        }
        private bool Current(Write w) { lock(gate)return session==w.Session && !w.Token.IsCancellationRequested && core.IsCurrentConnection(w.Generation); }
        private void Revoke() {
            Interlocked.Increment(ref epoch); session=""; target=""; clientGeneration="";
            cancellation.Cancel(); cancellation=new CancellationTokenSource();
            writes.CancelWhere(w=>true); core.Dispose();
        }
        private void Event(string name,Dictionary<string,object> values) {
            values["event"]=name;values["eventSeq"]=++eventSequence;values["sessionId"]=session;
            values["targetId"]=target;values["clientGeneration"]=clientGeneration; Send(0x91,values);
        }
        private void Reply(string id,bool ok,string code,Dictionary<string,object> values=null) {
            values=values??Map();values["requestId"]=id;values["ok"]=ok;values["code"]=code;Send(0x90,values);
        }
        private void Send(byte type,Dictionary<string,object> values) {
            try { lock(outputGate) {
                values["version"]=1;values["bridgeInstanceId"]=instance;
                byte[] body=Encoding.UTF8.GetBytes(new JavaScriptSerializer().Serialize(values));
                if(body.Length>16384)throw new IOException("FRAME_TOO_LARGE");
                var stream=owner.GetStream();byte[] packet=new byte[body.Length+3];packet[0]=type;packet[1]=(byte)body.Length;packet[2]=(byte)(body.Length>>8);Buffer.BlockCopy(body,0,packet,3,body.Length);stream.Write(packet,0,packet.Length);
            }} catch { owner?.Close(); }
        }
        private static async Task<byte[]> Read(NetworkStream stream,int count) {byte[] bytes=new byte[count];int at=0;while(at<count){int read=await stream.ReadAsync(bytes,at,count-at);if(read==0)throw new EndOfStreamException();at+=read;}return bytes;}
        private static async Task<T> Deadline<T>(Task<T> task,int ms) {if(await Task.WhenAny(task,Task.Delay(ms))!=task)throw new TimeoutException();return await task;}
        private static string Text(Dictionary<string,object> value,string key) {object item;if(!value.TryGetValue(key,out item)||!(item is string)||((string)item).Length>12000)throw new IOException("BAD_FIELD_"+key);return (string)item;}
        private static int Int(Dictionary<string,object> value,string key) {object item;return value.TryGetValue(key,out item)&&item is int?(int)item:-1;}
        private static Dictionary<string,object> Map(params object[] pairs) {var value=new Dictionary<string,object>();for(int i=0;i<pairs.Length;i+=2)value[(string)pairs[i]]=pairs[i+1];return value;}
    }
}
