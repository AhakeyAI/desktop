package com.example.ahakey.firmware;

import com.example.ahakey.update.VerifiedDownload;
import com.example.ahakey.update.WindowsUpdateInstaller;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import static com.example.ahakey.update.UpdateCenterChecks.*;

/** Production state machine and actual Windows Job implementation; never runs WCH or installs a driver. */
public final class SimpleFlashChecks {
    public static class Fixture implements FirmwareUpdateService.DeviceIO,FirmwareUpdateService.ToolIO,FirmwareUpdateService.DriverIO {
        public final DeviceMaintenanceCoordinator gate=new DeviceMaintenanceCoordinator();
        final Path root;public final FirmwareCatalog.Target target;public final FirmwareUpdateService service;
        public final List<String> calls=new ArrayList<>();
        List<BootDeviceDetector.Device> devices=List.of(boot(true));
        String actual="fixture-unknown-actual-version";long generation=8;String port="port-A";
        public int driverExit;public boolean driverEnded=true,lateCancel,timeout,alive,writeFailure,readFailure;public Runnable duringTool=()->{};
        public Fixture()throws Exception {
            root=Files.createTempDirectory("r9-simple-");Path hex=root.resolve("unknown.hex");Files.writeString(hex,":0100000001FE\n:00000001FF\n");
            target=new FirmwareCatalog().local(hex);service=new FirmwareUpdateService(gate,this,this,root.resolve("operations"),()->{});service.driverIO(this);
        }
        static BootDeviceDetector.Device boot(boolean ready){return new BootDeviceDetector.Device("USB\\VID_4348&PID_55E0\\test","port-A",ready?"CH375_A64":"",ready?"oem44.inf":"",ready?0:28);}
        public DeviceMaintenanceCoordinator.Identity identity(){throw new AssertionError("Simple flash must not require normal preconnection");}
        public DeviceMaintenanceCoordinator.Operation begin(DeviceMaintenanceCoordinator.Identity i,String h,String p){throw new AssertionError("Old backup path called");}
        public DeviceBackup backup(DeviceMaintenanceCoordinator.Operation o,Set<String> r,Runnable c){throw new AssertionError("Unexpected backup");}
        public DeviceRestoreService.Device restoreDevice(){throw new AssertionError("Unexpected restore");}
        public void downloadTarget(DeviceMaintenanceCoordinator.Identity i){throw new AssertionError("Old target path called");}
        public List<BootDeviceDetector.Device> bootDevices(){calls.add("observe");return devices;}
        public DeviceMaintenanceCoordinator.Operation beginBoot(DeviceMaintenanceCoordinator.Identity i,String h,String p)throws Exception {calls.add("begin boot");return gate.begin(new DeviceMaintenanceCoordinator.Identity(7,i.transport(),i.devicePath(),"",i.port(),""),h,p,false);}
        public void disconnect(DeviceMaintenanceCoordinator.Operation op){calls.add("disconnect");}
        public DeviceMaintenanceCoordinator.Identity reconnect(DeviceMaintenanceCoordinator.Operation op)throws Exception {
            calls.add("read actual version");if(readFailure)throw new java.io.IOException("fixture version read failed");
            var id=new DeviceMaintenanceCoordinator.Identity(generation,"USB","normal-HID","new-normal-container",port,actual);gate.bindReconnection(op,id);return id;
        }
        public WchRuntimeLocator.Runtime locate(Path dir){calls.add("bundled runtime");return new WchRuntimeLocator.Runtime("test",root,root.resolve("never-executed.exe"),Map.of());}
        public WchFlashAdapter.Result execute(WchRuntimeLocator.Runtime r,Path hex,String hash,Path directory,String operation,Runnable onTimeout)throws Exception {
            calls.add(operation);check("frozen HEX for "+operation,VerifiedDownload.sha256(hex).equals(hash));duringTool.run();
            if(timeout)onTimeout.run();if(lateCancel)service.requestSimpleExit();
            return new WchFlashAdapter.Result(!writeFailure,timeout,alive,writeFailure?1:0,"fixture terminal");
        }
        public WchDriverService.Result prepare(Path dir)throws Exception {calls.add("prepare driver");if(driverExit==0)devices=List.of(boot(true));return new WchDriverService.Result(driverExit,driverEnded,"fixture driver");}
        public void requestExit(){calls.add("request cleanup");}
        public boolean cleanupConfirmed(Path directory){return false;}
        void ready()throws Exception {service.prepareSimple(target,true);service.detectBoot();}
    }
    public static void main(String[] args)throws Exception {
        if(args.length>0 && args[0].equals("--boot-absent")) {
            long start=System.nanoTime();var devices=BootDeviceDetector.observe();
            check("production observation returns no devices",devices.isEmpty());
            System.out.println("OBSERVE_MS="+(System.nanoTime()-start)/1_000_000);return;
        }
        if(args.length>0 && args[0].equals("--boot-live")) {
            long start=System.nanoTime();var device=BootDeviceDetector.unique(BootDeviceDetector.observe());
            check("live exact instance",device.instanceId().equalsIgnoreCase(args[1]));
            check("live physical port",device.port().equalsIgnoreCase(args[2]));
            check("live CH375 driver binding",device.ready());
            System.out.println("OBSERVE_MS="+(System.nanoTime()-start)/1_000_000+" DEVICE="+device);return;
        }
        if(args.length>0 && args[0].equals("--maintenance-readonly")) {
            long start=System.nanoTime();var devices=com.example.ahakey.service.UsbHidTransport.maintenanceDevices();
            for(var device:devices) {
                check("maintenance physical identity",!device.container().isBlank()&&!device.port().isBlank());
                if(!device.download())check("normal maintenance HID interface",!device.interfaces().isEmpty());
                System.out.println("MAINTENANCE_DEVICE="+device);
            }
            System.out.println("MAINTENANCE_COUNT="+devices.size()+" ELAPSED_MS="+(System.nanoTime()-start)/1_000_000);return;
        }
        Path evidence=Path.of(args[0]).toAbsolutePath();Files.createDirectories(evidence);
        if(args.length>1 && args[1].equals("--boot-process")) {bootProcessChecks(evidence);return;}
        if(args.length>1 && args[1].equals("--device-query")) {deviceQueryChecks(evidence,args[2],args[3],args[4],args[5]);return;}
        stateChecks();bundleChecks(evidence);lateCleanupChecks();supervisorChecks(evidence);
        System.out.println("PASS R9 simple flash state, bundle integrity and actual Job supervision. No WCH/UAC/driver/device execution.");
    }
    /** Harmless subprocess fixtures: stdout/stderr only, no PowerShell, WCH, drivers or device I/O. */
    public static final class BootQueryFixture {
        public static void main(String[] args)throws Exception {
            Files.writeString(Path.of(args[1]),Long.toString(ProcessHandle.current().pid()));
            switch(args[0]) {
                case "empty" -> System.out.print("[]");
                case "one" -> System.out.print(bootJson());
                case "two" -> System.out.print("["+bootJson().substring(1,bootJson().length()-1)+","+bootJson().substring(1,bootJson().length()-1)+"]");
                case "invalid" -> System.out.print("not JSON");
                case "null" -> System.out.print("null");
                case "null-entry" -> System.out.print("[null]");
                case "failed" -> {System.err.print("fixture original query failure");System.exit(7);}
                case "stdout-flood" -> {for(int i=0;i<1000;i++)System.out.print("x".repeat(4096));}
                case "stderr-flood" -> {for(int i=0;i<1000;i++)System.err.print("x".repeat(4096));}
                default -> {System.err.print("fixture waiting for timeout");System.err.flush();Thread.sleep(30_000);System.out.print(bootJson());}
            }
        }
    }
    static String bootJson(){return "[{\"instanceId\":\"USB\\\\VID_4348&PID_55E0\\\\fixture\",\"port\":\"port-A\",\"service\":\"CH375_A64\",\"inf\":\"oem44.inf\",\"problem\":0}]";}
    static ProcessBuilder bootChild(String mode,Path pid) {
        return new ProcessBuilder(Path.of(System.getProperty("java.home"),"bin","java.exe").toString(),"-cp",System.getProperty("java.class.path"),BootQueryFixture.class.getName(),mode,pid.toString());
    }
    static void deviceQueryChecks(Path evidence,String instance,String port,String service,String inf)throws Exception {
        String checks="""
            function Check($name,$ok){if(-not $ok){throw ('FAIL '+$name)};Write-Output ('PASS '+$name)}
            $flags=[Reflection.BindingFlags]'NonPublic,Static'
            $decode=[AhaKeyReadOnlyDevices].GetMethod('DecodeString',$flags)
            $text=[Text.Encoding]::Unicode.GetBytes("CH375_A64`0")
            Check 'typed UTF16 text' ($decode.Invoke($null,[object[]]@($text,$false)) -ceq $expected.service)
            $multi=[Text.Encoding]::Unicode.GetBytes("PCIROOT(0)#USB(3)`0other`0`0")
            Check 'MULTI_SZ preserves entries' ($decode.Invoke($null,[object[]]@($multi,$true)) -ceq "PCIROOT(0)#USB(3)`0other")
            foreach($bytes in @([byte[]]@(65),[byte[]]@(65,0),[byte[]]@(0,0,65,0,0,0),[byte[]]@(0,216,0,0))) {
                $rejected=$false;try{[void]$decode.Invoke($null,[object[]]@($bytes,$false))}catch{$rejected=$true}
                Check 'malformed UTF16 rejected' $rejected
            }
            $rejected=$false;try{[void]$decode.Invoke($null,[object[]]@([byte[]]@(65,0,0,0),$true))}catch{$rejected=$true}
            Check 'MULTI_SZ requires double terminator' $rejected
            # PHANTOM is used only by this diagnostic to read historical metadata, never by production Node().
            $id=$expected.instance
            $locate=[AhaKeyReadOnlyDevices].GetMethod('CM_Locate_DevNodeW',$flags)
            $arguments=[object[]]@([uint32]0,$id,[uint32]1)
            Check 'historical fixture exists' ($locate.Invoke($null,$arguments) -eq 0)
            $node=[uint32]$arguments[0]
            $port=[AhaKeyReadOnlyDevices].GetMethod('Port',$flags).Invoke($null,[object[]]@($node))
            Check 'historical physical port' ($port -ceq $expected.port)
            $textMethod=[AhaKeyReadOnlyDevices].GetMethod('Text',$flags)
            Check 'historical service' ($textMethod.Invoke($null,[object[]]@($node,'a45c254e-df1c-4efd-8020-67d146a850e0',[uint32]6)) -ceq $expected.service)
            Check 'historical INF' ($textMethod.Invoke($null,[object[]]@($node,'a8b865dd-2e3d-4094-ad97-e593a70c75d6',[uint32]5)) -ceq $expected.inf)
            Check 'historical container GUID' ($null -ne [Guid]::Parse([AhaKeyReadOnlyDevices].GetMethod('Container',$flags).Invoke($null,[object[]]@($node))))
            $property=[AhaKeyReadOnlyDevices].GetMethod('Property',$flags)
            $rejected=$false;try{[void]$property.Invoke($null,[object[]]@($node,'a45c254e-df1c-4efd-8020-67d146a850e0',[uint32]37,[uint32]18))}catch{$rejected=$true}
            Check 'native property type mismatch rejected' $rejected
            $missing=$property.Invoke($null,[object[]]@($node,'00000000-0000-0000-0000-000000000000',[uint32]1,[uint32]7))
            Check 'missing property stays unknown' ($null -eq $missing)
            $arguments=[object[]]@([uint32]0,$id,[uint32]0)
            if($locate.Invoke($null,$arguments) -ne 0) {
                Check 'historical instance never admitted as present' (@([AhaKeyReadOnlyDevices]::Boot()|Where-Object instanceId -eq $id).Count -eq 0)
                Check 'offline problem is not ready' ([AhaKeyReadOnlyDevices].GetMethod('Problem',$flags).Invoke($null,[object[]]@($node)) -eq -1)
            }
            Write-Output 'PASS shared device query historical/decoder checks; not a live boot positive'
            """;
        String expected=Base64.getEncoder().encodeToString(new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsBytes(Map.of("instance",instance,"port",port,"service",service,"inf",inf)));
        Path script=evidence.resolve("query-checks.ps1");Files.writeString(script,BootDeviceDetector.deviceQueryScript()+"\n$expected=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+expected+"'))|ConvertFrom-Json\n"+checks);
        Process child=new ProcessBuilder(WindowsUpdateInstaller.powershell(),"-NoProfile","-NonInteractive","-File",script.toAbsolutePath().toString())
                .redirectErrorStream(true).redirectOutput(evidence.resolve("query-checks.log").toFile()).start();
        try {
            check("shared query checks bounded",child.waitFor(10,TimeUnit.SECONDS));
            System.out.print(Files.readString(evidence.resolve("query-checks.log")));
            check("actual shared query checks exit zero",child.exitValue()==0);
        } finally {
            if(child.isAlive()){child.destroyForcibly();check("query fixture cleanup",child.waitFor(3,TimeUnit.SECONDS));}
            child.getOutputStream().close();child.getInputStream().close();child.getErrorStream().close();
        }
    }
    static void ended(Path pid)throws Exception {
        check("fixture recorded own PID",Files.isRegularFile(pid));
        check("only query child ended",ProcessHandle.of(Long.parseLong(Files.readString(pid))).map(p->!p.isAlive()).orElse(true));
    }
    static void bootProcessChecks(Path evidence)throws Exception {
        Path unrelatedPid=evidence.resolve("unrelated.pid");Process unrelated=bootChild("wait",unrelatedPid).start();
        try {
            for(String mode:List.of("empty","one","two")) {
                Path pid=evidence.resolve(mode+".pid");var devices=BootDeviceDetector.observe(bootChild(mode,pid),5000);
                check("subprocess JSON count "+mode,devices.size()==(mode.equals("empty")?0:mode.equals("one")?1:2));
                if(mode.equals("one"))check("subprocess preserves exact identity/readiness",BootDeviceDetector.unique(devices).ready());
                else rejects("subprocess unique target rejects "+mode,()->BootDeviceDetector.unique(devices));
                ended(pid);
            }
            for(String mode:List.of("invalid","null","null-entry","failed","stdout-flood","stderr-flood","timeout")) {
                Path pid=evidence.resolve(mode+".pid");long start=System.nanoTime();
                try {BootDeviceDetector.observe(bootChild(mode,pid),mode.equals("timeout")?1200:5000);throw new AssertionError("Accepted "+mode);}
                catch(java.io.IOException expected) {
                    String message=expected.getMessage();
                    check("original diagnostic retained "+mode,mode.equals("timeout")?message.contains("超时")&&message.contains("fixture waiting"):
                            mode.equals("failed")?message.contains("退出码 7")&&message.contains("fixture original"):
                            mode.endsWith("flood")?message.contains("超限"):message.contains("无效数据"));
                    check("diagnostic bounded "+mode,message.length()<5000);
                    System.out.println("EXPECTED_FAILURE="+mode+" "+message.substring(0,Math.min(message.length(),180)));
                }
                check("query and cleanup bounded "+mode,(System.nanoTime()-start)/1_000_000<9000);ended(pid);
                check("unrelated same executable survives "+mode,unrelated.isAlive());
            }
            Path pid=evidence.resolve("interrupt.pid");var result=new java.util.concurrent.atomic.AtomicReference<Throwable>();
            Thread caller=new Thread(()->{try{BootDeviceDetector.observe(bootChild("wait",pid),10_000);}catch(Throwable e){result.set(e);}},"boot-check-interrupt");caller.start();
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);
            while(!Files.exists(pid)&&System.nanoTime()<deadline)Thread.sleep(20);
            check("interrupt fixture started",Files.exists(pid));caller.interrupt();caller.join(5000);
            check("interruption exits caller",!caller.isAlive()&&result.get() instanceof InterruptedException);ended(pid);
            check("unrelated child remains after interruption",unrelated.isAlive());
        } finally {unrelated.destroyForcibly();check("owned unrelated fixture cleanup",unrelated.waitFor(3,TimeUnit.SECONDS));unrelated.getInputStream().close();unrelated.getErrorStream().close();unrelated.getOutputStream().close();}
        System.out.println("PASS real boot query subprocess bounds, errors, interruption and ownership; no real device I/O.");
    }
    static void stateChecks()throws Exception {
        Fixture good=new Fixture();good.ready();check("boot-only start, no normal identity or backup",good.service.view().state()==FirmwareUpdateService.State.READY_TO_FLASH&&good.gate.active());
        rejects("maintenance excludes normal writer",()->good.gate.normalTransaction());good.service.flashSimple();check("download then verify, wait for real version",good.calls.indexOf("download")<good.calls.indexOf("verify")&&good.service.view().state()==FirmwareUpdateService.State.WAIT_RECONNECT);
        good.service.checkSimpleReconnect();check("unknown HEX accepts actual observed version",good.service.view().state()==FirmwareUpdateService.State.COMPLETE&&good.service.view().detail().contains(good.actual)&&!good.gate.active());
        Fixture risk=new Fixture();rejects("erase confirmation required",()->risk.service.prepareSimple(risk.target,false));check("no side effects without consent",risk.calls.isEmpty());risk.service.exitSimple();
        for(int count:new int[]{0,2}) {Fixture f=new Fixture();f.devices=count==0?List.of():List.of(Fixture.boot(true),Fixture.boot(true));f.service.prepareSimple(f.target,true);rejects("reject boot count "+count,f.service::detectBoot);check("zero writes on ambiguous boot",!f.calls.contains("download"));f.service.exitSimple();}
        rejects("unsupported VID not admitted",()->BootDeviceDetector.unique(List.of(new BootDeviceDetector.Device("USB\\VID_1A86&PID_55E0\\other","port-A","CH375_A64","oem.inf",0))));
        Fixture needs=new Fixture();needs.devices=List.of(Fixture.boot(false));needs.ready();check("presence is not driver readiness",needs.service.view().state()==FirmwareUpdateService.State.DRIVER_NEEDED);needs.service.prepareDriver();check("driver success reprobes binding",needs.service.view().state()==FirmwareUpdateService.State.READY_TO_FLASH);needs.service.exitSimple();
        for(int exit:new int[]{-1,259,3010,1641,5}) {Fixture f=new Fixture();f.driverExit=exit;f.devices=List.of(Fixture.boot(false));f.ready();rejects("driver result "+exit+" never authorizes flash",f.service::prepareDriver);check("driver failure no writes",!f.calls.contains("download")&&f.service.view().state()==FirmwareUpdateService.State.FAILED);f.service.exitSimple();check("known ended driver releases on exit",!f.gate.active());}
        Fixture unbound=new Fixture(){@Override public WchDriverService.Result prepare(Path dir){return new WchDriverService.Result(0,true,"staged only");}};unbound.devices=List.of(Fixture.boot(false));unbound.ready();rejects("exit zero without actual binding rejected",unbound.service::prepareDriver);unbound.service.exitSimple();
        Fixture swap=new Fixture();swap.ready();swap.devices=List.of(new BootDeviceDetector.Device(Fixture.boot(true).instanceId(),"other-port","CH375_A64","oem.inf",0));rejects("boot swap before flash",swap.service::flashSimple);check("no writes to changed target",!swap.calls.contains("download"));swap.service.exitSimple();
        Fixture corrupt=new Fixture();corrupt.ready();Path frozen;try(var paths=Files.walk(corrupt.root.resolve("operations"))){frozen=paths.filter(p->p.getFileName().toString().equals("firmware.hex")).findFirst().orElseThrow();}Files.writeString(frozen,"tampered");rejects("frozen HEX tamper blocks flash",corrupt.service::flashSimple);corrupt.service.exitSimple();
        for(String failure:List.of("late cancel","timeout","failed exit")) {Fixture f=new Fixture();f.ready();f.lateCancel=failure.equals("late cancel");f.timeout=failure.equals("timeout");f.writeFailure=failure.equals("failed exit");rejects(failure+" cannot turn successful late output into success",f.service::flashSimple);check("no verify after failure",!f.calls.contains("verify")&&f.service.view().state()==FirmwareUpdateService.State.FAILED);f.service.exitSimple();check("cleanup confirmed allows fresh attempt",!f.gate.active());f.ready();f.service.exitSimple();}
        Fixture live=new Fixture();live.ready();live.alive=true;rejects("unknown cleanup fails",live.service::flashSimple);live.service.exitSimple();check("unknown owned processes prohibit another attempt",live.gate.active()&&live.service.view().state()==FirmwareUpdateService.State.FAILED);rejects("no second write while cleanup unknown",()->live.service.prepareSimple(live.target,true));
        for(String mismatch:List.of("missing version","same generation","other port","read fail")) {Fixture f=new Fixture();f.ready();f.service.flashSimple();if(mismatch.equals("missing version"))f.actual="";if(mismatch.equals("same generation"))f.generation=7;if(mismatch.equals("other port"))f.port="other";f.readFailure=mismatch.equals("read fail");rejects(mismatch+" never completes",f.service::checkSimpleReconnect);check("version failure is terminal",f.service.view().state()==FirmwareUpdateService.State.FAILED);f.service.exitSimple();}
        Fixture expired=new Fixture();expired.ready();var deadline=FirmwareUpdateService.class.getDeclaredField("waitingDeadline");deadline.setAccessible(true);deadline.setLong(expired.service,System.currentTimeMillis()-1);expired.service.expireWaiting();check("idle waiting expires to terminal failure",expired.service.view().state()==FirmwareUpdateService.State.FAILED);expired.service.exitSimple();
        Fixture prelaunch=new Fixture(){@Override public WchDriverService.Result prepare(Path dir)throws WchDriverService.NotStartedException {throw new WchDriverService.NotStartedException(new java.io.IOException("fixture missing package before launch"));}};
        prelaunch.devices=List.of(Fixture.boot(false));prelaunch.ready();rejects("driver prelaunch failure",prelaunch.service::prepareDriver);prelaunch.service.exitSimple();check("proven not-started driver allows exit/retry",!prelaunch.gate.active());
    }
    static void bundleChecks(Path evidence)throws Exception {
        WchRuntimeLocator locator=new WchRuntimeLocator();Path source=Path.of("src/main/resources/firmware/wch").toAbsolutePath();var runtime=locator.locate(source);locator.verifyDrivers(source.resolve("driver"));
        check("all six runtime and seven driver files verified",runtime.hashes().size()==6);
        var copied=locator.copyForOperation(runtime,evidence.resolve("runtime 中文 space"));check("operation copy uses sanitized profile",copied.hashes().equals(runtime.hashes()));
        for(String name:List.of("CH375DLL.DLL","CONFIG_CH57X59X.WCH","ChipType/chiplist_CH57x_CH59x.wcfg")) {Path file=copied.directory().resolve(name);byte[] original=Files.readAllBytes(file);Files.write(file,new byte[]{1});rejects("bundle corruption "+name,()->locator.recheck(copied));Files.write(file,original);}
        Path driver=evidence.resolve("driver-copy");Files.createDirectory(driver);try(var files=Files.list(source.resolve("driver"))){for(Path p:files.toList())Files.copy(p,driver.resolve(p.getFileName()));}Files.write(driver.resolve("CH375WDM.CAT"),new byte[]{1});rejects("driver CAT tamper",()->locator.verifyDrivers(driver));
        Path hex=evidence.resolve("cancel-fixture.hex");Files.writeString(hex,":0100000001FE\n:00000001FF\n");String hash=VerifiedDownload.sha256(hex);
        for(int cancellationPoint:List.of(1,2,3)) {
            var checks=new java.util.concurrent.atomic.AtomicInteger();var launches=new java.util.concurrent.atomic.AtomicInteger();
            WchFlashAdapter adapter=new WchFlashAdapter((r,i,h,d,o,t)->{launches.incrementAndGet();throw new AssertionError("Cancelled preparation launched tool");});
            try{adapter.execute(runtime,hex,hash,evidence.resolve("cancel-before-launch-"+cancellationPoint),"download",()->{},()->checks.incrementAndGet()>=cancellationPoint);throw new AssertionError("Expected cancellation");}catch(WchFlashAdapter.NotStartedException expected){}
            check("cancellation during actual preparation point "+cancellationPoint+" never invokes runner",launches.get()==0);
        }
        var driverCancelled=new java.util.concurrent.atomic.AtomicBoolean();WchDriverService driverService=new WchDriverService(()->{driverCancelled.set(true);return source.resolve("driver");});
        try{driverService.prepare(evidence.resolve("driver-cancel-before-uac"),driverCancelled::get);throw new AssertionError("Expected cancellation");}catch(WchDriverService.NotStartedException expected){}
        check("driver cancellation before UAC launches no worker",!Files.exists(evidence.resolve("driver-cancel-before-uac/worker.log")));
        WchDriverService corruptDriver=new WchDriverService(()->driver);
        try{corruptDriver.prepare(evidence.resolve("driver-corrupt-before-uac"));throw new AssertionError("Expected rejection");}catch(WchDriverService.NotStartedException expected){}
        check("actual corrupt driver is proven not-started",!Files.exists(evidence.resolve("driver-corrupt-before-uac/worker.log")));
        Path receipt=evidence.resolve("invalid-output-ended");Files.createDirectory(receipt);String operation=UUID.randomUUID().toString();Files.writeString(receipt.resolve("operation.id"),operation);Files.writeString(receipt.resolve("result.json"),"{\"operationId\":\""+operation+"\",\"ended\":true,\"failed\":false,\"exitCode\":0}");Files.write(receipt.resolve("stdout.txt"),new byte[]{(byte)0xff,(byte)0xfe});
        var invalidOutput=WchFlashAdapter.readResult(receipt,false);check("ended receipt plus non-UTF8 diagnostics fails without stuck process flag",!invalidOutput.success()&&!invalidOutput.processAlive());
        Files.writeString(receipt.resolve("operation.id"),UUID.randomUUID().toString());check("unmatched receipt never proves cleanup",WchFlashAdapter.readResult(receipt,false).processAlive());
    }
    static void supervisorChecks(Path evidence)throws Exception {
        String script=Files.readString(Path.of("src/main/resources/firmware/wch-capture-worker.ps1"));int supervisor=script.indexOf("public static class WchOwnedSupervisor"),begin=script.lastIndexOf("using System;",supervisor),end=script.indexOf("\n'@",begin);String source=script.substring(begin,end);
        Path run=evidence.resolve("supervisor-fixture.ps1");String checks="""
            $ErrorActionPreference='Stop'
            $root=$PSScriptRoot;$log=Join-Path $root 'supervisor-checks.log'
            function Check($name,$value){if(-not $value){throw ('FAIL '+$name)};[IO.File]::AppendAllText($log,('PASS '+$name+"`n"))}
            $fixture=Join-Path $root 'HarmlessJobFixture.exe'
            Add-Type -OutputAssembly $fixture -OutputType ConsoleApplication -TypeDefinition @'
            using System;using System.IO;using System.Diagnostics;using System.Threading;
            public class HarmlessJobFixture {
             public static void Main(string[] args){
              if(args[0]=="ok"){Console.WriteLine("Status=Finished Code=0 Message=Succeed");return;}
              string root=args[1];File.AppendAllText(Path.Combine(root,"pids.txt"),Process.GetCurrentProcess().Id+"\\n");
              if(args[0]=="tree"||args[0]=="branch"||args[0]=="orphan") {var info=new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,(args[0]=="tree"?"branch":"leaf")+" \\\""+root+"\\\"");info.UseShellExecute=false;info.CreateNoWindow=true;Process.Start(info);if(args[0]=="orphan")return;}
              Thread.Sleep(3000);if(args[0]=="late")File.WriteAllText(Path.Combine(root,"late-success.txt"),"Status=Finished Code=0 Message=Succeed");Thread.Sleep(30000);
             }
            }
            '@
            $start=([DateTimeOffset](Get-Process -Id $PID).StartTime.ToUniversalTime()).ToUnixTimeMilliseconds()
            function Run-Case($name,$mode,$budget){
              $dir=Join-Path $root $name;[IO.Directory]::CreateDirectory($dir)|Out-Null;$id=[guid]::NewGuid().ToString();[IO.File]::WriteAllText((Join-Path $dir 'operation.id'),$id)
              $arguments=$mode+' '+[WchOwnedSupervisor]::Quote($dir)
              $exit=[WchOwnedSupervisor]::Run($fixture,$arguments,$root,$dir,$PID,$start,$budget,([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+10000),$id)
              return @{dir=$dir;exit=$exit;started=[WchOwnedSupervisor]::Started;ended=[WchOwnedSupervisor]::Ended;failed=[WchOwnedSupervisor]::Failed}
            }
            $outside=Join-Path $root 'outside';[IO.Directory]::CreateDirectory($outside)|Out-Null
            $unrelated=Start-Process -FilePath $fixture -ArgumentList @('leaf',('"'+$outside+'"')) -WindowStyle Hidden -PassThru
            try {
              $ok=Run-Case 'normal' 'ok' 5000;Check 'normal owned process completes' ($ok.exit -eq 0 -and $ok.started -and $ok.ended -and -not $ok.failed)
              foreach($mode in @('tree','orphan','late')) {
                $r=Run-Case $mode $mode 1200;Check ($mode+' terminal failure and zero owned processes') ($r.started -and $r.ended -and $r.failed)
                Start-Sleep -Milliseconds 200
                foreach($childId in (Get-Content -LiteralPath (Join-Path $r.dir 'pids.txt'))){Check ($mode+' recorded owned PID ended') ($null -eq (Get-Process -Id ([int]$childId) -ErrorAction SilentlyContinue))}
                Check ($mode+' late success absent') (-not (Test-Path -LiteralPath (Join-Path $r.dir 'late-success.txt')))
                Check 'unrelated same-name process remains alive' (-not $unrelated.HasExited)
              }
              foreach($case in @('expired','cancelled','wrong-operation','wrong-parent')) {
                $dir=Join-Path $root $case;[IO.Directory]::CreateDirectory($dir)|Out-Null;$id=[guid]::NewGuid().ToString();[IO.File]::WriteAllText((Join-Path $dir 'operation.id'),$id)
                $deadline=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+10000;$parentStart=$start
                if($case -eq 'expired'){$deadline=0};if($case -eq 'cancelled'){[IO.File]::WriteAllText((Join-Path $dir 'cancel.request'),'cancel')};if($case -eq 'wrong-operation'){$id=[guid]::NewGuid().ToString()};if($case -eq 'wrong-parent'){$parentStart=0}
                $rejected=$false;try{[void][WchOwnedSupervisor]::Run($fixture,'ok',$root,$dir,$PID,$parentStart,1000,$deadline,$id)}catch{$rejected=$true}
                Check ($case+' cannot start after late UAC') ($rejected -and -not [WchOwnedSupervisor]::Started -and -not (Test-Path -LiteralPath (Join-Path $dir 'owned-process.txt')))
              }
              foreach($case in @('target-swapped-before-resume','second-device-before-resume')) {
                $script:probes=0;[WchOwnedSupervisor]::TargetValid=[Func[bool]]{$script:probes++;return $script:probes -lt 3}
                $r=Run-Case $case 'leaf' 5000
                Check ($case+' never resumes suspended child and confirms cleanup') (-not $r.started -and $r.ended -and $r.failed -and -not (Test-Path -LiteralPath (Join-Path $r.dir 'pids.txt')))
              }
              $script:probes=0;[WchOwnedSupervisor]::TargetValid=[Func[bool]]{$script:probes++;return $script:probes -lt 4}
              $r=Run-Case 'target-changed-during-write' 'leaf' 5000
              Check 'target change during running operation fails and cleans owned child' ($r.started -and $r.ended -and $r.failed)
              [WchOwnedSupervisor]::TargetValid=$null
            } finally {if(-not $unrelated.HasExited){$unrelated.Kill();[void]$unrelated.WaitForExit(5000)}}
            """;
        Files.writeString(run,"Add-Type -TypeDefinition @'\n"+source+"\n'@\n"+checks);
        Process child=new ProcessBuilder(WindowsUpdateInstaller.powershell(),"-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",run.toString()).redirectErrorStream(true).redirectOutput(evidence.resolve("supervisor-process.log").toFile()).start();
        check("actual Windows supervisor fixture bounded",child.waitFor(50,TimeUnit.SECONDS));check("actual Windows supervisor fixture exits zero",child.exitValue()==0);
        System.out.print(Files.readString(evidence.resolve("supervisor-checks.log")));
    }
    static void lateCleanupChecks()throws Exception {
        for(boolean driver:new boolean[]{false,true}) {
            var pending=new java.util.concurrent.atomic.AtomicReference<Path>();var expected=new java.util.concurrent.atomic.AtomicReference<String>();
            WchFlashAdapter adapter=new WchFlashAdapter((r,i,h,d,o,t)->new WchFlashAdapter.Result(false,true,true,-1,"fixture unknown cleanup"));
            Fixture f=new Fixture(){
                @Override public WchRuntimeLocator.Runtime locate(Path dir){try{return new WchRuntimeLocator().locate(Path.of("src/main/resources/firmware/wch").toAbsolutePath());}catch(Exception e){throw new RuntimeException(e);}}
                @Override public WchFlashAdapter.Result execute(WchRuntimeLocator.Runtime r,Path hex,String hash,Path directory,String operation,Runnable timeout)throws Exception {
                    calls.add(operation);pending.set(directory);var result=adapter.execute(r,hex,hash,directory,operation,timeout);expected.set(Files.readString(directory.resolve("operation.id")));return result;
                }
                @Override public WchDriverService.Result prepare(Path directory)throws Exception {
                    Files.createDirectory(directory);pending.set(directory);expected.set(UUID.randomUUID().toString());Files.writeString(directory.resolve("operation.id"),expected.get());return new WchDriverService.Result(-1,false,"fixture delayed receipt");
                }
                @Override public boolean cleanupConfirmed(Path directory){return driver?WchDriverService.endedReceipt(directory,expected.get()):adapter.cleanupConfirmed(directory);}
            };
            if(driver)f.devices=List.of(Fixture.boot(false));f.ready();rejects("unknown cleanup remains failed driver="+driver,driver?f.service::prepareDriver:f.service::flashSimple);
            for(String receipt:List.of("missing","wrong operation","not ended","string ended","changed operation file")) {
                if(!receipt.equals("missing"))new com.fasterxml.jackson.databind.ObjectMapper().writeValue(pending.get().resolve("result.json").toFile(),Map.of("operationId",receipt.equals("wrong operation")?UUID.randomUUID().toString():expected.get(),"ended",receipt.equals("string ended")?"true":!receipt.equals("not ended"),"failed",false,"exitCode",0));
                if(receipt.equals("changed operation file"))Files.writeString(pending.get().resolve("operation.id"),UUID.randomUUID().toString());
                f.service.exitSimple();check("untrusted late receipt preserves maintenance "+receipt+" driver="+driver,f.gate.active()&&f.service.view().state()==FirmwareUpdateService.State.FAILED);
            }
            Files.writeString(pending.get().resolve("operation.id"),expected.get());new com.fasterxml.jackson.databind.ObjectMapper().writeValue(pending.get().resolve("result.json").toFile(),Map.of("operationId",expected.get(),"ended",true,"failed",false,"exitCode",0));
            f.service.exitSimple();check("matching late ended receipt permits explicit exit only driver="+driver,!f.gate.active()&&f.service.view().state()==FirmwareUpdateService.State.IDLE&&!f.calls.contains("verify"));
            f.ready();check("fresh attempt permitted after confirmed cleanup driver="+driver,f.gate.active());f.service.exitSimple();
        }
    }
}
