package com.example.ahakey.update;

import com.example.ahakey.firmware.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.*;
import java.util.*;
import java.io.*;
import static com.example.ahakey.update.UpdateCenterChecks.*;

public final class InstallerTrustChecks {
    public static void main(String[] args)throws Exception{
        if(args.length>0&&args[0].equals("r6-receipts")){rebootReceipts();bindingChecks();return;}
        if(args.length>0&&args[0].equals("r6-boot")){
            var method=WindowsUpdateInstaller.class.getDeclaredMethod("currentBootIdentity");method.setAccessible(true);
            String first=(String)method.invoke(null),second=(String)method.invoke(null);
            check("read-only actual Windows boot observation stable",first.matches("[0-9]{15,20}")&&first.equals(second));return;
        }
        Path dir=Files.createTempDirectory("trust-checks-");Path file=dir.resolve("package.exe");Files.writeString(file,"fixture-not-executable");String hash=VerifiedDownload.sha256(file);
        var release=ReleaseManifest.parse(manifest(hash,Files.size(file)).getBytes()).windows().get("local-model");String cert="a".repeat(64);
        InstallerTrustPolicy.Evidence valid=new InstallerTrustPolicy.Evidence("Valid",cert,"AhaKeyStudio","1.0.11",InstalledAppIdentity.UPGRADE_CODE,"local-model","x64","{11111111-1111-1111-1111-111111111111}","c".repeat(64),"a".repeat(64));
        var trust=new InstallerTrustPolicy(Map.of("test-only",Set.of(cert)),p->valid);trust.verify(file,release,app());check("valid exact test certificate and new MSI ProductCode",true);
        rejects("empty production policy",()->InstallerTrustPolicy.production(dir).verify(file,release,app()));
        rejects("unknown certificate",()->new InstallerTrustPolicy(Map.of("test-only",Set.of("b".repeat(64))),p->valid).verify(file,release,app()));
        rejects("NotSigned",()->new InstallerTrustPolicy(Map.of("test-only",Set.of(cert)),p->new InstallerTrustPolicy.Evidence("NotSigned",cert,valid.productName(),valid.version(),valid.upgradeCode(),valid.variant(),valid.arch(),valid.productCode())).verify(file,release,app()));
        rejects("MSI shape mismatch",()->new InstallerTrustPolicy(Map.of("test-only",Set.of(cert)),p->new InstallerTrustPolicy.Evidence("Valid",cert,valid.productName(),valid.version(),valid.upgradeCode(),"lite",valid.arch(),valid.productCode())).verify(file,release,app()));
        var gate=new DeviceMaintenanceCoordinator();var operation=gate.begin(null,hash,"test-only",true);Path launcher=dir.resolve("AhaKeyStudio.exe");Files.writeString(launcher,"not-executable");
        WindowsUpdateInstaller worker=new WindowsUpdateInstaller((command,log)->{
            Path request=Path.of(command.get(command.indexOf("-Request")+1));String requestHash=command.get(command.indexOf("-RequestHash")+1);var json=new ObjectMapper();var q=json.readTree(request.toFile());
            json.writeValue(request.resolveSibling("ready.json").toFile(),Map.of("operationId",q.path("operationId").asText(),"requestHash",requestHash));return new FakeProcess();
        },(entry,work)->snapshot(app(),"{22222222-2222-4222-8222-222222222222}",entry));
        System.setProperty("jpackage.app-path",launcher.toString());
        var h=worker.prepare(operation,file,release,app(),trust,dir,launcher);check("handshake does not permit installation",!Files.exists(h.directory().resolve("exit-permit.json")));worker.permitExit(h);check("explicit permit bound",Files.readString(h.directory().resolve("exit-permit.json")).contains(h.requestHash()));
        var permit=new ObjectMapper().readTree(h.directory().resolve("exit-permit.json").toFile());check("published permit complete identity",permit.path("operationId").asText().equals(h.operationId())&&permit.path("requestHash").asText().equals(h.requestHash()));
        String permitHash=VerifiedDownload.sha256(h.directory().resolve("exit-permit.json"));rejects("cannot overwrite existing permit",()->worker.permitExit(new WindowsUpdateInstaller.Handshake(h.directory(),"different","0".repeat(64))));
        check("old permit bytes preserved",VerifiedDownload.sha256(h.directory().resolve("exit-permit.json")).equals(permitHash));
        try(var files=Files.list(h.directory())){check("no permit staging remains",files.noneMatch(p->p.getFileName().toString().endsWith(".tmp")));}
        var json=new ObjectMapper();json.writeValue(h.directory().resolve("receipt.json").toFile(),Map.of("operationId",h.operationId(),"requestHash",h.requestHash(),"state","installed-unconfirmed","exitCode",0));
        check("old version cannot confirm",reconcile(dir,app(),()->"").contains("尚未"));
        var next=new InstalledAppIdentity("1.0.11","local-model","x64","AhaKeyStudio",InstalledAppIdentity.UPGRADE_CODE,"a".repeat(64),true);
        check("restart confirms installed identity",reconcile(dir,next,()->"").startsWith("重启已确认"));
        String markerHash=VerifiedDownload.sha256(h.directory().resolve("restart-confirmed.json"));
        check("confirmed receipt stays visible without rewriting",reconcile(dir,next,()->"").startsWith("重启已确认")&&VerifiedDownload.sha256(h.directory().resolve("restart-confirmed.json")).equals(markerHash));
        Files.writeString(file,"changed");rejects("TOCTOU rehash",()->trust.verify(file,release,app()));
        System.out.println("PASS installer trust/handshake checks; fake process only");
    }
    private static void rebootReceipts()throws Exception{
        System.setProperty("jpackage.app-path",Files.createTempDirectory("receipt-launcher-").resolve("AhaKeyStudio.exe").toString());
        String before="638966000000000000",after="638966100000000000";var json=new ObjectMapper();
        for(int code:new int[]{0,3010,1641}){
            String state=code==0?"installed-unconfirmed":code==3010?"reboot-required":"reboot-initiated";
            Path root=Files.createTempDirectory("r6-receipts-");Path dir=writeReceipt(root,"one",state,code,before,app());
            var old=new InstalledAppIdentity("1.0.9",app().variant(),app().arch(),app().productId(),app().upgradeCode(),"old",true);
            check("old version cannot settle "+code,!reconcile(root,old,()->after).startsWith("重启已确认"));
            var wrong=new InstalledAppIdentity(app().version(),"lite",app().arch(),app().productId(),app().upgradeCode(),"wrong",true);
            check("wrong variant cannot settle "+code,!reconcile(root,wrong,()->after).startsWith("重启已确认"));
            for(var mismatch:List.of(new InstalledAppIdentity(app().version(),app().variant(),"arm64",app().productId(),app().upgradeCode(),"x",true),new InstalledAppIdentity(app().version(),app().variant(),app().arch(),"Other",app().upgradeCode(),"x",true),new InstalledAppIdentity(app().version(),app().variant(),app().arch(),app().productId(),"other-upgrade","x",true)))
                check("strict target identity "+code,!reconcile(root,mismatch,()->after).startsWith("重启已确认"));
            if(code!=0){
                check("app restart is not OS restart "+code,reconcile(root,app(),()->before).contains("Windows"));
                check("unavailable boot evidence stays pending "+code,!reconcile(root,app(),()->"").startsWith("重启已确认"));
            }
            check("successful receipt settles "+code,reconcile(root,app(),()->after).startsWith("重启已确认"));
            Path marker=dir.resolve("restart-confirmed.json");String hash=VerifiedDownload.sha256(marker);var value=json.readTree(marker.toFile());
            check("original code and reboot fact preserved "+code,value.path("exitCode").asInt()==code&&value.path("systemRebootObserved").asBoolean()==(code!=0));
            check("repeat confirmation stable and visible "+code,reconcile(root,app(),()->{throw new AssertionError("already reconciled");}).startsWith("重启已确认")&&hash.equals(VerifiedDownload.sha256(marker)));
        }
        for(String state:List.of("cancelled","installer-failed","worker-failed")){
            Path root=Files.createTempDirectory("r6-failed-");writeReceipt(root,"one",state,1602,before,app());
            check("failed/cancelled never confirms "+state,!reconcile(root,app(),()->after).startsWith("重启已确认"));
        }
        for(boolean reverse:new boolean[]{false,true}){
            Path root=Files.createTempDirectory("r6-order-");Path latest=writeReceipt(root,reverse?"a":"z","installed-unconfirmed",0,before,app());Path old=writeReceipt(root,reverse?"z":"a","cancelled",1602,before,app());
            Files.setLastModifiedTime(old.resolve("request.json"),java.nio.file.attribute.FileTime.fromMillis(1000));Files.setLastModifiedTime(latest.resolve("request.json"),java.nio.file.attribute.FileTime.fromMillis(2000));
            check("latest valid operation independent of listing order "+reverse,reconcile(root,app(),()->after).startsWith("重启已确认"));
        }
        System.out.println("PASS R6 0/3010/1641 receipts; injected boot observations, no installer or OS reboot");
    }
    private static Path writeReceipt(Path root,String name,String state,int code,String boot,InstalledAppIdentity app)throws Exception{
        Path dir=Files.createDirectories(root.resolve(name));var json=new ObjectMapper();Path request=dir.resolve("request.json");
        var requestFields=new LinkedHashMap<String,Object>();
        requestFields.put("operationId",name);requestFields.put("version",app.version());requestFields.put("variant",app.variant());requestFields.put("productId",app.productId());requestFields.put("upgradeCode",app.upgradeCode());requestFields.put("arch",app.arch());
        requestFields.put("targetProductCode","{11111111-1111-1111-1111-111111111111}");requestFields.put("targetMsiSha256","c".repeat(64));requestFields.put("targetBuildId",app.buildId());
        requestFields.put("source",snapshot(app,"{22222222-2222-4222-8222-222222222222}",Path.of(System.getProperty("jpackage.app-path"))));
        json.writeValue(request.toFile(),requestFields);
        json.writeValue(dir.resolve("receipt.json").toFile(),Map.of("operationId",name,"requestHash",VerifiedDownload.sha256(request),"state",state,"exitCode",code,"bootIdBefore",boot));return dir;
    }
    private static WindowsInstalledApplication.Snapshot snapshot(InstalledAppIdentity app,String product,Path entry) {
        return new WindowsInstalledApplication.Snapshot(product,app.upgradeCode(),app.version(),app.variant(),app.arch(),entry.getParent().toString(),entry.toString(),app.buildId(),"c".repeat(64),4);
    }
    private static void bindingChecks()throws Exception{
        Path root=Files.createTempDirectory("r10-receipt-binding-");
        Path entry=root.resolve("installed/AhaKeyStudio.exe");System.setProperty("jpackage.app-path",entry.toString());
        Path dir=writeReceipt(root,"operation","installed-unconfirmed",0,"",app());
        var correct=snapshot(app(),"{11111111-1111-1111-1111-111111111111}",entry);
        var variants=List.of(
                snapshot(app(),"{22222222-2222-4222-8222-222222222222}",entry),
                snapshot(app(),correct.productCode(),root.resolve("other/AhaKeyStudio.exe")),
                new WindowsInstalledApplication.Snapshot(correct.productCode(),correct.upgradeCode(),correct.version(),correct.variant(),correct.arch(),correct.directory(),correct.launcher(),"old-same-version-build",correct.msiSha256(),4),
                new WindowsInstalledApplication.Snapshot(correct.productCode(),correct.upgradeCode(),correct.version(),correct.variant(),correct.arch(),correct.directory(),correct.launcher(),correct.buildId(),correct.msiSha256(),2));
        for(var wrong:variants)check("wrong product/path/build/scope cannot confirm",!WindowsUpdateInstaller.reconcileReceipts(root,app(),()->"",(p,w)->wrong).startsWith("重启已确认"));
        check("unavailable registration cannot confirm",!WindowsUpdateInstaller.reconcileReceipts(root,app(),()->"",(p,w)->{throw new IOException("fixture denied");}).startsWith("重启已确认"));
        check("exact registered target confirms",WindowsUpdateInstaller.reconcileReceipts(root,app(),()->"",(p,w)->correct).startsWith("重启已确认"));
        check("existing confirmation cannot conceal later identity mismatch",!WindowsUpdateInstaller.reconcileReceipts(root,app(),()->"",(p,w)->variants.get(0)).startsWith("重启已确认"));
        var json=new ObjectMapper();var q=(com.fasterxml.jackson.databind.node.ObjectNode)json.readTree(dir.resolve("request.json").toFile());q.remove("targetProductCode");q.remove("targetBuildId");json.writeValue(dir.resolve("request.json").toFile(),q);
        var r=(com.fasterxml.jackson.databind.node.ObjectNode)json.readTree(dir.resolve("receipt.json").toFile());r.put("requestHash",VerifiedDownload.sha256(dir.resolve("request.json")));json.writeValue(dir.resolve("receipt.json").toFile(),r);
        check("legacy receipt never defaults to success",!WindowsUpdateInstaller.reconcileReceipts(root,app(),()->"",(p,w)->correct).startsWith("重启已确认"));
        System.out.println("PASS R10 target registration binding and legacy receipt checks");
    }
    private static String reconcile(Path root,InstalledAppIdentity app,WindowsUpdateInstaller.BootIdentity boot)throws IOException {
        return WindowsUpdateInstaller.reconcileReceipts(root,app,boot,(entry,work)->snapshot(app,"{11111111-1111-1111-1111-111111111111}",entry));
    }
    private static final class FakeProcess extends Process {
        public OutputStream getOutputStream(){return OutputStream.nullOutputStream();}public InputStream getInputStream(){return InputStream.nullInputStream();}public InputStream getErrorStream(){return InputStream.nullInputStream();}
        public int waitFor(){return 0;}public int exitValue(){return 0;}public void destroy(){throw new AssertionError("No kill");}public boolean isAlive(){return true;}
    }
}
