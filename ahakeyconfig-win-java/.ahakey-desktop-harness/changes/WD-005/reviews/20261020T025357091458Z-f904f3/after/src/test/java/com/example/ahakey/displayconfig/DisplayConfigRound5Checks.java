package com.example.ahakey.displayconfig;

import com.example.ahakey.model.*;
import com.example.ahakey.service.*;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.*;
import java.nio.file.*;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Round 5: real service and in-memory transports, isolated from user state/devices. */
public final class DisplayConfigRound5Checks {
    private static int checks;
    private static final List<String> failures = new ArrayList<>();
    private static final long MINUTE = TimeUnit.MINUTES.toNanos(1);
    public static void main(String[] args) throws Exception {
        Path temp = Files.createTempDirectory("wd005-r5-");
        String home = System.getProperty("user.home");
        System.setProperty("user.home", temp.toString());
        try {
            for (boolean pending : new boolean[]{false, true}) {
                interleave(pending);
                anonymous(pending);
            }
            retryTtl();
            if (!failures.isEmpty()) throw new AssertionError(failures.toString());
            System.out.println("PASS " + checks + " round5 checks; no device or application started");
        } finally { System.setProperty("user.home", home); }
    }
    private static DisplayConfigChecks.FakeSession wire(List<byte[]> sent) throws Exception {
        var w = new DisplayConfigChecks.FakeSession();
        w.ble.getCachedStatus().setFirmwareCatalogKey("x1-c582-hw1-p1-1.0.0-r001");
        w.respond = r -> { sent.add(r.clone()); w.reply(AhaKeyProtocol.buildFrame(r[2], new byte[]{0})); };
        return w;
    }
    private static AiRuntimeDisplayService service(DisplayConfigChecks.FakeSession w) {
        var s = new AiRuntimeDisplayService(w.ble) {
            @Override public List<AiRuntimeSession> discoverCodexSessions() {
                return List.of(new AiRuntimeSession("Codex", "a", "A", "", "", "", Instant.EPOCH),
                        new AiRuntimeSession("Codex", "b", "B", "", "", "", Instant.EPOCH));
            }
            @Override public List<AiRuntimeSession> discoverCursorSessions() { return List.of(); }
        };
        s.displayModeProperty().set(AiRuntimeDisplayMode.SINGLE);
        for (int i=0;i<4;i++) s.getSlots().set(i,new AiRuntimeSlotBinding(i));
        s.getSlots().get(0).setStableId("a"); s.getSlots().get(1).setStableId("b");
        return s;
    }
    private static AiRuntimeDisplayService.Delivery event(AiRuntimeDisplayService s, String tool, String id, IDEState state) throws Exception {
        return s.handleHookEventResult(tool, state, id == null ? null : new ObjectMapper().readTree("{\"session_id\":\""+id+"\"}"));
    }
    private static void interleave(boolean pending) throws Exception {
        List<byte[]> sent = new ArrayList<>(); var w = wire(sent); var s=service(w);
        var lease = pending ? w.ble.openDisplayLease(true) : null;
        event(s,"Codex","a",IDEState.USER_PROMPT_SUBMIT);
        event(s,"Codex","b",IDEState.PRE_TOOL_USE);
        int count=sent.size();
        check("F1-ignore-display-"+pending,event(s,"Codex","a",IDEState.TASK_COMPLETED)==AiRuntimeDisplayService.Delivery.IGNORED);
        check("F1-no-overwrite-"+pending,sent.size()==count);
        if (lease!=null) lease.close();
        check("F1-current-B-"+pending,sent.get(sent.size()-1)[3]==IDEState.PRE_TOOL_USE.getCode());
        check("F1-write-count-"+pending,sent.size()==(pending?1:2));
        s.displayModeProperty().set(AiRuntimeDisplayMode.MULTI);
        var plan=s.prepareApply(true,true);
        check("F1-A-fact-completed-"+pending,plan.slots()[0].runtimeState()==AiRuntimeSlotState.DONE);
        check("F1-B-fact-running-"+pending,plan.slots()[1].runtimeState()==AiRuntimeSlotState.RUNNING);
        sent.clear();s.applyToKeyboard(true,true);
        check("F1-actual-multi-snapshot-"+pending,Arrays.equals(sent.get(sent.size()-1),AhaKeyProtocol.multiRuntimeSnapshot(plan.slots())));
        // Inspect the transmitted state, not merely equality with a potentially stale plan.
        check("F1-transmitted-A-not-running-"+pending,sent.get(sent.size()-1)[5]==AiRuntimeSlotState.DONE.getProtocolValue());
        invoke(w.ble,"resetDisplaySession");
        check("F1-reconnect-clears-A-"+pending,s.prepareApply(true,true).slots()[0].runtimeState()==AiRuntimeSlotState.EMPTY);
        check("F1-reconnect-clears-B-"+pending,s.prepareApply(true,true).slots()[1].runtimeState()==AiRuntimeSlotState.EMPTY);
    }
    private static void anonymous(boolean pending) throws Exception {
        List<byte[]> sent=new ArrayList<>();var w=wire(sent);var s=service(w);
        var lease=pending?w.ble.openDisplayLease(true):null;
        event(s,"Codex","a",IDEState.USER_PROMPT_SUBMIT);
        event(s,"Kimi",null,IDEState.PRE_TOOL_USE);
        int count=sent.size();
        check("F2-known-late-end-"+pending,event(s,"Codex","a",IDEState.SESSION_END)==AiRuntimeDisplayService.Delivery.IGNORED);
        check("F2-no-overwrite-"+pending,sent.size()==count);
        if(lease!=null)lease.close();
        check("F2-Kimi-remains-"+pending,sent.get(sent.size()-1)[3]==IDEState.PRE_TOOL_USE.getCode());
        check("F2-anonymous-own-end-"+pending,event(s,"Kimi",null,IDEState.SESSION_END)==AiRuntimeDisplayService.Delivery.SENT);
        event(s,"Codex","b",IDEState.PRE_TOOL_USE);
        check("F2-other-anonymous-late-end-"+pending,event(s,"Kimi",null,IDEState.SESSION_END)==AiRuntimeDisplayService.Delivery.IGNORED);
        check("F2-named-own-end-"+pending,event(s,"Codex","b",IDEState.SESSION_END)==AiRuntimeDisplayService.Delivery.SENT);
        event(s,"Kimi",null,IDEState.USER_PROMPT_SUBMIT);
        event(s,"Claude",null,IDEState.PRE_TOOL_USE);
        check("F2-cross-anonymous-end-"+pending,event(s,"Kimi",null,IDEState.STOP)==AiRuntimeDisplayService.Delivery.IGNORED);
        check("F2-Claude-own-end-"+pending,event(s,"Claude",null,IDEState.STOP)==AiRuntimeDisplayService.Delivery.SENT);
    }
    private static void retryTtl() throws Exception {
        List<byte[]> sent=new ArrayList<>();var w=wire(sent);
        var lease=w.ble.openDisplayLease(true);w.ble.sendRuntimeState((byte)1);
        long observed=System.nanoTime()-4*MINUTE;w.field("deferredRuntimeAt",observed);
        int[] attempts={0};
        w.field("outputStream",new OutputStream(){
            @Override public void write(int b) throws IOException { throw new IOException("controlled retry failure"); }
            @Override public void write(byte[] b,int off,int len) throws IOException { attempts[0]++;throw new IOException("controlled retry failure"); }
        });
        lease.close();
        check("F3-retry-at-four-minutes",attempts[0]==1);
        long after=(long)field(w.ble,"deferredRuntimeAt");
        check("F3-failure-preserves-original-time",after==observed);
        // Advance effective age by two minutes without sleeping or changing production clocks.
        w.field("deferredRuntimeAt",after-2*MINUTE);
        w.field("outputStream",new ByteArrayOutputStream(){
            @Override public void write(byte[] b,int off,int len){sent.add(Arrays.copyOfRange(b,off+3,off+len));}
        });
        invoke(w.ble,"flushDeferredRuntimeState");
        check("F3-six-minute-event-not-sent",sent.isEmpty());
        check("F3-expired-pending-cleared",field(w.ble,"deferredRuntimeState")==null);
        check("F3-new-event-sends",w.ble.sendRuntimeState((byte)2));
        check("F3-new-event-new-time",(long)field(w.ble,"deferredRuntimeAt")>observed);
        check("F3-new-event-byte",sent.get(sent.size()-1)[3]==2);
        sent.clear();lease=w.ble.openDisplayLease(true);
        w.ble.sendRuntimeState((byte)3);w.ble.sendRuntimeState((byte)4);lease.close();
        check("F3-latest-replaces",sent.size()==1 && sent.get(0)[3]==4);
        sent.clear();lease=w.ble.openDisplayLease(true);w.ble.sendRuntimeState((byte)5);
        w.ble.requireDisplayRecovery(w.ble.connectionGeneration());lease.close();
        check("F3-unknown-ACK-protected",sent.isEmpty());
        invoke(w.ble,"resetDisplaySession");invoke(w.ble,"flushDeferredRuntimeState");
        check("F3-reconnect-no-old-pending",sent.isEmpty() && field(w.ble,"deferredRuntimeState")==null);
    }
    private static Object field(Object target,String name) throws Exception {
        var f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);
    }
    private static void invoke(BleManager target,String name) throws Exception {
        var m=BleManager.class.getDeclaredMethod(name);m.setAccessible(true);m.invoke(target);
    }
    private static void check(String id,boolean ok){checks++;System.out.println((ok?"PASS ":"FAIL ")+id);if(!ok)failures.add(id);}
}
