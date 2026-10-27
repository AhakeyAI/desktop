param([Parameter(Mandatory=$true)][string]$Request,[ValidateSet('Launch','Supervise')][string]$Mode='Launch')
$ErrorActionPreference='Stop'
$env:PSModulePath = Join-Path $PSHOME 'Modules'
# AHAKEY_READ_ONLY_DEVICE_QUERY_BEGIN
$deviceQueryScript = @'
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
[assembly:DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
public static class AhaKeyReadOnlyDevices {
    const uint Present = 0x100, BufferSmall = 0x1a, NoSuchValue = 0x25;
    const string DeviceKey = "a45c254e-df1c-4efd-8020-67d146a850e0";
    const string ContainerKey = "8c7ed206-3f8a-4827-b3ab-ae9e1faefc6c";
    const string BootPrefix = "USB\\VID_4348&PID_55E0\\";
    const string NormalPrefix = "USB\\VID_413C&PID_2107\\";
    [StructLayout(LayoutKind.Sequential)] struct Key {
        public Guid fmtid; public uint pid;
        public Key(string guid,uint id) {fmtid=new Guid(guid);pid=id;}
    }
    [DllImport("cfgmgr32.dll",CharSet=CharSet.Unicode,ExactSpelling=true)] static extern uint CM_Get_Device_ID_List_SizeW(out uint size,string filter,uint flags);
    [DllImport("cfgmgr32.dll",CharSet=CharSet.Unicode,ExactSpelling=true)] static extern uint CM_Get_Device_ID_ListW(string filter,[Out] char[] buffer,uint size,uint flags);
    [DllImport("cfgmgr32.dll",CharSet=CharSet.Unicode,ExactSpelling=true)] static extern uint CM_Locate_DevNodeW(out uint node,string id,uint flags);
    [DllImport("cfgmgr32.dll",CharSet=CharSet.Unicode,ExactSpelling=true)] static extern uint CM_Get_DevNode_PropertyW(uint node,ref Key key,out uint type,[Out] byte[] bytes,ref uint size,uint flags);
    static void Require(bool value,string message) {if(!value)throw new InvalidOperationException(message);}
    static bool Starts(string value,string prefix) {return value.StartsWith(prefix,StringComparison.OrdinalIgnoreCase);}
    static string[] PresentIds() {
        for(int attempt=0;attempt<3;attempt++) {
            uint size;uint rc=CM_Get_Device_ID_List_SizeW(out size,null,Present);
            Require(rc==0 && size>0 && size<=1000000,"Cannot size present device list: "+rc);
            char[] buffer=new char[size];rc=CM_Get_Device_ID_ListW(null,buffer,size,Present);
            if(rc==BufferSmall)continue;
            Require(rc==0 && buffer[buffer.Length-1]=='\0',"Cannot read present device list: "+rc);
            return new string(buffer).Split(new[]{'\0'},StringSplitOptions.RemoveEmptyEntries);
        }
        throw new InvalidOperationException("Present device list kept changing");
    }
    static uint Node(string id) {
        uint node;uint rc=CM_Locate_DevNodeW(out node,id,0);
        Require(rc==0,"Present device disappeared: "+rc);return node;
    }
    static byte[] Property(uint node,string guid,uint id,uint expectedType) {
        Key key=new Key(guid,id);uint type,size=0;
        uint rc=CM_Get_DevNode_PropertyW(node,ref key,out type,null,ref size,0);
        if(rc==NoSuchValue)return null;
        Require(rc==BufferSmall && size>0 && size<=65536,"Cannot size device property: "+rc);
        byte[] bytes=new byte[size];uint allocated=size;
        rc=CM_Get_DevNode_PropertyW(node,ref key,out type,bytes,ref size,0);
        Require(rc==0 && type==expectedType && size<=allocated,"Invalid device property result/type: "+rc+"/"+type);
        if(size!=allocated)Array.Resize(ref bytes,(int)size);
        return bytes;
    }
    static string DecodeString(byte[] bytes,bool list) {
        if(bytes==null)return "";
        Require(bytes.Length>=(list?4:2) && bytes.Length%2==0,"Invalid device string length");
        string value=new UnicodeEncoding(false,false,true).GetString(bytes);
        Require(value.EndsWith(list?"\0\0":"\0",StringComparison.Ordinal),"Unterminated device string");
        if(!list)Require(value.IndexOf('\0')==value.Length-1,"Embedded device string terminator");
        return value.TrimEnd('\0');
    }
    static string Text(uint node,string guid,uint id) {return DecodeString(Property(node,guid,id,18),false);}
    static string Port(uint node) {
        string locations=DecodeString(Property(node,DeviceKey,37,8210),true);
        foreach(string location in locations.Split('\0'))
            if(Starts(location,"PCIROOT") && location.IndexOf("USB",StringComparison.OrdinalIgnoreCase)>=0)return location;
        return "";
    }
    static string Container(uint node) {
        byte[] bytes=Property(node,ContainerKey,2,13);
        if(bytes==null)return "";
        Require(bytes.Length==16,"Invalid container GUID length");return new Guid(bytes).ToString();
    }
    static int Problem(uint node) {
        byte[] bytes=Property(node,"4340a6c5-93fa-4706-972c-7b648008a5a7",3,7);
        if(bytes==null)return -1;
        Require(bytes.Length==4,"Invalid problem code length");uint value=BitConverter.ToUInt32(bytes,0);
        Require(value<=Int32.MaxValue,"Invalid problem code");return (int)value;
    }
    public sealed class BootItem {public string instanceId,port,service,inf;public int problem;}
    public sealed class MaintenanceItem {public string instanceId,container,port;public bool download;public string[] interfaces;}
    public static BootItem[] Boot() {
        var items=new List<BootItem>();
        foreach(string id in PresentIds()) {
            if(!Starts(id,BootPrefix))continue;
            uint node=Node(id);
            var item=new BootItem {instanceId=id,port=Port(node),service=Text(node,DeviceKey,6),inf=Text(node,"a8b865dd-2e3d-4094-ad97-e593a70c75d6",5),problem=Problem(node)};
            Node(id);items.Add(item);
        }
        return items.ToArray();
    }
    public static MaintenanceItem[] Maintenance() {
        string[] ids=PresentIds();var hid=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        foreach(string id in ids)if(Starts(id,"HID\\VID_413C&PID_2107&MI_01"))hid.Add(id,Container(Node(id)));
        var items=new List<MaintenanceItem>();
        foreach(string id in ids) {
            if(!Starts(id,BootPrefix) && !Starts(id,NormalPrefix))continue;
            uint node=Node(id);string container=Container(node);string port=Port(node);
            Require(!String.IsNullOrWhiteSpace(container) && !String.IsNullOrWhiteSpace(port),"Missing USB container/port");
            var interfaces=new List<string>();
            foreach(var pair in hid)if(String.Equals(container,pair.Value,StringComparison.OrdinalIgnoreCase)){Node(pair.Key);interfaces.Add(pair.Key);}
            Node(id);items.Add(new MaintenanceItem {instanceId=id,container=container,port=port,download=Starts(id,BootPrefix),interfaces=interfaces.ToArray()});
        }
        return items.ToArray();
    }
}
"@
'@
# AHAKEY_READ_ONLY_DEVICE_QUERY_END
$q=Get-Content -LiteralPath $Request -Raw -Encoding UTF8 | ConvertFrom-Json
$directory=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Request))
function Save-Result($value) {
    $value.operationId=$q.operationId
    $file=Join-Path $directory 'result.json'
    if(Test-Path -LiteralPath $file){return}
    [IO.File]::WriteAllText(($file+'.tmp'),($value|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move(($file+'.tmp'),$file)
}
if($Mode -eq 'Launch') {
    $supervisor=$null
    try {
        if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -gt $q.launchDeadline){throw 'Expired elevation request'}
        $shell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        if($PSCommandPath.Contains('"') -or $Request.Contains('"')){throw 'Invalid path'}
        $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Mode Supervise -Request "'+$Request+'"'
        # Only this narrowly scoped supervisor is elevated. The Studio process remains unchanged.
        $supervisor=Start-Process -FilePath $shell -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -PassThru
        if(-not $supervisor.WaitForExit(160000)) { [IO.File]::WriteAllText((Join-Path $directory 'cancel.request'),'timeout');[void]$supervisor.WaitForExit(7000) }
    } catch { Save-Result @{started=($null -ne $supervisor);ended=($null -eq $supervisor);failed=$true;exitCode=-1;detail=$_.Exception.Message} }
    exit
}
$result=@{started=$false;ended=$true;failed=$true;exitCode=-1}
try {
    if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -gt $q.launchDeadline -or (Test-Path (Join-Path $directory 'cancel.request'))){throw 'Expired or cancelled elevation request'}
    if($q.operation -cnotin @('download','verify') -or [IO.Path]::GetFullPath($q.directory) -cne $directory){throw 'Invalid operation directory'}
    $work=Join-Path $directory 'runtime';$tool=Join-Path $work 'WCHISPTool_CH57x-59x.exe';$hex=Join-Path $directory 'firmware.hex';$ini=Join-Path $directory 'operation.ini'
    if([IO.Path]::GetFullPath($q.work) -ine $work -or [IO.Path]::GetFullPath($q.tool) -ine $tool -or [IO.Path]::GetFullPath($q.hex) -ine $hex -or [IO.Path]::GetFullPath($q.ini) -ine $ini){throw 'Untrusted operation path'}
    # Compiled distribution pins, never taken from the low integrity request.
    $pins=ConvertFrom-Json '{"WCHISPTool_CH57x-59x.exe":"7b5d84bfcc8786aabf74ba264de29c1e2eda7907fb8385426fda3270cd793f95","WCH55xISPDLL.dll":"c56f1f2250c9e3862e3ef86887d7e81302bb008a722a3b18555f5cd0acd875ff","CH343PT.DLL":"4b7f30dfbc886e1359c7adc4d9fdcc3cb6543c373fc214e8641e314df41fe65a","CH375DLL.DLL":"0f019b958d4d3f6b8ec0d282ef848a57f0f92a0596d7405b6c58f5aa383a326c","ChipType/chiplist_CH57x_CH59x.wcfg":"2e2369ed14f3c351c4404bdbfa45890e3b7562c7a201111e90f7004c4dc882a0","CONFIG_CH57X59X.WCH":"f21f73360c7f650ab36cc4a0bbe2b88316c85bc1caf2e010139a47486abf5a8a"}'
    foreach($p in $pins.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $work $p.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $p.Value){throw 'Bundled runtime changed'}}
    if((Get-FileHash -LiteralPath $hex -Algorithm SHA256).Hash.ToLowerInvariant() -cne $q.hexHash -or (Get-FileHash -LiteralPath $ini -Algorithm SHA256).Hash.ToLowerInvariant() -cne $q.iniHash){throw 'Frozen operation changed'}
    # INI command fields are rebuilt from constants; a request hash never authorizes arbitrary WCH operations.
    $expected=@"
