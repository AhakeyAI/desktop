package com.example.ahakey.firmware;

import com.example.ahakey.update.WindowsUpdateInstaller;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Fixed bundled INF preparation. No general elevated command interface. */
public final class WchDriverService {
    public static final class NotStartedException extends IOException {public NotStartedException(Exception cause){super("驱动准备尚未启动："+cause.getMessage(),cause);}}
    @FunctionalInterface interface DirectoryProvider {Path get()throws Exception;}
    private final DirectoryProvider bundled;
    public WchDriverService(){this(()->new WchRuntimeLocator().driverDirectory());}
    WchDriverService(DirectoryProvider bundled){this.bundled=bundled;}
    public record Result(int exitCode,boolean ended,String detail) {}
    private volatile Path active;
    private final java.util.concurrent.ConcurrentMap<Path,String> operations=new java.util.concurrent.ConcurrentHashMap<>();
    public boolean cleanupConfirmed(Path directory){String id=operations.get(directory);if(id==null)return false;boolean ended=endedReceipt(directory,id);if(ended)operations.remove(directory,id);return ended;}
    static boolean endedReceipt(Path directory,String id) {
        try {Path receipt=directory.resolve("result.json");if(Files.size(receipt)>65536||!id.equals(Files.readString(directory.resolve("operation.id"))))return false;
            var result=new ObjectMapper().readTree(receipt.toFile());return id.equals(result.path("operationId").asText())&&result.path("ended").isBoolean()&&result.path("ended").asBoolean();
        }catch(Exception e){return false;}
    }
    public void requestExit() { Path directory=active;if(directory!=null)try{Files.writeString(directory.resolve("cancel.request"),"cancel");}catch(IOException ignored){} }
    public Result prepare(Path directory)throws Exception {
        return prepare(directory,()->false);
    }
    public Result prepare(Path directory,java.util.function.BooleanSupplier cancelled)throws Exception {
        Process child=null;
        try {
        if(cancelled.getAsBoolean())throw new IOException("本次链路已退出。");
        Files.createDirectory(directory);active=directory;
        Path drivers=bundled.get();new WchRuntimeLocator().verifyDrivers(drivers);
        String id=UUID.randomUUID().toString();Files.writeString(directory.resolve("operation.id"),id);operations.put(directory,id);
        Path worker=directory.resolve("wch-driver-worker.ps1");
        try(var in=getClass().getResourceAsStream("/firmware/wch-driver-worker.ps1")){if(in==null)throw new IOException("随包驱动准备程序缺失。");Files.copy(in,worker);}
        Path request=directory.resolve("request.json");var json=new ObjectMapper();
        json.writeValue(request.toFile(),Map.of("drivers",drivers.toString(),"operationId",id,"parentPid",ProcessHandle.current().pid(),"parentStart",ProcessHandle.current().info().startInstant().orElseThrow().toEpochMilli(),"launchDeadline",System.currentTimeMillis()+60_000));
            if(cancelled.getAsBoolean()||Files.exists(directory.resolve("cancel.request")))throw new IOException("本次链路已退出。");
            child=new ProcessBuilder(WindowsUpdateInstaller.powershell(),"-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",worker.toString(),"-Mode","Launch","-Request",request.toString()).redirectErrorStream(true).redirectOutput(directory.resolve("worker.log").toFile()).start();
            long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(160);Path receipt=directory.resolve("result.json");
            while(child.isAlive()&&!Files.isRegularFile(receipt)&&System.nanoTime()<end){if(cancelled.getAsBoolean())requestExit();Thread.sleep(100);}
            if(!Files.isRegularFile(receipt)){requestExit();child.waitFor(7,TimeUnit.SECONDS);}
            if(!Files.isRegularFile(receipt))return new Result(-1,false,"驱动准备超时，未确认本次进程结束。");
            var result=json.readTree(receipt.toFile());if(!id.equals(result.path("operationId").asText()))throw new IOException("驱动准备结果不属于本次操作。");
            boolean ended=endedReceipt(directory,id);if(ended)operations.remove(directory,id);
            return new Result(result.path("exitCode").asInt(-1),ended,result.path("detail").asText());
        } catch(Exception e){if(child==null){operations.remove(directory);throw new NotStartedException(e);}throw e;} finally {active=null;}
    }
}
