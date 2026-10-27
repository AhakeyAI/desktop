package com.example.ahakey.update;

import java.io.*;
import java.nio.file.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public final class UpdateCenterChecks {
    public static int checks;
    @FunctionalInterface public interface Action { void run() throws Exception; }
    public static void check(String name, boolean value) { if(!value)throw new AssertionError(name);checks++;System.out.println("PASS "+name); }
    public static void rejects(String name,Action action) throws Exception {try{action.run();}catch(Exception expected){check(name,true);return;}throw new AssertionError(name+" was accepted");}
    public static String manifest(String hash,long size) {return """
        {"schema":2,"channel":"stable","generatedAt":"2026-10-23T00:00:00Z","windows":{"local-model":{
        "version":"1.0.11","arch":"x64","installerKind":"jpackage-exe","url":"https://ahakey.com/update.exe","size":%d,
        "sha256":"%s","productId":"AhaKeyStudio","upgradeCode":"{03E5A934-FFCA-3815-B455-7D49BF1CA1DC}","signerPolicyId":"test-only"}},"firmware":{"entries":[]}}
        """.formatted(size,hash);}
    public static InstalledAppIdentity app(){return new InstalledAppIdentity("1.0.10","local-model","x64","AhaKeyStudio",InstalledAppIdentity.UPGRADE_CODE,"fixture",true);}
    public static void main(String[] args)throws Exception{
        Path dir=Files.createTempDirectory("update-checks-");byte[] payload="fixture-installer-not-executable".getBytes();Path original=dir.resolve("input");Files.write(original,payload);String hash=VerifiedDownload.sha256(original);
        byte[] m=manifest(hash,payload.length).getBytes();var parsed=ReleaseManifest.parse(m);check("schema2 release",parsed.windows().size()==1);parsed.windows().get("local-model").matches(app());
        rejects("schema1",()->ReleaseManifest.parse(new String(m).replace("\"schema\":2","\"schema\":1").getBytes()));
        rejects("duplicate schema",()->ReleaseManifest.parse(new String(m).replace("\"schema\":2","\"schema\":2,\"schema\":2").getBytes()));
        rejects("http blocked",()->ReleaseManifest.parse(new String(m).replace("https:","http:").getBytes()));
        rejects("host blocked",()->ReleaseManifest.parse(new String(m).replace("ahakey.com","evil.example").getBytes()));
        rejects("wrong family",()->ReleaseManifest.parse(new String(m).replace("AhaKeyStudio","Other").getBytes()));
        rejects("wrong arch",()->ReleaseManifest.parse(new String(m).replace("x64","arm64").getBytes()));
        rejects("size absent",()->ReleaseManifest.parse(new String(m).replace("\"size\":"+payload.length+",","").getBytes()));
        rejects("variant mismatch",()->parsed.windows().get("local-model").matches(new InstalledAppIdentity("1.0.10","lite","x64","AhaKeyStudio",InstalledAppIdentity.UPGRADE_CODE,"x",true)));
        rejects("downgrade blocked",()->parsed.windows().get("local-model").matches(new InstalledAppIdentity("1.0.12","local-model","x64","AhaKeyStudio",InstalledAppIdentity.UPGRADE_CODE,"x",true)));
        rejects("404 unavailable",()->new ReleaseManifestClient(uri->new ReleaseManifestClient.Response(404,0,new ByteArrayInputStream(new byte[0]))).fetch());
        rejects("redirect rejected",()->new ReleaseManifestClient(uri->new ReleaseManifestClient.Response(302,0,new ByteArrayInputStream(new byte[0]))).fetch());
        rejects("oversized manifest",()->new ReleaseManifestClient(uri->new ReleaseManifestClient.Response(200,1048577,new ByteArrayInputStream(new byte[0]))).fetch());
        AtomicInteger progress=new AtomicInteger();var transfer=new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,-1,new ByteArrayInputStream(payload)));
        Path result=transfer.fetch(ReleaseManifestClient.STABLE,payload.length,hash,dir,".exe",n->progress.set((int)n));check("unknown transport length accepted only exact verified size",Files.size(result)==payload.length&&progress.get()==payload.length);
        rejects("hash mismatch",()->new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,-1,new ByteArrayInputStream(payload))).fetch(ReleaseManifestClient.STABLE,payload.length,"0".repeat(64),dir,".exe",n->{}));
        rejects("excess bytes",()->new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,-1,new ByteArrayInputStream(payload))).fetch(ReleaseManifestClient.STABLE,payload.length-1,hash,dir,".exe",n->{}));
        VerifiedDownload cancelled=new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,-1,new ByteArrayInputStream(payload)));cancelled.cancel();rejects("cancel before read",()->cancelled.fetch(ReleaseManifestClient.STABLE,payload.length,hash,dir,".exe",n->{}));
        CountDownLatch reading=new CountDownLatch(1),closed=new CountDownLatch(1);
        InputStream blocking=new InputStream(){public int read()throws IOException{reading.countDown();try{closed.await();}catch(InterruptedException e){throw new IOException(e);}throw new IOException("cancelled");}public void close(){closed.countDown();}};
        VerifiedDownload inFlight=new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,-1,blocking));
        var future=CompletableFuture.runAsync(()->{try{inFlight.fetch(ReleaseManifestClient.STABLE,1,hash,dir,".exe",n->{});throw new AssertionError();}catch(Exception expected){}});
        check("read entered",reading.await(2,TimeUnit.SECONDS));inFlight.cancel();future.get(2,TimeUnit.SECONDS);
        try(var files=Files.list(dir)){check("cancel and failure remove partials",files.noneMatch(p->p.toString().endsWith(".part")));}
        serviceFlow(dir,payload,hash,m);
        schema3Checks(dir);
        receiptVisibility(dir);
        System.out.println("PASS update checks="+checks+"; fake HTTP only");
    }
    private static void schema3Checks(Path root)throws Exception {
        String cloud="https://7072-prod-0gkk7gxj94d927df-1398334410.tcb.qcloud.la/package.exe?token=fixture-secret";
        String minimal="{\"schema\":3,\"channel\":\"stable\",\"version\":\"1.0.12\",\"windows\":{\"local-model\":{\"url\":\""+cloud+"\"},\"lite\":{\"url\":\"https://ahakey.com/lite.exe\"}}}";
        var parsed=ReleaseManifest.parse(minimal.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        check("schema3 shared version and no remote hash/size required",parsed.windows().size()==2&&parsed.windows().values().stream().allMatch(r->r.version().equals("1.0.12")&&r.size()==-1&&r.sha256().isEmpty()));
        rejects("schema3 invalid shared version",()->ReleaseManifest.parse(minimal.replace("1.0.12","1.0.x").getBytes()));
        rejects("schema3 no version cannot claim current",()->ReleaseManifest.parse(minimal.replace("\"version\":\"1.0.12\",","").getBytes()));
        for(String bad:java.util.List.of("http://ahakey.com/a.exe","https://other.tcb.qcloud.la/a.exe","https://ahakey.com.evil.example/a.exe","https://user@ahakey.com/a.exe","https://ahakey.com:444/a.exe","https://ahakey.com/a.exe#fragment"))rejects("schema3 rejects unsafe URL",()->ReleaseManifestClient.requireAllowedUrl(java.net.URI.create(bad)));
        var closes=new AtomicInteger();var hops=new java.util.ArrayList<java.net.URI>();
        var following=ReleaseManifestClient.redirecting(uri->{hops.add(uri);int hop=hops.size();return new ReleaseManifestClient.HopResponse(hop<3?302:200,1,new ByteArrayInputStream(new byte[]{1}){@Override public void close(){closes.incrementAndGet();}},hop==1?cloud:hop==2?"/final.exe?token=fixture-secret":null);});
        try(var response=following.get(java.net.URI.create("https://ahakey.com/package.exe"))){check("exact allowed HTTPS redirects followed and query retained for request",response.status()==200&&hops.size()==3&&hops.get(2).getQuery().contains("fixture-secret"));}check("redirect bodies closed",closes.get()==3);
        rejects("stable manifest never redirects",()->ReleaseManifestClient.redirecting(uri->new ReleaseManifestClient.HopResponse(302,0,new ByteArrayInputStream(new byte[0]),cloud)).get(ReleaseManifestClient.STABLE));
        AtomicInteger requests=new AtomicInteger();var unsafe=ReleaseManifestClient.redirecting(uri->{requests.incrementAndGet();return new ReleaseManifestClient.HopResponse(302,0,new ByteArrayInputStream(new byte[0]),"http://ahakey.com/final.exe");});rejects("redirect downgrade rejected before next request",()->unsafe.get(java.net.URI.create(cloud)));check("unsafe next hop never requested",requests.get()==1);
        requests.set(0);var loop=ReleaseManifestClient.redirecting(uri->{requests.incrementAndGet();return new ReleaseManifestClient.HopResponse(302,0,new ByteArrayInputStream(new byte[0]),"/loop.exe");});rejects("redirect count bounded",()->loop.get(java.net.URI.create(cloud)));check("only four requests across three redirects",requests.get()==4);
        byte[] bytes="fixture signed-download bytes".getBytes();Path dir=root.resolve("schema3-download");
        Path file=new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,-1,new ByteArrayInputStream(bytes))).fetch(java.net.URI.create(cloud),-1,"",dir,".exe",n->{});check("schema3 streams unknown transport length",Files.size(file)==bytes.length);
        rejects("advertised package above local 2GiB cap",()->new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,ReleaseSignature.MAX_FILE+1,new ByteArrayInputStream(bytes))).fetch(java.net.URI.create(cloud),-1,"",dir,".exe",n->{}));
        rejects("schema3 transport truncation",()->new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,bytes.length+1,new ByteArrayInputStream(bytes))).fetch(java.net.URI.create(cloud),-1,"",dir,".exe",n->{}));
        rejects("firmware cannot use unsigned-length software exception",()->new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,-1,new ByteArrayInputStream(bytes))).fetch(java.net.URI.create(cloud),-1,"",dir,".hex",n->{}));
        var firmware=new com.example.ahakey.firmware.FirmwareUpdateChecks.Fixture();var ble=new com.example.ahakey.firmware.DeviceMaintenanceChecks.FixtureBle();
        byte[] onlyLite=minimal.replace("\"local-model\":{\"url\":\""+cloud+"\"},","").getBytes();
        var missing=new UpdateCenterService(ble,firmware.service,root.resolve("missing-variant"),app(),new ReleaseManifestClient(uri->new ReleaseManifestClient.Response(200,onlyLite.length,new ByteArrayInputStream(onlyLite))));missing.check();awaitIdle(missing);check("missing current variant never downloads other variant",missing.view().state()==UpdateCenterService.State.NO_VARIANT);missing.close();
        var failure=new UpdateCenterService(ble,firmware.service,root.resolve("redacted-error"),app(),new ReleaseManifestClient(uri->{throw new IOException("network "+cloud); }));failure.check();awaitIdle(failure);check("network failure unavailable and signed URL token redacted",failure.view().state()==UpdateCenterService.State.UNAVAILABLE&&!failure.view().detail().contains("fixture-secret"));failure.close();
    }
    private static void receiptVisibility(Path root)throws Exception{
        var json=new com.fasterxml.jackson.databind.ObjectMapper();
        for(String state:new String[]{"installed-unconfirmed","cancelled","installer-failed","reboot-required"}){
            Path serviceRoot=root.resolve("receipt-"+state);Path receipt=Files.createDirectories(serviceRoot.resolve("installations").resolve("one"));Path request=receipt.resolve("request.json");
            json.writeValue(request.toFile(),java.util.Map.of("operationId",state,"version",app().version(),"variant",app().variant(),"productId",app().productId(),"upgradeCode",app().upgradeCode(),"arch",app().arch()));
            json.writeValue(receipt.resolve("receipt.json").toFile(),java.util.Map.of("operationId",state,"requestHash",VerifiedDownload.sha256(request),"state",state,"exitCode",state.equals("installed-unconfirmed")?0:state.equals("reboot-required")?3010:1602));
            var service=new UpdateCenterService(new com.example.ahakey.firmware.DeviceMaintenanceChecks.FixtureBle(),new com.example.ahakey.firmware.FirmwareUpdateChecks.Fixture().service,serviceRoot,app(),new ReleaseManifestClient(uri->new ReleaseManifestClient.Response(404,0,new ByteArrayInputStream(new byte[0]))));
            service.check();awaitIdle(service);String visible=service.installationResult();
            check("receipt survives real unavailable state "+state,service.view().state()==UpdateCenterService.State.UNAVAILABLE&&visible.contains(state)&&!visible.startsWith("重启已确认"));
            service.check();awaitIdle(service);check("receipt stays visible after next check "+state,service.installationResult().equals(visible));service.close();
        }
        for(int code:new int[]{3010,1641}){
            Path serviceRoot=root.resolve("confirmed-reboot-"+code),receipt=Files.createDirectories(serviceRoot.resolve("installations").resolve("one")),request=receipt.resolve("request.json");
            json.writeValue(request.toFile(),java.util.Map.of("operationId","reboot","version",app().version(),"variant",app().variant(),"productId",app().productId(),"upgradeCode",app().upgradeCode(),"arch",app().arch()));
            json.writeValue(receipt.resolve("receipt.json").toFile(),java.util.Map.of("operationId","reboot","requestHash",VerifiedDownload.sha256(request),"state",code==3010?"reboot-required":"reboot-initiated","exitCode",code,"bootIdBefore","638966000000000000"));
            WindowsUpdateInstaller.reconcileReceipts(serviceRoot.resolve("installations"),app(),()->"638966100000000000");
            var service=new UpdateCenterService(new com.example.ahakey.firmware.DeviceMaintenanceChecks.FixtureBle(),new com.example.ahakey.firmware.FirmwareUpdateChecks.Fixture().service,serviceRoot,app(),new ReleaseManifestClient(uri->new ReleaseManifestClient.Response(404,0,new ByteArrayInputStream(new byte[0]))));
            service.check();awaitIdle(service);service.check();awaitIdle(service);
            check("legacy reboot receipt remains unconfirmed with 404 "+code,service.view().state()==UpdateCenterService.State.UNAVAILABLE&&!service.installationResult().startsWith("重启已确认")&&service.installationResult().contains("尚未"));service.close();
        }
    }
    public static void awaitIdle(UpdateCenterService service)throws Exception{
        long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);
        while(service.busy()&&System.nanoTime()<end)Thread.sleep(5);
        check("service settled",!service.busy());
    }
    private static void serviceFlow(Path root,byte[] payload,String hash,byte[] manifest)throws Exception{
        var ble=new com.example.ahakey.firmware.DeviceMaintenanceChecks.FixtureBle();
        var firmware=new com.example.ahakey.firmware.FirmwareUpdateChecks.Fixture();
        AtomicInteger fetches=new AtomicInteger(),downloads=new AtomicInteger(),exits=new AtomicInteger();
        var client=new ReleaseManifestClient(uri->{fetches.incrementAndGet();return new ReleaseManifestClient.Response(200,manifest.length,new ByteArrayInputStream(manifest));});
        String cert="a".repeat(64);
        var trust=new InstallerTrustPolicy(java.util.Map.of("test-only",java.util.Set.of(cert)),p->new InstallerTrustPolicy.Evidence("Valid",cert,"AhaKeyStudio","1.0.11",InstalledAppIdentity.UPGRADE_CODE,"local-model","x64","{11111111-1111-1111-1111-111111111111}","c".repeat(64),"a".repeat(64)));
        var dependencies=new UpdateCenterService.Dependencies(()->new VerifiedDownload(uri->{downloads.incrementAndGet();return new ReleaseManifestClient.Response(200,-1,new ByteArrayInputStream(payload));}),p->trust,
                new WindowsUpdateInstaller((command,log)->{throw new IOException("fixture worker could not start");},(entry,work)->new WindowsInstalledApplication.Snapshot("{22222222-2222-4222-8222-222222222222}",app().upgradeCode(),app().version(),app().variant(),app().arch(),entry.getParent().toString(),entry.toString(),app().buildId(),"c".repeat(64),4)));
        Path serviceRoot=root.resolve("service");Files.createDirectories(serviceRoot);
        var service=new UpdateCenterService(ble,firmware.service,serviceRoot,app(),client,dependencies);service.setExitHandler(op->exits.incrementAndGet());
        service.startup();service.startup();awaitIdle(service);check("startup checks info once without downloading",fetches.get()==1&&downloads.get()==0&&service.view().state()==UpdateCenterService.State.AVAILABLE);
        service.downloadSoftware();awaitIdle(service);check("actual service download trust ready",downloads.get()==1&&service.view().state()==UpdateCenterService.State.READY);
        Path launcher=root.resolve("AhaKeyStudio.exe");Files.writeString(launcher,"not executable");System.setProperty("jpackage.app-path",launcher.toString());
        service.installConfirmed();awaitIdle(service);check("worker failure leaves app running and gate released",exits.get()==0&&!ble.maintenance().active()&&service.view().state()==UpdateCenterService.State.FAILED);
        service.check();awaitIdle(service);check("new check after failure",fetches.get()==2&&service.view().state()==UpdateCenterService.State.AVAILABLE);
        Path receiptDir=Files.createDirectories(serviceRoot.resolve("installations").resolve("fixture-completed"));var json=new com.fasterxml.jackson.databind.ObjectMapper();Path request=receiptDir.resolve("request.json");
        json.writeValue(request.toFile(),java.util.Map.of("operationId","receipt-fixture","version",app().version(),"variant",app().variant(),"productId",app().productId(),"upgradeCode",app().upgradeCode(),"arch",app().arch()));
        json.writeValue(receiptDir.resolve("receipt.json").toFile(),java.util.Map.of("operationId","receipt-fixture","requestHash",VerifiedDownload.sha256(request),"state","installed-unconfirmed","exitCode",0));
        service.check();awaitIdle(service);service.check();awaitIdle(service);check("restart receipt never blocks future catalog checks",fetches.get()==4&&service.view().state()==UpdateCenterService.State.AVAILABLE);service.close();
        CountDownLatch read=new CountDownLatch(1),cancelled=new CountDownLatch(1);
        var blocking=new UpdateCenterService.Dependencies(()->new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,-1,new InputStream(){public int read()throws IOException{read.countDown();try{cancelled.await();}catch(InterruptedException e){throw new IOException(e);}throw new IOException("closed");}public void close(){cancelled.countDown();}})),p->trust,dependencies.installer());
        var cancelService=new UpdateCenterService(ble,firmware.service,root.resolve("cancel-service"),app(),client,blocking);cancelService.check();awaitIdle(cancelService);cancelService.downloadSoftware();check("service reached download",read.await(2,TimeUnit.SECONDS));
        check("close cancels instead of background exit",!cancelService.requestClose(null));awaitIdle(cancelService);check("service cancellation stops download",!cancelService.downloading()&&cancelled.getCount()==0);cancelService.close();
    }
}
