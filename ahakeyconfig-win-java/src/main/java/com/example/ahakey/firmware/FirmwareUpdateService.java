package com.example.ahakey.firmware;

import com.example.ahakey.service.*;
import com.example.ahakey.protocol.*;
import com.example.ahakey.update.VerifiedDownload;
import com.example.ahakey.util.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;

public final class FirmwareUpdateService {
    public enum State { IDLE, PREPARING, PREPARED, WAIT_DOWNLOAD, WAIT_BOOT, DRIVER_NEEDED, DRIVER_PREPARING, READY_TO_FLASH, FLASHING, VERIFYING, WAIT_RECONNECT, READY_RESTORE, RESTORING, COMPLETE, FAILED, UNCERTAIN }
    public record View(State state, String detail, String target, String backup, boolean canCancel, boolean canRelease) {}
    public interface DeviceIO {
        DeviceMaintenanceCoordinator.Identity identity() throws Exception;
        DeviceMaintenanceCoordinator.Operation begin(DeviceMaintenanceCoordinator.Identity identity, String hash, String profile) throws Exception;
        DeviceBackup backup(DeviceMaintenanceCoordinator.Operation op, Set<String> required, Runnable cancellation) throws Exception;
        void disconnect(DeviceMaintenanceCoordinator.Operation op) throws Exception;
        void downloadTarget(DeviceMaintenanceCoordinator.Identity source) throws Exception;
        DeviceMaintenanceCoordinator.Identity reconnect(DeviceMaintenanceCoordinator.Operation op) throws Exception;
        DeviceRestoreService.Device restoreDevice();
        default List<BootDeviceDetector.Device> bootDevices()throws Exception { return BootDeviceDetector.observe(); }
        default DeviceMaintenanceCoordinator.Operation beginBoot(DeviceMaintenanceCoordinator.Identity identity,String hash,String profile)throws Exception { throw new IOException("下载模式入口不可用。"); }
    }
    public interface ToolIO {
        WchRuntimeLocator.Runtime locate(Path directory) throws Exception;
        WchFlashAdapter.Result execute(WchRuntimeLocator.Runtime runtime, Path hex, String hash, Path directory, String operation, Runnable timeout) throws Exception;
        default void requestExit() {}
        default boolean cleanupConfirmed(Path directory){return false;}
        default WchFlashAdapter.Result execute(WchRuntimeLocator.Runtime runtime,Path hex,String hash,Path directory,String operation,Runnable timeout,java.util.function.BooleanSupplier cancel,DeviceMaintenanceCoordinator.Identity target)throws Exception {
            if(cancel.getAsBoolean())throw new WchFlashAdapter.NotStartedException(new IOException("本次链路已退出。"));return execute(runtime,hex,hash,directory,operation,timeout);
        }
    }
    public interface DriverIO {
        WchDriverService.Result prepare(Path directory)throws Exception;
        void requestExit();
        default boolean cleanupConfirmed(Path directory){return false;}
        default WchDriverService.Result prepare(Path directory,java.util.function.BooleanSupplier cancel)throws Exception {if(cancel.getAsBoolean())throw new WchDriverService.NotStartedException(new IOException("本次链路已退出。"));return prepare(directory);}
    }
    private final DeviceMaintenanceCoordinator gate;
    private final DeviceIO device;
    private final ToolIO tool;
    private final Path root;
    private final DeviceBackupStore store;
    private final FirmwareCatalog catalog;
    private final Runnable maintenanceChanged;
    private volatile View view = new View(State.IDLE, "", "", "", false, false);
    private DeviceMaintenanceCoordinator.Operation op;
    private FirmwareCatalog.Target target;
    private WchRuntimeLocator.Runtime runtime;
    private DeviceBackupStore.Saved backup;
    private Path directory;
    private String reconnectedCatalog;
    private DeviceMaintenanceCoordinator.Identity reconnectedIdentity;
    private boolean simple;
    private Path cleanupDirectory;
    private boolean driverCleanup;
    private volatile long waitingDeadline;
    private final java.util.concurrent.atomic.AtomicBoolean simpleExit=new java.util.concurrent.atomic.AtomicBoolean();
    private DriverIO driver=new DriverIO() {
        private final WchDriverService service=new WchDriverService();
        public WchDriverService.Result prepare(Path directory)throws Exception{return service.prepare(directory);}
        public WchDriverService.Result prepare(Path directory,java.util.function.BooleanSupplier cancel)throws Exception{return service.prepare(directory,cancel);}
        public void requestExit(){service.requestExit();}
        public boolean cleanupConfirmed(Path directory){return service.cleanupConfirmed(directory);}
    };
    public void driverIO(DriverIO driver) { if(view.state()!=State.IDLE)throw new IllegalStateException("维护已开始");this.driver=Objects.requireNonNull(driver); }
    public record RestorePlan(String operationId, DeviceMaintenanceCoordinator.Identity source, String targetHash,
                              String backupHash, String profile, Map<String,Set<String>> catalogCapabilities, List<String> items) {
        public RestorePlan {
            Map<String,Set<String>> copy=new HashMap<>(); catalogCapabilities.forEach((key,value)->copy.put(key,Set.copyOf(value)));
            catalogCapabilities=Map.copyOf(copy); items=List.copyOf(items);
        }
    }
    private RestorePlan plan;
    private String planHash;
    public FirmwareUpdateService(DeviceMaintenanceCoordinator gate, DeviceIO device, ToolIO tool, Path root, Runnable changed) {
        this(gate,device,tool,root,changed,new FirmwareCatalog());
    }
    public FirmwareUpdateService(DeviceMaintenanceCoordinator gate, DeviceIO device, ToolIO tool, Path root, Runnable changed, FirmwareCatalog catalog) {
        this.gate=gate; this.device=device; this.tool=tool; this.root=root; this.store=new DeviceBackupStore(root.resolve("backups")); this.maintenanceChanged=changed;
        this.catalog=catalog;
    }
    public View view() { return view; }
    public boolean simpleActive() { return simple && view.state()!=State.IDLE && view.state()!=State.COMPLETE; }
    public boolean waitingExpired() { return simple && waitingDeadline!=0 && System.currentTimeMillis()>waitingDeadline && Set.of(State.WAIT_BOOT,State.DRIVER_NEEDED,State.READY_TO_FLASH,State.WAIT_RECONNECT).contains(view.state()); }
    public synchronized void expireWaiting()throws IOException {if(waitingExpired())simpleFailed("等待设备或操作超时。");}
    public void requestSimpleExit() {simpleExit.set(true);tool.requestExit();driver.requestExit();}
    private void checkSimple()throws IOException {if(simpleExit.get())throw new IOException("已请求退出本次链路。");if(waitingDeadline!=0&&System.currentTimeMillis()>waitingDeadline)throw new IOException("本次链路等待超时。");}
    private void simpleShow(State state,String detail,long waitMillis) {waitingDeadline=waitMillis==0?0:System.currentTimeMillis()+waitMillis;show(state,detail);}
    private void simpleFailed(String detail)throws IOException {
        waitingDeadline=0;if(op!=null)gate.uncertain(op);
        if(directory!=null)try{Files.writeString(directory.resolve("failure.txt"),String.valueOf(detail)+System.lineSeparator(),StandardOpenOption.CREATE,StandardOpenOption.APPEND);}catch(IOException ignored){}
        show(State.FAILED,"本次链路失败，点击退出重新链路。"+(processAlive?" 工具结束状态尚未确认，暂不能重新烧录。":""));
    }
    public synchronized void prepareSimple(FirmwareCatalog.Target selected,boolean riskConfirmed)throws Exception {
        if(op!=null||!Set.of(State.IDLE,State.COMPLETE).contains(view.state()))throw new IOException("请先退出本次链路。");
        simple=true;simpleExit.set(false);target=selected;backup=null;processAlive=false;directory=null;cleanupDirectory=null;
        try {
            if(!riskConfirmed)throw new IOException("请先确认清除固件与设备配置。");
            runtime=tool.locate(null);Files.createDirectories(root);directory=Files.createTempDirectory(root,"simple-flash-");
            Path hex=directory.resolve("firmware.hex");Files.copy(selected.file(),hex);IntelHexValidator.validate(hex);
            if(!VerifiedDownload.sha256(hex).equals(selected.hash()))throw new IOException("所选 HEX 已改变。");
            target=new FirmwareCatalog.Target(selected.source(),selected.releaseId(),selected.catalog(),selected.hardware(),selected.protocol(),selected.hash(),selected.capabilities(),selected.order(),hex);
            checkSimple();simpleShow(State.WAIT_BOOT,"拔掉 USB，将键盘关机；在关机状态按住最左侧语音键；保持按住，将 USB 插入电脑；点击检测下载设备。",120_000);
        }catch(Exception e){simpleFailed(e.getMessage());throw e;}
    }
    public synchronized void detectBoot()throws Exception {
        if(!simple||view.state()!=State.WAIT_BOOT)throw new IOException("请先选择 HEX 并开始准备。");
        try {
            checkSimple();var boot=BootDeviceDetector.unique(device.bootDevices());checkSimple();
            op=device.beginBoot(boot.identity(-1),target.hash(),runtime.profile());maintenanceChanged.run();
            gate.stage(op,DeviceMaintenanceCoordinator.Stage.BACKUP,DeviceMaintenanceCoordinator.Stage.DOWNLOAD_MODE);device.disconnect(op);
            verifyBoot(false);simpleShow(boot.ready()?State.READY_TO_FLASH:State.DRIVER_NEEDED,boot.ready()?"已确认唯一下载设备，点击开始烧录。":"已检测到下载设备，需要在应用内准备驱动。Windows 将请求权限确认。",120_000);
        }catch(Exception e){simpleFailed(e.getMessage());throw e;}
    }
    private void verifyBoot(boolean ready)throws Exception {
        var boot=BootDeviceDetector.unique(device.bootDevices());
        if(op==null||!op.source().port().equalsIgnoreCase(boot.port())||!op.source().devicePath().equalsIgnoreCase(boot.instanceId()))throw new IOException("下载设备身份已改变。");
        if(ready&&!boot.ready())throw new IOException("下载设备驱动尚未就绪。");
    }
    public synchronized void prepareDriver()throws Exception {
        require(State.DRIVER_NEEDED);
        try {
            checkSimple();verifyBoot(false);simpleShow(State.DRIVER_PREPARING,"正在准备随包驱动，请完成 Windows 权限确认。",0);
            cleanupDirectory=directory.resolve("driver");driverCleanup=true;processAlive=true;gate.processAlive(op,true);var result=driver.prepare(cleanupDirectory,simpleExit::get);
            processAlive=!result.ended();gate.processAlive(op,processAlive);new ObjectMapper().writeValue(directory.resolve("driver-result.json").toFile(),result);
            checkSimple();if(processAlive||result.exitCode()!=0)throw new IOException("驱动准备未确认（返回码 "+result.exitCode()+"）。"+(result.exitCode()==3010?"请重启 Windows 后重新链路。":result.detail()));
            verifyBoot(true);checkSimple();simpleShow(State.READY_TO_FLASH,"驱动绑定已确认，点击开始烧录。",120_000);
        }catch(Exception e){if(e instanceof WchDriverService.NotStartedException){processAlive=false;gate.processAlive(op,false);}simpleFailed(e.getMessage());throw e;}
    }
    public synchronized void flashSimple()throws Exception {
        require(State.READY_TO_FLASH);
        try {
            checkSimple();verifyBoot(true);if(!VerifiedDownload.sha256(target.file()).equals(target.hash()))throw new IOException("冻结 HEX 已改变。");
            gate.stage(op,DeviceMaintenanceCoordinator.Stage.DOWNLOAD_MODE,DeviceMaintenanceCoordinator.Stage.FLASH);
            for(String phase:List.of("download","verify")) {
                checkSimple();verifyBoot(true);waitingDeadline=0;processAlive=true;gate.processAlive(op,true);
                show(phase.equals("download")?State.FLASHING:State.VERIFYING,phase.equals("download")?"正在清除并写入，请勿拔线。":"正在校验写入内容，请勿拔线。");
                cleanupDirectory=directory.resolve(phase);driverCleanup=false;
                var result=tool.execute(runtime,target.file(),target.hash(),cleanupDirectory,phase,()->simpleExit.set(true),simpleExit::get,op.source());
                processAlive=result.processAlive();gate.processAlive(op,processAlive);saveResult(phase,result);checkSimple();
                if(!result.success()||processAlive)throw new IOException(phase+" 未确认："+result.output());
                if(phase.equals("download"))gate.stage(op,DeviceMaintenanceCoordinator.Stage.FLASH,DeviceMaintenanceCoordinator.Stage.VERIFY);
            }
            gate.stage(op,DeviceMaintenanceCoordinator.Stage.VERIFY,DeviceMaintenanceCoordinator.Stage.RECONNECT);
            simpleShow(State.WAIT_RECONNECT,"写入与校验已完成。拔 USB、松开语音键，再正常接入开机，点击检查重连。",120_000);
        }catch(Exception e){if(e instanceof WchFlashAdapter.NotStartedException){processAlive=false;gate.processAlive(op,false);}simpleFailed(e.getMessage());throw e;}
    }
    public synchronized void checkSimpleReconnect()throws Exception {
        require(State.WAIT_RECONNECT);
        try {
            checkSimple();var observed=device.reconnect(op);checkSimple();
            if(!op.source().samePhysicalDevice(observed)||observed.generation()==op.source().generation()||observed.catalog()==null||observed.catalog().isBlank())throw new IOException("未读到原目标正常重连后的实际版本。");
            if(!target.unknownLocal()&&!target.catalog().equals(observed.catalog()))throw new IOException("实际版本与已知固件目标不匹配。");
            waitingDeadline=0;finish("烧录成功，当前版本 "+observed.catalog());
        }catch(Exception e){simpleFailed(e.getMessage());throw e;}
    }
    public synchronized void exitSimple()throws Exception {
        if(!simple)return;requestSimpleExit();waitingDeadline=0;
        if(processAlive&&cleanupDirectory!=null&&(driverCleanup?driver.cleanupConfirmed(cleanupDirectory):tool.cleanupConfirmed(cleanupDirectory))) {processAlive=false;gate.processAlive(op,false);}
        if(processAlive){simpleFailed("清理未确认。");return;}
        if(op!=null){gate.finish(op,true);op=null;maintenanceChanged.run();}
        simple=false;target=null;show(State.IDLE,"请选择 HEX，重新开始链路。");
    }
    private void show(State state, String detail) {
        view = new View(state, detail, target == null ? "" : target.releaseId(), backup == null ? "" : backup.file().toString(),
                Set.of(State.PREPARING, State.PREPARED, State.WAIT_DOWNLOAD).contains(state), state == State.UNCERTAIN && op != null && !processAlive);
    }
    private volatile boolean processAlive;
    private final java.util.concurrent.atomic.AtomicBoolean cancelPreparation = new java.util.concurrent.atomic.AtomicBoolean();
    public void requestCancelPreparation() { cancelPreparation.set(true); }
    private void checkCancellation() { if(cancelPreparation.get()) throw new java.util.concurrent.CancellationException("准备已取消，未执行擦除或写入。"); }
    private Set<String> restoreCapabilities() {
        return plan.catalogCapabilities().getOrDefault(reconnectedCatalog, Set.of());
    }
    private void freezePlan(DeviceBackup facts) throws IOException {
        Map<String,Set<String>> candidates = target.unknownLocal() ? catalog.knownCapabilities() : Map.of(target.catalog(), catalog.capabilities(target.catalog()));
        if (candidates.isEmpty() || candidates.values().stream().anyMatch(caps->caps.isEmpty() || !FirmwareCatalog.ALL.containsAll(caps))
                || (!target.unknownLocal() && !candidates.get(target.catalog()).equals(target.capabilities())))
            throw new IOException("目标能力不能在当前底层恢复链执行，未进入清除。");
        List<String> items=new ArrayList<>();
        facts.keys().forEach(k->items.add("key:"+k.mode()+":"+k.index()));
        if(facts.side()!=null)items.add("side");if(facts.brightness()!=null)items.add("brightness");
        facts.lights().forEach(l->items.add("light:"+l.mode()+":"+l.ai()));
        plan=new RestorePlan(op.id().toString(),op.source(),op.targetHash(),backup.hash(),op.profile(),candidates,items);
        Path file=directory.resolve("restore-plan.json");new ObjectMapper().writeValue(file.toFile(),plan);planHash=VerifiedDownload.sha256(file);
    }
    private void validatePlan() throws IOException {
        if(plan==null || !plan.operationId().equals(op.id().toString()) || !plan.source().equals(op.source()) || !plan.targetHash().equals(op.targetHash())
                || !plan.backupHash().equals(op.backupHash()) || !plan.profile().equals(op.profile())
                || !VerifiedDownload.sha256(directory.resolve("restore-plan.json")).equals(planHash)
                || !VerifiedDownload.sha256(target.file()).equals(plan.targetHash())) throw new IOException("冻结恢复计划或目标身份已改变。");
        for(var entry:plan.catalogCapabilities().entrySet())if(!catalog.capabilities(entry.getKey()).equals(entry.getValue()))throw new IOException("恢复能力目录已改变。");
    }
    public synchronized void prepare(FirmwareCatalog.Target selected, Path toolDirectory, boolean riskConfirmed) throws Exception {
        if (op != null) throw new IOException("请先结束当前维护。");
        cancelPreparation.set(false); target=selected; backup=null; plan=null; planHash=null; reconnectedCatalog=null; reconnectedIdentity=null; show(State.PREPARING,"正在核对工具、键盘和备份范围。");
        try {
            if (!riskConfirmed) throw new IOException("请先确认双区清除及未知本地固件/降级风险。");
            runtime=tool.locate(toolDirectory);
            var source=device.identity(); catalog.compatible(target,source.catalog());
            Set<String> available=catalog.capabilities(source.catalog());
            if (!available.containsAll(target.requiredBackup())) throw new IOException("无法可靠读取必要配置；当前没有可识别的旧版清空升级例外。");
            Files.createDirectories(root); directory=Files.createTempDirectory(root,"maintenance-");
            Path frozen=directory.resolve("firmware.hex"); Files.copy(target.file(),frozen);
            if (!VerifiedDownload.sha256(frozen).equals(target.hash())) throw new IOException("所选固件已改变，请重新选择。");
            IntelHexValidator.validate(frozen);
            target=new FirmwareCatalog.Target(target.source(),target.releaseId(),target.catalog(),target.hardware(),target.protocol(),target.hash(),target.capabilities(),target.order(),frozen);
            checkCancellation(); op=device.begin(source,target.hash(),runtime.profile()); maintenanceChanged.run();
            DeviceBackup facts=gate.within(op,()->device.backup(op,target.requiredBackup(),this::checkCancellation));
            if (!facts.operationId().equals(op.id().toString()) || !facts.source().equals(source) || !facts.targetHash().equals(target.hash())) throw new IOException("备份绑定身份不匹配。");
            checkCancellation(); backup=store.save(facts); gate.bindBackup(op,backup.hash()); freezePlan(facts);
            gate.stage(op,DeviceMaintenanceCoordinator.Stage.BACKUP,DeviceMaintenanceCoordinator.Stage.PREPARED);
            show(State.PREPARED,"备份已保存并读回校验。确认后按住最左语音键插入 USB，进入下载模式。");
        } catch(Exception e) {
            if(op!=null) { gate.finish(op,false); op=null; maintenanceChanged.run(); }
            show(e instanceof java.util.concurrent.CancellationException ? State.IDLE : State.FAILED,e.getMessage()); throw e;
        }
    }
    public synchronized void enterDownloadMode() throws Exception {
        require(State.PREPARED); store.load(backup); validatePlan();
        var current=device.identity(); if(!current.equals(op.source())) throw new IOException("备份后键盘身份改变，请取消并重新准备。");
        gate.stage(op,DeviceMaintenanceCoordinator.Stage.PREPARED,DeviceMaintenanceCoordinator.Stage.DOWNLOAD_MODE);
        device.disconnect(op); show(State.WAIT_DOWNLOAD,"关机并断开 USB，按住最左语音键插入 USB。保持仅一个目标键盘，再点击开始写入。");
    }
    public synchronized void flash() throws Exception {
        require(State.WAIT_DOWNLOAD); store.load(backup); validatePlan(); device.downloadTarget(op.source());
        if(!VerifiedDownload.sha256(target.file()).equals(op.targetHash())) throw new IOException("冻结 HEX 已改变。");
        gate.stage(op,DeviceMaintenanceCoordinator.Stage.DOWNLOAD_MODE,DeviceMaintenanceCoordinator.Stage.FLASH);
        try {
            processAlive=true; gate.processAlive(op,true); show(State.FLASHING,"正在写入；不能取消或退出，请勿拔线。");
            var download=tool.execute(runtime,target.file(),target.hash(),directory.resolve("download"),"download",this::timeout);
            processAlive=download.processAlive(); gate.processAlive(op,processAlive);
            saveResult("download",download);
            if(!download.success() || download.processAlive()) { uncertain("写入未确认。"+download.output()); return; }
            gate.stage(op,DeviceMaintenanceCoordinator.Stage.FLASH,DeviceMaintenanceCoordinator.Stage.VERIFY);
            processAlive=true; gate.processAlive(op,true); show(State.VERIFYING,"写入已确认；正在校验所选 HEX。");
            var verify=tool.execute(runtime,target.file(),target.hash(),directory.resolve("verify"),"verify",this::timeout);
            processAlive=verify.processAlive(); gate.processAlive(op,processAlive); saveResult("verify",verify);
            if(!verify.success() || verify.processAlive()) { uncertain("校验未确认。"+verify.output()); return; }
            gate.stage(op,DeviceMaintenanceCoordinator.Stage.VERIFY,DeviceMaintenanceCoordinator.Stage.RECONNECT);
            show(State.WAIT_RECONNECT,"所选 HEX 写入与校验完成。拔掉 USB、松键，正常接入开机，然后检查重连。");
        } catch(Exception e) {
            if(e instanceof WchFlashAdapter.NotStartedException) { processAlive=false; gate.processAlive(op,false); }
            uncertain("工具结果不确定："+e.getMessage()); throw e;
        }
    }
    private void saveResult(String name,WchFlashAdapter.Result result) throws IOException { new ObjectMapper().writeValue(directory.resolve(name+"-result.json").toFile(),result); }
    private void timeout() { try { gate.uncertain(op); show(State.UNCERTAIN,"工具超时，仍可能执行；保持维护锁，不自动终止或重试。"); } catch(IOException ignored) {} }
    private void uncertain(String message) throws IOException { gate.uncertain(op); show(State.UNCERTAIN,message); }
    public synchronized void checkReconnect() throws Exception {
        require(State.WAIT_RECONNECT);
        try {
            validatePlan(); var identity=device.reconnect(op); reconnectedCatalog=identity.catalog(); reconnectedIdentity=identity;
            if(!op.source().samePhysicalDevice(identity) || (!target.catalog().isBlank() && !target.catalog().equals(identity.catalog()))) throw new IOException("重连设备或固件目录不匹配，禁止恢复。");
            if(restoreCapabilities().isEmpty()) throw new IOException("重连固件能力未知，禁止恢复。");
            show(State.READY_RESTORE,"重连观察版本："+identity.catalog()+"。此观察不证明远程二进制 hash。可选择恢复配置或保留清空状态。");
        } catch(Exception e) { uncertain(e.getMessage()); throw e; }
    }
    public synchronized DeviceRestoreService.Report restore() throws Exception {
        require(State.READY_RESTORE);
        var current=device.identity();
        validatePlan(); if(!current.equals(reconnectedIdentity)) throw new IOException("恢复前设备身份或连接代次改变。");
        DeviceBackup facts=store.load(backup);
        if(!facts.targetHash().equals(op.targetHash()) || !backup.hash().equals(op.backupHash())) throw new IOException("恢复备份与目标不匹配。");
        gate.stage(op,DeviceMaintenanceCoordinator.Stage.RECONNECT,DeviceMaintenanceCoordinator.Stage.RESTORE); show(State.RESTORING,"逐项保存并核对设备读回，不重放 OLED、配对、睡眠、语音或历史 AI。");
        try {
            var report=gate.within(op,()->new DeviceRestoreService().restore(facts,restoreCapabilities(),device.restoreDevice()));
            new ObjectMapper().writeValue(directory.resolve("restore-result.json").toFile(),report);
            if(!report.complete()) { uncertain("部分恢复失败，原备份和逐项报告已保留："+directory.resolve("restore-result.json")); return report; }
            finish("恢复完成：所有已执行项 ACK 与读回一致；重启持久性仍需真机确认。"); return report;
        } catch(Exception e) { uncertain("恢复结果未确认："+e.getMessage()); throw e; }
    }
    public synchronized void keepCleared() throws Exception { require(State.READY_RESTORE); finish("已保留清空后的设备配置；PC 草稿与绑定保持。"); }
    public synchronized void cancel() throws Exception { if(!view.canCancel()) throw new IOException("写入开始后不能取消。"); gate.finish(op,false); op=null; maintenanceChanged.run(); show(State.IDLE,"准备已取消，备份保留。"); }
    public synchronized void acknowledgeFailure() throws Exception {
        if(!view.canRelease() || processAlive) throw new IOException("不能确认工具已退出，维护锁保持。");
        gate.finish(op,true); op=null; maintenanceChanged.run(); show(State.FAILED,"已结束本次维护。结果未确认；请检查设备后重新连接，不自动重刷。");
    }
    private void finish(String message) throws Exception { gate.finish(op,false); op=null; maintenanceChanged.run(); show(State.COMPLETE,message); }
    private void require(State state) throws IOException { if(view.state()!=state || op==null) throw new IOException("当前固件维护阶段不允许此操作。"); }

