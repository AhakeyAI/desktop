package com.example.ahakey.firmware;

import java.nio.file.*;
import static com.example.ahakey.update.UpdateCenterChecks.*;
public final class WchAdapterChecks {
    public static void main(String[] args)throws Exception{
        if(args.length>0 && args[0].equals("--terminal")) { terminalChecks(args); return; }
        String terminal="Status=Finished\nCode=0\nMessage=Succeed";
        check("complete terminal and exit",WchFlashAdapter.terminalSuccess(terminal,0));
        check("exit alone insufficient",!WchFlashAdapter.terminalSuccess("",0));
        check("conflicting exit",!WchFlashAdapter.terminalSuccess(terminal,13));
        check("failure wins",!WchFlashAdapter.terminalSuccess("Error\n"+terminal,0));
        check("nonzero terminal wins",!WchFlashAdapter.terminalSuccess("Code=14\n"+terminal,0));
        check("incomplete terminal",!WchFlashAdapter.terminalSuccess("Finished Code=0 Succeed",0));
        String ini=WchFlashAdapter.configuration(Path.of("C:/temporary fixture/firmware.hex"));
        check("double erase exact 3.9 section",ini.contains("[CH57x-58xUICfg]")&&ini.contains("IsEraseAllCFlash=1")&&ini.contains("IsClearDataFlash=1"));
        check("only code file no datafile",ini.contains("DataFlashFileSel=0")&&ini.contains("IsUserFile1Sel=1")&&ini.contains("IsUserFile5Sel=0"));
        check("no automatic reset",ini.contains("IsAfterDownRest=0"));
        rejects("injected INI path",()->WchFlashAdapter.configuration(Path.of("evil\nIsClearDataFlash=0")));
        rejects("missing runtime",()->new WchRuntimeLocator().locate(Files.createTempDirectory("empty-wch-")));
        IntelHexValidator.validate(":0100000001FE\n:00000001FF\n");check("valid tiny HEX",true);
        for(String text:new String[]{":0100000001FF\n:00000001FF",":0100000001FE",":0100000001FE\n:0100000001FE\n:00000001FF",":020000040007F3\n:0100000001FE\n:00000001FF",":00000001FF",":0100000001FE\n:00000001FF\n:00000001FF"})rejects("HEX corruption/overlap/bounds/EOF "+text.hashCode(),()->IntelHexValidator.validate(text));
        try(var input=WchAdapterChecks.class.getResourceAsStream("/firmware/"+FirmwareCatalog.HEX_NAME)){Path hex=Files.createTempFile("builtin-",".hex");Files.copy(input,hex,StandardCopyOption.REPLACE_EXISTING);var result=IntelHexValidator.validate(hex);check("pinned real HEX static validation",result.bytes()==458492&&result.lastAddress()==458491);}
        if(args.length>0)for(String mode:new String[]{"download","verify"}){
            Path dir=Path.of(args[0]).resolve(mode);
            var result=new com.fasterxml.jackson.databind.ObjectMapper().readTree(dir.resolve("result.json").toFile());
            String console=Files.readString(dir.resolve("console.txt")),stdout=Files.readString(dir.resolve("stdout.txt")),stderr=Files.readString(dir.resolve("stderr.txt"));
            check("actual hidden-console GUI fixture captured "+mode,result.path("started").asBoolean()&&result.path("ended").asBoolean()&&console.contains("Status=Finished")&&stdout.contains("fixture stdout")&&stderr.contains("fixture diagnostic"));
            check("actual terminal and OS exit reconciled "+mode,WchFlashAdapter.terminalSuccess(console+stdout+stderr,result.path("exitCode").asInt())==mode.equals("download"));
        }
        System.out.println("PASS WCH/HEX checks; no vendor executable started");
    }

