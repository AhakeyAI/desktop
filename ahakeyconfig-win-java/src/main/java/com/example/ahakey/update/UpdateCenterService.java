package com.example.ahakey.update;

import com.example.ahakey.firmware.*;
import com.example.ahakey.service.BleManager;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;

public final class UpdateCenterService implements AutoCloseable {
    public enum State { IDLE, CHECKING, UNAVAILABLE, NO_VARIANT, CURRENT, AVAILABLE, DOWNLOADING, CANCELLED, FAILED, READY, INSTALLING, INSTALL_UNCONFIRMED, RESTART_CONFIRMED }
    public record View(State state, String detail, long received, long total, String version) {}
    private final InstalledAppIdentity app;
    private final ReleaseManifestClient client;
    private final Path root;
    private final BleManager ble;
    @FunctionalInterface public interface TrustFactory { InstallerTrustPolicy create(Path work) throws Exception; }
    public record Dependencies(java.util.function.Supplier<VerifiedDownload> downloads, TrustFactory trust, WindowsUpdateInstaller installer) {}
    private final Dependencies dependencies;
    private final FirmwareUpdateService firmware;
    private final ExecutorService worker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"update-center");t.setDaemon(true);return t;});
    private final AtomicBoolean busy=new AtomicBoolean(), started=new AtomicBoolean();
    private volatile View view=new View(State.IDLE,"",0,0,"");
    private volatile String installationResult="";
    private volatile ReleaseManifest manifest;
    private volatile VerifiedDownload download;
    private ReleaseManifest.WindowsRelease release;
    private Path downloaded;
    private volatile FirmwareCatalog.Target selected;
    private volatile String firmwareError="";
    private volatile boolean firmwareDownload;
    private volatile DeviceMaintenanceCoordinator.Operation installOp;
    private Consumer<DeviceMaintenanceCoordinator.Operation> exitHandler=op->{};
    public UpdateCenterService(BleManager ble, FirmwareUpdateService firmware, Path root) { this(ble,firmware,root,InstalledAppIdentity.load(),new ReleaseManifestClient()); }
    public UpdateCenterService(BleManager ble,FirmwareUpdateService firmware,Path root,InstalledAppIdentity app,ReleaseManifestClient client) {
        this(ble,firmware,root,app,client,new Dependencies(VerifiedDownload::new,InstallerTrustPolicy::production,new WindowsUpdateInstaller()));
    }
    public UpdateCenterService(BleManager ble,FirmwareUpdateService firmware,Path root,InstalledAppIdentity app,ReleaseManifestClient client,Dependencies dependencies) {
        this.ble=ble;this.firmware=firmware;this.root=root;this.app=app;this.client=client;this.dependencies=dependencies;
    }
    public void setExitHandler(Consumer<DeviceMaintenanceCoordinator.Operation> handler) { exitHandler=handler; }
    public InstalledAppIdentity app() { return app; }
    public View view() { return view; }
    public String installationResult() { return installationResult; }
    public FirmwareUpdateService firmware() { return firmware; }
    public FirmwareCatalog.Target selectedFirmware() { return selected; }
    public String firmwareError() { return firmwareError; }
    public boolean busy() { return busy.get(); }
    public List<ReleaseManifest.FirmwareRelease> officialFirmware() { return manifest==null?List.of():manifest.firmware(); }
    public boolean downloading() { return download!=null || firmwareDownload; }
    public void startup() {
        if(!started.compareAndSet(false,true)) return;
        check();
    }
    public void check() { execute(()->{
        view=new View(State.CHECKING,"",0,0,app.version());
        try {
            Files.createDirectories(root); String receipt=WindowsUpdateInstaller.reconcileReceipts(root.resolve("installations"),app);
            if(!receipt.isBlank()) installationResult=receipt;
            acceptManifest(client.fetch()); release=manifest.windows().get(app.variant());
            if(release==null) { view=new View(State.NO_VARIANT,"尚未发布匹配当前安装形态的版本。",0,0,app.version());return; }
            app.validate(); int compare=InstalledAppIdentity.compareVersions(release.version(),app.version());
            view=new View(compare>0?State.AVAILABLE:State.CURRENT,"",0,0,release.version());
        } catch(Exception e) { view=new View(State.UNAVAILABLE,reason(e),0,0,app.version()); }
    },false); }
    public void downloadSoftware() { execute(()->{
        if(release==null || view.state()!=State.AVAILABLE) throw new IOException("请先检查新版信息。");
        release.matches(app); VerifiedDownload transfer=dependencies.downloads().get(); download=transfer;
        try {
            view=new View(State.DOWNLOADING,"",0,release.size(),release.version());
            downloaded=transfer.fetch(release.url(),release.size(),release.sha256(),root.resolve("downloads"),".exe",
                    count->view=new View(State.DOWNLOADING,"",count,release.size(),release.version()));
            dependencies.trust().create(root).verify(downloaded,release,app);
            if(transfer.isCancelled()){Files.deleteIfExists(downloaded);downloaded=null;throw new CancellationException("下载已取消。");}
            view=new View(State.READY,"发行签名与实际安装身份已核对；安装仍需确认。",Files.size(downloaded),Files.size(downloaded),release.version());
        } catch(Exception e) { view=new View(e instanceof CancellationException||transfer.isCancelled()?State.CANCELLED:State.FAILED,reason(e),0,0,app.version()); }
        finally { download=null; }
    },false); }
    public void cancelDownload() { VerifiedDownload current=download;if(current!=null)current.cancel(); }
    public void installConfirmed() { execute(()->{
        if(view.state()!=State.READY || downloaded==null) throw new IOException("安装包尚未就绪。");
        var trust=dependencies.trust().create(root);trust.verify(downloaded,release,app);
        installOp=ble.beginMaintenance(null,VerifiedDownload.sha256(downloaded),"release-rsa3072-v1",true);
        view=new View(State.INSTALLING,"正在建立安装协调握手；就绪前原应用保持运行。",0,0,release.version());
        try {
            Path launch=currentLauncher(); Path installations=root.resolve("installations");Files.createDirectories(installations);
            WindowsUpdateInstaller installer=dependencies.installer();
            var handshake=installer.prepare(installOp,downloaded,release,app,trust,installations,launch);
            installer.permitExit(handshake);
            // The single application shutdown path acquires the same gate before cleanup.
            exitHandler.accept(installOp);
            view=new View(State.INSTALL_UNCONFIRMED,"已交给安装协调；等待真实安装结果及重启确认。",0,0,release.version());
        } catch(Exception e) {
            ble.maintenance().finish(installOp,false);installOp=null;throw e;
        }
    },false); }
    private Path currentLauncher() throws IOException {
        String configured=System.getProperty("jpackage.app-path","");
        if(configured.isBlank()) throw new IOException("当前不是可确认的安装形态启动入口。"); return Path.of(configured).toAbsolutePath();
    }
    public void openOfficialToolPage() { execute(()->java.awt.Desktop.getDesktop().browse(java.net.URI.create("https://www.wch.cn/downloads/WCHISPTool_Setup_exe.html")),true); }
    public void chooseBuiltin() { execute(()->{ ensureNoMaintenance();selected=new FirmwareCatalog().builtin(root.resolve("builtin")); },true); }
    public void chooseLocal(Path path) { execute(()->{ensureNoMaintenance();selected=new FirmwareCatalog().local(path);},true); }
    private void acceptManifest(ReleaseManifest value) throws IOException { ble.firmwareCatalog().acceptOfficial(value.firmware()); manifest=value; }
    public void refreshFirmwareCatalog() { execute(()->{ensureNoMaintenance();acceptManifest(client.fetch());},true); }
    public void chooseOfficial(ReleaseManifest.FirmwareRelease selectedRelease) { execute(()->{
        ensureNoMaintenance(); if(manifest==null || !manifest.firmware().contains(selectedRelease)) throw new IOException("官方目录已改变。");
        VerifiedDownload transfer=dependencies.downloads().get();download=transfer;firmwareDownload=true;
        try { Path file=transfer.fetch(selectedRelease.hexUrl(),selectedRelease.size(),selectedRelease.sha256(),root.resolve("downloads"),".hex",count->{});
            if(transfer.isCancelled()){Files.deleteIfExists(file);throw new CancellationException("下载已取消。");}
            selected=ble.firmwareCatalog().official(selectedRelease,file);
        } finally {download=null;firmwareDownload=false;}
    },true); }
    public void prepareFirmware(Path toolDirectory,boolean riskConfirmed) { firmwareAction(()->{if(selected==null)throw new IOException("请先选择固件。");firmware.prepare(selected,toolDirectory,riskConfirmed);}); }
    public void prepareSimpleFirmware(boolean riskConfirmed) {firmwareAction(()->{if(selected==null)throw new IOException("请先选择固件。");firmware.prepareSimple(selected,riskConfirmed);});}
    public void detectSimpleFirmware(boolean riskConfirmed) {firmwareAction(()->{
        if(selected==null)throw new IOException("请先选择固件。");
        if(!firmware.simpleActive())firmware.prepareSimple(selected,riskConfirmed);
        firmware.detectBoot();
    });}
    private final AtomicBoolean exitQueued=new AtomicBoolean();
    public void exitFirmware() {
        firmware.requestSimpleExit();
        if(!exitQueued.compareAndSet(false,true))return;
        worker.execute(()->{busy.set(true);try{firmware.exitSimple();if(firmware.view().state()==FirmwareUpdateService.State.IDLE)selected=null;firmwareError="";}catch(Exception e){firmwareError=reason(e);}finally{exitQueued.set(false);busy.set(false);}});
    }
    public void expireFirmware() { if(firmware.waitingExpired())firmwareAction(firmware::expireWaiting); }
    public void firmwareAction(Action action) { execute(action,true); }
    private void ensureNoMaintenance() throws IOException { if(ble.maintenance().active()||firmware.simpleActive())throw new IOException("请先退出本次链路，再更换 HEX。"); }
    @FunctionalInterface public interface Action { void run() throws Exception; }
    private void execute(Action action,boolean firmwareAction) {
        if(!busy.compareAndSet(false,true))return;
        worker.execute(()->{try{if(firmwareAction)firmwareError="";action.run();}catch(Exception e){if(firmwareAction)firmwareError=firmware.simpleActive()&&firmware.view().state()==FirmwareUpdateService.State.FAILED?"":reason(e);else view=new View(State.FAILED,reason(e),0,0,app.version());}finally{busy.set(false);}});
    }
    private static String reason(Exception e) {String message=e.getMessage()==null?e.getClass().getSimpleName():e.getMessage();return message.replaceAll("(?i)https?://[^\\s\"<>]+","[更新地址已隐藏]");}
    public boolean windowCloseReady() {
        return !busy.get() && !downloading() && !firmware.simpleActive() && !ble.maintenance().active();
    }
    /** Nonblocking preparation shared by window hide and explicit application exit. */
    public void prepareWindowClose(Consumer<Boolean> completion) {
        cancelDownload();
        if (downloading() || !busy.compareAndSet(false,true)) { completion.accept(false); return; }
        if (!firmware.simpleActive() || firmware.view().state()!=FirmwareUpdateService.State.FAILED) {
            busy.set(false); completion.accept(windowCloseReady()); return;
        }
        // exitSimple alone decides whether owned processes have ended; never unlock the gate here.
        worker.execute(()->{
            try {
                firmware.exitSimple();
                if (firmware.view().state()==FirmwareUpdateService.State.IDLE) { selected=null;firmwareError=""; }
            } catch(Exception e) { firmwareError=reason(e); }
            finally { busy.set(false); }
            completion.accept(windowCloseReady());
        });
    }
    public boolean requestClose(DeviceMaintenanceCoordinator.Operation installation) {
        cancelDownload();
        if(downloading())return false;
        if(busy.get() && installation==null)return false;
        return ble.requestApplicationExit(installation);
    }
    @Override public void close() {cancelDownload();worker.shutdown();}
}
