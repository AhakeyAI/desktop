package com.example.ahakey.firmware;

import com.example.ahakey.update.WindowsUpdateInstaller;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Read-only physical boot observation, independent of normal HID and onboarding. */
public final class BootDeviceDetector {
    public record Device(String instanceId,String port,String service,String inf,int problem) {
        public boolean ready() { return problem==0 && "CH375_A64".equalsIgnoreCase(service) && inf!=null&&!inf.isBlank(); }
        public DeviceMaintenanceCoordinator.Identity identity(long generation) {
            return new DeviceMaintenanceCoordinator.Identity(generation,"USB",instanceId,"",port,"");
        }
    }
    @FunctionalInterface public interface Probe { List<Device> observe()throws Exception; }
    public static Device unique(List<Device> devices)throws IOException {
        if(devices.size()!=1)throw new IOException(devices.isEmpty()?"未检测到下载设备，请关机后按住语音键插入 USB。":"检测到多个下载设备，请只保留目标键盘。");
        Device device=devices.get(0);
        if(device.instanceId()==null||!device.instanceId().toUpperCase(Locale.ROOT).startsWith("USB\\VID_4348&PID_55E0\\")||device.port()==null||device.port().isBlank())throw new IOException("无法确认下载设备的物理端口。");
        return device;
    }
    public record UsbIdentity(String instanceId,String container,String port,boolean download,List<String> interfaces) {}
    public static List<Device> observe()throws Exception {
        return observe(queryBuilder("Boot"),20_000);
    }
    public static List<UsbIdentity> observeUsbIdentities()throws Exception {
        return observe(queryBuilder("Maintenance"),20_000,UsbIdentity[].class);
    }
    // The same bundled query is used by the pre-write worker and reconnect observation.
    // Only the marked literal is read; the worker/supervisor entry point is never executed here.
    static String deviceQueryScript()throws IOException {
        try(var in=BootDeviceDetector.class.getResourceAsStream("/firmware/wch-capture-worker.ps1")) {
            if(in==null)throw new IOException("设备身份查询资源缺失。");
            String source=new String(in.readAllBytes(),StandardCharsets.UTF_8).replace("\r\n","\n");
            String begin="# AHAKEY_READ_ONLY_DEVICE_QUERY_BEGIN\n$deviceQueryScript = @'\n";
            String end="\n'@\n# AHAKEY_READ_ONLY_DEVICE_QUERY_END";
            int start=source.indexOf(begin),finish=source.indexOf(end);
            if(start<0||finish<=start||source.indexOf(begin,start+1)>=0)throw new IOException("设备身份查询资源边界无效。");
            return source.substring(start+begin.length(),finish);
        }
    }
    private static ProcessBuilder queryBuilder(String method)throws IOException {
        String script=deviceQueryScript()+"\nConvertTo-Json -InputObject @([AhaKeyReadOnlyDevices]::"+method+"()) -Depth 4 -Compress";
        return new ProcessBuilder(WindowsUpdateInstaller.powershell(),"-NoProfile","-NonInteractive","-EncodedCommand",
                Base64.getEncoder().encodeToString(script.getBytes(StandardCharsets.UTF_16LE)));
    }

