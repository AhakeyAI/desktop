package com.example.ahakey.wd009;

import com.example.ahakey.model.*;
import com.example.ahakey.protocol.*;
import com.example.ahakey.service.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Real status/readback and Hook handler paths. No device, installed hook or native input. */
public final class ApprovalFactsChecks {
    static int checks;
    static void check(String name, boolean value) { if (!value) throw new AssertionError(name); checks++; System.out.println("PASS " + name); }
    static final BleManager.BleCallback CALLBACK = new BleManager.BleCallback() {
        public void onConnected() {} public void onDisconnected() {} public void onStatusReceived(DeviceStatus s) {} public void onError(String s) {}
    };
    static void field(Object object, Class<?> type, String name, Object value) throws Exception {
        Field f = type.getDeclaredField(name); f.setAccessible(true); f.set(object, value);
    }
    static AhaKeyResponseParser.SideSwitchConfig config(int position, int up, int down) {
        return new AhaKeyResponseParser.SideSwitchConfig(position,
            new AhaKeyResponseParser.SideSwitchPositionConfig(up, new byte[0]),
            new AhaKeyResponseParser.SideSwitchPositionConfig(down, new byte[0]));
    }
    static final class Wire extends BleManager {
        final boolean usb;
        int position, up, down = 1, mode, reads, writes;
        boolean dropStatus, malformedSide, resetOnSide;
        Wire(boolean usb) throws Exception {
            super(CALLBACK); this.usb = usb;
            field(this, BleManager.class, "usbTransport", new UsbHidTransport() {
                public boolean isOpen() { return usb; }
                public void open(java.util.function.Consumer<byte[]> c) { throw new AssertionError("No real USB"); }
                public void sendCommand(byte[] c) { respond(c); }
                public void sendData(byte[] c) { throw new AssertionError("No upload"); }
                public void close() {}
            });
            field(this, BleManager.class, "isConnected", true); getCachedStatus().setConnected(true);
            field(this, BleManager.class, "outputStream", new ByteArrayOutputStream() {
                public synchronized void write(byte[] b, int off, int len) { respond(Arrays.copyOfRange(b, off + 3, off + len)); }
            });
            readFirmwareCatalogKey();
        }
        protected boolean isUsbDevicePresent() { return false; }
        public void connect() { throw new AssertionError("No real connect"); }
        void reset() {
            try { Method m=BleManager.class.getDeclaredMethod("resetDisplaySession"); m.setAccessible(true); m.invoke(this); }
            catch (Exception e) { throw new AssertionError(e); }
        }
        void reply(byte[] b, long generation) {
            try {
                Method m=BleManager.class.getDeclaredMethod("onSessionNotify", long.class, byte[].class); m.setAccessible(true); m.invoke(this,generation,b);
            } catch (Exception e) { throw new AssertionError(e); }
        }
        void respond(byte[] q) {
            if(q.length < 3) throw new AssertionError("Unexpected transport request");
            int cmd=q[2]&255; long generation=connectionGeneration();
            byte[] data;
            if(cmd==0x9F) data=("\0x1-c582-hw1-p1-1.0.1-r001").getBytes(StandardCharsets.US_ASCII);
            else if(cmd==0) { if(dropStatus)return; data=new byte[]{100,0,1,1,(byte)mode,0,(byte)position,35}; }
            else if(cmd==0x97 && q.length==5) {
                reads++; if(resetOnSide) {reset(); return;}
                data=malformedSide?new byte[]{0,0}:new byte[]{0,(byte)position,2,(byte)up,0,(byte)down,0};
            } else { writes++; data=new byte[]{0}; }
            reply(AhaKeyProtocol.buildFrame((byte)cmd,data), generation);
        }
    }
    static String hook(HookDispatchServer server, String method, String event) throws Exception {
        Method m=HookDispatchServer.class.getDeclaredMethod(method,PrintWriter.class,String.class,IDEState.class,JsonNode.class);
        m.setAccessible(true); StringWriter out=new StringWriter();
        m.invoke(server,new PrintWriter(out,true),event,IDEState.PERMISSION_REQUEST,new ObjectMapper().createObjectNode());
        return out.toString();
    }
    public static void main(String[] args) throws Exception {
        DeviceStatus status=new DeviceStatus(); status.setConnected(true); status.setSwitchState(0);
        check("physical up without saved binding is not approval",!status.isAutoApproval());
        status.setSavedBindings(config(0,0,1)); check("confirmed up auto",status.isAutoApproval());
        status.setSwitchState(1); check("down manual",!status.isAutoApproval());
        status.setSavedBindings(config(1,1,0)); check("auto follows action not fixed up position",status.isAutoApproval());
        status.setSwitchState(-1); check("unknown position defers",!status.isAutoApproval());
        status.setSwitchState(0); status.setSavedBindings(config(0,0,1)); status.setWorkMode(2);
        check("mode change invalidates approval",!status.isAutoApproval());
        status.setWorkMode(255); status.setSavedBindings(config(0,0,1));
        check("invalid mode cannot approve", !status.isAutoApproval()); status.setWorkMode(0);
        status.setSavedBindings(config(0,0,1)); status.setConnected(false); status.setConnected(true);
        check("disconnect prevents inherited approval",!status.isAutoApproval());
        KeyConfig shortcut=new KeyConfig(0x206,""); byte[] action=DeviceSyncService.encodeSideSwitchActionPayload(shortcut);
        var custom=new AhaKeyResponseParser.SideSwitchConfig(0,new AhaKeyResponseParser.SideSwitchPositionConfig(3,action),config(0,0,1).down());
        status.setSavedBindings(custom); status.setSwitchState(0);
        check("custom up displays Ctrl+C",status.getSwitchTitle().equals("上拨 · Ctrl+C"));
        check("custom up does not auto approve",!status.isAutoApproval());
        action[2]=0; check("saved action copies input bytes",status.getSwitchTitle().equals("上拨 · Ctrl+C"));
        status.getSavedBindings().up().actionPayload()[2]=0;
        check("saved action copies returned bytes",status.getSwitchTitle().equals("上拨 · Ctrl+C"));
        StudioState draft=new StudioState(); draft.applySideSwitchReadback(custom);
        draft.updateSideSwitchBinding(0,0);
        check("draft changes do not activate approval",!status.isAutoApproval() && draft.isDirty(StudioPart.TOGGLE_SWITCH));
        draft.applySideSwitchReadback(custom);
        check("readback preserves dirty draft",draft.getSideSwitchConfig().up().binding()==0);
        draft.setCp4cInputConfigEnabled(true); draft.setCp4cInputConfigEnabled(false);
        check("disconnect/capability loss preserves side draft",draft.getSideSwitchConfig().up().binding()==0 && draft.isDirty(StudioPart.TOGGLE_SWITCH));
        status.clearFirmwareIdentity(); check("unknown version never invented",status.getDisplayFirmwareVersion().contains("未知"));
        status.setFirmwareMain(1);status.setFirmwareSub(0);
        check("basic version explicit incomplete",status.getDisplayFirmwareVersion().contains("完整标识未读到"));
        status.setFirmwareCatalogKey("x1-c582-hw2-p1-1.0.1-r001");
        check("exact firmware identity",status.getDisplayFirmwareVersion().equals("x1-c582-hw2-p1-1.0.1-r001"));
        status.setConnected(false);check("disconnected version unknown",status.getDisplayFirmwareVersion().contains("未连接"));
        for(boolean usb:new boolean[]{false,true}) {
            Wire wire=new Wire(usb);
            check("fresh wire approves only confirmed auto "+usb,wire.refreshAutoApproval() && wire.reads==1);
            wire.up=3;check("fresh custom suppresses physical up "+usb,!wire.refreshAutoApproval());
            wire.up=1;wire.down=0;wire.position=1;check("fresh down auto "+usb,wire.refreshAutoApproval());
            wire.dropStatus=true;check("timeout cannot reuse previous auto "+usb,!wire.refreshAutoApproval() && wire.getCachedStatus().getSavedBindings()==null);
            wire.dropStatus=false;wire.malformedSide=true;
            check("bad binding response defers "+usb,!wire.refreshAutoApproval());wire.malformedSide=false;
            check("recover after failed read "+usb,wire.refreshAutoApproval());
            wire.writeSideSwitchConfig(config(1,1,0));check("write ACK alone does not activate "+usb,!wire.getCachedStatus().isAutoApproval());
            wire.readSideSwitchConfig();check("confirmed read restores action "+usb,wire.getCachedStatus().isAutoApproval());
            long stale=wire.connectionGeneration();wire.reset();int before=wire.writes;
            try {wire.writeSideSwitchConfig(config(1,1,0),stale);throw new AssertionError("stale write");}catch(IOException expected){}
            check("old generation cannot write new target "+usb,wire.writes==before && !wire.getCachedStatus().isAutoApproval());
        }
        final boolean[] auto={false};
        BleManager fake=new BleManager(CALLBACK) {
            public boolean refreshAutoApproval(){return auto[0];}
            public boolean sendRuntimeState(byte s){return true;}
        };
        HookDispatchServer server=new HookDispatchServer(fake);
        server.setApprovalCallback((p,e)->{throw new AssertionError("AhaKey dialog called");});
        for(boolean enabled:new boolean[]{false,true}) {
            auto[0]=enabled;
            check("Claude explicit auto only "+enabled,hook(server,"handleClaudeEvent","PermissionRequest").contains("\"autoApproved\":"+enabled));
            check("Codex explicit auto only "+enabled,hook(server,"handleCodexEvent","CodexPreToolUse").contains("\"autoApproved\":"+enabled));
            check("Kimi hook native defer "+enabled,hook(server,"handleKimiEvent","KimiPreToolUse").trim().equals("{}"));
            String cursor=hook(server,"handleCursorEvent","preToolUse");
            check("Cursor native or allow "+enabled,enabled?cursor.contains("allow"):cursor.contains("defer_to_native"));
        }
        HookInstaller installer=new HookInstaller(1,s->{});Path scripts=Path.of(System.getProperty("user.home"),"generated-only");Files.createDirectories(scripts);
        for(String name:List.of("Claude","Codex","Kimi","Cursor")) {
            Method method=HookInstaller.class.getDeclaredMethod("generate"+name+"Script",Path.class);method.setAccessible(true);method.invoke(installer,scripts);
        }
        for(Path p:Files.list(scripts).toList()) {
            String s=Files.readString(p);
            check("generated script no forced ask/deny "+p.getFileName(),!s.contains("behavior\\\":\\\"ask")&&!s.contains("permissionDecision\\\":\\\"deny")&&!s.contains("behavior\":\"ask"));
            check("generated script current marker "+p.getFileName(),s.contains(HookInstaller.AHAKEY_HOOK_VERSION));
        }
        System.out.println("PASS "+checks+" checks; isolated memory transports and generated-only scripts; no live platform or hardware UAT");
    }
}