    private static void terminalChecks(String[] args)throws Exception {
        String good="{\"Device\":\"CH582\",\"Status\":\"Finished\",\"Code\":0,\"Message\":\"Succeed\"}";
        check("actual quoted JSON terminal",WchFlashAdapter.terminalSuccess(good,0));
        check("JSON order independent",WchFlashAdapter.terminalSuccess("{\"Message\":\"Succeed\",\"Code\":0,\"Status\":\"Finished\"}",0));
        check("prefix and actual non-JSON progress",WchFlashAdapter.terminalSuccess("CFG FILE PATH: C:\\fixture\\operation.ini "
                +"{\"Device\":\"CH582\",\"Status\":\"Programming\",\"Progress\":100%}"+good,0));
        check("repeated captured terminal",WchFlashAdapter.terminalSuccess(good+good,0));
        check("pinned vendor Verifing percentage template",WchFlashAdapter.terminalSuccess(
                "{\"Device\":\"CH582\",\"Status\":\"Verifing\",\"Progress\":0%}"
                +"{\"Device\":\"CH582\",\"Status\":\"Verifing\",\"Progress\":100%}"+good,0));
        check("bracketed console prefix",WchFlashAdapter.terminalSuccess("[WCH] "+good,0));
        check("escaped braces remain in string",WchFlashAdapter.terminalSuccess("{\"Status\":\"Reading {chip} \\\"info\\\"\"}"+good,0));
        String[] invalid={"", "Succeed", "Progress:100%", good.replace("Finished","Finishing"),
            good.replace("Succeed","Not Succeed"), good.replace("CH582","CH583"),
            good.replace("\"Code\":0,",""), good.replace("\"Message\":\"Succeed\"","\"other\":\"Succeed\""),
            good.replace("\"Status\":\"Finished\",",""), good.replace("\"Code\":0","\"Code\":\"0\""),
            good.replace("\"Code\":0","\"Code\":0.0"), good.replace("\"Code\":0","\"Code\":false"),
            good.replace("\"Code\":0","\"Code\":null"), good.replace("\"Code\":0","\"Code\":-1"),
            good.replace("\"Code\":0","\"Code\":4294967296"), good.replace("\"Code\":0","\"Code\":14"),
            good.replace("\"Status\":\"Finished\"","\"Status\":true"),
            good.replace("\"Message\":\"Succeed\"","\"Message\":[\"Succeed\"]"),
            good.replace("\"Device\":\"CH582\"","\"Device\":null"),
            good.replace("\"Code\":0","\"Code\":1,\"Code\":0"),
            good.replace("\"Code\":0","\"Code\":0,\"Code\":0"),
            "{\"wrapper\":"+good+"}", "["+good+"]", "{\"Status\":\"Finished\"}{\"Code\":0,\"Message\":\"Succeed\"}",
            "{Status=Finished Code=0 Message=Succeed}", "\"Status=Finished Code=0 Message=Succeed\"",
            new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(good),
            good.substring(0,good.length()-1),good.replace(",\"Code\""," \"Code\""),
            "{\"Device\":\"CH582\",\"Status\":\"Programming\",\"Progress\":100%,\"Code\":14}"};
        for(int i=0;i<invalid.length;i++)check("reject malformed/fake terminal "+i,!WchFlashAdapter.terminalSuccess(invalid[i],0));
        for(String conflict:new String[]{"Error", "Clear DataFlash Timeout...", "Write DataFlash Timeout...", "Code=-1", "Code=14", "{\"Code\":14}",
                good.replace("\"Code\":0","\"Code\":1"),good.replace("Succeed","Failed"),
                "{\"Status\":\"Finished\"}","{\"Status\":\"Finished\",\"Code\":0,\"Message\":\"Succeed\",}",
                "{\"outer\":"+good+"}","{\"code\":14}","{\"Status\":\"Programming\",\"Progress\":100%,\"Code\":0}",
                "{\"Status\":\"\\u0045rror\"}","{\"Status\":\"Programming\",\"Progress\":101%}"}) {
            check("conflict before success "+conflict,!WchFlashAdapter.terminalSuccess(conflict+"\n"+good,0));
            check("conflict after success "+conflict,!WchFlashAdapter.terminalSuccess(good+"\n"+conflict,0));
        }
        check("nonzero exit still fails",!WchFlashAdapter.terminalSuccess(good,1));
        for(int i=1;i<args.length;i++) {
            Path directory=Path.of(args[i]);
            var replay=WchFlashAdapter.readResult(directory,false);
            check("real captured download "+directory,replay.success()&&!replay.processAlive()&&!replay.timedOut()&&replay.exitCode()==0);
        }
        Path dir=Files.createTempDirectory("wch-result-only-");
        try {
            Files.writeString(dir.resolve("operation.id"),"fixture-operation");
            Files.writeString(dir.resolve("console.txt"),good);
            String receipt="{\"operationId\":\"fixture-operation\",\"ended\":true,\"failed\":false,\"exitCode\":0}";
            Files.writeString(dir.resolve("result.json"),receipt);
            check("receipt reconciles terminal",WchFlashAdapter.readResult(dir,false).success());
            check("timeout wins",!WchFlashAdapter.readResult(dir,true).success());
            check("expected operation mismatch",!WchFlashAdapter.readResult(dir,false,"other").success());
            for(String changed:new String[]{receipt.replace("fixture-operation","other"),receipt.replace("\"ended\":true","\"ended\":false"),
                    receipt.replace("\"failed\":false","\"failed\":true"),receipt.replace("\"exitCode\":0","\"exitCode\":3")}) {
                Files.writeString(dir.resolve("result.json"),changed);
                check("receipt guard "+changed,!WchFlashAdapter.readResult(dir,false).success());
            }
            Files.writeString(dir.resolve("result.json"),receipt);
            Files.writeString(dir.resolve("stderr.txt"),"Error: unsuccessful operation");
            check("stderr overrides successful console",!WchFlashAdapter.readResult(dir,false).success());
            Files.delete(dir.resolve("result.json"));
            check("missing receipt cannot release",WchFlashAdapter.readResult(dir,false).processAlive());
        } finally {
            try(var files=Files.list(dir)){for(Path file:files.toList())Files.delete(file);}Files.delete(dir);
        }
        System.out.println("PASS terminal/receipt checks="+com.example.ahakey.update.UpdateCenterChecks.checks+"; no vendor executable or device access");
    }
}