[Public]
MCUName=CH582
bMCULine=6
bMCUType=130
DataFlashFile=.
swzUserFile1=$hex
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
IsClearDataFlash=1
IsEraseAllCFlash=1
IsAfterDownRest=0
bVerifyType=0
"@
    if(([IO.File]::ReadAllText($ini).Replace("`r`n","`n").TrimEnd()) -cne $expected.TrimEnd()){throw 'Unexpected operation configuration'}
    $held=[Collections.Generic.List[IO.FileStream]]::new()
    foreach($file in @($hex,$ini,(Join-Path $directory 'operation.id')) + @($pins.PSObject.Properties | Where-Object {$_.Name -cne 'CONFIG_CH57X59X.WCH'} | ForEach-Object { Join-Path $work $_.Name })) {$held.Add([IO.File]::Open($file,'Open','Read','Read'))}
    # The vendor configuration is writable only in this operation copy; it is reset from the pinned clean source for every phase.
    foreach($p in $pins.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $work $p.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $p.Value){throw 'Bundled runtime changed'}}
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class WchOwnedSupervisor {
 public static Func<bool> TargetValid;
 public static bool Started,Ended,Failed; public static string Detail="";
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Startup {public int cb; public string reserved,desktop,title;public int x,y,xSize,ySize,xChars,yChars,fill,flags;public short show,reserved2;public IntPtr reservedPtr,input,output,error;}
 [StructLayout(LayoutKind.Sequential)] struct ProcessInfo {public IntPtr process,thread;public uint pid,tid;}
 [StructLayout(LayoutKind.Sequential)] struct Security {public int length;public IntPtr descriptor;[MarshalAs(UnmanagedType.Bool)]public bool inherit;}
 [StructLayout(LayoutKind.Sequential)] struct Coord {public short x,y;}
 [StructLayout(LayoutKind.Sequential)] struct Rect {public short l,t,r,b;}
 [StructLayout(LayoutKind.Sequential)] struct ConsoleInfo {public Coord size,cursor;public short attributes;public Rect window;public Coord max;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr CreateJobObject(IntPtr a,string n);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool SetInformationJobObject(IntPtr j,int c,IntPtr p,uint n);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool QueryInformationJobObject(IntPtr j,int c,IntPtr p,uint n,IntPtr r);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool AssignProcessToJobObject(IntPtr j,IntPtr p);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool TerminateJobObject(IntPtr j,uint code);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool TerminateProcess(IntPtr p,uint code);
 [DllImport("kernel32.dll",SetLastError=true)]static extern uint ResumeThread(IntPtr t);
 [DllImport("kernel32.dll",SetLastError=true)]static extern uint WaitForSingleObject(IntPtr p,uint timeout);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetExitCodeProcess(IntPtr p,out uint code);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool CloseHandle(IntPtr p);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool CreateProcess(string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string work,ref Startup si,out ProcessInfo pi);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr CreateFile(string path,uint access,uint share,ref Security security,uint disposition,uint flags,IntPtr template);
 [DllImport("kernel32.dll")]static extern bool FreeConsole();
 [DllImport("kernel32.dll")]static extern bool AllocConsole();
 [DllImport("kernel32.dll")]static extern IntPtr GetConsoleWindow();
 [DllImport("user32.dll")]static extern bool ShowWindow(IntPtr p,int cmd);
 [DllImport("kernel32.dll")]static extern bool GetConsoleScreenBufferInfo(IntPtr p,out ConsoleInfo info);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern bool ReadConsoleOutputCharacter(IntPtr p,StringBuilder b,uint n,Coord xy,out uint count);
 static Exception Error(string action){return new Exception(action+" Win32="+Marshal.GetLastWin32Error());}
 static bool Parent(long pid,long start){try{using(var p=Process.GetProcessById((int)pid))return !p.HasExited && Math.Abs(new DateTimeOffset(p.StartTime.ToUniversalTime()).ToUnixTimeMilliseconds()-start)<=2;}catch{return false;}}
 static int Active(IntPtr job){IntPtr p=Marshal.AllocHGlobal(48);try{if(!QueryInformationJobObject(job,1,p,48,IntPtr.Zero))throw Error("Query job");return Marshal.ReadInt32(p,40);}finally{Marshal.FreeHGlobal(p);}}
 static bool Clean(IntPtr job){if(Active(job)==0)return true;if(!TerminateJobObject(job,1))return false;var watch=Stopwatch.StartNew();while(watch.ElapsedMilliseconds<5000){if(Active(job)==0)return true;System.Threading.Thread.Sleep(25);}return Active(job)==0;}
 public static string Quote(string s){if(s.Contains("\"")||s.Contains("\n")||s.Contains("\r")||s.EndsWith("\\"))throw new Exception("Invalid argument");return "\""+s+"\"";}
 static void Capture(IntPtr console,string dir){ConsoleInfo info;if(GetConsoleScreenBufferInfo(console,out info)){int count=Math.Min(1000000,info.size.x*(info.cursor.y+1));if(count>0){var b=new StringBuilder(count);uint read;if(ReadConsoleOutputCharacter(console,b,(uint)count,new Coord(),out read))File.WriteAllText(Path.Combine(dir,"console.txt"),b.ToString(),new UTF8Encoding(false));}}}
 static void CheckLaunch(string dir,long pid,long start,long deadline,string id) { if(TargetValid!=null && !TargetValid())throw new Exception("Boot target changed or driver not ready");Guid parsed;if(!Guid.TryParse(id,out parsed)||DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()>deadline||!Parent(pid,start)||File.Exists(Path.Combine(dir,"cancel.request"))||File.ReadAllText(Path.Combine(dir,"operation.id"))!=id)throw new Exception("Expired, cancelled, or replaced operation"); }
 public static int Run(string tool,string arguments,string work,string dir,long parentPid,long parentStart,int timeoutMs,long launchDeadline,string operationId) {
  Started=false;Ended=false;Failed=false;Detail="";
  if(IntPtr.Size!=8)throw new Exception("x64 supervisor required");
  CheckLaunch(dir,parentPid,parentStart,launchDeadline,operationId);
  IntPtr job=CreateJobObject(IntPtr.Zero,null),output=IntPtr.Zero,error=IntPtr.Zero,input=IntPtr.Zero,console=IntPtr.Zero;ProcessInfo pi=new ProcessInfo();bool assigned=false;
  if(job==IntPtr.Zero)throw Error("Create job");
  try {
   IntPtr limits=Marshal.AllocHGlobal(144);try{for(int i=0;i<144;i++)Marshal.WriteByte(limits,i,0);Marshal.WriteInt32(limits,16,0x2000);if(!SetInformationJobObject(job,9,limits,144))throw Error("Set job limits");}finally{Marshal.FreeHGlobal(limits);}
   FreeConsole();if(!AllocConsole())throw Error("Allocate private console");ShowWindow(GetConsoleWindow(),0);
   var security=new Security();security.length=Marshal.SizeOf(security);security.inherit=true;
   output=CreateFile(Path.Combine(dir,"stdout.txt"),0x40000000,1,ref security,2,128,IntPtr.Zero);error=CreateFile(Path.Combine(dir,"stderr.txt"),0x40000000,1,ref security,2,128,IntPtr.Zero);input=CreateFile("NUL",0x80000000,3,ref security,3,128,IntPtr.Zero);
   security.inherit=false;console=CreateFile("CONOUT$",0x80000000,3,ref security,3,0,IntPtr.Zero);
   foreach(IntPtr h in new[]{output,error,input,console})if(h==new IntPtr(-1))throw Error("Open owned stream");
   var si=new Startup();si.cb=Marshal.SizeOf(si);si.flags=0x101;si.show=0;si.input=input;si.output=output;si.error=error;
   CheckLaunch(dir,parentPid,parentStart,launchDeadline,operationId);
   if(!CreateProcess(tool,new StringBuilder(Quote(tool)+" "+arguments),IntPtr.Zero,IntPtr.Zero,true,4,IntPtr.Zero,work,ref si,out pi))throw Error("Create suspended tool");
   if(!AssignProcessToJobObject(job,pi.process))throw Error("Assign suspended tool");assigned=true;
   CheckLaunch(dir,parentPid,parentStart,launchDeadline,operationId);
   if(ResumeThread(pi.thread)==0xffffffff)throw Error("Resume owned tool");Started=true;
   using(var p=Process.GetProcessById((int)pi.pid))File.WriteAllText(Path.Combine(dir,"owned-process.txt"),pi.pid+"\n"+p.StartTime.ToUniversalTime().ToString("o")+"\nassigned-before-resume",new UTF8Encoding(false));
   var clock=Stopwatch.StartNew();long lastTargetCheck=0;
   while(true){
    if(clock.ElapsedMilliseconds>=timeoutMs || File.Exists(Path.Combine(dir,"cancel.request")) || !Parent(parentPid,parentStart)){Failed=true;Detail="Owned operation timed out, cancelled, or parent exited";break;}
    if(TargetValid!=null && clock.ElapsedMilliseconds-lastTargetCheck>=1000){if(!TargetValid()){Failed=true;Detail="Boot target changed during operation";break;}lastTargetCheck=clock.ElapsedMilliseconds;}
    Capture(console,dir);uint waited=WaitForSingleObject(pi.process,100);if(waited==0)break;if(waited!=258)throw Error("Wait tool");
   }
   if(!Failed && TargetValid!=null && !TargetValid()){Failed=true;Detail="Boot target could not be confirmed at completion";}
   uint exit;if(!GetExitCodeProcess(pi.process,out exit))throw Error("Tool exit code");
   for(int settle=0;settle<10 && !Failed && Active(job)!=0;settle++)System.Threading.Thread.Sleep(10);
   if(Active(job)!=0){Failed=true;if(Detail=="")Detail="Owned descendants still active";}
   Ended=Clean(job);if(!Ended){Failed=true;Detail="Owned job cleanup not confirmed";}
   Capture(console,dir);return Failed?-1:(int)exit;
  }catch(Exception e){Failed=true;Detail=e.Message;if(pi.process!=IntPtr.Zero&&!assigned){TerminateProcess(pi.process,1);Ended=WaitForSingleObject(pi.process,5000)==0;}else{try{Ended=Clean(job);}catch{Ended=false;}}return -1;}
  finally{foreach(IntPtr h in new[]{pi.thread,pi.process,output,error,input,console,job})if(h!=IntPtr.Zero&&h!=new IntPtr(-1))CloseHandle(h);FreeConsole();}
 }
}
'@
    if($q.bootInstance -notmatch '^USB\\VID_4348&PID_55E0\\' -or [string]::IsNullOrWhiteSpace($q.bootPort)){throw 'Missing frozen boot target'}
    function Test-FrozenBoot {
        $probeScript=$deviceQueryScript+"`nConvertTo-Json -InputObject @([AhaKeyReadOnlyDevices]::Boot()) -Compress"
        $probe=[Diagnostics.Process]::new();$probe.StartInfo.FileName=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $probe.StartInfo.Arguments='-NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probeScript))
        $probe.StartInfo.UseShellExecute=$false;$probe.StartInfo.CreateNoWindow=$true;$probe.StartInfo.RedirectStandardOutput=$true;$probe.StartInfo.RedirectStandardError=$true
        try {
            [void]$probe.Start();$output=$probe.StandardOutput.ReadToEndAsync();$errorOutput=$probe.StandardError.ReadToEndAsync()
            if(-not $probe.WaitForExit(8000)){return $false}
            if($probe.ExitCode -ne 0 -or -not $output.Wait(1000) -or $output.Result.Length -gt 65536){return $false}
            $devices=@($output.Result|ConvertFrom-Json)
            return ($devices.Count -eq 1 -and $devices[0].instanceId -ieq $q.bootInstance -and $devices[0].port -ieq $q.bootPort -and $devices[0].service -ieq 'CH375_A64' -and $devices[0].problem -eq 0 -and -not [string]::IsNullOrWhiteSpace($devices[0].inf))
        } catch {return $false} finally {try{if(-not $probe.HasExited){$probe.Kill();[void]$probe.WaitForExit(1000)}}catch{};$probe.Dispose()}
    }
    [WchOwnedSupervisor]::TargetValid=[Func[bool]]{Test-FrozenBoot}
    $arguments='-c '+[WchOwnedSupervisor]::Quote($ini)+' -o '+$q.operation+' -f '+[WchOwnedSupervisor]::Quote($hex)
    $result.exitCode=[WchOwnedSupervisor]::Run($tool,$arguments,$work,$directory,[long]$q.parentPid,[long]$q.parentStart,120000,[long]$q.launchDeadline,[string]$q.operationId)
    $result.started=[WchOwnedSupervisor]::Started;$result.ended=[WchOwnedSupervisor]::Ended;$result.failed=[WchOwnedSupervisor]::Failed;$result.detail=[WchOwnedSupervisor]::Detail
} catch { $result.detail=$_.Exception.Message } finally { if($held){foreach($handle in $held){$handle.Dispose()}} }
Save-Result $result
