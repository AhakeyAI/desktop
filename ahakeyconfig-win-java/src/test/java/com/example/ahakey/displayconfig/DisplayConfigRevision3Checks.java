package com.example.ahakey.displayconfig;

import com.example.ahakey.model.*;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.service.*;
import com.example.ahakey.util.AiRuntimeStore;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.lang.reflect.Field;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.sql.DriverManager;
import java.io.*;
import com.fasterxml.jackson.databind.JsonNode;

/** Real runtime service with memory transport and a temporary user home only. */
public final class DisplayConfigRevision3Checks {
    private static final List<String> failures = new ArrayList<>();
    private static int checks;
    public static void main(String[] args) throws Exception {
        Path temp = Files.createTempDirectory("wd005-r3-");
        String home = System.getProperty("user.home");
        System.setProperty("user.home", temp.toString());
        try {
            runtime();
            sources(temp);
            singleAndFeedback();
            for (boolean usb : new boolean[]{false, true}) { uploadDiagnostics(usb); uploadUnknown(usb); }
            optionalQueries();
            if (!failures.isEmpty()) throw new AssertionError(failures.toString());
            System.out.println("PASS " + checks + " revision3 checks; no hardware/application claims");
        } finally {
            System.setProperty("user.home", home);
            try (var paths = Files.walk(temp)) {
                for (Path p : paths.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(p);
            }
        }
    }
    private static void runtime() throws Exception {
        var wire = new DisplayConfigChecks.FakeSession();
        wire.ble.getCachedStatus().setFirmwareCatalogKey("x1-c582-hw1-p1-1.0.0-r001");
        List<byte[]> sent = new ArrayList<>();
        wire.respond = r -> { sent.add(r.clone()); wire.reply(AhaKeyProtocol.buildFrame(r[2], new byte[]{0})); };
        var draft = AiRuntimeStore.Draft.defaults();
        draft.slots[0].setStableId("session-a");
        draft.slots[0].setLastIdeState(IDEState.USER_PROMPT_SUBMIT.name());
        AiRuntimeStore.save(draft);
        var service = new AiRuntimeDisplayService(wire.ble);
        check("RT02-restart-does-not-restore-running", service.getSlots().get(0).runtimeState() == AiRuntimeSlotState.EMPTY);
        service.displayModeProperty().set(AiRuntimeDisplayMode.SINGLE);
        try (var lease = wire.ble.openDisplayLease(true)) {
            check("FB01-deferred-is-not-sent", !service.handleHookEvent("Codex", IDEState.USER_PROMPT_SUBMIT,
                    new ObjectMapper().readTree("{\"session_id\":\"session-a\"}")));
            check("FB01-no-write-under-lease", sent.isEmpty());
        }
        check("FB01-latest-sends-after-lease", sent.size() == 1);
        service.displayModeProperty().set(AiRuntimeDisplayMode.MULTI);
        AiRuntimeSlotBinding slot = new AiRuntimeSlotBinding(0);
        slot.setStableId("session-a"); slot.setCwd("C:/project"); slot.setTranscriptPath("C:/session-a.jsonl");
        Field f = AiRuntimeDisplayService.class.getDeclaredField("appliedSlots"); f.setAccessible(true);
        f.set(service, new AiRuntimeSlotBinding[]{slot, new AiRuntimeSlotBinding(1), new AiRuntimeSlotBinding(2), new AiRuntimeSlotBinding(3)});
        sent.clear();
        check("RT02-conflicting-id-not-rescued", !service.handleHookEvent("Codex", IDEState.USER_PROMPT_SUBMIT,
                new ObjectMapper().readTree("{\"session_id\":\"other\",\"transcript_path\":\"C:/session-a.jsonl\",\"cwd\":\"C:/project\"}")));
        check("RT02-conflict-zero-commands", sent.isEmpty());
        check("RT02-no-cwd-fallback", !service.handleHookEvent("Codex", IDEState.USER_PROMPT_SUBMIT,
                new ObjectMapper().readTree("{\"cwd\":\"C:/project\"}")));
        check("RT02-no-anonymous-terminal", !service.handleHookEvent("Codex", IDEState.SESSION_END, null));
        check("RT02-exact-new-id-accepted", service.handleHookEvent("Codex", IDEState.USER_PROMPT_SUBMIT, json("{\"session_id\":\"session-a\"}")));
        check("RT02-matching-completion", service.handleHookEvent("Codex", IDEState.TASK_COMPLETED, json("{\"session_id\":\"session-a\"}")));
        check("RT02-unique-transcript-no-id", service.handleHookEvent("Codex", IDEState.PRE_TOOL_USE, json("{\"transcript_path\":\"C:/session-a.jsonl\"}")));
        var applied = (AiRuntimeSlotBinding[])f.get(service);
        applied[1].setStableId("session-b"); applied[1].setTranscriptPath("C:/session-a.jsonl");
        check("RT02-ambiguous-transcript-rejected", !service.handleHookEvent("Codex", IDEState.STOP, json("{\"transcript_path\":\"C:/session-a.jsonl\"}")));
        applied[1].setProvider("Cursor"); applied[1].setStableId("conversation-a");
        for (String alias : List.of("thread_id", "workspace_id", "session_id"))
            check("RT02-Cursor-reject-" + alias, !service.handleHookEvent("Cursor", IDEState.PRE_TOOL_USE, json("{\""+alias+"\":\"conversation-a\"}")));
        check("RT02-Cursor-conversation", service.handleHookEvent("Cursor", IDEState.PRE_TOOL_USE, json("{\"conversation_id\":\"conversation-a\"}")));
        Field factsField = AiRuntimeDisplayService.class.getDeclaredField("liveFacts"); factsField.setAccessible(true);
        @SuppressWarnings("unchecked") Map<String,Object> facts = (Map<String,Object>)factsField.get(service);
        Object fact = facts.get("Codex:session-a");
        var constructor = fact.getClass().getDeclaredConstructors()[0]; constructor.setAccessible(true);
        facts.put("Codex:session-a", constructor.newInstance(IDEState.PRE_TOOL_USE,
                System.nanoTime() - TimeUnit.MINUTES.toNanos(6), wire.ble.connectionGeneration()));
        var applyFact = AiRuntimeDisplayService.class.getDeclaredMethod("applyLiveFact", AiRuntimeSlotBinding.class); applyFact.setAccessible(true);
        applyFact.invoke(service, applied[0]);
        check("RT02-expired-live-fact-empty", applied[0].runtimeState() == AiRuntimeSlotState.EMPTY);
        var reset = BleManager.class.getDeclaredMethod("resetDisplaySession"); reset.setAccessible(true); reset.invoke(wire.ble);
        applyFact.invoke(service, applied[1]);
        check("RT02-old-connection-fact-empty", applied[1].runtimeState() == AiRuntimeSlotState.EMPTY);
        check("RT02-binding-preserved", "session-a".equals(AiRuntimeStore.loadOrDefault().slots[0].getStableId()));
    }

    private static void sources(Path root) throws Exception {
        Path dir = Files.createDirectory(root.resolve("metadata"));
        Path db = dir.resolve("state_5.sqlite");
        try (var c = DriverManager.getConnection("jdbc:sqlite:" + db); var s = c.createStatement()) {
            s.execute("create table threads(id text primary key, source text, thread_source text)");
            s.execute("insert into threads values('user','vscode','user'),('prediction','vscode','composer_predictions'),"
                    + "('guardian','{\"subagent\":{\"other\":\"guardian\"}}',null),('spawn','{\"subagent\":{\"thread_spawn\":{}}}','subagent')");
        }
        byte[] before = Files.readAllBytes(db);
        var discovery = new CodexSessionDiscoveryService();
        check("RT01-user-source", discovery.eventSource(dir,"user") == CodexSessionDiscoveryService.EventSource.USER);
        check("RT01-prediction-source", discovery.eventSource(dir,"prediction") == CodexSessionDiscoveryService.EventSource.BACKGROUND);
        check("RT01-guardian-source", discovery.eventSource(dir,"guardian") == CodexSessionDiscoveryService.EventSource.BACKGROUND);
        check("RT01-generic-subagent-not-blocked", discovery.eventSource(dir,"spawn") == CodexSessionDiscoveryService.EventSource.UNKNOWN);
        check("RT01-new-index-delay-not-background", discovery.eventSource(dir,"new") == CodexSessionDiscoveryService.EventSource.UNKNOWN);
        check("RT01-metadata-bytes-unchanged", Arrays.equals(before, Files.readAllBytes(db)));
        var wire = wire(false, new ArrayList<>());
        var service = new AiRuntimeDisplayService(wire.ble);
        service.setCodexDataDir(dir.toString()); service.displayModeProperty().set(AiRuntimeDisplayMode.SINGLE);
        check("RT01-background-runtime-ignored", service.handleHookEventResult("Codex", IDEState.SESSION_START,
                json("{\"session_id\":\"guardian\"}")) == AiRuntimeDisplayService.Delivery.IGNORED);
        check("RT01-new-real-runtime-preserved", service.handleHookEvent("Codex", IDEState.SESSION_START, json("{\"session_id\":\"new\"}")));
    }

    private static void singleAndFeedback() throws Exception {
        List<byte[]> sent = new ArrayList<>(); var wire = wire(false, sent);
        var service = new AiRuntimeDisplayService(wire.ble);
        service.displayModeProperty().set(AiRuntimeDisplayMode.SINGLE);
        var a = json("{\"session_id\":\"a\"}"); var b = json("{\"session_id\":\"b\"}");
        try (var lease = wire.ble.openDisplayLease(true)) {
            service.handleHookEvent("Codex", IDEState.USER_PROMPT_SUBMIT, a);
            service.handleHookEvent("Codex", IDEState.USER_PROMPT_SUBMIT, b);
            check("RT01-late-other-terminal-ignored", service.handleHookEventResult("Codex", IDEState.SESSION_END,a) == AiRuntimeDisplayService.Delivery.IGNORED);
            check("RT01-current-terminal-pending", service.handleHookEventResult("Codex", IDEState.TASK_COMPLETED,b) == AiRuntimeDisplayService.Delivery.PENDING);
            var server = new HookDispatchServer(wire.ble, service);
            var method = HookDispatchServer.class.getDeclaredMethod("handleGeneric", PrintWriter.class, String.class, IDEState.class, String.class, JsonNode.class);
            method.setAccessible(true); StringWriter result = new StringWriter();
            method.invoke(server, new PrintWriter(result), "CodexTaskCompleted", IDEState.TASK_COMPLETED,"Codex",b);
            JsonNode response = json(result.toString());
            check("FB01-Hook-pending-not-displayUpdated", response.path("ok").asBoolean() && !response.path("displayUpdated").asBoolean()
                    && response.path("delivery").asText().equals("PENDING"));
            check("FB01-no-listener-started", !server.isRunning());
        }
        check("RT01-interleaving-latest-only", sent.size() == 1 && sent.get(0)[3] == IDEState.TASK_COMPLETED.getCode());
        sent.clear();
        try (var lease = wire.ble.openDisplayLease(true)) {
            wire.ble.sendRuntimeState((byte)1);
            wire.field("deferredRuntimeAt", System.nanoTime() - TimeUnit.MINUTES.toNanos(6));
        }
        check("RT01-expired-pending-not-replayed", sent.isEmpty());
        var legacy = new AiRuntimeDisplayService(wire.ble); legacy.displayModeProperty().set(AiRuntimeDisplayMode.SINGLE);
        for (String tool : List.of("Claude", "Kimi", "Cursor")) {
            check("RT01-legacy-start-" + tool, legacy.handleHookEvent(tool,IDEState.SESSION_START,null));
            check("RT01-legacy-end-" + tool, legacy.handleHookEvent(tool,IDEState.SESSION_END,null));
        }
        wire.ble.requireDisplayRecovery(wire.ble.connectionGeneration());
        check("FB01-unknown-quarantine-pending", legacy.handleHookEventResult("Codex",IDEState.USER_PROMPT_SUBMIT,a) == AiRuntimeDisplayService.Delivery.PENDING);
        Field queuedAt = BleManager.class.getDeclaredField("deferredRuntimeAt"); queuedAt.setAccessible(true);
        long observed = queuedAt.getLong(wire.ble);
        var flush = BleManager.class.getDeclaredMethod("flushDeferredRuntimeState"); flush.setAccessible(true); flush.invoke(wire.ble);
        check("RT01-quarantine-does-not-renew-TTL",queuedAt.getLong(wire.ble)==observed);
        wire.field("isConnected",false); wire.ble.getCachedStatus().setConnected(false);
        check("FB01-offline-failed", legacy.handleHookEventResult("Codex",IDEState.USER_PROMPT_SUBMIT,a) == AiRuntimeDisplayService.Delivery.FAILED);
    }

    private static DisplayConfigChecks.FakeSession wire(boolean usb, List<byte[]> sent) throws Exception {
        var wire = new DisplayConfigChecks.FakeSession();
        wire.ble.getCachedStatus().setFirmwareCatalogKey("x1-c582-hw1-p1-1.0.0-r001");
        if (usb) wire.useUsb();
        wire.respond = r -> { sent.add(r.clone()); wire.reply(AhaKeyProtocol.buildFrame(r[2],new byte[]{0})); };
        return wire;
    }
    private static void uploadDiagnostics(boolean usb) throws Exception {
        String path = usb ? "USB" : "BLE";
        List<byte[]> sent = new ArrayList<>(); var wire = wire(usb,sent);
        var asset = OledResourceState.Asset.fromBytes(new byte[28672]);
        wire.respond = r -> { sent.add(r.clone()); wire.reply(AhaKeyProtocol.buildFrame(r[2],new byte[]{1})); };
        try {
            OledUploadService.uploadResource(wire.ble,0,0,asset,p->{},()->{});
            check(path+"-begin-rejected",false);
        } catch (OledUploadService.UploadFailure e) {
            check(path+"-begin-diagnostic",e.getMessage().contains("BEGIN") && e.getMessage().contains("0/28672") && !e.commitUncertain());
        }
        check(path+"-no-auto-retry", sent.size()==1 && !wire.ble.isDisplayWriteUncertain());
        sent.clear();
        wire.respond = r -> {
            sent.add(r.clone());
            if (r[2] == (byte)0x8B) Thread.currentThread().interrupt();
            else wire.reply(AhaKeyProtocol.buildFrame(r[2],new byte[]{0}));
        };
        try {
            OledUploadService.uploadResource(wire.ble,0,0,asset,p->{},()->{});
            check(path+"-chunk-interrupted",false);
        } catch (OledUploadService.UploadFailure e) {
            check(path+"-recovery-feedback",e.getMessage().contains("CHUNK") && e.getMessage().contains("AI 状态发送已暂停") && e.getMessage().contains("本地资源已保留"));
        } finally { Thread.interrupted(); }
        check(path+"-no-next-chunk-or-commit",sent.size()==2 && wire.ble.isDisplayWriteUncertain());
        wire.reply(AhaKeyProtocol.buildFrame((byte)0x8B,new byte[]{0}));
        check(path+"-late-ACK-cannot-clear-quarantine",wire.ble.isDisplayWriteUncertain());
        sent.clear(); var successWire = wire(usb,sent);
        List<OledUploadService.Progress> progress = new ArrayList<>();
        OledUploadService.uploadResource(successWire.ble,0,0,asset,p->{},()->{},progress::add);
        check(path+"-progress-acknowledged",progress.size()==598 && progress.get(0).acknowledgedBytes()==48
                && progress.get(597).acknowledgedBytes()==28672 && progress.get(597).text().startsWith("100%"));
        check(path+"-progress-monotonic",java.util.stream.IntStream.range(1,progress.size()).allMatch(i -> progress.get(i).elapsedMillis()>=progress.get(i-1).elapsedMillis()));
    }
    private static void optionalQueries() throws Exception {
        List<byte[]> sent = new ArrayList<>(); var wire = wire(true,sent);
        try (var lease = wire.ble.openDisplayLease(true)) {
            wire.ble.queryStatus(); wire.ble.queryStatus(); wire.ble.queryStatus();
            check("BLEPERF-coalesced-optional-status",sent.size()==1);
            wire.ble.queryStatusAndWait(0);
            check("BLEPERF-explicit-refresh-not-coalesced",sent.size()==2);
        }
    }
    private static void uploadUnknown(boolean usb) throws Exception {
        String transport = usb ? "USB" : "BLE";
        for (int failedOpcode : new int[]{0x8B,0x8C}) {
            List<byte[]> sent = new ArrayList<>(); var wire = wire(usb,sent);
            wire.respond = r -> {
                sent.add(r.clone());
                if ((r[2]&255) == failedOpcode) {
                    // Chunk uses the real 15-second timeout; Commit uses the interrupted unknown-ACK path.
                    if (failedOpcode == 0x8C) Thread.currentThread().interrupt();
                } else wire.reply(AhaKeyProtocol.buildFrame(r[2],new byte[]{0}));
            };
            long start = System.nanoTime();
            try {
                OledUploadService.uploadResource(wire.ble,0,0,OledResourceState.Asset.fromBytes(new byte[28672]),p->{},()->{});
                check(transport+"-unknown-fails",false);
            } catch (OledUploadService.UploadFailure e) {
                check(transport+"-unknown-stage-"+failedOpcode,e.getMessage().contains(failedOpcode==0x8B?"CHUNK":"COMMIT")
                        && e.commitUncertain()==(failedOpcode==0x8C));
            } finally { Thread.interrupted(); }
            if(failedOpcode==0x8B) check(transport+"-actual-chunk-timeout",System.nanoTime()-start>=TimeUnit.SECONDS.toNanos(14));
            check(transport+"-unknown-no-retry-"+failedOpcode,sent.size()==(failedOpcode==0x8B?2:600) && wire.ble.isDisplayWriteUncertain());
            wire.reply(AhaKeyProtocol.buildFrame((byte)failedOpcode,new byte[]{0}));
            try { wire.ble.openDisplayLease(true); check(transport+"-reject-retry",false); }
            catch(IOException expected) { check(transport+"-late-ACK-retry-blocked-"+failedOpcode,true); }
        }
    }
    private static JsonNode json(String value) throws Exception { return new ObjectMapper().readTree(value); }
    private static void check(String id, boolean ok) {
        checks++;
        System.out.println((ok ? "PASS " : "FAIL ") + id);
        if (!ok) failures.add(id);
    }
}