    /** Package-private seam runs real child processes in regression checks, without querying or writing devices. */
    static List<Device> observe(ProcessBuilder builder,long timeoutMillis)throws Exception {
        return observe(builder,timeoutMillis,Device[].class);
    }
    private static <T> List<T> observe(ProcessBuilder builder,long timeoutMillis,Class<T[]> resultType)throws Exception {
        try(Observation observation=new Observation(builder.start())) {
            Process child=observation.child;
            child.getOutputStream().close();
            long deadline=System.nanoTime()+TimeUnit.MILLISECONDS.toNanos(timeoutMillis);
            while(child.isAlive()) {
                observation.checkLimits();
                long remaining=deadline-System.nanoTime();
                if(remaining<=0)throw observation.failure("下载设备检测超时（"+timeoutMillis+" ms）。");
                child.waitFor(Math.min(remaining,TimeUnit.MILLISECONDS.toNanos(50)),TimeUnit.NANOSECONDS);
            }
            observation.awaitReaders();
            observation.checkLimits();
            if(child.exitValue()!=0)throw observation.failure("下载设备检测失败，退出码 "+child.exitValue()+"。");
            if(observation.output.error!=null||observation.error.error!=null)
                throw observation.failure("下载设备检测输出读取失败。");
            String json=observation.output.text();
            try {
                var mapper=new ObjectMapper();var tree=mapper.readTree(json);
                if(tree==null||!tree.isArray())throw new IOException("Expected a JSON array");
                var devices=mapper.treeToValue(tree,resultType);
                for(T device:devices)if(device==null)throw new IOException("Null device entry");
                return List.of(devices);
            } catch(IOException e) {
                throw new IOException(observation.failure("下载设备检测返回无效数据。").getMessage(),e);
            }
        }
    }

    private static final class Capture implements Runnable {
        private final InputStream stream;
        private final int limit;
        private final ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        private final Thread thread;
        private volatile boolean overflow;
        private volatile IOException error;
        Capture(InputStream stream,int limit,String name) {
            this.stream=stream;this.limit=limit;thread=new Thread(this,name);thread.setDaemon(true);thread.start();
        }
        public void run() {
            byte[] buffer=new byte[4096];
            try {
                int count;
                while((count=stream.read(buffer))!=-1) {
                    synchronized(bytes) {
                        int kept=Math.min(count,limit-bytes.size());bytes.write(buffer,0,kept);
                        if(kept<count)overflow=true;
                    }
                }
            } catch(IOException e) {error=e;}
        }
        String text(){synchronized(bytes){return bytes.toString(StandardCharsets.UTF_8);}}
    }

    /** Owns only the query child. try-with-resources preserves the primary failure if cleanup also fails. */
    private static final class Observation implements AutoCloseable {
        private final Process child;
        private final Capture output,error;
        Observation(Process child) {
            this.child=child;
            output=new Capture(child.getInputStream(),1_000_000,"boot-observe-out");
            error=new Capture(child.getErrorStream(),16_384,"boot-observe-err");
        }
        IOException failure(String message) {
            String detail=error.text().strip();
            return new IOException(message+(detail.isEmpty()?"":" stderr: "+detail.substring(0,Math.min(detail.length(),4096))));
        }
        void checkLimits()throws IOException {
            if(output.overflow||error.overflow)throw failure("下载设备检测输出超限。");
        }
        void awaitReaders()throws Exception {
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(1);
            for(Capture capture:List.of(output,error)) {
                long remaining=deadline-System.nanoTime();
                if(remaining>0)TimeUnit.NANOSECONDS.timedJoin(capture.thread,remaining);
            }
            if(output.thread.isAlive()||error.thread.isAlive())throw failure("下载设备检测输出未结束。");
        }
        public void close()throws Exception {
            // An interrupted caller must still terminate its own query before restoring the interrupt flag.
            boolean interrupted=Thread.interrupted();Exception failure=null;
            try {
                if(child.isAlive()) {
                    child.destroyForcibly();
                    if(!child.waitFor(3,TimeUnit.SECONDS))failure=new IOException("下载设备检测子进程清理未确认。");
                }
            } catch(Exception e) {failure=e;interrupted|=e instanceof InterruptedException;}
            for(var stream:List.of(child.getOutputStream(),child.getInputStream(),child.getErrorStream())) {
                try {stream.close();}catch(Exception e){if(failure==null)failure=e;else failure.addSuppressed(e);}
            }
            try {awaitReaders();}catch(Exception e){if(failure==null)failure=e;else failure.addSuppressed(e);interrupted|=e instanceof InterruptedException;}
            if(interrupted)Thread.currentThread().interrupt();
            if(failure!=null)throw failure;
        }
    }
}