    public static DeviceIO deviceIO(BleManager ble, DeviceMaintenanceCoordinator.Task<List<UsbHidTransport.MaintenanceDevice>> inventory,
                                    DeviceMaintenanceCoordinator.Task<List<String>> paths) {
        return new DeviceIO() {
            public DeviceMaintenanceCoordinator.Identity identity() throws Exception {
                if(!ble.isUsbConnected() || !ble.getCachedStatus().isConnected()) throw new IOException("请先连接唯一 USB 键盘并读取固件版本；BLE 地址不能证明 USB 目标身份。");
                var list=inventory.run();
                if(list.size()!=1 || list.get(0).download() || !list.get(0).ownsHidPath(ble.usbDevicePath())) throw new IOException("USB 目标不唯一或当前连接不匹配。");
                var d=list.get(0); if(d.container().isBlank() || d.port().isBlank()) throw new IOException("缺少可靠 USB 容器/端口关联。");
                return new DeviceMaintenanceCoordinator.Identity(ble.connectionGeneration(),"USB",ble.usbDevicePath(),d.container(),d.port(),ble.firmwareIdentity().catalogKey());
            }
            public DeviceMaintenanceCoordinator.Operation begin(DeviceMaintenanceCoordinator.Identity identity,String hash,String profile) throws Exception { return ble.beginMaintenance(identity,hash,profile,false); }
            public DeviceMaintenanceCoordinator.Operation beginBoot(DeviceMaintenanceCoordinator.Identity identity,String hash,String profile)throws Exception { return ble.beginBootMaintenance(identity,hash,profile); }
            public DeviceBackup backup(DeviceMaintenanceCoordinator.Operation op,Set<String> required,Runnable cancellation) throws Exception {
                List<DeviceBackup.Key> keys=new ArrayList<>(); DeviceBackup.Side side=null; Integer brightness=null; List<DeviceBackup.Light> lights=new ArrayList<>();
                if(required.contains("keys")) for(int mode=0;mode<4;mode++) for(int key=0;key<4;key++) {
                    cancellation.run(); var read=ble.readOrdinaryKeyConfig(mode,key); keys.add(new DeviceBackup.Key(mode,key,read.actionType(),HexFormat.of().formatHex(read.actionPayload()),read.description()));
                }
                if(required.contains("side")) { cancellation.run(); var read=ble.readSideSwitchConfig(); side=new DeviceBackup.Side(read.up().binding(),HexFormat.of().formatHex(read.up().actionPayload()),read.down().binding(),HexFormat.of().formatHex(read.down().actionPayload())); }
                if(required.contains("lights")) try(var lease=ble.openDisplayLease(false)) {
                    brightness=readLight(lease,0);
                    for(int mode=0;mode<4;mode++) for(int ai=0;ai<9;ai++) { cancellation.run(); lights.add(new DeviceBackup.Light(mode,ai,readLight(lease,1,mode,ai))); }
                }
                if(!identity().equals(op.source())) throw new IOException("备份过程中键盘身份改变。");
                return new DeviceBackup(1,op.id().toString(),op.source(),op.targetHash(),required,keys,side,brightness,lights,
                        Map.of("studio-draft.json",StudioStore.strictSnapshot(),"ai-runtime.json",AiRuntimeStore.strictSnapshot()));
            }
            private int readLight(BleManager.DisplayLease lease,int kind,int... selectors) throws Exception {
                var read=AhaKeyResponseParser.parseDisplayRead(ble.exchangeDisplay(lease,AhaKeyProtocol.displayRead(kind,selectors)),kind,selectors);
                if(read==null) { ble.invalidateDisplayRead(lease); throw new IOException("必要灯光回读失败。"); } return read.value();
            }
            public void disconnect(DeviceMaintenanceCoordinator.Operation op) throws Exception { ble.maintenanceDisconnect(op); }
            public void downloadTarget(DeviceMaintenanceCoordinator.Identity source) throws Exception {
                var devices=inventory.run();
                if(devices.size()!=1 || !devices.get(0).download() || source.port().isBlank() || !source.port().equalsIgnoreCase(devices.get(0).port())) throw new IOException("未检测到与原 USB 端口关联的唯一 WCH 下载设备。");
            }
            public DeviceMaintenanceCoordinator.Identity reconnect(DeviceMaintenanceCoordinator.Operation op) throws Exception {
                var devices=inventory.run(); if(devices.size()!=1 || devices.get(0).download()) throw new IOException("请正常重连唯一键盘。");
                var d=devices.get(0); var matchedPaths=paths.run().stream().filter(d::ownsHidPath).toList();
                if(matchedPaths.size()!=1) throw new IOException("无法唯一关联正常态 HID 接口。");
                var observed=new DeviceMaintenanceCoordinator.Identity(ble.connectionGeneration(),"USB",matchedPaths.get(0),d.container(),d.port(),"");
                ble.maintenanceReconnect(op,observed);
                ble.maintenance().within(op,()->ble.readFirmwareCatalogKey()); return identity();
            }
            public DeviceRestoreService.Device restoreDevice() { return DeviceRestoreService.ble(ble); }
        };
    }
    public static FirmwareUpdateService production(BleManager ble, Path root, Runnable changed) {
        DeviceIO io=deviceIO(ble,UsbHidTransport::maintenanceDevices,UsbHidTransport::listDevicePaths);
        ToolIO tool=new ToolIO() {
            private final WchFlashAdapter adapter=new WchFlashAdapter();
            public WchRuntimeLocator.Runtime locate(Path p) throws Exception { return new WchRuntimeLocator().locate(p); }
            public WchFlashAdapter.Result execute(WchRuntimeLocator.Runtime runtime,Path hex,String hash,Path directory,String operation,Runnable timeout) throws Exception {
                return adapter.execute(runtime,hex,hash,directory,operation,timeout);
            }
            public void requestExit(){adapter.requestExit();}
            public boolean cleanupConfirmed(Path directory){return adapter.cleanupConfirmed(directory);}
            public WchFlashAdapter.Result execute(WchRuntimeLocator.Runtime r,Path hex,String hash,Path dir,String operation,Runnable timeout,java.util.function.BooleanSupplier cancel,DeviceMaintenanceCoordinator.Identity target)throws Exception{return adapter.execute(r,hex,hash,dir,operation,timeout,cancel,target);}
        };
        return new FirmwareUpdateService(ble.maintenance(),io,tool,root,changed,ble.firmwareCatalog());
    }
}
