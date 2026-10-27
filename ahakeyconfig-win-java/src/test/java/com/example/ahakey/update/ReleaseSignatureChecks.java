package com.example.ahakey.update;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.interfaces.RSAPublicKey;
import java.util.*;
import java.util.concurrent.TimeUnit;
import static com.example.ahakey.update.UpdateCenterChecks.*;

public final class ReleaseSignatureChecks {
    static byte[] envelope(byte[] prefix,byte[] payload,byte[] signature) {
        return ByteBuffer.allocate(prefix.length+payload.length+400).order(ByteOrder.LITTLE_ENDIAN).put(prefix).put(payload).put(signature)
                .put("AHAKEND1".getBytes(StandardCharsets.US_ASCII)).putInt(payload.length).putInt(1).array();
    }
    public static void main(String[] args)throws Exception {
        Path out=Path.of(args[0]);Files.createDirectories(out);var json=new ObjectMapper();
        var vector=json.readTree(Path.of(".ahakey-desktop-harness/changes/WD-006/R9_RELEASE_SIGNATURE_VECTOR_20261024.json").toFile());
        byte[] prefix=Base64.getDecoder().decode(vector.path("prefix").asText()),payload=Base64.getDecoder().decode(vector.path("payload").asText()),sig=Base64.getDecoder().decode(vector.path("signature").asText());
        var verifier=new ReleaseSignature(ReleaseSignature.publicKey(vector.path("modulus").asText(),vector.path("exponent").asText()));
        Path dotnet=out.resolve("dotnet-vector.exe");byte[] original=envelope(prefix,payload,sig);Files.write(dotnet,original);
        check("Java verifies actual .NET RSA3072 vector",verifier.verify(dotnet).version().equals("1.0.12"));
        for(String kind:List.of("prefix","signature","footer","extra","truncated","overflow","payload")){
            byte[] bad=original.clone();switch(kind){case "prefix"->bad[4]^=1;case "signature"->bad[bad.length-20]^=1;case "footer"->bad[bad.length-16]^=1;case "extra"->bad=Arrays.copyOf(bad,bad.length+1);case "truncated"->bad=Arrays.copyOf(bad,bad.length-1);case "overflow"->{Arrays.fill(bad,bad.length-8,bad.length-4,(byte)255);}case "payload"->bad[prefix.length+50]^=1;}
            Path file=out.resolve(kind+".exe");Files.write(file,bad);rejects("reject "+kind,()->verifier.verify(file));
        }
        var generator=KeyPairGenerator.getInstance("RSA");generator.initialize(3072);var keys=generator.generateKeyPair();
        var sign=Signature.getInstance("SHA256withRSA");sign.initSign(keys.getPrivate());sign.update(payload);
        Path javaFile=out.resolve("java-vector.exe");Files.write(javaFile,envelope(prefix,payload,sign.sign()));
        rejects("wrong key rejected",()->verifier.verify(javaFile));
        var javaVerifier=new ReleaseSignature(keys.getPublic());check("Java own signature",javaVerifier.verify(javaFile).prefixLength()==prefix.length);
        var actual=javaVerifier.verify(javaFile);
        var app=new InstalledAppIdentity("1.0.11","local-model","x64",InstalledAppIdentity.PRODUCT,InstalledAppIdentity.UPGRADE_CODE,"fixture",true);
        var release=new ReleaseManifest.WindowsRelease("local-model","1.0.12","x64","jpackage-exe",java.net.URI.create("https://ahakey.com/test.exe"),-1,"",InstalledAppIdentity.PRODUCT,InstalledAppIdentity.UPGRADE_CODE,"release-rsa3072-v1");
        var trust=new InstallerTrustPolicy(javaVerifier,p->new InstallerTrustPolicy.Evidence("MetadataOnly","",actual.productId(),actual.version(),actual.upgradeCode(),actual.variant(),actual.arch(),actual.productCode()));
        check("signed software does not require Owner certificate",trust.verify(javaFile,release,app).version().equals("1.0.12"));
        var wrongMsi=new InstallerTrustPolicy(javaVerifier,p->new InstallerTrustPolicy.Evidence("Valid","",actual.productId(),"1.0.13",actual.upgradeCode(),actual.variant(),actual.arch(),actual.productCode()));
        rejects("signed envelope cannot override real MSI",()->wrongMsi.verify(javaFile,release,app));
        for(String field:List.of("version","variant","arch","product","upgrade","productCode")) {
            var wrong=new InstallerTrustPolicy(javaVerifier,p->new InstallerTrustPolicy.Evidence("NotSigned","",field.equals("product")?"Other":actual.productId(),field.equals("version")?"1.0.13":actual.version(),field.equals("upgrade")?"{11111111-1111-1111-1111-111111111111}":actual.upgradeCode(),field.equals("variant")?"lite":actual.variant(),field.equals("arch")?"arm64":actual.arch(),field.equals("productCode")?"{22222222-2222-2222-2222-222222222222}":actual.productCode()));
            rejects("signed package rejects actual MSI mismatch "+field,()->wrong.verify(javaFile,release,app));
        }
        List<String> workerNegatives=new ArrayList<>();
        byte[] javaBytes=Files.readAllBytes(javaFile);
        for(String kind:List.of("prefix","signature","extra","truncated","overflow","footer")) {
            byte[] bad=javaBytes.clone();switch(kind){case "prefix"->bad[4]^=1;case "signature"->bad[bad.length-20]^=1;case "extra"->bad=Arrays.copyOf(bad,bad.length+1);case "truncated"->bad=Arrays.copyOf(bad,bad.length-1);case "overflow"->Arrays.fill(bad,bad.length-8,bad.length-4,(byte)255);case "footer"->bad[bad.length-16]^=1;}
            Path file=out.resolve("worker-bad-"+kind+".exe");Files.write(file,bad);workerNegatives.add(file.toAbsolutePath().toString());
        }
        RSAPublicKey pub=(RSAPublicKey)keys.getPublic();byte[] modulus=pub.getModulus().toByteArray();if(modulus[0]==0)modulus=Arrays.copyOfRange(modulus,1,modulus.length);
        Path data=out.resolve("interop.json");json.writeValue(data.toFile(),Map.of("modulus",Base64.getEncoder().encodeToString(modulus),"exponent","AQAB","file",javaFile.toAbsolutePath().toString(),"worker",Path.of("src/main/resources/update/windows-update-worker.ps1").toAbsolutePath().toString(),"badFiles",workerNegatives));
        Path script=out.resolve("interop.ps1");Files.writeString(script,"""
                param([string]$Data)
                $ErrorActionPreference='Stop'
                if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Expected Windows PowerShell 5.1' }
                $q=Get-Content -LiteralPath $Data -Raw -Encoding UTF8|ConvertFrom-Json
                $worker=[IO.File]::ReadAllText($q.worker)
                $start=$worker.IndexOf("Add-Type -TypeDefinition @'")+27
                $end=$worker.IndexOf("'@",$start)
                Add-Type -TypeDefinition $worker.Substring($start,$end-$start)
                $identity=[AhaReleaseSignature]::VerifyWithKey($q.file,$q.modulus,$q.exponent)
                if($identity.version -cne '1.0.12'){throw 'Wrong identity'}
                $rejected=$false
                try{[void][AhaReleaseSignature]::Verify($q.file)}catch{$rejected=$true}
                if(-not $rejected){throw 'Production key accepted test signature'}
                foreach($bad in $q.badFiles){$rejected=$false;try{[void][AhaReleaseSignature]::VerifyWithKey($bad,$q.modulus,$q.exponent)}catch{$rejected=$true};if(-not $rejected){throw 'Worker accepted damaged envelope'};Write-Output ('PASS actual worker rejects '+[IO.Path]::GetFileName($bad))}
                Write-Output 'PASS actual worker .NET verifier accepts Java vector and rejects it under fixed production key; Windows PowerShell 5.1'
                """,StandardCharsets.UTF_8);
        Process process=new ProcessBuilder(WindowsUpdateInstaller.powershell(),"-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",script.toAbsolutePath().toString(),"-Data",data.toAbsolutePath().toString()).redirectErrorStream(true).redirectOutput(out.resolve("worker-interop.log").toFile()).start();
        check("actual PS5 worker completes",process.waitFor(30,TimeUnit.SECONDS));check("actual PS5 worker verifies Java signature",process.exitValue()==0);
        byte[] minimal=("{\"schema\":3,\"channel\":\"stable\",\"version\":\"1.0.12\",\"windows\":{\"local-model\":{\"url\":\"https://ahakey.com/fixture.exe\"}}}").getBytes(StandardCharsets.UTF_8);
        var ble=new com.example.ahakey.firmware.DeviceMaintenanceChecks.FixtureBle();var fixture=new com.example.ahakey.firmware.FirmwareUpdateChecks.Fixture();
        var service=new UpdateCenterService(ble,fixture.service,out.resolve("schema3-flow"),app,new ReleaseManifestClient(uri->new ReleaseManifestClient.Response(200,minimal.length,new java.io.ByteArrayInputStream(minimal))),
                new UpdateCenterService.Dependencies(()->new VerifiedDownload(uri->new ReleaseManifestClient.Response(200,-1,new java.io.ByteArrayInputStream(javaBytes))),p->trust,new WindowsUpdateInstaller((command,log)->{throw new AssertionError("Tampered installer must not start worker");})));
        service.check();awaitIdle(service);check("actual schema3 service reports target version",service.view().state()==UpdateCenterService.State.AVAILABLE&&service.view().version().equals("1.0.12"));
        service.downloadSoftware();awaitIdle(service);check("actual service downloads and verifies signed schema3 package",service.view().state()==UpdateCenterService.State.READY);
        Path cached;try(var files=Files.list(out.resolve("schema3-flow/downloads"))){cached=files.filter(p->p.toString().endsWith(".exe")).findFirst().orElseThrow();}byte[] tampered=Files.readAllBytes(cached);tampered[4]^=1;Files.write(cached,tampered);
        service.installConfirmed();awaitIdle(service);check("changed cache fails revalidation before worker and application exit",service.view().state()==UpdateCenterService.State.FAILED&&!ble.maintenance().active());service.close();
        if(args.length>1) {
            Path historical=Path.of(args[1]);String before=VerifiedDownload.sha256(historical);var evidence=WindowsUpdateInstaller.inspect(historical,out);
            check("actual PowerShell MSI inspection JSON deserializes strictly in Java",evidence.productName().equals("AhaKeyStudio")&&evidence.msiSha256()!=null&&evidence.msiSha256().length()==64);
            check("read-only inspection preserves historical EXE bytes",VerifiedDownload.sha256(historical).equals(before));
            String unexpected=json.writeValueAsString(evidence).replaceFirst("\\{","{\"unexpected\":true,");rejects("unexpected worker JSON field still rejected",()->json.readValue(unexpected,InstallerTrustPolicy.Evidence.class));
        }
        System.out.println("PASS R9 release signature behavior and Java/.NET actual-worker interoperability; no installer execution");
    }
}
