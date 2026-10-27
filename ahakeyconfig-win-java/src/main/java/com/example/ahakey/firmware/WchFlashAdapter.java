package com.example.ahakey.firmware;

import com.example.ahakey.update.*;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

public final class WchFlashAdapter {
    public static final class NotStartedException extends IOException {
        public NotStartedException(Exception cause) { super("工具尚未启动：" + cause.getMessage(), cause); }
    }
    public record Result(boolean success, boolean timedOut, boolean processAlive, int exitCode, String output) {}
    @FunctionalInterface public interface Runner { Result run(WchRuntimeLocator.Runtime runtime, Path ini, Path hex, Path directory, String operation, Runnable timeout) throws Exception; }
    private final Runner runner;
    private volatile Path activeDirectory;
    private volatile java.util.function.BooleanSupplier cancelled=()->false;
    private DeviceMaintenanceCoordinator.Identity target;
    private final java.util.concurrent.ConcurrentMap<Path,String> operations=new java.util.concurrent.ConcurrentHashMap<>();
    public boolean cleanupConfirmed(Path directory) {String id=operations.get(directory);if(id==null)return false;boolean ended=!readResult(directory,true,id).processAlive();if(ended)operations.remove(directory,id);return ended;}
    public WchFlashAdapter() { this.runner=this::runWorker; }
    public WchFlashAdapter(Runner runner) { this.runner = runner; }
    public void requestExit() { Path current=activeDirectory;if(current!=null)try{Files.writeString(current.resolve("cancel.request"),"cancel");}catch(IOException ignored){} }
    public Result execute(WchRuntimeLocator.Runtime runtime, Path hex, String hash, Path directory, String operation, Runnable timeout) throws Exception {
        return execute(runtime,hex,hash,directory,operation,timeout,()->false);
    }
    public Result execute(WchRuntimeLocator.Runtime runtime, Path hex, String hash, Path directory, String operation, Runnable timeout,java.util.function.BooleanSupplier cancellation) throws Exception {
        return execute(runtime,hex,hash,directory,operation,timeout,cancellation,null);
    }
    public Result execute(WchRuntimeLocator.Runtime runtime,Path hex,String hash,Path directory,String operation,Runnable timeout,java.util.function.BooleanSupplier cancellation,DeviceMaintenanceCoordinator.Identity target)throws Exception {
        cancelled=cancellation;this.target=target;
        if (!Set.of("download", "verify").contains(operation)) throw new IOException("WCH 操作无效。");
        Path ini;String id=UUID.randomUUID().toString();
        try {
        checkCancelled();
        new WchRuntimeLocator().recheck(runtime);
        if (!VerifiedDownload.sha256(hex).equals(hash)) throw new IOException("冻结 HEX 已改变。");
        IntelHexValidator.validate(hex); Files.createDirectory(directory);activeDirectory=directory;checkCancelled();
        Path frozen=directory.resolve("firmware.hex");Files.copy(hex,frozen);if(!VerifiedDownload.sha256(frozen).equals(hash))throw new IOException("HEX复制期间改变");hex=frozen;
        runtime=new WchRuntimeLocator().copyForOperation(runtime,directory.resolve("runtime"));
        ini = directory.resolve("operation.ini"); Files.writeString(ini, configuration(hex), StandardCharsets.UTF_8);
        checkCancelled();
        Files.writeString(directory.resolve("operation.id"),id);operations.put(directory,id);
        } catch (Exception e) { activeDirectory=null;throw new NotStartedException(e); }
        try {Result result=runner.run(runtime,ini,hex,directory,operation,timeout);if(!result.processAlive())operations.remove(directory,id);return result;}
        catch(NotStartedException e){operations.remove(directory,id);throw e;}finally{activeDirectory=null;}
    }
    private void checkCancelled()throws IOException {if(cancelled.getAsBoolean()||(activeDirectory!=null&&Files.exists(activeDirectory.resolve("cancel.request"))))throw new IOException("本次链路已退出，工具未启动。");}
    private static final Pattern FAILURE = Pattern.compile("(?i)\\b(?:error|fail|failed|failure|exception|timeout)\\b|\\bCode\\s*[:=]\\s*-?[1-9][0-9]*\\b");
    private static final Pattern RESULT_FIELD = Pattern.compile("(?i)\\b(?:Status|Code|Message)\\b\\s*[:=]");
    private static final Pattern PLAIN_TERMINAL = Pattern.compile("(?is)\\bStatus\\s*[:=]\\s*Finished\\s*[,;\\r\\n ]+Code\\s*[:=]\\s*0\\s*[,;\\r\\n ]+Message\\s*[:=]\\s*Succeed\\b");
    // The vendor's percentage records are not JSON. Only this exact nonterminal shape is noise.
    private static final Pattern PERCENT_PROGRESS = Pattern.compile("\\{\\s*\"Device\"\\s*:\\s*\"CH582\"\\s*,\\s*\"Status\"\\s*:\\s*\"(?:Programming|Verifing)\"\\s*,\\s*\"Progress\"\\s*:\\s*(?:100|[1-9]?[0-9])%\\s*}");
    private static final ObjectMapper TERMINAL_JSON = new ObjectMapper()
            .enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION)
            .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);

    public static boolean terminalSuccess(String text, int exitCode) {
        if (text == null || text.length() > 6_100_000 || exitCode != 0 || FAILURE.matcher(text).find()) return false;
        boolean success = false, structured = false;
        StringBuilder outside = new StringBuilder();
        try {
            // Console capture can place several records on one line. Never combine their fields.
            for (int i = 0; i < text.length();) {
                char ch = text.charAt(i);
                if (ch == '"') {
                    int end = quotedEnd(text, i);
                    outside.append(text, i, end); i = end;
                } else if (ch == '{') {
                    structured = true;
                    int start = i++, depth = 1;
                    while (i < text.length() && depth > 0) {
                        ch = text.charAt(i);
                        if (ch == '"') i = quotedEnd(text, i);
                        else {
                            if (ch == '{') depth++;
                            if (ch == '}') depth--;
                            i++;
                        }
                    }
                    if (depth != 0) return false;
                    String record = text.substring(start, i);
                    if (PERCENT_PROGRESS.matcher(record).matches()) continue;
                    JsonNode node = TERMINAL_JSON.readTree(record);
                    if (!node.isObject()) return false;
                    for (JsonNode value : node) if (value.isContainerNode()) return false;
                    for (var names = node.fieldNames(); names.hasNext();) {
                        String name = names.next();
                        for (String reserved : List.of("Device", "Status", "Code", "Message"))
                            if (reserved.equalsIgnoreCase(name) && !reserved.equals(name)) return false;
                    }
                    if (FAILURE.matcher(node.toString()).find()) return false;
                    if (node.has("Status") && !node.get("Status").isTextual()) return false;
                    if (node.has("Code") || node.has("Message") || "Finished".equalsIgnoreCase(node.path("Status").asText())) {
                        if (!"Finished".equals(node.path("Status").textValue())
                                || !node.path("Code").isIntegralNumber() || node.path("Code").bigIntegerValue().signum() != 0
                                || !"Succeed".equals(node.path("Message").textValue())
                                || (node.has("Device") && !"CH582".equals(node.get("Device").textValue()))) return false;
                        success = true;
                    }
                    outside.append('\n');
                } else {
                    // Arrays/nested wrappers must not expose an inner object as a top-level result.
                    if (ch == '[') {
                        int end = text.indexOf(']', i + 1);
                        if (end < 0) return false;
                        String prefix = text.substring(i, end + 1);
                        if (prefix.indexOf('{') >= 0 || prefix.indexOf('"') >= 0 || prefix.indexOf('[', 1) >= 0) return false;
                        outside.append(prefix); i = end + 1; continue;
                    }
                    if (ch == ']' || ch == '}') return false;
                    outside.append(ch); i++;
                }
            }
        } catch (IOException e) { return false; }
        String plain = outside.toString();
        if (structured) return success && plain.indexOf('"') < 0 && plain.indexOf('\'') < 0 && !RESULT_FIELD.matcher(plain).find();
        // Retain the historical plain-text fixture format, but not quoted or split records.
        if (plain.indexOf('"') >= 0 || plain.indexOf('\'') >= 0) return false;
        var terminal = PLAIN_TERMINAL.matcher(plain);
        if (!terminal.find()) return false;
        return !RESULT_FIELD.matcher(plain.substring(0, terminal.start()) + "\n" + plain.substring(terminal.end())).find();
    }

    private static int quotedEnd(String text, int start) throws IOException {
        for (int i = start + 1; i < text.length(); i++) {
            char ch = text.charAt(i);
            if (ch == '\\') i++;
            else if (ch == '"') return i + 1;
        }
        throw new IOException("WCH 记录包含未结束的字符串。");
    }
    public static String configuration(Path hex) throws IOException {
        String path = hex.toAbsolutePath().toString(); if (path.contains("\n") || path.contains("\r") || path.contains("\"")) throw new IOException("HEX 路径无效。");
        return """
                [Public]
                MCUName=CH582
                bMCULine=6
                bMCUType=130
                DataFlashFile=.
                swzUserFile1=%s
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
                """.formatted(path);
    }
    private Result runWorker(WchRuntimeLocator.Runtime runtime, Path ini, Path hex, Path directory, String operation, Runnable timeout) throws Exception {
        Process worker;
        try {
        Path script = directory.resolve("wch-capture-worker.ps1");
        try (var in = WchFlashAdapter.class.getResourceAsStream("/firmware/wch-capture-worker.ps1")) { if (in == null) throw new IOException("WCH 捕获资源缺失。"); Files.copy(in, script); }
        var json = new ObjectMapper(); Path request = directory.resolve("request.json");
        Map<String,Object> input=new LinkedHashMap<>();
        if(target==null||target.port().isBlank()||!target.devicePath().toUpperCase(Locale.ROOT).startsWith("USB\\VID_4348&PID_55E0\\"))throw new IOException("缺少本次冻结下载目标身份。");
        input.put("bootInstance",target.devicePath());input.put("bootPort",target.port());
        String operationId=operations.get(directory);if(operationId==null)throw new IOException("操作身份缺失");input.put("operationId",operationId);
        input.put("tool",runtime.executable().toString());input.put("work",runtime.directory().toString());input.put("ini",ini.toString());input.put("hex",hex.toString());input.put("operation",operation);input.put("directory",directory.toString());
        input.put("hexHash",VerifiedDownload.sha256(hex));input.put("iniHash",VerifiedDownload.sha256(ini));input.put("parentPid",ProcessHandle.current().pid());input.put("parentStart",ProcessHandle.current().info().startInstant().orElseThrow().toEpochMilli());input.put("launchDeadline",System.currentTimeMillis()+60_000);
        json.writeValue(request.toFile(),input);activeDirectory=directory;
        checkCancelled();
        worker = new ProcessBuilder(WindowsUpdateInstaller.powershell(), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script.toString(), "-Mode", "Launch", "-Request", request.toString())
                .redirectErrorStream(true).redirectOutput(directory.resolve("worker.log").toFile()).start();
        } catch (Exception e) { throw new NotStartedException(e); }
        var json = new ObjectMapper();
        boolean timedOut=false;
        try {
            // Elevated supervisor owns its Job and enforces its own deadline; low integrity never kills elevated PIDs.
            long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(240);
            while(System.nanoTime()<end&&!Files.isRegularFile(directory.resolve("result.json"))&&worker.isAlive()){if(cancelled.getAsBoolean()){timedOut=true;requestExit();}Thread.sleep(100);}
            if(!Files.isRegularFile(directory.resolve("result.json"))){timedOut=true;requestExit();timeout.run();worker.waitFor(7,TimeUnit.SECONDS);}
        } finally {activeDirectory=null;}
        return readResult(directory,timedOut,operations.get(directory));
    }
    public static Result readResult(Path directory,boolean timedOut) {
        try{return readResult(directory,timedOut,Files.readString(directory.resolve("operation.id")));}catch(IOException e){return new Result(false,timedOut,true,-1,"工具操作身份不可确认。");}
    }
    public static Result readResult(Path directory,boolean timedOut,String expectedId) {
        boolean ended=false;
        try {
        var json=new ObjectMapper();Path receipt = directory.resolve("result.json");
        if (!Files.isRegularFile(receipt)) return new Result(false, timedOut, true, -1, "工具结果未知；无法证明子进程已结束。");
        if(Files.size(receipt)>65536)throw new IOException("工具回执超过上限");
        var result = json.readTree(receipt.toFile());
        if(expectedId==null||!expectedId.equals(Files.readString(directory.resolve("operation.id")))||!expectedId.equals(result.path("operationId").asText()))return new Result(false,true,true,-1,"工具回执不属于本次操作。");
        if (!result.path("ended").isBoolean()||!result.path("ended").asBoolean()) return new Result(false, timedOut, true, -1, "工具进程尚未结束。");
        ended=true;
        timedOut = timedOut || result.path("failed").asBoolean();
        String output = result.path("detail").asText("");
        for (String name : List.of("stdout.txt", "stderr.txt", "console.txt")) {
            Path file = directory.resolve(name); if (Files.exists(file)) {
                if(Files.size(file)>2_000_000)return new Result(false,timedOut,false, -1,"工具输出超过诊断上限，本次链路失败。");
                output += Files.readString(file, StandardCharsets.UTF_8) + "\n";
            }
        }
        int exit = result.path("exitCode").asInt(-1);
        return new Result(!timedOut && terminalSuccess(output, exit), timedOut, false, exit, output);
        }catch(Exception e){return new Result(false,timedOut,!ended,-1,ended?"本次进程已结束，但工具诊断无法完整读取，本次链路失败。":"工具回执无法确认，本次链路失败；维护保护保持。");}
    }

}
